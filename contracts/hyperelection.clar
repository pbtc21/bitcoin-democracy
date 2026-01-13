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
(define-constant err-challenge-pending (err u111))
(define-constant err-no-pending-finalization (err u112))
(define-constant err-challenge-period-active (err u113))

;; Board size = 30 cities
(define-constant board-size u30)

;; Challenge period: ~24 hours (144 blocks at 10 min/block)
(define-constant challenge-period u144)

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

;; Recall votes - keyed by epoch to auto-invalidate after recall
(define-map recall-votes {voter: principal, epoch: uint} uint)

;; Pending finalization (challenge period)
(define-data-var pending-trustees (list 30 principal) (list))
(define-data-var pending-stake uint u0)
(define-data-var finalization-proposed-at uint u0)
(define-data-var finalization-pending bool false)

;; Check if delegation would create a loop
;; Clarity doesn't support recursion, so we unroll 30 hops explicitly
;; Uses fold over a list of indices to traverse the delegation chain
(define-private (follow-delegation (idx uint) (acc {current: (optional principal), found-loop: bool, target: principal}))
  (if (get found-loop acc)
    acc  ;; Already found loop, short-circuit
    (match (get current acc)
      curr
        (if (is-eq curr (get target acc))
          (merge acc {found-loop: true})
          (merge acc {current: (map-get? delegations curr)}))
      acc)))  ;; No current, end of chain

(define-private (would-create-loop (delegator principal) (target principal))
  (if (is-eq delegator target)
    true
    (let
      (
        (initial {current: (map-get? delegations target), found-loop: false, target: delegator})
        (result (fold follow-delegation
          (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20 u21 u22 u23 u24 u25 u26 u27 u28 u29)
          initial))
      )
      (get found-loop result))))

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

;; ============================================
;; ELECTION FINALIZATION WITH CHALLENGE PERIOD
;; ============================================

;; Step 1: Propose finalization (starts 24-hour challenge window)
;; Trustees are calculated off-chain from delegation graph
(define-public (propose-finalization (new-trustees (list 30 principal)) (total-stake uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get election-finalized)) err-election-finalized)
    (asserts! (not (var-get finalization-pending)) err-challenge-pending)
    (asserts! (is-eq (len new-trustees) board-size) err-invalid-trustees)

    ;; Store pending finalization
    (var-set pending-trustees new-trustees)
    (var-set pending-stake total-stake)
    (var-set finalization-proposed-at stacks-block-height)
    (var-set finalization-pending true)

    (print {event: "finalization-proposed", trustees: new-trustees, total-stake: total-stake, challenge-ends: (+ stacks-block-height challenge-period)})
    (ok true)))

;; Step 2: Challenge finalization (anyone can call during challenge period)
;; If challenge is valid, cancels pending finalization
;; Note: In production, this would verify a merkle proof of correct ranking
;; For now, only contract-owner can cancel (trusted challenge review)
(define-public (cancel-finalization)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get finalization-pending) err-no-pending-finalization)

    ;; Clear pending state
    (var-set pending-trustees (list))
    (var-set pending-stake u0)
    (var-set finalization-pending false)

    (print {event: "finalization-cancelled"})
    (ok true)))

;; Step 3: Execute finalization (after challenge period ends)
;; Anyone can call once challenge period has passed
(define-public (execute-finalization)
  (let
    (
      (proposed-at (var-get finalization-proposed-at))
      (new-trustees (var-get pending-trustees))
      (total-stake (var-get pending-stake))
    )
    (asserts! (var-get finalization-pending) err-no-pending-finalization)
    (asserts! (not (var-get election-finalized)) err-election-finalized)
    (asserts! (>= stacks-block-height (+ proposed-at challenge-period)) err-challenge-period-active)

    ;; Set trustees
    (var-set trustee-list new-trustees)
    (map set-trustee new-trustees)

    ;; Record election stake for recall threshold
    (var-set election-stake total-stake)
    (var-set election-finalized true)
    (var-set election-epoch (+ (var-get election-epoch) u1))

    ;; Clear pending state
    (var-set finalization-pending false)

    (print {event: "election-finalized", trustees: new-trustees, total-stake: total-stake, epoch: (var-get election-epoch)})
    (ok true)))

;; Legacy function for backwards compatibility (immediate finalization)
;; Only works if no challenge period is desired (emergency use)
(define-public (finalize-election (new-trustees (list 30 principal)) (total-stake uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get election-finalized)) err-election-finalized)
    (asserts! (not (var-get finalization-pending)) err-challenge-pending)
    (asserts! (is-eq (len new-trustees) board-size) err-invalid-trustees)

    ;; Set trustees directly (no challenge period)
    (var-set trustee-list new-trustees)
    (map set-trustee new-trustees)

    ;; Record election stake for recall threshold
    (var-set election-stake total-stake)
    (var-set election-finalized true)
    (var-set election-epoch (+ (var-get election-epoch) u1))

    (print {event: "election-finalized-immediate", trustees: new-trustees, total-stake: total-stake, epoch: (var-get election-epoch)})
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
      (current-epoch (var-get election-epoch))
      (stake (unwrap! (contract-call? .city-btc-token get-balance voter) err-zero-stake))
      (current-vote (default-to u0 (map-get? recall-votes {voter: voter, epoch: current-epoch})))
    )
    (asserts! (var-get election-finalized) err-election-not-finalized)
    (asserts! (> stake u0) err-zero-stake)

    ;; Update recall vote (keyed by epoch so previous epoch votes don't count)
    (map-set recall-votes {voter: voter, epoch: current-epoch} stake)
    (var-set recall-stake (+ (- (var-get recall-stake) current-vote) stake))

    (print {event: "recall-vote", voter: voter, stake: stake, epoch: current-epoch, total-recall: (var-get recall-stake)})
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

;; Challenge period read-only functions

(define-read-only (is-finalization-pending)
  (var-get finalization-pending))

(define-read-only (get-pending-trustees)
  (var-get pending-trustees))

(define-read-only (get-pending-stake)
  (var-get pending-stake))

(define-read-only (get-challenge-end-block)
  (if (var-get finalization-pending)
    (some (+ (var-get finalization-proposed-at) challenge-period))
    none))

(define-read-only (can-execute-finalization)
  (and
    (var-get finalization-pending)
    (not (var-get election-finalized))
    (>= stacks-block-height (+ (var-get finalization-proposed-at) challenge-period))))
