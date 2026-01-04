;; election.clar
;; Delegation-based election system for city governance
;; Token holders delegate their voting power to council candidates

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-registered (err u101))
(define-constant err-already-registered (err u102))
(define-constant err-self-delegation (err u103))
(define-constant err-zero-delegation (err u104))
(define-constant err-election-not-active (err u105))
(define-constant err-election-active (err u106))
(define-constant err-insufficient-votes (err u107))
(define-constant err-not-council-member (err u108))
(define-constant err-recall-threshold-not-met (err u109))

;; Election configuration
(define-constant council-size u5)
(define-constant recall-threshold-percent u51) ;; 51% to recall

;; State
(define-data-var election-active bool true)
(define-data-var election-epoch uint u1)
(define-data-var last-tally-block uint u0)

;; Candidate registration
(define-map candidates principal bool)

;; Delegations: delegator -> delegate
(define-map delegations principal principal)

;; Delegation amounts (cached for efficiency)
(define-map delegation-amounts
  { delegator: principal, delegate: principal }
  uint)

;; Total votes received by each candidate
(define-map candidate-votes principal uint)

;; Current council members (after tally)
(define-map council-members principal bool)

;; Council member list for iteration
(define-data-var council-list (list 5 principal) (list))

;; Recall votes against council members
(define-map recall-votes
  { member: principal, voter: principal }
  uint)
(define-map recall-totals principal uint)

;; Register as a candidate
(define-public (register-candidate)
  (let ((caller tx-sender))
    (asserts! (var-get election-active) err-election-not-active)
    (asserts! (is-none (map-get? candidates caller)) err-already-registered)
    (map-set candidates caller true)
    (map-set candidate-votes caller u0)
    (print {event: "candidate-registered", candidate: caller, epoch: (var-get election-epoch)})
    (ok true)))

;; Unregister as candidate (forfeits all delegated votes)
(define-public (unregister-candidate)
  (let ((caller tx-sender))
    (asserts! (is-some (map-get? candidates caller)) err-not-registered)
    (map-delete candidates caller)
    (map-set candidate-votes caller u0)
    (print {event: "candidate-unregistered", candidate: caller})
    (ok true)))

;; Delegate voting power to a candidate
(define-public (delegate (candidate principal))
  (let
    (
      (delegator tx-sender)
      (voting-power (unwrap! (contract-call? .city-btc-token get-balance delegator) err-zero-delegation))
      (current-delegate (map-get? delegations delegator))
    )
    (asserts! (var-get election-active) err-election-not-active)
    (asserts! (not (is-eq delegator candidate)) err-self-delegation)
    (asserts! (> voting-power u0) err-zero-delegation)
    (asserts! (is-some (map-get? candidates candidate)) err-not-registered)

    ;; Remove previous delegation if exists
    (match current-delegate
      prev-delegate
      (let ((prev-amount (default-to u0 (map-get? delegation-amounts {delegator: delegator, delegate: prev-delegate}))))
        (map-set candidate-votes prev-delegate
          (- (default-to u0 (map-get? candidate-votes prev-delegate)) prev-amount))
        (map-delete delegation-amounts {delegator: delegator, delegate: prev-delegate}))
      true)

    ;; Set new delegation
    (map-set delegations delegator candidate)
    (map-set delegation-amounts {delegator: delegator, delegate: candidate} voting-power)
    (map-set candidate-votes candidate
      (+ (default-to u0 (map-get? candidate-votes candidate)) voting-power))

    (print {event: "delegation", delegator: delegator, delegate: candidate, amount: voting-power})
    (ok voting-power)))

;; Remove delegation
(define-public (undelegate)
  (let
    (
      (delegator tx-sender)
      (current-delegate (map-get? delegations delegator))
    )
    (match current-delegate
      current-del
      (let ((amount (default-to u0 (map-get? delegation-amounts {delegator: delegator, delegate: current-del}))))
        (map-set candidate-votes current-del
          (- (default-to u0 (map-get? candidate-votes current-del)) amount))
        (map-delete delegation-amounts {delegator: delegator, delegate: current-del})
        (map-delete delegations delegator)
        (print {event: "undelegation", delegator: delegator, former-delegate: current-del})
        (ok true))
      err-not-registered)))

;; Refresh delegation amount (call when token balance changes)
(define-public (refresh-delegation)
  (let
    (
      (delegator tx-sender)
      (new-voting-power (unwrap! (contract-call? .city-btc-token get-balance delegator) err-zero-delegation))
      (current-delegate (map-get? delegations delegator))
    )
    (match current-delegate
      current-del
      (let ((old-amount (default-to u0 (map-get? delegation-amounts {delegator: delegator, delegate: current-del}))))
        ;; Update candidate votes with difference
        (map-set candidate-votes current-del
          (+ (- (default-to u0 (map-get? candidate-votes current-del)) old-amount) new-voting-power))
        (map-set delegation-amounts {delegator: delegator, delegate: current-del} new-voting-power)
        (print {event: "delegation-refreshed", delegator: delegator, delegate: current-del, new-amount: new-voting-power})
        (ok new-voting-power))
      err-not-registered)))

;; Tally votes and form new council (top 5 candidates)
;; Note: This is a simplified version. Full implementation would need
;; off-chain sorting or on-chain iteration with gas limits
(define-public (tally-election (top-candidates (list 5 principal)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get election-active) err-election-not-active)

    ;; Clear old council
    (var-set council-list (list))

    ;; Validate and set new council (provided candidates must have votes in descending order)
    (let ((validated-council (validate-council-list top-candidates)))
      (var-set council-list validated-council)

      ;; Mark council members
      (map set-council-member validated-council)

      ;; Update election state
      (var-set last-tally-block block-height)
      (var-set election-epoch (+ (var-get election-epoch) u1))

      (print {event: "election-tallied", council: validated-council, epoch: (var-get election-epoch)})
      (ok validated-council))))

;; Helper to set council member
(define-private (set-council-member (member principal))
  (map-set council-members member true))

;; Validate that provided list is ordered by votes (simplified - trusts input order)
(define-private (validate-council-list (council-candidates (list 5 principal)))
  council-candidates)

;; Vote to recall a council member
(define-public (vote-recall (member principal))
  (let
    (
      (voter tx-sender)
      (voting-power (unwrap! (contract-call? .city-btc-token get-balance voter) err-zero-delegation))
      (current-recall-vote (default-to u0 (map-get? recall-votes {member: member, voter: voter})))
    )
    (asserts! (is-some (map-get? council-members member)) err-not-council-member)
    (asserts! (> voting-power u0) err-zero-delegation)

    ;; Update recall vote
    (map-set recall-votes {member: member, voter: voter} voting-power)
    (map-set recall-totals member
      (+ (- (default-to u0 (map-get? recall-totals member)) current-recall-vote) voting-power))

    (print {event: "recall-vote", member: member, voter: voter, amount: voting-power})
    (ok voting-power)))

;; Execute recall if threshold met
(define-public (execute-recall (member principal))
  (let
    (
      (total-recall-votes (default-to u0 (map-get? recall-totals member)))
      (total-supply (unwrap! (contract-call? .city-btc-token get-total-supply) err-zero-delegation))
      (threshold (/ (* total-supply recall-threshold-percent) u100))
    )
    (asserts! (is-some (map-get? council-members member)) err-not-council-member)
    (asserts! (>= total-recall-votes threshold) err-recall-threshold-not-met)

    ;; Remove from council
    (map-delete council-members member)
    (map-set recall-totals member u0)

    (print {event: "member-recalled", member: member, votes: total-recall-votes, threshold: threshold})
    (ok true)))

;; Admin: pause/resume elections
(define-public (set-election-active (active bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set election-active active)
    (ok true)))

;; Read-only functions

(define-read-only (is-candidate (account principal))
  (is-some (map-get? candidates account)))

(define-read-only (get-delegation (delegator principal))
  (map-get? delegations delegator))

(define-read-only (get-candidate-votes (candidate principal))
  (default-to u0 (map-get? candidate-votes candidate)))

(define-read-only (is-council-member (account principal))
  (is-some (map-get? council-members account)))

(define-read-only (get-council)
  (var-get council-list))

(define-read-only (get-election-epoch)
  (var-get election-epoch))

(define-read-only (is-election-active)
  (var-get election-active))

(define-read-only (get-recall-votes (member principal))
  (default-to u0 (map-get? recall-totals member)))

(define-read-only (get-council-size)
  council-size)

(define-read-only (get-recall-threshold)
  recall-threshold-percent)
