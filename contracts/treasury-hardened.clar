;; treasury-hardened.clar
;; Censorship-resistant treasury - NO pause, NO yield deps, NO admin after burn
;;
;; Design principles:
;; - No external protocol dependencies (can't be frozen by Zest/ALEX)
;; - No pause function (can't be stopped)
;; - Admin keys burned after deployment (deployer becomes irrelevant)
;; - Coordinator spending with limits (damage capped)
;; - All critical functions permissionless

;; Constants
(define-constant ERR-PAUSED (err u100))           ;; Kept for interface but never triggers
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-TRANSFER-FAILED (err u104))
(define-constant ERR-NOT-COORDINATOR (err u105))
(define-constant ERR-NOT-BOARD (err u106))
(define-constant ERR-NO-COORDINATOR (err u107))
(define-constant ERR-ALREADY-INITIALIZED (err u108))
(define-constant ERR-SPEND-LIMIT-EXCEEDED (err u109))
(define-constant ERR-ADMIN-BURNED (err u120))
(define-constant ERR-NOT-BURNED-YET (err u121))

;; Burn address - funds sent here are unrecoverable
(define-constant BURN-ADDRESS 'SP000000000000000000002Q6VF78)

;; Conversion rate: 1 sBTC (8 decimals) = 1,000,000 tokens (6 decimals)
(define-constant SBTC-TO-TOKEN-MULTIPLIER u10000)

;; Default daily spend limit: 1 BTC (100,000,000 satoshis)
(define-constant DEFAULT-DAILY-LIMIT u100000000)

;; ============================================
;; ADMIN STATE (burnable)
;; ============================================

(define-data-var contract-owner principal tx-sender)
(define-data-var admin-burned bool false)

;; ============================================
;; CORE STATE
;; ============================================

(define-data-var total-deposits uint u0)
(define-map contributions principal uint)

;; Coordinator - has direct spending authority
(define-data-var coordinator (optional principal) none)

;; Board contract - can set coordinator and limits
(define-data-var board-contract principal tx-sender)
(define-data-var board-contract-set bool false)

;; Spending limits
(define-data-var daily-spend-limit uint DEFAULT-DAILY-LIMIT)
(define-data-var spend-today uint u0)
(define-data-var last-spend-day uint u0)

;; ============================================
;; ADMIN BURN (call once, irreversible)
;; ============================================

;; Burns admin permanently. After this:
;; - No pause possible
;; - No owner functions work
;; - Contract runs autonomously forever
(define-public (burn-admin-forever)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-COORDINATOR)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    (asserts! (var-get board-contract-set) ERR-NOT-BURNED-YET) ;; Must set board first

    (var-set admin-burned true)
    (var-set contract-owner BURN-ADDRESS)

    (print {event: "admin-burned-forever", block: stacks-block-height,
            message: "This contract is now unstoppable"})
    (ok true)))

(define-read-only (is-admin-burned)
  (var-get admin-burned))

;; ============================================
;; DEPOSIT / WITHDRAW (always open, no pause)
;; ============================================

;; Deposit sBTC and receive governance tokens
(define-public (deposit (amount uint))
  (let
    (
      (depositor tx-sender)
      (token-amount (* amount SBTC-TO-TOKEN-MULTIPLIER))
      (current-contribution (default-to u0 (map-get? contributions depositor)))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer sBTC from depositor to treasury
    (try! (contract-call? .mock-sbtc transfer amount depositor (as-contract tx-sender) none))

    ;; Mint governance tokens to depositor
    (try! (contract-call? .city-btc-token-hardened mint token-amount depositor))

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
      (sbtc-amount (/ token-amount SBTC-TO-TOKEN-MULTIPLIER))
      (current-contribution (default-to u0 (map-get? contributions withdrawer)))
    )
    (asserts! (> token-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= current-contribution sbtc-amount) ERR-INSUFFICIENT-BALANCE)

    ;; Burn governance tokens
    (try! (contract-call? .city-btc-token-hardened burn token-amount withdrawer))

    ;; Transfer sBTC back to withdrawer
    (try! (as-contract (contract-call? .mock-sbtc transfer sbtc-amount tx-sender withdrawer none)))

    ;; Update contribution tracking
    (map-set contributions withdrawer (- current-contribution sbtc-amount))
    (var-set total-deposits (- (var-get total-deposits) sbtc-amount))

    (print {event: "withdraw", withdrawer: withdrawer, tokens-burned: token-amount, sbtc-returned: sbtc-amount})
    (ok sbtc-amount)))

;; ============================================
;; COORDINATOR SPENDING
;; ============================================

;; Coordinator direct spend - NO voting required, but LIMITED
(define-public (coordinator-spend (amount uint) (recipient principal) (memo (optional (buff 34))))
  (let
    (
      (current-coordinator (unwrap! (var-get coordinator) ERR-NO-COORDINATOR))
      (today (/ stacks-block-height u144))  ;; ~1 day in blocks
    )
    (asserts! (is-eq tx-sender current-coordinator) ERR-NOT-COORDINATOR)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Reset daily counter if new day
    (if (> today (var-get last-spend-day))
      (begin
        (var-set spend-today u0)
        (var-set last-spend-day today))
      true)

    ;; Check spending limit
    (asserts! (<= (+ (var-get spend-today) amount) (var-get daily-spend-limit)) ERR-SPEND-LIMIT-EXCEEDED)

    ;; Update spend tracking
    (var-set spend-today (+ (var-get spend-today) amount))

    ;; Transfer sBTC from treasury to recipient
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender recipient memo)))

    (print {event: "coordinator-spend", coordinator: current-coordinator, amount: amount,
            recipient: recipient, daily-total: (var-get spend-today)})
    (ok true)))

;; ============================================
;; BOARD FUNCTIONS (governance controlled)
;; ============================================

;; Set coordinator - only callable by board contract
(define-public (set-coordinator (new-coordinator principal))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) ERR-NOT-BOARD)
    (var-set coordinator (some new-coordinator))
    (print {event: "coordinator-set", coordinator: new-coordinator})
    (ok true)))

;; Set daily spending limit - only callable by board contract
(define-public (set-daily-limit (new-limit uint))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) ERR-NOT-BOARD)
    (var-set daily-spend-limit new-limit)
    (print {event: "daily-limit-set", new-limit: new-limit})
    (ok true)))

;; Board dilution - mint new tokens (tax)
;; Only callable by board contract after approval
(define-public (board-dilute (amount uint))
  (begin
    (asserts! (is-eq contract-caller (var-get board-contract)) ERR-NOT-BOARD)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Mint tokens to treasury itself (for coordinator to spend)
    (try! (contract-call? .city-btc-token-hardened mint amount (as-contract tx-sender)))

    (print {event: "board-dilution", amount: amount})
    (ok true)))

;; ============================================
;; SETUP (only before admin burn)
;; ============================================

;; Set board contract (one-time setup - cannot be changed after)
(define-public (set-board-contract (board principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-COORDINATOR)
    (asserts! (not (var-get admin-burned)) ERR-ADMIN-BURNED)
    (asserts! (not (var-get board-contract-set)) ERR-ALREADY-INITIALIZED)
    (var-set board-contract board)
    (var-set board-contract-set true)
    (print {event: "board-contract-set", board: board})
    (ok true)))

;; ============================================
;; READ-ONLY FUNCTIONS
;; ============================================

(define-read-only (get-contribution (account principal))
  (default-to u0 (map-get? contributions account)))

(define-read-only (get-total-deposits)
  (var-get total-deposits))

(define-read-only (get-treasury-balance)
  (contract-call? .mock-sbtc get-balance (as-contract tx-sender)))

(define-read-only (get-coordinator)
  (var-get coordinator))

(define-read-only (get-board-contract)
  (var-get board-contract))

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

(define-read-only (calculate-tokens-for-deposit (sbtc-amount uint))
  (* sbtc-amount SBTC-TO-TOKEN-MULTIPLIER))

(define-read-only (calculate-sbtc-for-withdrawal (token-amount uint))
  (/ token-amount SBTC-TO-TOKEN-MULTIPLIER))
