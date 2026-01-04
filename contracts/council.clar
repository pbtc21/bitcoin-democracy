;; council.clar
;; City Council - Multisig governance for treasury actions
;; Elected council members propose and approve spending

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-council-member (err u101))
(define-constant err-proposal-not-found (err u102))
(define-constant err-already-voted (err u103))
(define-constant err-proposal-expired (err u104))
(define-constant err-proposal-not-approved (err u105))
(define-constant err-proposal-already-executed (err u106))
(define-constant err-invalid-proposal-type (err u107))
(define-constant err-threshold-not-met (err u108))
(define-constant err-proposal-still-active (err u109))

;; Configuration
(define-constant approval-threshold u3) ;; 3-of-5 required
(define-constant proposal-duration u144) ;; ~24 hours in blocks

;; Proposal types
(define-constant proposal-type-spend u1)
(define-constant proposal-type-appoint-coordinator u2)
(define-constant proposal-type-config-change u3)

;; State
(define-data-var proposal-nonce uint u0)
(define-data-var coordinator (optional principal) none)

;; Proposals
(define-map proposals
  uint
  {
    proposer: principal,
    proposal-type: uint,
    target: principal,
    amount: uint,
    memo: (optional (buff 256)),
    created-at: uint,
    executed: bool,
    approval-count: uint
  })

;; Votes on proposals
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  bool)

;; Create a spending proposal
(define-public (propose-spend (recipient principal) (amount uint) (memo (optional (buff 256))))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
    )
    (asserts! (unwrap! (contract-call? .election is-council-member proposer) err-not-council-member)
              err-not-council-member)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: proposal-type-spend,
      target: recipient,
      amount: amount,
      memo: memo,
      created-at: block-height,
      executed: false,
      approval-count: u1
    })

    ;; Proposer automatically votes yes
    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)

    (var-set proposal-nonce (+ proposal-id u1))
    (print {event: "proposal-created", id: proposal-id, type: "spend", proposer: proposer, recipient: recipient, amount: amount})
    (ok proposal-id)))

;; Propose appointing a coordinator
(define-public (propose-coordinator (new-coordinator principal))
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get proposal-nonce))
    )
    (asserts! (unwrap! (contract-call? .election is-council-member proposer) err-not-council-member)
              err-not-council-member)

    (map-set proposals proposal-id {
      proposer: proposer,
      proposal-type: proposal-type-appoint-coordinator,
      target: new-coordinator,
      amount: u0,
      memo: none,
      created-at: block-height,
      executed: false,
      approval-count: u1
    })

    (map-set proposal-votes {proposal-id: proposal-id, voter: proposer} true)
    (var-set proposal-nonce (+ proposal-id u1))

    (print {event: "proposal-created", id: proposal-id, type: "coordinator", proposer: proposer, coordinator: new-coordinator})
    (ok proposal-id)))

;; Vote on a proposal
(define-public (vote (proposal-id uint))
  (let
    (
      (voter tx-sender)
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (unwrap! (contract-call? .election is-council-member voter) err-not-council-member)
              err-not-council-member)
    (asserts! (is-none (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})) err-already-voted)
    (asserts! (<= (- block-height (get created-at proposal)) proposal-duration) err-proposal-expired)
    (asserts! (not (get executed proposal)) err-proposal-already-executed)

    (map-set proposal-votes {proposal-id: proposal-id, voter: voter} true)
    (map-set proposals proposal-id
      (merge proposal {approval-count: (+ (get approval-count proposal) u1)}))

    (print {event: "vote-cast", proposal-id: proposal-id, voter: voter, new-count: (+ (get approval-count proposal) u1)})
    (ok true)))

;; Execute an approved spending proposal
(define-public (execute-spend (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-eq (get proposal-type proposal) proposal-type-spend) err-invalid-proposal-type)
    (asserts! (not (get executed proposal)) err-proposal-already-executed)
    (asserts! (>= (get approval-count proposal) approval-threshold) err-threshold-not-met)

    ;; Mark as executed
    (map-set proposals proposal-id (merge proposal {executed: true}))

    ;; Execute treasury spend
    (try! (contract-call? .treasury council-spend
      (get amount proposal)
      (get target proposal)
      none))

    (print {event: "spend-executed", proposal-id: proposal-id, recipient: (get target proposal), amount: (get amount proposal)})
    (ok true)))

;; Execute coordinator appointment
(define-public (execute-coordinator (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (is-eq (get proposal-type proposal) proposal-type-appoint-coordinator) err-invalid-proposal-type)
    (asserts! (not (get executed proposal)) err-proposal-already-executed)
    (asserts! (>= (get approval-count proposal) approval-threshold) err-threshold-not-met)

    ;; Mark as executed
    (map-set proposals proposal-id (merge proposal {executed: true}))

    ;; Appoint coordinator
    (var-set coordinator (some (get target proposal)))

    (print {event: "coordinator-appointed", proposal-id: proposal-id, coordinator: (get target proposal)})
    (ok true)))

;; Cancel an expired proposal (cleanup)
(define-public (cancel-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
    )
    (asserts! (> (- block-height (get created-at proposal)) proposal-duration) err-proposal-still-active)
    (asserts! (not (get executed proposal)) err-proposal-already-executed)

    (map-delete proposals proposal-id)
    (print {event: "proposal-cancelled", proposal-id: proposal-id})
    (ok true)))

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes {proposal-id: proposal-id, voter: voter}))

(define-read-only (get-coordinator)
  (var-get coordinator))

(define-read-only (get-proposal-nonce)
  (var-get proposal-nonce))

(define-read-only (get-approval-threshold)
  approval-threshold)

(define-read-only (get-proposal-duration)
  proposal-duration)

(define-read-only (is-proposal-approved (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (>= (get approval-count proposal) approval-threshold)
    false))

(define-read-only (is-proposal-expired (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (> (- block-height (get created-at proposal)) proposal-duration)
    true))

(define-read-only (can-execute (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and
      (>= (get approval-count proposal) approval-threshold)
      (not (get executed proposal))
      (<= (- block-height (get created-at proposal)) proposal-duration))
    false))
