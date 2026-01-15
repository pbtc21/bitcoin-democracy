;; city-key-reveal.clar
;; Secure handoff of trustee keys to city election winners
;;
;; Flow:
;; 1. City elections determine winners (off-chain or separate contract)
;; 2. Owner encrypts location text with winner's public key (off-chain)
;; 3. Owner stores encrypted blob on-chain via set-winner()
;; 4. Winner calls reveal() - contract emits encrypted blob in event
;; 5. Winner decrypts locally with their private key - gets key location
;; 6. Winner retrieves key - calls abnegate() on hyperelection

;; Constants
(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-NOT-WINNER (err u101))
(define-constant ERR-ALREADY-REVEALED (err u102))
(define-constant ERR-CITY-NOT-SET (err u103))
(define-constant ERR-INVALID-CITY (err u104))
(define-constant ERR-ALREADY-SET (err u105))

(define-constant BOARD-SIZE u30)

;; Owner (can be burned after all cities set)
(define-data-var contract-owner principal tx-sender)
(define-data-var owner-burned bool false)

;; City data
;; encrypted-location: ECIES ciphertext (only winner can decrypt)
(define-map city-data
  uint  ;; city-id (0-29)
  {
    winner: principal,
    encrypted-location: (buff 512),
    revealed: bool,
    city-name: (string-ascii 32)
  })

;; Track setup progress
(define-data-var cities-configured uint u0)

;; ============================================
;; OWNER FUNCTIONS
;; ============================================

;; Set winner and their encrypted location text
;; Call this after each city election is decided
(define-public (set-winner
    (city-id uint)
    (winner principal)
    (encrypted-location (buff 512))
    (city-name (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get owner-burned)) ERR-NOT-OWNER)
    (asserts! (< city-id BOARD-SIZE) ERR-INVALID-CITY)
    (asserts! (is-none (map-get? city-data city-id)) ERR-ALREADY-SET)

    (map-set city-data city-id {
      winner: winner,
      encrypted-location: encrypted-location,
      revealed: false,
      city-name: city-name
    })

    (var-set cities-configured (+ (var-get cities-configured) u1))

    (print {
      event: "city-winner-set",
      city-id: city-id,
      city-name: city-name,
      winner: winner,
      configured-count: (var-get cities-configured)
    })
    (ok true)))

;; Update encrypted location if needed (before reveal)
(define-public (update-encrypted-location (city-id uint) (new-encrypted (buff 512)))
  (let
    (
      (city (unwrap! (map-get? city-data city-id) ERR-CITY-NOT-SET))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get owner-burned)) ERR-NOT-OWNER)
    (asserts! (not (get revealed city)) ERR-ALREADY-REVEALED)

    (map-set city-data city-id (merge city {encrypted-location: new-encrypted}))

    (print {event: "location-updated", city-id: city-id})
    (ok true)))

;; Burn owner after all setup complete (optional but recommended)
(define-public (burn-owner)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (is-eq (var-get cities-configured) BOARD-SIZE) ERR-INVALID-CITY)

    (var-set owner-burned true)
    (var-set contract-owner 'SP000000000000000000002Q6VF78)

    (print {event: "owner-burned", message: "All cities configured, owner burned"})
    (ok true)))

;; ============================================
;; WINNER FUNCTIONS
;; ============================================

;; Winner calls this to reveal their encrypted location
;; The encrypted blob is emitted in the event
;; Only the winner can decrypt it with their private key
(define-public (reveal (city-id uint))
  (let
    (
      (city (unwrap! (map-get? city-data city-id) ERR-CITY-NOT-SET))
      (winner (get winner city))
      (encrypted (get encrypted-location city))
    )
    (asserts! (is-eq tx-sender winner) ERR-NOT-WINNER)
    (asserts! (not (get revealed city)) ERR-ALREADY-REVEALED)

    (map-set city-data city-id (merge city {revealed: true}))

    ;; Emit the encrypted location - only winner can decrypt
    (print {
      event: "key-location-revealed",
      city-id: city-id,
      city-name: (get city-name city),
      winner: winner,
      encrypted-location: encrypted
    })
    (ok encrypted)))

;; ============================================
;; READ-ONLY FUNCTIONS
;; ============================================

(define-read-only (get-city-info (city-id uint))
  (match (map-get? city-data city-id)
    city (some {
      winner: (get winner city),
      revealed: (get revealed city),
      city-name: (get city-name city)
    })
    none))

(define-read-only (get-winner (city-id uint))
  (match (map-get? city-data city-id)
    city (some (get winner city))
    none))

(define-read-only (is-revealed (city-id uint))
  (match (map-get? city-data city-id)
    city (get revealed city)
    false))

(define-read-only (get-cities-configured)
  (var-get cities-configured))

(define-read-only (is-all-configured)
  (is-eq (var-get cities-configured) BOARD-SIZE))

(define-read-only (is-owner-burned)
  (var-get owner-burned))

(define-read-only (get-reveal-status)
  {
    configured: (var-get cities-configured),
    total: BOARD-SIZE,
    owner-burned: (var-get owner-burned)
  })
