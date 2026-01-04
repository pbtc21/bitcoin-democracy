;; treasury.clar
;; City Treasury - Bitzion model
;;
;; - Accepts sBTC deposits, mints governance tokens
;; - Coordinator has DIRECT spending authority (no voting per spend)
;; - Board can dilute (mint tokens) as "tax"
;; - Hodlers can deposit/withdraw freely

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-paused (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-transfer-failed (err u104))
(define-constant err-not-coordinator (err u105))
(define-constant err-not-board (err u106))
(define-constant err-no-coordinator (err u107))

;; Conversion rate: 1 sBTC (8 decimals) = 1,000,000 tokens (6 decimals)
(define-constant sbtc-to-token-multiplier u10000)

;; State
(define-data-var paused bool false)
(define-data-var total-deposits uint u0)

;; Track individual contributions
(define-map contributions principal uint)

;; Coordinator - has direct spending authority
(define-data-var coordinator (optional principal) none)

;; Board contract - can dilute
(define-data-var board-contract principal contract-owner)

;; sBTC contract reference
(define-data-var sbtc-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.sbtc-token)

;; Deposit sBTC and receive governance tokens
(define-public (deposit (amount uint))
  (let
    (
      (depositor tx-sender)
      (token-amount (* amount sbtc-to-token-multiplier))
      (current-contribution (default-to u0 (map-get? contributions depositor)))
    )
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)

    ;; Transfer sBTC from depositor to treasury
    (try! (contract-call? .mock-sbtc transfer amount depositor (as-contract tx-sender) none))

    ;; Mint governance tokens to depositor
    (try! (contract-call? .city-btc-token mint token-amount depositor))

    ;; Update contribution tracking
    (map-set contributions depositor (+ current-contribution amount))
    (var-set total-deposits (+ (var-get total-deposits) amount))

    (print {event: "deposit", depositor: depositor, sbtc-amount: amount, tokens-minted: token-amount})
    (ok token-amount)))

;; Withdraw sBTC by burning governance tokens
(define-public (withdraw (token-amount uint))
  (let
    (
      (withdrawer tx-sender)
      (sbtc-amount (/ token-amount sbtc-to-token-multiplier))
      (current-contribution (default-to u0 (map-get? contributions withdrawer)))
    )
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> token-amount u0) err-invalid-amount)
    (asserts! (>= current-contribution sbtc-amount) err-insufficient-balance)

    ;; Burn governance tokens
    (try! (contract-call? .city-btc-token burn token-amount withdrawer))

    ;; Transfer sBTC back to withdrawer
    (try! (as-contract (contract-call? .mock-sbtc transfer sbtc-amount tx-sender withdrawer none)))

    ;; Update contribution tracking
    (map-set contributions withdrawer (- current-contribution sbtc-amount))
    (var-set total-deposits (- (var-get total-deposits) sbtc-amount))

    (print {event: "withdraw", withdrawer: withdrawer, tokens-burned: token-amount, sbtc-returned: sbtc-amount})
    (ok sbtc-amount)))

;; Coordinator direct spend - NO voting required
;; The coordinator has full authority over treasury spending
(define-public (coordinator-spend (amount uint) (recipient principal) (memo (optional (buff 34))))
  (let
    (
      (current-coordinator (unwrap! (var-get coordinator) err-no-coordinator))
    )
    (asserts! (is-eq tx-sender current-coordinator) err-not-coordinator)
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)

    ;; Transfer sBTC from treasury to recipient
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender recipient memo)))

    (print {event: "coordinator-spend", coordinator: current-coordinator, amount: amount, recipient: recipient})
    (ok true)))

;; Board dilution - mint new tokens (tax)
;; Only callable by board contract after approval
(define-public (board-dilute (amount uint))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) err-not-board)
    (asserts! (> amount u0) err-invalid-amount)

    ;; Mint tokens to treasury itself (for coordinator to spend)
    (try! (contract-call? .city-btc-token mint amount (as-contract tx-sender)))

    (print {event: "board-dilution", amount: amount})
    (ok true)))

;; Admin Functions

;; Set coordinator - only callable by board contract
(define-public (set-coordinator (new-coordinator principal))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) err-not-board)
    (var-set coordinator (some new-coordinator))
    (print {event: "coordinator-set", coordinator: new-coordinator})
    (ok true)))

;; Set board contract (one-time setup)
(define-public (set-board-contract (board principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set board-contract board)
    (ok true)))

;; Emergency pause
(define-public (set-paused (is-paused bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set paused is-paused)
    (print {event: "pause-toggled", paused: is-paused})
    (ok true)))

;; Set sBTC contract reference
(define-public (set-sbtc-contract (sbtc principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set sbtc-contract sbtc)
    (ok true)))

;; Read-only functions

(define-read-only (get-contribution (account principal))
  (default-to u0 (map-get? contributions account)))

(define-read-only (get-total-deposits)
  (var-get total-deposits))

(define-read-only (get-treasury-balance)
  (contract-call? .mock-sbtc get-balance (as-contract tx-sender)))

(define-read-only (get-paused)
  (var-get paused))

(define-read-only (get-coordinator)
  (var-get coordinator))

(define-read-only (get-board-contract)
  (var-get board-contract))

(define-read-only (calculate-tokens-for-deposit (sbtc-amount uint))
  (* sbtc-amount sbtc-to-token-multiplier))

(define-read-only (calculate-sbtc-for-withdrawal (token-amount uint))
  (/ token-amount sbtc-to-token-multiplier))
