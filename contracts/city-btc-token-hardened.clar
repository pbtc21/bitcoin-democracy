;; city-btc-token-hardened.clar
;; Censorship-resistant SIP-010 Governance Token
;; NO admin functions after burn - fully autonomous
;;
;; 1 sBTC deposited = 1,000,000 tokens (micro-units for precision)

(impl-trait .sip-010-trait.sip-010-trait)

;; Constants
(define-constant ERR-NOT-TOKEN-OWNER (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-METADATA-LOCKED (err u104))
(define-constant ERR-NOT-MINTER (err u105))
(define-constant ERR-ADMIN-BURNED (err u120))
(define-constant ERR-NOT-OWNER (err u121))
(define-constant ERR-MINTER-ALREADY-SET (err u122))

;; Burn address
(define-constant BURN-ADDRESS 'SP000000000000000000002Q6VF78)

;; ============================================
;; ADMIN STATE (burnable)
;; ============================================

(define-data-var contract-owner principal tx-sender)
(define-data-var admin-burned bool false)

;; ============================================
;; TOKEN STATE
;; ============================================

(define-fungible-token city-btc)

;; Token metadata (locked after initialization)
(define-data-var token-name (string-ascii 32) "CityBTC")
(define-data-var token-symbol (string-ascii 10) "CITYBTC")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var token-decimals uint u6)
(define-data-var metadata-locked bool false)

;; Authorized minter (treasury contract) - set once, never changes
(define-data-var authorized-minter principal tx-sender)
(define-data-var minter-set bool false)

;; ============================================
;; ADMIN BURN (call once, irreversible)
;; ============================================

(define-public (burn-admin-forever)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    ;; Must set minter and lock metadata first
    (asserts! (var-get minter-set) ERR-NOT-MINTER)
    (asserts! (var-get metadata-locked) ERR-METADATA-LOCKED)

    (var-set admin-burned true)
    (var-set contract-owner BURN-ADDRESS)

    (print {event: "admin-burned-forever", block: stacks-block-height,
            message: "Token contract is now unstoppable"})
    (ok true)))

(define-read-only (is-admin-burned)
  (var-get admin-burned))

;; ============================================
;; SIP-010 READ-ONLY FUNCTIONS
;; ============================================

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

;; ============================================
;; SIP-010 TRANSFER (always permissionless)
;; ============================================

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-TOKEN-OWNER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-transfer? city-btc amount sender recipient))
    (match memo to-print (print to-print) 0x)
    (ok true)))

;; ============================================
;; MINT/BURN (treasury only)
;; ============================================

;; Mint tokens - only authorized minter (treasury)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq contract-caller (var-get authorized-minter)) ERR-NOT-MINTER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ft-mint? city-btc amount recipient)))

;; Burn tokens - only treasury or token holder can burn
(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (or (is-eq tx-sender owner) (is-eq contract-caller (var-get authorized-minter))) ERR-NOT-TOKEN-OWNER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ft-burn? city-btc amount owner)))

;; ============================================
;; SETUP (only before burn)
;; ============================================

;; Set authorized minter (one-time only, cannot change after)
(define-public (set-authorized-minter (new-minter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    (asserts! (not (var-get minter-set)) ERR-MINTER-ALREADY-SET)

    (var-set authorized-minter new-minter)
    (var-set minter-set true)

    (print {event: "minter-set", minter: new-minter})
    (ok true)))

;; Initialize token metadata (one-time only)
(define-public (initialize (name (string-ascii 32)) (symbol (string-ascii 10)) (uri (optional (string-utf8 256))))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    (asserts! (not (var-get metadata-locked)) ERR-METADATA-LOCKED)

    (var-set token-name name)
    (var-set token-symbol symbol)
    (var-set token-uri uri)
    (var-set metadata-locked true)

    (print {event: "token-initialized", name: name, symbol: symbol})
    (ok true)))

;; ============================================
;; READ-ONLY HELPERS
;; ============================================

(define-read-only (get-authorized-minter)
  (var-get authorized-minter))

(define-read-only (is-minter-set)
  (var-get minter-set))

(define-read-only (is-metadata-locked)
  (var-get metadata-locked))
