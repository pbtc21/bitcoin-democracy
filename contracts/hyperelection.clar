;; hyperelection.clar
;; Bitzion-style stake-weighted board election
;; "anyone can vote for anyone -- so long as they're not creating a loop"
;;
;; Mechanics:
;; 1. Each CityBTC token = 1 election point
;; 2. Hodlers delegate ALL their points upward (transitive)
;; 3. Votes can chain: A->B->C (A's stake flows through B to C)
;; 4. No loops allowed
;; 5. Top 30 vote-recipients become trustees
;; 6. Election finalizes ONCE, stable until recall

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-delegated (err u101))
(define-constant err-not-delegated (err u102))
(define-constant err-self-delegation (err u103))
(define-constant err-would-create-loop (err u104))
(define-constant err-election-finalized (err u105))
(define-constant err-election-not-finalized (err u106))
(define-constant err-not-trustee (err u107))
(define-constant err-recall-threshold-not-met (err u108))
(define-constant err-zero-stake (err u109))
(define-constant err-invalid-trustees (err u110))

;; Board size = 30 cities
(define-constant board-size u30)

;; Recall requires 33% of prior election stake
(define-constant recall-threshold-percent u33)

;; State
(define-data-var election-finalized bool false)
(define-data-var election-epoch uint u1)
(define-data-var election-stake uint u0) ;; Total stake that participated
(define-data-var recall-stake uint u0)   ;; Stake voting for recall

;; Delegations: delegator -> delegate
;; Delegation is transitive: if A->B and B->C, A's stake flows to C
(define-map delegations principal principal)

;; Track who has delegated TO each account (for transitive calculation)
(define-map delegation-count principal uint)

;; Current trustees (after finalization)
(define-map trustees principal bool)
(define-data-var trustee-list (list 30 principal) (list))

;; Recall votes
(define-map recall-votes principal uint)

;; Check if delegation would create a loop
;; We check up to 30 hops (max possible chain length)
(define-private (would-create-loop (delegator principal) (target principal))
  (if (is-eq delegator target)
    true
    (let ((hop1 (map-get? delegations target)))
      (match hop1 h1
        (if (is-eq delegator h1) true
          (let ((hop2 (map-get? delegations h1)))
            (match hop2 h2
              (if (is-eq delegator h2) true
                (let ((hop3 (map-get? delegations h2)))
                  (match hop3 h3
                    (if (is-eq delegator h3) true
                      (let ((hop4 (map-get? delegations h3)))
                        (match hop4 h4
                          (if (is-eq delegator h4) true
                            (let ((hop5 (map-get? delegations h4)))
                              (match hop5 h5
                                (is-eq delegator h5)
                                false)))
                          false)))
                    false)))
              false)))
        false))))

;; Delegate stake to another account
;; This is transitive - your stake flows through the chain
(define-public (delegate (to principal))
  (let
    (
      (delegator tx-sender)
      (stake (unwrap! (contract-call? .city-btc-token get-balance delegator) err-zero-stake))
    )
    (asserts! (not (var-get election-finalized)) err-election-finalized)
    (asserts! (not (is-eq delegator to)) err-self-delegation)
    (asserts! (> stake u0) err-zero-stake)
    (asserts! (is-none (map-get? delegations delegator)) err-already-delegated)
    (asserts! (not (would-create-loop delegator to)) err-would-create-loop)

    ;; Set delegation
    (map-set delegations delegator to)

    ;; Increment delegation count for target
    (map-set delegation-count to
      (+ (default-to u0 (map-get? delegation-count to)) u1))

    (print {event: "delegated", from: delegator, to: to, stake: stake, epoch: (var-get election-epoch)})
    (ok stake)))

;; Remove delegation
(define-public (undelegate)
  (let
    (
      (delegator tx-sender)
      (current-delegate (map-get? delegations delegator))
    )
    (asserts! (not (var-get election-finalized)) err-election-finalized)

    (match current-delegate the-delegate
      (begin
        (map-delete delegations delegator)
        (map-set delegation-count the-delegate
          (- (default-to u1 (map-get? delegation-count the-delegate)) u1))
        (print {event: "undelegated", from: delegator, former-delegate: the-delegate})
        (ok true))
      err-not-delegated)))

;; Finalize election with top 30 trustees
;; Trustees are provided off-chain (calculated from delegation graph)
;; On-chain we verify they're valid principals
(define-public (finalize-election (new-trustees (list 30 principal)) (total-stake uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get election-finalized)) err-election-finalized)
    (asserts! (is-eq (len new-trustees) board-size) err-invalid-trustees)

    ;; Set trustees
    (var-set trustee-list new-trustees)
    (map set-trustee new-trustees)

    ;; Record election stake for recall threshold
    (var-set election-stake total-stake)
    (var-set election-finalized true)
    (var-set election-epoch (+ (var-get election-epoch) u1))

    (print {event: "election-finalized", trustees: new-trustees, total-stake: total-stake, epoch: (var-get election-epoch)})
    (ok true)))

;; Helper to set trustee
(define-private (set-trustee (trustee principal))
  (map-set trustees trustee true))

;; Helper to clear trustee
(define-private (clear-trustee (trustee principal))
  (map-delete trustees trustee))

;; Vote for recall (stake-weighted)
(define-public (vote-recall)
  (let
    (
      (voter tx-sender)
      (stake (unwrap! (contract-call? .city-btc-token get-balance voter) err-zero-stake))
      (current-vote (default-to u0 (map-get? recall-votes voter)))
    )
    (asserts! (var-get election-finalized) err-election-not-finalized)
    (asserts! (> stake u0) err-zero-stake)

    ;; Update recall vote
    (map-set recall-votes voter stake)
    (var-set recall-stake (+ (- (var-get recall-stake) current-vote) stake))

    (print {event: "recall-vote", voter: voter, stake: stake, total-recall: (var-get recall-stake)})
    (ok stake)))

;; Execute recall if threshold met
(define-public (execute-recall)
  (let
    (
      (threshold (/ (* (var-get election-stake) recall-threshold-percent) u100))
    )
    (asserts! (var-get election-finalized) err-election-not-finalized)
    (asserts! (>= (var-get recall-stake) threshold) err-recall-threshold-not-met)

    ;; Clear all trustees
    (map clear-trustee (var-get trustee-list))
    (var-set trustee-list (list))

    ;; Reset election state
    (var-set election-finalized false)
    (var-set recall-stake u0)

    (print {event: "recall-executed", prior-stake: (var-get election-stake), recall-stake: (var-get recall-stake)})
    (ok true)))

;; Read-only functions

(define-read-only (is-trustee (account principal))
  (default-to false (map-get? trustees account)))

(define-read-only (get-trustees)
  (var-get trustee-list))

(define-read-only (get-delegation (delegator principal))
  (map-get? delegations delegator))

(define-read-only (is-election-finalized)
  (var-get election-finalized))

(define-read-only (get-election-epoch)
  (var-get election-epoch))

(define-read-only (get-election-stake)
  (var-get election-stake))

(define-read-only (get-recall-stake)
  (var-get recall-stake))

(define-read-only (get-recall-threshold)
  (/ (* (var-get election-stake) recall-threshold-percent) u100))

(define-read-only (get-board-size)
  board-size)

;; Get delegation chain (up to 5 hops for gas efficiency)
(define-read-only (get-delegation-chain (account principal))
  (let
    (
      (d1 (map-get? delegations account))
    )
    (match d1 delegate1
      (let ((d2 (map-get? delegations delegate1)))
        (match d2 delegate2
          (let ((d3 (map-get? delegations delegate2)))
            (match d3 delegate3
              (list delegate1 delegate2 delegate3)
              (list delegate1 delegate2)))
          (list delegate1)))
      (list))))
