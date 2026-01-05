;; democracy-factory.clar
;; Factory contract for deploying and managing all 30 city-states
;; Each city gets its own token name/symbol but shares contract logic

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-city-not-found (err u101))
(define-constant err-city-already-exists (err u102))
(define-constant err-max-cities-reached (err u103))
(define-constant err-invalid-city-id (err u104))

(define-constant max-cities u30)

;; City data structure
;; In a full implementation, each city would have separate contract deployments
;; For now, we store city metadata and use a single set of contracts
(define-map cities
  uint ;; city-id
  {
    name: (string-ascii 32),
    token-name: (string-ascii 32),
    ticker: (string-ascii 10),
    active: bool,
    created-at: uint,
    total-staked: uint
  })

;; City name to ID mapping
(define-map city-name-to-id (string-ascii 32) uint)

;; State
(define-data-var city-count uint u0)
(define-data-var factory-active bool true)

;; Initialize a city
(define-public (create-city (name (string-ascii 32)) (token-name (string-ascii 32)) (ticker (string-ascii 10)))
  (let
    (
      (city-id (var-get city-count))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get factory-active) err-owner-only)
    (asserts! (< city-id max-cities) err-max-cities-reached)
    (asserts! (is-none (map-get? city-name-to-id name)) err-city-already-exists)

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

    (print {event: "city-created", id: city-id, name: name, token-name: token-name, ticker: ticker})
    (ok city-id)))

;; Batch create cities from predefined list
(define-public (initialize-all-cities)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (var-get city-count) u0) err-city-already-exists) ;; Only run once

    ;; North America (8)
    (try! (create-city "Austin" "AustinBTC" "AUSBTC"))
    (try! (create-city "Las Vegas" "LasVegasBTC" "LVBTC"))
    (try! (create-city "Los Angeles" "LosAngelesBTC" "LABTC"))
    (try! (create-city "Mexico City" "MexicoCityBTC" "MEXBTC"))
    (try! (create-city "Miami" "MiamiBTC" "MIABTC"))
    (try! (create-city "New York City" "NewYorkBTC" "NYCBTC"))
    (try! (create-city "San Francisco" "SanFranciscoBTC" "SFBTC"))
    (try! (create-city "Toronto" "TorontoBTC" "TORBTC"))

    ;; Europe (8)
    (try! (create-city "Amsterdam" "AmsterdamBTC" "AMSBTC"))
    (try! (create-city "Berlin" "BerlinBTC" "BERBTC"))
    (try! (create-city "London" "LondonBTC" "LONBTC"))
    (try! (create-city "Lisbon" "LisbonBTC" "LISBTC"))
    (try! (create-city "Paris" "ParisBTC" "PARBTC"))
    (try! (create-city "Stockholm" "StockholmBTC" "STOBTC"))
    (try! (create-city "Tallinn" "TallinnBTC" "TALBTC"))
    (try! (create-city "Zurich" "ZurichBTC" "ZURBTC"))

    ;; Oceania (3)
    (try! (create-city "Auckland" "AucklandBTC" "AUKBTC"))
    (try! (create-city "Melbourne" "MelbourneBTC" "MELBTC"))
    (try! (create-city "Sydney" "SydneyBTC" "SYDBTC"))

    ;; Asia (8)
    (try! (create-city "Bangalore" "BangaloreBTC" "BANBTC"))
    (try! (create-city "Bangkok" "BangkokBTC" "BKKBTC"))
    (try! (create-city "Dubai" "DubaiBTC" "DUBBTC"))
    (try! (create-city "Ho Chi Minh" "HoChiMinhBTC" "HCMBTC"))
    (try! (create-city "Seoul" "SeoulBTC" "SEBTC"))
    (try! (create-city "Singapore" "SingaporeBTC" "SINBTC"))
    (try! (create-city "Tel Aviv" "TelAvivBTC" "TLVBTC"))
    (try! (create-city "Tokyo" "TokyoBTC" "TOKBTC"))

    ;; Africa (3)
    (try! (create-city "Lagos" "LagosBTC" "LAGBTC"))
    (try! (create-city "Cairo" "CairoBTC" "CAIBTC"))
    (try! (create-city "Cape Town" "CapeTownBTC" "CPTBTC"))

    (print {event: "all-cities-initialized", count: u30})
    (ok u30)))

;; Deactivate a city
(define-public (deactivate-city (city-id uint))
  (let
    (
      (city (unwrap! (map-get? cities city-id) err-city-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (map-set cities city-id (merge city {active: false}))
    (print {event: "city-deactivated", id: city-id})
    (ok true)))

;; Reactivate a city
(define-public (reactivate-city (city-id uint))
  (let
    (
      (city (unwrap! (map-get? cities city-id) err-city-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (map-set cities city-id (merge city {active: true}))
    (print {event: "city-reactivated", id: city-id})
    (ok true)))

;; Update city staked amount (called by treasury or tracking contract)
(define-public (update-city-stake (city-id uint) (new-total uint))
  (let
    (
      (city (unwrap! (map-get? cities city-id) err-city-not-found))
    )
    ;; In production, this would have access control
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (map-set cities city-id (merge city {total-staked: new-total}))
    (ok true)))

;; Pause factory
(define-public (set-factory-active (active bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set factory-active active)
    (ok true)))

;; Read-only functions

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

(define-read-only (is-factory-active)
  (var-get factory-active))

(define-read-only (get-max-cities)
  max-cities)

;; Get cities in a range (for pagination)
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

;; Helper to get all city IDs as a list
(define-read-only (get-all-city-ids)
  (list
    u0 u1 u2 u3 u4 u5 u6 u7 u8 u9
    u10 u11 u12 u13 u14 u15 u16 u17 u18 u19
    u20 u21 u22 u23 u24 u25 u26 u27 u28 u29))

;; City lookup by region (returns city IDs)
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
