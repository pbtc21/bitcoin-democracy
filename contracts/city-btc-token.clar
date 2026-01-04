;; city-btc-token.clar
;; SIP-010 Fungible Token for City Governance
;; Format: [City]BTC (e.g., MiamiBTC)
;; 1 sBTC deposited = 1,000,000 tokens (micro-units for precision)

(impl-trait .sip-010-trait.sip-010-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))

;; Token configuration - set by factory on deployment
(define-data-var token-name (string-ascii 32) "CityBTC")
(define-data-var token-symbol (string-ascii 10) "CITYBTC")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var token-decimals uint u6)

;; Authorized minter (treasury contract)
(define-data-var authorized-minter principal contract-owner)

;; SIP-010 Functions

(define-read-only (get-name)
  (ok (var-get token-name)))

(define-read-only (get-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok (var-get token-decimals)))

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance city-btc account)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply city-btc)))

(define-read-only (get-token-uri)
  (ok (var-get token-uri)))

;; Transfer tokens
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (try! (ft-transfer? city-btc amount sender recipient))
    (match memo to-print (print to-print) 0x)
    (ok true)))

;; Mint tokens - only authorized minter (treasury)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq contract-caller (var-get authorized-minter)) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (ft-mint? city-btc amount recipient)))

;; Burn tokens - only treasury or token holder can burn
(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (or (is-eq tx-sender owner) (is-eq contract-caller (var-get authorized-minter))) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (ft-burn? city-btc amount owner)))

;; Admin Functions

;; Set authorized minter (treasury contract)
(define-public (set-authorized-minter (new-minter principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set authorized-minter new-minter)
    (ok true)))

;; Initialize token metadata (called by factory)
(define-public (initialize (name (string-ascii 32)) (symbol (string-ascii 10)) (uri (optional (string-utf8 256))))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set token-name name)
    (var-set token-symbol symbol)
    (var-set token-uri uri)
    (ok true)))

;; Read-only helpers

(define-read-only (get-authorized-minter)
  (var-get authorized-minter))

(define-read-only (get-contract-owner)
  contract-owner)

;; Define the fungible token
(define-fungible-token city-btc)
