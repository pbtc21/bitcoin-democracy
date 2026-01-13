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
(define-constant err-already-initialized (err u108))
(define-constant err-spend-limit-exceeded (err u109))
(define-constant err-no-yield (err u110))

;; Conversion rate: 1 sBTC (8 decimals) = 1,000,000 tokens (6 decimals)
(define-constant sbtc-to-token-multiplier u10000)

;; Default daily spend limit: 1 BTC (100,000,000 satoshis)
(define-constant default-daily-limit u100000000)

;; State
(define-data-var paused bool false)
(define-data-var total-deposits uint u0)

;; Track individual contributions
(define-map contributions principal uint)

;; Coordinator - has direct spending authority
(define-data-var coordinator (optional principal) none)

;; Board contract - can dilute
(define-data-var board-contract principal contract-owner)
(define-data-var board-contract-set bool false)

;; sBTC contract reference (set via set-sbtc-contract after deployment)
(define-data-var sbtc-contract principal contract-owner)

;; Yield protocol reference
(define-data-var yield-protocol principal contract-owner)
(define-data-var yield-deployed uint u0)  ;; Amount deployed to yield

;; Spending limits
(define-data-var daily-spend-limit uint default-daily-limit)
(define-data-var spend-today uint u0)
(define-data-var last-spend-day uint u0)

;; Yield tracking for claims
(define-data-var total-yield-harvested uint u0)
(define-map yield-claimed principal uint)  ;; Track how much each user has claimed

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
;; The coordinator has full authority over treasury spending (within daily limit)
(define-public (coordinator-spend (amount uint) (recipient principal) (memo (optional (buff 34))))
  (let
    (
      (current-coordinator (unwrap! (var-get coordinator) err-no-coordinator))
      (today (/ stacks-block-height u144))  ;; ~1 day in blocks
    )
    (asserts! (is-eq tx-sender current-coordinator) err-not-coordinator)
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)

    ;; Reset daily counter if new day
    (if (> today (var-get last-spend-day))
      (begin
        (var-set spend-today u0)
        (var-set last-spend-day today))
      true)

    ;; Check spending limit
    (asserts! (<= (+ (var-get spend-today) amount) (var-get daily-spend-limit)) err-spend-limit-exceeded)

    ;; Update spend tracking
    (var-set spend-today (+ (var-get spend-today) amount))

    ;; Transfer sBTC from treasury to recipient
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender recipient memo)))

    (print {event: "coordinator-spend", coordinator: current-coordinator, amount: amount, recipient: recipient, daily-total: (var-get spend-today)})
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

;; ============================================
;; YIELD FUNCTIONS
;; ============================================

;; Deploy treasury sBTC to yield protocol (coordinator only)
(define-public (deploy-to-yield (amount uint))
  (let
    (
      (current-coordinator (unwrap! (var-get coordinator) err-no-coordinator))
    )
    (asserts! (is-eq tx-sender current-coordinator) err-not-coordinator)
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)

    ;; Transfer sBTC from treasury to yield protocol
    (try! (as-contract (contract-call? .mock-zest supply amount)))

    ;; Track deployed amount
    (var-set yield-deployed (+ (var-get yield-deployed) amount))

    (print {event: "deployed-to-yield", amount: amount, total-deployed: (var-get yield-deployed)})
    (ok amount)))

;; Withdraw from yield protocol (coordinator only)
(define-public (withdraw-from-yield (amount uint))
  (let
    (
      (current-coordinator (unwrap! (var-get coordinator) err-no-coordinator))
    )
    (asserts! (is-eq tx-sender current-coordinator) err-not-coordinator)
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= amount (var-get yield-deployed)) err-insufficient-balance)

    ;; Withdraw from yield protocol back to treasury
    (try! (as-contract (contract-call? .mock-zest withdraw amount)))

    ;; Update tracking
    (var-set yield-deployed (- (var-get yield-deployed) amount))

    (print {event: "withdrawn-from-yield", amount: amount, remaining-deployed: (var-get yield-deployed)})
    (ok amount)))

;; Harvest yield rewards (anyone can call - gas sponsor friendly)
(define-public (harvest-yield)
  (let
    (
      (rewards (try! (as-contract (contract-call? .mock-zest claim-rewards))))
    )
    ;; Track total harvested for proportional claims
    (var-set total-yield-harvested (+ (var-get total-yield-harvested) rewards))

    (print {event: "yield-harvested", rewards: rewards, total-harvested: (var-get total-yield-harvested)})
    (ok rewards)))

;; User claims their proportional share of yield
(define-public (claim-yield)
  (let
    (
      (claimer tx-sender)
      (user-tokens (unwrap! (contract-call? .city-btc-token get-balance claimer) err-no-yield))
      (total-tokens (unwrap! (contract-call? .city-btc-token get-total-supply) err-no-yield))
      (total-harvested (var-get total-yield-harvested))
      (already-claimed (default-to u0 (map-get? yield-claimed claimer)))
      ;; User's total entitled share based on their % of tokens
      (user-total-share (if (> total-tokens u0)
                           (/ (* total-harvested user-tokens) total-tokens)
                           u0))
      ;; What they can claim now (total share minus already claimed)
      (claimable (if (> user-total-share already-claimed)
                    (- user-total-share already-claimed)
                    u0))
    )
    (asserts! (> claimable u0) err-no-yield)

    ;; Transfer yield to claimer
    (try! (as-contract (contract-call? .mock-sbtc transfer claimable tx-sender claimer none)))

    ;; Update claimed tracking
    (map-set yield-claimed claimer (+ already-claimed claimable))

    (print {event: "yield-claimed", claimer: claimer, amount: claimable, total-claimed: (+ already-claimed claimable)})
    (ok claimable)))

;; ============================================
;; ADMIN FUNCTIONS
;; ============================================

;; Set coordinator - only callable by board contract
(define-public (set-coordinator (new-coordinator principal))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) err-not-board)
    (var-set coordinator (some new-coordinator))
    (print {event: "coordinator-set", coordinator: new-coordinator})
    (ok true)))

;; Set board contract (one-time setup - cannot be changed after)
(define-public (set-board-contract (board principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get board-contract-set)) err-already-initialized)
    (var-set board-contract board)
    (var-set board-contract-set true)
    (print {event: "board-contract-set", board: board})
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

;; Set yield protocol reference
(define-public (set-yield-protocol (protocol principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set yield-protocol protocol)
    (ok true)))

;; Set daily spending limit - only callable by board contract
(define-public (set-daily-limit (new-limit uint))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) err-not-board)
    (var-set daily-spend-limit new-limit)
    (print {event: "daily-limit-set", new-limit: new-limit})
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

;; Yield read-only functions

(define-read-only (get-yield-deployed)
  (var-get yield-deployed))

(define-read-only (get-total-yield-harvested)
  (var-get total-yield-harvested))

(define-read-only (get-yield-claimed (account principal))
  (default-to u0 (map-get? yield-claimed account)))

(define-read-only (get-claimable-yield (account principal))
  (let
    (
      (user-tokens (unwrap-panic (contract-call? .city-btc-token get-balance account)))
      (total-tokens (unwrap-panic (contract-call? .city-btc-token get-total-supply)))
      (total-harvested (var-get total-yield-harvested))
      (already-claimed (default-to u0 (map-get? yield-claimed account)))
      (user-total-share (if (> total-tokens u0) (/ (* total-harvested user-tokens) total-tokens) u0))
    )
    (if (> user-total-share already-claimed)
      (- user-total-share already-claimed)
      u0)))

;; Spending limit read-only functions

(define-read-only (get-daily-spend-limit)
  (var-get daily-spend-limit))

(define-read-only (get-spend-today)
  (var-get spend-today))

(define-read-only (get-remaining-daily-budget)
  (let
    (
      (today (/ stacks-block-height u144))
      (current-spend (if (is-eq today (var-get last-spend-day))
                        (var-get spend-today)
                        u0))
    )
    (- (var-get daily-spend-limit) current-spend)))
