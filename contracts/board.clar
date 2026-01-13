;; board.clar
;; Board of Trustees - Passive oversight for Bitzion governance
;;
;; Powers (from Yarvin's essay):
;; - Hire/fire the coordinator
;; - Approve regular tax (ongoing dilution rate)
;; - Approve special tax (one-time dilution)
;; - NO operational decisions, NO per-spend approval
;;
;; The coordinator handles all operational matters including treasury spending

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-trustee (err u101))
(define-constant err-proposal-not-found (err u102))
(define-constant err-already-voted (err u103))
(define-constant err-proposal-executed (err u104))
(define-constant err-threshold-not-met (err u105))
(define-constant err-invalid-proposal-type (err u106))
(define-constant err-no-coordinator (err u107))
(define-constant err-proposal-expired (err u108))

;; 16/30 majority required (53%+)
(define-constant approval-threshold u16)
(define-constant board-size u30)

;; Proposals expire after ~7 days (1008 blocks at 10 min/block)
(define-constant proposal-expiry-blocks u1008)

;; Proposal types
(define-constant proposal-type-coordinator u1)
(define-constant proposal-type-regular-tax u2)
(define-constant proposal-type-special-tax u3)

;; State
(define-data-var proposal-nonce uint u0)
(define-data-var coordinator (optional principal) none)
(define-data-var regular-tax-rate uint u50) ;; 0.5% annual (50 basis points)

;; Proposals
(define-map proposals
  uint
  {
    proposer: principal,
    proposal-type: uint,
    target: principal,        ;; For coordinator: new coordinator. For tax: recipient (treasury)
    amount: uint,             ;; For special tax: amount to mint. For regular: new rate
    memo: (optional (buff 256)),
    executed: bool,
    approval-count: uint,
    created-at: uint,         ;; Block height when created
    expires-at: uint          ;; Block height when expires
  })

;; Votes on proposals
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  bool)

;; Check if caller is a trustee
(define-private (is-trustee-caller)
  (contract-call? .hyperelection is-trustee tx-sender))

;; Propose new coordinator
(define-public (propose-coordinator (candidate principal))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) err-not-trustee)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: proposal-type-coordinator,
      target: candidate,
      amount: u0,
      memo: none,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now proposal-expiry-blocks)
    })

    ;; Proposer automatically votes yes
    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-coordinator", id: proposal-id, proposer: proposer, candidate: candidate})
    (ok proposal-id)))

;; Propose regular tax rate change (basis points, 100 = 1%)
(define-public (propose-regular-tax (new-rate uint))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) err-not-trustee)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: proposal-type-regular-tax,
      target: tx-sender, ;; Not used
      amount: new-rate,
      memo: none,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now proposal-expiry-blocks)
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-regular-tax", id: proposal-id, proposer: proposer, rate: new-rate})
    (ok proposal-id)))

;; Propose special tax (one-time dilution)
(define-public (propose-special-tax (amount uint) (memo (optional (buff 256))))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
      (now stacks-block-height)
    )
    (asserts! (is-trustee-caller) err-not-trustee)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: proposal-type-special-tax,
      target: tx-sender, ;; Not used, mints to treasury
      amount: amount,
      memo: memo,
      executed: false,
      approval-count: u1,
      created-at: now,
      expires-at: (+ now proposal-expiry-blocks)
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-special-tax", id: proposal-id, proposer: proposer, amount: amount})
    (ok proposal-id)))

;; Vote on any proposal
(define-public (vote (proposal-id uint))
  (let
    (
      (voter tx-sender)
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-trustee-caller) err-not-trustee)
    (asserts! (is-none (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})) err-already-voted)
    (asserts! (not (get executed proposal)) err-proposal-executed)
    (asserts! (<= stacks-block-height (get expires-at proposal)) err-proposal-expired)

    (map-set proposal-votes {proposal-id: proposal-id, voter: voter} true)
    (map-set proposals proposal-id
      (merge proposal {approval-count: (+ (get approval-count proposal) u1)}))

    (print {event: "vote", proposal-id: proposal-id, voter: voter, new-count: (+ (get approval-count proposal) u1)})
    (ok true)))

;; Execute coordinator appointment
(define-public (execute-coordinator (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-eq (get proposal-type proposal) proposal-type-coordinator) err-invalid-proposal-type)
    (asserts! (not (get executed proposal)) err-proposal-executed)
    (asserts! (>= (get approval-count proposal) approval-threshold) err-threshold-not-met)
    (asserts! (<= stacks-block-height (get expires-at proposal)) err-proposal-expired)

    ;; Mark executed
    (map-set proposals proposal-id (merge proposal {executed: true}))

    ;; Set new coordinator
    (var-set coordinator (some (get target proposal)))

    ;; Update treasury with new coordinator
    (try! (contract-call? .treasury set-coordinator (get target proposal)))

    (print {event: "coordinator-appointed", proposal-id: proposal-id, coordinator: (get target proposal)})
    (ok true)))

;; Execute regular tax rate change
(define-public (execute-regular-tax (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-eq (get proposal-type proposal) proposal-type-regular-tax) err-invalid-proposal-type)
    (asserts! (not (get executed proposal)) err-proposal-executed)
    (asserts! (>= (get approval-count proposal) approval-threshold) err-threshold-not-met)
    (asserts! (<= stacks-block-height (get expires-at proposal)) err-proposal-expired)

    ;; Mark executed
    (map-set proposals proposal-id (merge proposal {executed: true}))

    ;; Set new rate
    (var-set regular-tax-rate (get amount proposal))

    (print {event: "regular-tax-updated", proposal-id: proposal-id, new-rate: (get amount proposal)})
    (ok true)))

;; Execute special tax (mint tokens to treasury)
(define-public (execute-special-tax (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-eq (get proposal-type proposal) proposal-type-special-tax) err-invalid-proposal-type)
    (asserts! (not (get executed proposal)) err-proposal-executed)
    (asserts! (>= (get approval-count proposal) approval-threshold) err-threshold-not-met)
    (asserts! (<= stacks-block-height (get expires-at proposal)) err-proposal-expired)

    ;; Mark executed
    (map-set proposals proposal-id (merge proposal {executed: true}))

    ;; Mint tokens to treasury (dilution)
    (try! (contract-call? .treasury board-dilute (get amount proposal)))

    (print {event: "special-tax-executed", proposal-id: proposal-id, amount: (get amount proposal)})
    (ok true)))

;; Read-only functions

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
  approval-threshold)

(define-read-only (is-proposal-approved (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (>= (get approval-count proposal) approval-threshold)
    false))

(define-read-only (can-execute (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and
      (>= (get approval-count proposal) approval-threshold)
      (not (get executed proposal)))
    false))
