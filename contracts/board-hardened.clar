;; board-hardened.clar
;; Censorship-resistant Board of Trustees
;; NO admin functions after burn - fully autonomous
;;
;; Powers (from Yarvin's essay):
;; - Hire/fire the coordinator
;; - Approve regular tax (ongoing dilution rate)
;; - Approve special tax (one-time dilution)
;; - Set spending limits
;; - NO operational decisions, NO per-spend approval

;; Constants
(define-constant ERR-NOT-TRUSTEE (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-EXECUTED (err u104))
(define-constant ERR-THRESHOLD-NOT-MET (err u105))
(define-constant ERR-INVALID-PROPOSAL-TYPE (err u106))
(define-constant ERR-NO-COORDINATOR (err u107))
(define-constant ERR-PROPOSAL-EXPIRED (err u108))
(define-constant ERR-ADMIN-BURNED (err u120))
(define-constant ERR-NOT-BURNED-YET (err u121))

;; Burn address
(define-constant BURN-ADDRESS 'SP000000000000000000002Q6VF78)

;; 16/30 majority required (53%+)
(define-constant APPROVAL-THRESHOLD u16)
(define-constant BOARD-SIZE u30)

;; Proposals expire after ~7 days (1008 blocks at 10 min/block)
(define-constant PROPOSAL-EXPIRY-BLOCKS u1008)

;; Proposal types
(define-constant PROPOSAL-TYPE-COORDINATOR u1)
(define-constant PROPOSAL-TYPE-REGULAR-TAX u2)
(define-constant PROPOSAL-TYPE-SPECIAL-TAX u3)
(define-constant PROPOSAL-TYPE-SPEND-LIMIT u4)

;; ============================================
;; ADMIN STATE (burnable)
;; ============================================

(define-data-var contract-owner principal tx-sender)
(define-data-var admin-burned bool false)

;; ============================================
;; BOARD STATE
;; ============================================

(define-data-var proposal-nonce uint u0)
(define-data-var coordinator (optional principal) none)
(define-data-var regular-tax-rate uint u50) ;; 0.5% annual (50 basis points)
(define-data-var first-coordinator-appointed bool false) ;; Track if abnegation should trigger

;; Proposals
(define-map proposals
  uint
  {
    proposer: principal,
    proposal-type: uint,
    target: principal,
    amount: uint,
    memo: (optional (buff 256)),
    executed: bool,
    approval-count: uint,
    created-at: uint,
    expires-at: uint
  })

;; Votes on proposals
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  bool)

;; ============================================
;; ADMIN BURN (call once, irreversible)
;; ============================================

(define-public (burn-admin-forever)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-TRUSTEE)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)

    (var-set admin-burned true)
    (var-set contract-owner BURN-ADDRESS)

    (print {event: "admin-burned-forever", block: stacks-block-height,
            message: "Board contract is now unstoppable"})
    (ok true)))

(define-read-only (is-admin-burned)
  (var-get admin-burned))

;; ============================================
;; TRUSTEE CHECK (uses hyperelection-hardened)
;; ============================================

(define-private (is-trustee-caller)
  (contract-call? .hyperelection-hardened is-trustee tx-sender))

;; ============================================
;; PROPOSALS (trustee-only to propose)
;; ============================================

(define-public (propose-coordinator (candidate principal))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) ERR-NOT-TRUSTEE)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: PROPOSAL-TYPE-COORDINATOR,
      target: candidate,
      amount: u0,
      memo: none,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now PROPOSAL-EXPIRY-BLOCKS)
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-coordinator", id: proposal-id, proposer: proposer, candidate: candidate})
    (ok proposal-id)))

(define-public (propose-regular-tax (new-rate uint))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) ERR-NOT-TRUSTEE)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: PROPOSAL-TYPE-REGULAR-TAX,
      target: tx-sender,
      amount: new-rate,
      memo: none,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now PROPOSAL-EXPIRY-BLOCKS)
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-regular-tax", id: proposal-id, proposer: proposer, rate: new-rate})
    (ok proposal-id)))

(define-public (propose-special-tax (amount uint) (memo (optional (buff 256))))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) ERR-NOT-TRUSTEE)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: PROPOSAL-TYPE-SPECIAL-TAX,
      target: tx-sender,
      amount: amount,
      memo: memo,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now PROPOSAL-EXPIRY-BLOCKS)
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-special-tax", id: proposal-id, proposer: proposer, amount: amount})
    (ok proposal-id)))

(define-public (propose-spend-limit (new-limit uint))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) ERR-NOT-TRUSTEE)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: PROPOSAL-TYPE-SPEND-LIMIT,
      target: tx-sender,
      amount: new-limit,
      memo: none,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now PROPOSAL-EXPIRY-BLOCKS)
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-spend-limit", id: proposal-id, proposer: proposer, new-limit: new-limit})
    (ok proposal-id)))

;; ============================================
;; VOTING (trustee-only)
;; ============================================

(define-public (vote (proposal-id uint))
  (let
    (
      (voter tx-sender)
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-trustee-caller) ERR-NOT-TRUSTEE)
    (asserts! (is-none (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})) ERR-ALREADY-VOTED)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXECUTED)
    (asserts! (<= stacks-block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)

    (map-set proposal-votes {proposal-id: proposal-id, voter: voter} true)
    (map-set proposals proposal-id
      (merge proposal {approval-count: (+ (get approval-count proposal) u1)}))

    (print {event: "vote", proposal-id: proposal-id, voter: voter,
            new-count: (+ (get approval-count proposal) u1)})
    (ok true)))

;; ============================================
;; EXECUTION (permissionless if threshold met)
;; ============================================

;; ANYONE can execute if threshold met (permissionless)
(define-public (execute-coordinator (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
      (is-first (not (var-get first-coordinator-appointed)))
    )
    (asserts! (is-eq (get proposal-type proposal) PROPOSAL-TYPE-COORDINATOR) ERR-INVALID-PROPOSAL-TYPE)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXECUTED)
    (asserts! (>= (get approval-count proposal) APPROVAL-THRESHOLD) ERR-THRESHOLD-NOT-MET)
    (asserts! (<= stacks-block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)

    (map-set proposals proposal-id (merge proposal {executed: true}))

    (var-set coordinator (some (get target proposal)))

    ;; Update treasury with new coordinator
    (try! (contract-call? .treasury-hardened set-coordinator (get target proposal)))

    ;; Trigger initial abnegation if this is the FIRST coordinator (Yarvin's resignation ritual)
    (if is-first
      (begin
        (var-set first-coordinator-appointed true)
        (try! (contract-call? .hyperelection-hardened start-abnegation))
        (print {event: "abnegation-triggered",
                message: "Initial trustees must now resign to successors"})
        true)
      true)

    (print {event: "coordinator-appointed", proposal-id: proposal-id,
            coordinator: (get target proposal), executed-by: tx-sender,
            first-coordinator: is-first})
    (ok true)))

(define-public (execute-regular-tax (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-eq (get proposal-type proposal) PROPOSAL-TYPE-REGULAR-TAX) ERR-INVALID-PROPOSAL-TYPE)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXECUTED)
    (asserts! (>= (get approval-count proposal) APPROVAL-THRESHOLD) ERR-THRESHOLD-NOT-MET)
    (asserts! (<= stacks-block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)

    (map-set proposals proposal-id (merge proposal {executed: true}))

    (var-set regular-tax-rate (get amount proposal))

    (print {event: "regular-tax-updated", proposal-id: proposal-id,
            new-rate: (get amount proposal), executed-by: tx-sender})
    (ok true)))

(define-public (execute-special-tax (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-eq (get proposal-type proposal) PROPOSAL-TYPE-SPECIAL-TAX) ERR-INVALID-PROPOSAL-TYPE)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXECUTED)
    (asserts! (>= (get approval-count proposal) APPROVAL-THRESHOLD) ERR-THRESHOLD-NOT-MET)
    (asserts! (<= stacks-block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)

    (map-set proposals proposal-id (merge proposal {executed: true}))

    ;; Mint tokens to treasury (dilution)
    (try! (contract-call? .treasury-hardened board-dilute (get amount proposal)))

    (print {event: "special-tax-executed", proposal-id: proposal-id,
            amount: (get amount proposal), executed-by: tx-sender})
    (ok true)))

(define-public (execute-spend-limit (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-eq (get proposal-type proposal) PROPOSAL-TYPE-SPEND-LIMIT) ERR-INVALID-PROPOSAL-TYPE)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXECUTED)
    (asserts! (>= (get approval-count proposal) APPROVAL-THRESHOLD) ERR-THRESHOLD-NOT-MET)
    (asserts! (<= stacks-block-height (get expires-at proposal)) ERR-PROPOSAL-EXPIRED)

    (map-set proposals proposal-id (merge proposal {executed: true}))

    (try! (contract-call? .treasury-hardened set-daily-limit (get amount proposal)))

    (print {event: "spend-limit-updated", proposal-id: proposal-id,
            new-limit: (get amount proposal), executed-by: tx-sender})
    (ok true)))

;; ============================================
;; READ-ONLY FUNCTIONS
;; ============================================

(define-read-only (get-coordinator)
  (var-get coordinator))

(define-read-only (get-regular-tax-rate)
  (var-get regular-tax-rate))

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes {proposal-id: proposal-id, voter: voter}))

(define-read-only (get-proposal-nonce)
  (var-get proposal-nonce))

(define-read-only (get-approval-threshold)
  APPROVAL-THRESHOLD)

(define-read-only (is-proposal-approved (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (>= (get approval-count proposal) APPROVAL-THRESHOLD)
    false))

(define-read-only (can-execute (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and
      (>= (get approval-count proposal) APPROVAL-THRESHOLD)
      (not (get executed proposal))
      (<= stacks-block-height (get expires-at proposal)))
    false))

(define-read-only (is-first-coordinator-appointed)
  (var-get first-coordinator-appointed))
