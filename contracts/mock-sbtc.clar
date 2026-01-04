;; mock-sbtc.clar
;; Mock sBTC token for testnet/devnet testing
;; Implements SIP-010 standard

(impl-trait .sip-010-trait.sip-010-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))

;; SIP-010 Functions

(define-read-only (get-name)
  (ok "Mock sBTC"))

(define-read-only (get-symbol)
  (ok "sBTC"))

(define-read-only (get-decimals)
  (ok u8))

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance mock-sbtc account)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply mock-sbtc)))

(define-read-only (get-token-uri)
  (ok none))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-token-owner)
    (try! (ft-transfer? mock-sbtc amount sender recipient))
    (match memo to-print (print to-print) 0x)
    (ok true)))

;; Faucet for testing - anyone can mint mock sBTC
(define-public (faucet (amount uint) (recipient principal))
  (ft-mint? mock-sbtc amount recipient))

;; Define the fungible token
(define-fungible-token mock-sbtc)
