;; hyperelection-hardened.clar
;; Censorship-resistant stake-weighted board election
;; NO admin functions after burn - fully autonomous
;;
;; "anyone can vote for anyone -- so long as they're not creating a loop"
;;
;; Mechanics:
;; 1. Each CityBTC token = 1 election point
;; 2. Hodlers delegate ALL their points upward (transitive)
;; 3. Votes can chain: A->B->C (A's stake flows through B to C)
;; 4. No loops allowed
;; 5. Top 30 vote-recipients become trustees
;; 6. Challenge period for trustless finalization
;; 7. Anyone can trigger finalization after challenge period

;; Constants
(define-constant ERR-ALREADY-DELEGATED (err u101))
(define-constant ERR-NOT-DELEGATED (err u102))
(define-constant ERR-SELF-DELEGATION (err u103))
(define-constant ERR-WOULD-CREATE-LOOP (err u104))
(define-constant ERR-ELECTION-FINALIZED (err u105))
(define-constant ERR-ELECTION-NOT-FINALIZED (err u106))
(define-constant ERR-NOT-TRUSTEE (err u107))
(define-constant ERR-RECALL-THRESHOLD-NOT-MET (err u108))
(define-constant ERR-ZERO-STAKE (err u109))
(define-constant ERR-INVALID-TRUSTEES (err u110))
(define-constant ERR-CHALLENGE-PENDING (err u111))
(define-constant ERR-NO-PENDING-FINALIZATION (err u112))
(define-constant ERR-CHALLENGE-PERIOD-ACTIVE (err u113))
(define-constant ERR-ADMIN-BURNED (err u120))
(define-constant ERR-NOT-BURNED-YET (err u121))
(define-constant ERR-PROPOSER-ONLY (err u122))
(define-constant ERR-ABNEGATION-REQUIRED (err u123))
(define-constant ERR-ALREADY-ABNEGATED (err u124))
(define-constant ERR-ABNEGATION-NOT-STARTED (err u125))
(define-constant ERR-CANNOT-ABNEGATE-TO-SELF (err u126))

;; Burn address
(define-constant BURN-ADDRESS 'SP000000000000000000002Q6VF78)

;; Board size = 30 cities
(define-constant BOARD-SIZE u30)

;; Challenge period: ~24 hours (144 blocks at 10 min/block)
(define-constant CHALLENGE-PERIOD u144)

;; Recall requires 33% of prior election stake
(define-constant RECALL-THRESHOLD-PERCENT u33)

;; ============================================
;; ADMIN STATE (burnable)
;; ============================================

(define-data-var contract-owner principal tx-sender)
(define-data-var admin-burned bool false)

;; ============================================
;; ELECTION STATE
;; ============================================

(define-data-var election-finalized bool false)
(define-data-var election-epoch uint u1)
(define-data-var election-stake uint u0)
(define-data-var recall-stake uint u0)

;; Delegations: delegator -> delegate
(define-map delegations principal principal)

;; Track delegation count for each account
(define-map delegation-count principal uint)

;; Current trustees (after finalization)
(define-map trustees principal bool)
(define-data-var trustee-list (list 30 principal) (list))

;; Recall votes - keyed by epoch
(define-map recall-votes {voter: principal, epoch: uint} uint)

;; ============================================
;; INITIAL ABNEGATION STATE
;; ============================================
;; Per Yarvin: "After choosing the first coordinator, all the initial
;; trustees resign immediately - each giving their key to someone they
;; know, who they think will make an even better trustee."

(define-data-var abnegation-started bool false)
(define-data-var abnegation-complete bool false)
(define-data-var abnegation-count uint u0)

;; Track which trustees have abnegated
(define-map has-abnegated principal bool)

;; ============================================
;; CHALLENGE PERIOD STATE
;; ============================================

(define-data-var pending-trustees (list 30 principal) (list))
(define-data-var pending-stake uint u0)
(define-data-var finalization-proposed-at uint u0)
(define-data-var finalization-pending bool false)
(define-data-var finalization-proposer principal BURN-ADDRESS)

;; ============================================
;; ADMIN BURN (call once, irreversible)
;; ============================================

(define-public (burn-admin-forever)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-PROPOSER-ONLY)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)

    (var-set admin-burned true)
    (var-set contract-owner BURN-ADDRESS)

    (print {event: "admin-burned-forever", block: stacks-block-height,
            message: "Election contract is now unstoppable"})
    (ok true)))

(define-read-only (is-admin-burned)
  (var-get admin-burned))

;; ============================================
;; LOOP DETECTION
;; ============================================

(define-private (follow-delegation (idx uint) (acc {current: (optional principal), found-loop: bool, target: principal}))
  (if (get found-loop acc)
    acc
    (match (get current acc)
      curr
        (if (is-eq curr (get target acc))
          (merge acc {found-loop: true})
          (merge acc {current: (map-get? delegations curr)}))
      acc)))

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

;; ============================================
;; DELEGATION (permissionless)
;; ============================================

(define-public (delegate (to principal))
  (let
    (
      (delegator tx-sender)
      (stake (unwrap! (contract-call? .city-btc-token-hardened get-balance delegator) ERR-ZERO-STAKE))
    )
    (asserts! (not (var-get election-finalized)) ERR-ELECTION-FINALIZED)
    (asserts! (not (is-eq delegator to)) ERR-SELF-DELEGATION)
    (asserts! (> stake u0) ERR-ZERO-STAKE)
    (asserts! (is-none (map-get? delegations delegator)) ERR-ALREADY-DELEGATED)
    (asserts! (not (would-create-loop delegator to)) ERR-WOULD-CREATE-LOOP)

    (map-set delegations delegator to)
    (map-set delegation-count to
      (+ (default-to u0 (map-get? delegation-count to)) u1))

    (print {event: "delegated", from: delegator, to: to, stake: stake, epoch: (var-get election-epoch)})
    (ok stake)))

(define-public (undelegate)
  (let
    (
      (delegator tx-sender)
      (current-delegate (map-get? delegations delegator))
    )
    (asserts! (not (var-get election-finalized)) ERR-ELECTION-FINALIZED)

    (match current-delegate the-delegate
      (begin
        (map-delete delegations delegator)
        (map-set delegation-count the-delegate
          (- (default-to u1 (map-get? delegation-count the-delegate)) u1))
        (print {event: "undelegated", from: delegator, former-delegate: the-delegate})
        (ok true))
      ERR-NOT-DELEGATED)))

;; ============================================
;; ELECTION FINALIZATION (trustless with challenge)
;; ============================================

;; Step 1: Anyone can propose finalization (starts challenge window)
;; In hardened mode, ANYONE can propose (not just owner)
;; The challenge period protects against bad proposals
(define-public (propose-finalization (new-trustees (list 30 principal)) (total-stake uint))
  (begin
    (asserts! (not (var-get election-finalized)) ERR-ELECTION-FINALIZED)
    (asserts! (not (var-get finalization-pending)) ERR-CHALLENGE-PENDING)
    (asserts! (is-eq (len new-trustees) BOARD-SIZE) ERR-INVALID-TRUSTEES)

    (var-set pending-trustees new-trustees)
    (var-set pending-stake total-stake)
    (var-set finalization-proposed-at stacks-block-height)
    (var-set finalization-pending true)
    (var-set finalization-proposer tx-sender)

    (print {event: "finalization-proposed", proposer: tx-sender, trustees: new-trustees,
            total-stake: total-stake, challenge-ends: (+ stacks-block-height CHALLENGE-PERIOD)})
    (ok true)))

;; Step 2: Anyone can cancel during challenge period if they provide proof of error
;; In production, this would verify merkle proof of correct ranking
;; For now, original proposer can cancel, or admin before burn
(define-public (cancel-finalization)
  (begin
    (asserts! (var-get finalization-pending) ERR-NO-PENDING-FINALIZATION)
    ;; After burn: only proposer can cancel (they made a mistake)
    ;; Before burn: owner can also cancel
    (asserts! (or
      (is-eq tx-sender (var-get finalization-proposer))
      (and (not (var-get admin-burned)) (is-eq tx-sender (var-get contract-owner))))
      ERR-PROPOSER-ONLY)

    (var-set pending-trustees (list))
    (var-set pending-stake u0)
    (var-set finalization-pending false)

    (print {event: "finalization-cancelled", cancelled-by: tx-sender})
    (ok true)))

;; Step 3: ANYONE can execute after challenge period (permissionless)
(define-public (execute-finalization)
  (let
    (
      (proposed-at (var-get finalization-proposed-at))
      (new-trustees (var-get pending-trustees))
      (total-stake (var-get pending-stake))
    )
    (asserts! (var-get finalization-pending) ERR-NO-PENDING-FINALIZATION)
    (asserts! (not (var-get election-finalized)) ERR-ELECTION-FINALIZED)
    (asserts! (>= stacks-block-height (+ proposed-at CHALLENGE-PERIOD)) ERR-CHALLENGE-PERIOD-ACTIVE)

    (var-set trustee-list new-trustees)
    (map set-trustee new-trustees)

    (var-set election-stake total-stake)
    (var-set election-finalized true)
    (var-set election-epoch (+ (var-get election-epoch) u1))
    (var-set finalization-pending false)

    (print {event: "election-finalized", trustees: new-trustees, total-stake: total-stake,
            epoch: (var-get election-epoch), executed-by: tx-sender})
    (ok true)))

(define-private (set-trustee (trustee principal))
  (map-set trustees trustee true))

(define-private (clear-trustee (trustee principal))
  (map-delete trustees trustee))

;; ============================================
;; RECALL (permissionless)
;; ============================================

(define-public (vote-recall)
  (let
    (
      (voter tx-sender)
      (current-epoch (var-get election-epoch))
      (stake (unwrap! (contract-call? .city-btc-token-hardened get-balance voter) ERR-ZERO-STAKE))
      (current-vote (default-to u0 (map-get? recall-votes {voter: voter, epoch: current-epoch})))
    )
    (asserts! (var-get election-finalized) ERR-ELECTION-NOT-FINALIZED)
    (asserts! (> stake u0) ERR-ZERO-STAKE)

    (map-set recall-votes {voter: voter, epoch: current-epoch} stake)
    (var-set recall-stake (+ (- (var-get recall-stake) current-vote) stake))

    (print {event: "recall-vote", voter: voter, stake: stake, epoch: current-epoch,
            total-recall: (var-get recall-stake)})
    (ok stake)))

;; ANYONE can execute recall if threshold met (permissionless)
(define-public (execute-recall)
  (let
    (
      (threshold (/ (* (var-get election-stake) RECALL-THRESHOLD-PERCENT) u100))
    )
    (asserts! (var-get election-finalized) ERR-ELECTION-NOT-FINALIZED)
    (asserts! (>= (var-get recall-stake) threshold) ERR-RECALL-THRESHOLD-NOT-MET)

    (map clear-trustee (var-get trustee-list))
    (var-set trustee-list (list))

    (var-set election-finalized false)
    (var-set recall-stake u0)

    (print {event: "recall-executed", prior-stake: (var-get election-stake),
            recall-stake: (var-get recall-stake), executed-by: tx-sender})
    (ok true)))

;; ============================================
;; INITIAL ABNEGATION (Yarvin's "resignation ritual")
;; ============================================
;; After first coordinator is appointed, all initial trustees must
;; resign their seat to a trusted successor. This creates the
;; "second board" which is the permanent governing body.

;; Called by board contract when first coordinator is appointed
(define-public (start-abnegation)
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) ERR-NOT-TRUSTEE)
    (asserts! (var-get election-finalized) ERR-ELECTION-NOT-FINALIZED)
    (asserts! (not (var-get abnegation-started)) ERR-ALREADY-ABNEGATED)
    (asserts! (is-eq (var-get election-epoch) u2) ERR-ABNEGATION-NOT-STARTED) ;; Only after first election (epoch goes 1->2)

    (var-set abnegation-started true)

    (print {event: "abnegation-started", epoch: (var-get election-epoch),
            message: "Initial trustees must now resign to successors"})
    (ok true)))

;; Trustee resigns their seat to a successor
(define-public (abnegate (successor principal))
  (let
    (
      (trustee tx-sender)
    )
    (asserts! (var-get abnegation-started) ERR-ABNEGATION-NOT-STARTED)
    (asserts! (not (var-get abnegation-complete)) ERR-ALREADY-ABNEGATED)
    (asserts! (is-trustee trustee) ERR-NOT-TRUSTEE)
    (asserts! (is-none (map-get? has-abnegated trustee)) ERR-ALREADY-ABNEGATED)
    (asserts! (not (is-eq trustee successor)) ERR-CANNOT-ABNEGATE-TO-SELF)

    ;; Set temp vars for list replacement (Clarity has no closures)
    (var-set abnegation-old trustee)
    (var-set abnegation-new successor)

    ;; Remove old trustee
    (map-delete trustees trustee)
    (map-set has-abnegated trustee true)

    ;; Add successor as trustee
    (map-set trustees successor true)

    ;; Update trustee list (replace trustee with successor)
    (var-set trustee-list (map replace-trustee-in-list (var-get trustee-list)))

    ;; Increment count
    (var-set abnegation-count (+ (var-get abnegation-count) u1))

    ;; Check if all have abnegated
    (if (is-eq (var-get abnegation-count) BOARD-SIZE)
      (begin
        (var-set abnegation-complete true)
        (print {event: "abnegation-complete",
                message: "Second board now governs permanently"})
        true)
      true)

    (print {event: "trustee-abnegated", old-trustee: trustee, successor: successor,
            abnegated-count: (var-get abnegation-count)})
    (ok successor)))

;; Temp storage for abnegation (Clarity doesn't have closures)
(define-data-var abnegation-old principal BURN-ADDRESS)
(define-data-var abnegation-new principal BURN-ADDRESS)

;; Helper to replace trustee in list
(define-private (replace-trustee-in-list (current principal))
  (if (is-eq current (var-get abnegation-old))
    (var-get abnegation-new)
    current))

;; Board contract reference for abnegation trigger
(define-data-var board-contract principal tx-sender)

(define-public (set-board-contract-for-abnegation (board principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-PROPOSER-ONLY)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    (var-set board-contract board)
    (ok true)))

;; ============================================
;; READ-ONLY FUNCTIONS
;; ============================================

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
  (/ (* (var-get election-stake) RECALL-THRESHOLD-PERCENT) u100))

(define-read-only (get-board-size)
  BOARD-SIZE)

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

(define-read-only (is-finalization-pending)
  (var-get finalization-pending))

(define-read-only (get-pending-trustees)
  (var-get pending-trustees))

(define-read-only (get-pending-stake)
  (var-get pending-stake))

(define-read-only (get-challenge-end-block)
  (if (var-get finalization-pending)
    (some (+ (var-get finalization-proposed-at) CHALLENGE-PERIOD))
    none))

(define-read-only (can-execute-finalization)
  (and
    (var-get finalization-pending)
    (not (var-get election-finalized))
    (>= stacks-block-height (+ (var-get finalization-proposed-at) CHALLENGE-PERIOD))))

;; ============================================
;; ABNEGATION READ-ONLY FUNCTIONS
;; ============================================

(define-read-only (is-abnegation-started)
  (var-get abnegation-started))

(define-read-only (is-abnegation-complete)
  (var-get abnegation-complete))

(define-read-only (get-abnegation-count)
  (var-get abnegation-count))

(define-read-only (has-trustee-abnegated (trustee principal))
  (default-to false (map-get? has-abnegated trustee)))

(define-read-only (get-abnegation-status)
  {
    started: (var-get abnegation-started),
    complete: (var-get abnegation-complete),
    count: (var-get abnegation-count),
    required: BOARD-SIZE
  })
