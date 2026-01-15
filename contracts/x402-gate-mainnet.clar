;; x402-gate.clar (MAINNET)
;; Micropayment gate for Stacks Intelligence API
;; Payments in sBTC (Bitcoin on Stacks)
;;
;; AIs pay sBTC per request, receive access token
;; Server verifies payment before returning data

(define-constant ERR-INSUFFICIENT-PAYMENT (err u100))
(define-constant ERR-ALREADY-USED (err u101))
(define-constant ERR-TRANSFER-FAILED (err u102))

;; Real sBTC contract (mainnet)
(define-constant SBTC-CONTRACT 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token)

;; Price per request in sats (100 sats = ~$0.10 at $100k BTC)
(define-data-var price-per-request uint u100)

;; Treasury receives payments
(define-data-var treasury principal tx-sender)

;; Track used access tokens to prevent replay
(define-map used-tokens (buff 32) bool)

;; Track bulk credits per address
(define-map credits principal uint)

;; Nonce for generating unique access tokens
(define-data-var token-nonce uint u0)

;; Pay for API access with sBTC - returns access token
(define-public (pay-for-access)
  (let
    (
      (price (var-get price-per-request))
      (payer tx-sender)
      (nonce (var-get token-nonce))
      (access-token (keccak256 (concat
        (concat (unwrap-panic (to-consensus-buff? payer)) (unwrap-panic (to-consensus-buff? nonce)))
        (unwrap-panic (to-consensus-buff? stacks-block-height)))))
    )
    ;; Transfer sBTC to treasury
    (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer price payer (var-get treasury) none) ERR-TRANSFER-FAILED)

    ;; Increment nonce
    (var-set token-nonce (+ nonce u1))

    ;; Emit access token in event
    (print {
      event: "access-granted",
      payer: payer,
      token: access-token,
      price-sats: price,
      block: stacks-block-height,
      expires: (+ stacks-block-height u144)
    })

    (ok access-token)))

;; Bulk purchase - pay for multiple requests at discount (10% off)
(define-public (pay-bulk (count uint))
  (let
    (
      (base-price (var-get price-per-request))
      (bulk-price (/ (* base-price count u90) u100))
      (payer tx-sender)
      (nonce (var-get token-nonce))
      (access-token (keccak256 (concat
        (concat (unwrap-panic (to-consensus-buff? payer)) (unwrap-panic (to-consensus-buff? nonce)))
        (unwrap-panic (to-consensus-buff? stacks-block-height)))))
    )
    ;; Transfer sBTC
    (unwrap! (contract-call? 'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token transfer bulk-price payer (var-get treasury) none) ERR-TRANSFER-FAILED)

    ;; Grant credits
    (map-set credits payer (+ (default-to u0 (map-get? credits payer)) count))

    (var-set token-nonce (+ nonce u1))

    (print {
      event: "bulk-access-granted",
      payer: payer,
      token: access-token,
      requests: count,
      total-sats: bulk-price,
      block: stacks-block-height,
      expires: (+ stacks-block-height u1008)
    })

    (ok access-token)))

;; Use a credit (for bulk purchasers)
(define-public (use-credit)
  (let
    (
      (user tx-sender)
      (current-credits (default-to u0 (map-get? credits user)))
      (nonce (var-get token-nonce))
      (access-token (keccak256 (concat
        (concat (unwrap-panic (to-consensus-buff? user)) (unwrap-panic (to-consensus-buff? nonce)))
        (unwrap-panic (to-consensus-buff? stacks-block-height)))))
    )
    (asserts! (> current-credits u0) ERR-INSUFFICIENT-PAYMENT)

    (map-set credits user (- current-credits u1))
    (var-set token-nonce (+ nonce u1))

    (print {
      event: "credit-used",
      user: user,
      token: access-token,
      remaining-credits: (- current-credits u1),
      block: stacks-block-height,
      expires: (+ stacks-block-height u144)
    })

    (ok access-token)))

;; Server calls this to mark token as used
(define-public (mark-used (token (buff 32)))
  (begin
    (asserts! (is-eq tx-sender (var-get treasury)) ERR-INSUFFICIENT-PAYMENT)
    (asserts! (is-none (map-get? used-tokens token)) ERR-ALREADY-USED)
    (map-set used-tokens token true)
    (ok true)))

;; Read-only functions
(define-read-only (is-token-used (token (buff 32)))
  (default-to false (map-get? used-tokens token)))

(define-read-only (get-credits (user principal))
  (default-to u0 (map-get? credits user)))

(define-read-only (get-price)
  (var-get price-per-request))

(define-read-only (get-treasury)
  (var-get treasury))

(define-read-only (get-price-info)
  {
    per-request-sats: (var-get price-per-request),
    bulk-discount-percent: u10,
    currency: "sBTC"
  })

;; Admin functions
(define-public (set-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get treasury)) ERR-INSUFFICIENT-PAYMENT)
    (var-set price-per-request new-price)
    (ok true)))

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender (var-get treasury)) ERR-INSUFFICIENT-PAYMENT)
    (var-set treasury new-treasury)
    (ok true)))
