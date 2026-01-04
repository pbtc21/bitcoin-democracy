;; treasury.clar
;; City Treasury - accepts sBTC deposits, mints governance tokens
;; 1 sBTC = 1,000,000 CityBTC tokens (micro-units)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-paused (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-transfer-failed (err u104))
(define-constant err-not-authorized (err u105))

;; Conversion rate: 1 sBTC (8 decimals) = 1,000,000 tokens (6 decimals)
;; sBTC has 8 decimals, our token has 6
;; 1 sBTC = 100,000,000 sats = 1,000,000 CityBTC
(define-constant sbtc-to-token-multiplier u10000)

;; State
(define-data-var paused bool false)
(define-data-var total-deposits uint u0)

;; Track individual contributions
(define-map contributions principal uint)

;; Authorized council for withdrawals
(define-data-var council-contract principal contract-owner)

;; sBTC contract reference (testnet)
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

;; Council-authorized treasury spend
(define-public (council-spend (amount uint) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender (var-get council-contract)) err-not-authorized)
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)

    ;; Transfer sBTC from treasury to recipient
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender recipient memo)))

    (print {event: "council-spend", amount: amount, recipient: recipient})
    (ok true)))

;; Admin Functions

;; Emergency pause
(define-public (set-paused (is-paused bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set paused is-paused)
    (print {event: "pause-toggled", paused: is-paused})
    (ok true)))

;; Set council contract for authorized spending
(define-public (set-council-contract (council principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set council-contract council)
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

(define-read-only (is-paused)
  (var-get paused))

(define-read-only (get-council-contract)
  (var-get council-contract))

(define-read-only (calculate-tokens-for-deposit (sbtc-amount uint))
  (* sbtc-amount sbtc-to-token-multiplier))

(define-read-only (calculate-sbtc-for-withdrawal (token-amount uint))
  (/ token-amount sbtc-to-token-multiplier))
