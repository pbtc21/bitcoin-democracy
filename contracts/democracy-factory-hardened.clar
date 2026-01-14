;; democracy-factory-hardened.clar (bloc-registry)
;; Censorship-resistant regional bloc registry
;; NO admin functions after burn - fully autonomous
;;
;; The 30 blocs are identity/community affiliations
;; All serve one king - blocs have no separate sovereignty

;; Constants
(define-constant ERR-CITY-NOT-FOUND (err u101))
(define-constant ERR-CITY-ALREADY-EXISTS (err u102))
(define-constant ERR-MAX-CITIES-REACHED (err u103))
(define-constant ERR-INVALID-CITY-ID (err u104))
(define-constant ERR-ADMIN-BURNED (err u120))
(define-constant ERR-NOT-OWNER (err u121))
(define-constant ERR-NOT-ACTIVE (err u122))

;; Burn address
(define-constant BURN-ADDRESS 'SP000000000000000000002Q6VF78)

(define-constant MAX-CITIES u30)

;; ============================================
;; ADMIN STATE (burnable)
;; ============================================

(define-data-var contract-owner principal tx-sender)
(define-data-var admin-burned bool false)

;; ============================================
;; CITY DATA
;; ============================================

(define-map cities
  uint
  {
    name: (string-ascii 32),
    token-name: (string-ascii 32),
    ticker: (string-ascii 10),
    active: bool,
    created-at: uint,
    total-staked: uint
  })

(define-map city-name-to-id (string-ascii 32) uint)

;; ============================================
;; BLOC IDENTITY
;; ============================================

(define-map user-bloc principal uint)
(define-map bloc-member-count uint uint)

;; State
(define-data-var city-count uint u0)

;; ============================================
;; ADMIN BURN (call once, irreversible)
;; ============================================

(define-public (burn-admin-forever)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    ;; Must initialize all cities first
    (asserts! (is-eq (var-get city-count) MAX-CITIES) ERR-MAX-CITIES-REACHED)

    (var-set admin-burned true)
    (var-set contract-owner BURN-ADDRESS)

    (print {event: "admin-burned-forever", block: stacks-block-height,
            message: "Bloc registry is now unstoppable"})
    (ok true)))

(define-read-only (is-admin-burned)
  (var-get admin-burned))

;; ============================================
;; CITY INITIALIZATION (only before burn)
;; ============================================

(define-private (create-city-internal (name (string-ascii 32)) (token-name (string-ascii 32)) (ticker (string-ascii 10)))
  (let
    (
      (city-id (var-get city-count))
    )
    (asserts! (< city-id MAX-CITIES) ERR-MAX-CITIES-REACHED)
    (asserts! (is-none (map-get? city-name-to-id name)) ERR-CITY-ALREADY-EXISTS)

    (map-set cities city-id {
      name: name,
      token-name: token-name,
      ticker: ticker,
      active: true,
      created-at: stacks-block-height,
      total-staked: u0
    })

    (map-set city-name-to-id name city-id)
    (var-set city-count (+ city-id u1))
    (ok city-id)))

;; Initialize all 30 cities (only callable once, before burn)
(define-public (initialize-all-cities)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-OWNER)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    (asserts! (is-eq (var-get city-count) u0) ERR-CITY-ALREADY-EXISTS)

    ;; North America (8)
    (try! (create-city-internal "Austin" "AustinBTC" "AUSBTC"))
    (try! (create-city-internal "Las Vegas" "LasVegasBTC" "LVBTC"))
    (try! (create-city-internal "Los Angeles" "LosAngelesBTC" "LABTC"))
    (try! (create-city-internal "Mexico City" "MexicoCityBTC" "MEXBTC"))
    (try! (create-city-internal "Miami" "MiamiBTC" "MIABTC"))
    (try! (create-city-internal "New York City" "NewYorkBTC" "NYCBTC"))
    (try! (create-city-internal "San Francisco" "SanFranciscoBTC" "SFBTC"))
    (try! (create-city-internal "Toronto" "TorontoBTC" "TORBTC"))

    ;; Europe (8)
    (try! (create-city-internal "Amsterdam" "AmsterdamBTC" "AMSBTC"))
    (try! (create-city-internal "Berlin" "BerlinBTC" "BERBTC"))
    (try! (create-city-internal "London" "LondonBTC" "LONBTC"))
    (try! (create-city-internal "Lisbon" "LisbonBTC" "LISBTC"))
    (try! (create-city-internal "Paris" "ParisBTC" "PARBTC"))
    (try! (create-city-internal "Stockholm" "StockholmBTC" "STOBTC"))
    (try! (create-city-internal "Tallinn" "TallinnBTC" "TALBTC"))
    (try! (create-city-internal "Zurich" "ZurichBTC" "ZURBTC"))

    ;; Oceania (3)
    (try! (create-city-internal "Auckland" "AucklandBTC" "AUKBTC"))
    (try! (create-city-internal "Melbourne" "MelbourneBTC" "MELBTC"))
    (try! (create-city-internal "Sydney" "SydneyBTC" "SYDBTC"))

    ;; Asia (8)
    (try! (create-city-internal "Bangalore" "BangaloreBTC" "BANBTC"))
    (try! (create-city-internal "Bangkok" "BangkokBTC" "BKKBTC"))
    (try! (create-city-internal "Dubai" "DubaiBTC" "DUBBTC"))
    (try! (create-city-internal "Ho Chi Minh" "HoChiMinhBTC" "HCMBTC"))
    (try! (create-city-internal "Seoul" "SeoulBTC" "SEBTC"))
    (try! (create-city-internal "Singapore" "SingaporeBTC" "SINBTC"))
    (try! (create-city-internal "Tel Aviv" "TelAvivBTC" "TLVBTC"))
    (try! (create-city-internal "Tokyo" "TokyoBTC" "TOKBTC"))

    ;; Africa (3)
    (try! (create-city-internal "Lagos" "LagosBTC" "LAGBTC"))
    (try! (create-city-internal "Cairo" "CairoBTC" "CAIBTC"))
    (try! (create-city-internal "Cape Town" "CapeTownBTC" "CPTBTC"))

    (print {event: "all-cities-initialized", count: u30})
    (ok u30)))

;; ============================================
;; BLOC IDENTITY (always permissionless)
;; ============================================

;; Join a bloc (anyone can join any bloc, can switch anytime)
(define-public (join-bloc (city-id uint))
  (let
    (
      (user tx-sender)
      (city (unwrap! (map-get? cities city-id) ERR-CITY-NOT-FOUND))
      (current-bloc (map-get? user-bloc user))
    )
    (asserts! (get active city) ERR-NOT-ACTIVE)

    ;; If user was in a different bloc, decrement old bloc's count
    (match current-bloc old-bloc
      (map-set bloc-member-count old-bloc
        (- (default-to u1 (map-get? bloc-member-count old-bloc)) u1))
      true)

    ;; Set new bloc
    (map-set user-bloc user city-id)

    ;; Increment new bloc's count
    (map-set bloc-member-count city-id
      (+ (default-to u0 (map-get? bloc-member-count city-id)) u1))

    (print {event: "joined-bloc", user: user, bloc-id: city-id, bloc-name: (get name city)})
    (ok city-id)))

;; Leave current bloc (go bloc-less)
(define-public (leave-bloc)
  (let
    (
      (user tx-sender)
      (current-bloc (unwrap! (map-get? user-bloc user) ERR-CITY-NOT-FOUND))
    )
    ;; Decrement bloc's count
    (map-set bloc-member-count current-bloc
      (- (default-to u1 (map-get? bloc-member-count current-bloc)) u1))

    ;; Remove user's bloc affiliation
    (map-delete user-bloc user)

    (print {event: "left-bloc", user: user, former-bloc: current-bloc})
    (ok true)))

;; ============================================
;; READ-ONLY FUNCTIONS
;; ============================================

(define-read-only (get-city (city-id uint))
  (map-get? cities city-id))

(define-read-only (get-city-by-name (name (string-ascii 32)))
  (match (map-get? city-name-to-id name)
    city-id (map-get? cities city-id)
    none))

(define-read-only (get-city-id-by-name (name (string-ascii 32)))
  (map-get? city-name-to-id name))

(define-read-only (get-city-count)
  (var-get city-count))

(define-read-only (is-city-active (city-id uint))
  (match (map-get? cities city-id)
    city (get active city)
    false))

(define-read-only (get-max-cities)
  MAX-CITIES)

(define-read-only (get-city-info (city-id uint))
  (match (map-get? cities city-id)
    city (some {
      id: city-id,
      name: (get name city),
      token-name: (get token-name city),
      ticker: (get ticker city),
      active: (get active city),
      total-staked: (get total-staked city)
    })
    none))

(define-read-only (get-all-city-ids)
  (list
    u0 u1 u2 u3 u4 u5 u6 u7 u8 u9
    u10 u11 u12 u13 u14 u15 u16 u17 u18 u19
    u20 u21 u22 u23 u24 u25 u26 u27 u28 u29))

;; Regional lookups
(define-read-only (get-north-america-cities)
  (list u0 u1 u2 u3 u4 u5 u6 u7))

(define-read-only (get-europe-cities)
  (list u8 u9 u10 u11 u12 u13 u14 u15))

(define-read-only (get-oceania-cities)
  (list u16 u17 u18))

(define-read-only (get-asia-cities)
  (list u19 u20 u21 u22 u23 u24 u25 u26))

(define-read-only (get-africa-cities)
  (list u27 u28 u29))

;; Bloc identity
(define-read-only (get-user-bloc (user principal))
  (map-get? user-bloc user))

(define-read-only (get-bloc-member-count (city-id uint))
  (default-to u0 (map-get? bloc-member-count city-id)))

(define-read-only (get-user-bloc-info (user principal))
  (match (map-get? user-bloc user)
    bloc-id (map-get? cities bloc-id)
    none))

(define-read-only (is-user-in-bloc (user principal) (city-id uint))
  (match (map-get? user-bloc user)
    bloc-id (is-eq bloc-id city-id)
    false))
