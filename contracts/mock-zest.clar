;; mock-zest.clar
;; Mock yield protocol for testing
;; Simulates ~10% APY (simplified for testing)

(impl-trait .yield-trait.yield-protocol)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-insufficient-balance (err u100))
(define-constant err-no-deposits (err u101))

;; Simulated APY: 10% per 52560 blocks (~1 year at 10 min/block)
;; Simplified: 1 satoshi per 525600 deposited per block
(define-constant yield-rate-per-block u1)
(define-constant yield-denominator u525600)

;; Track deposits per user
(define-map deposits principal {amount: uint, deposit-block: uint})

;; Track total deposited
(define-data-var total-deposits uint u0)

;; Accumulated rewards pool (for testing, we mint fake rewards)
(define-data-var rewards-pool uint u0)

;; Supply assets to earn yield
(define-public (supply (amount uint))
  (let
    (
      (depositor tx-sender)
      (current-deposit (default-to {amount: u0, deposit-block: u0} (map-get? deposits depositor)))
    )
    ;; Transfer sBTC from depositor to this contract
    (try! (contract-call? .mock-sbtc transfer amount depositor (as-contract tx-sender) none))

    ;; Update deposit tracking
    (map-set deposits depositor {
      amount: (+ (get amount current-deposit) amount),
      deposit-block: stacks-block-height
    })
    (var-set total-deposits (+ (var-get total-deposits) amount))

    (print {event: "zest-supply", depositor: depositor, amount: amount})
    (ok amount)))

;; Withdraw assets with accumulated yield
(define-public (withdraw (amount uint))
  (let
    (
      (withdrawer tx-sender)
      (deposit-info (unwrap! (map-get? deposits withdrawer) err-no-deposits))
      (deposited (get amount deposit-info))
    )
    (asserts! (>= deposited amount) err-insufficient-balance)

    ;; Transfer sBTC back to withdrawer
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender withdrawer none)))

    ;; Update deposit tracking
    (map-set deposits withdrawer {
      amount: (- deposited amount),
      deposit-block: (get deposit-block deposit-info)
    })
    (var-set total-deposits (- (var-get total-deposits) amount))

    (print {event: "zest-withdraw", withdrawer: withdrawer, amount: amount})
    (ok amount)))

;; Claim accumulated rewards
(define-public (claim-rewards)
  (let
    (
      (claimer tx-sender)
      (deposit-info (unwrap! (map-get? deposits claimer) err-no-deposits))
      (deposited (get amount deposit-info))
      (deposit-block (get deposit-block deposit-info))
      (blocks-elapsed (- stacks-block-height deposit-block))
      (rewards (calculate-rewards deposited blocks-elapsed))
    )
    ;; Mint rewards to claimer (mock behavior)
    (try! (as-contract (contract-call? .mock-sbtc faucet rewards claimer)))

    ;; Reset deposit block to now (rewards claimed up to this point)
    (map-set deposits claimer {
      amount: deposited,
      deposit-block: stacks-block-height
    })

    (print {event: "zest-claim", claimer: claimer, rewards: rewards})
    (ok rewards)))

;; Get current balance (principal only in this mock)
(define-public (get-balance (account principal))
  (ok (get amount (default-to {amount: u0, deposit-block: u0} (map-get? deposits account)))))

;; Get pending rewards
(define-public (get-pending-rewards (account principal))
  (let
    (
      (deposit-info (default-to {amount: u0, deposit-block: stacks-block-height} (map-get? deposits account)))
      (deposited (get amount deposit-info))
      (deposit-block (get deposit-block deposit-info))
      (blocks-elapsed (- stacks-block-height deposit-block))
    )
    (ok (calculate-rewards deposited blocks-elapsed))))

;; Calculate rewards based on time and amount
(define-private (calculate-rewards (amount uint) (blocks uint))
  (/ (* amount blocks yield-rate-per-block) yield-denominator))

;; Read-only helpers
(define-read-only (get-deposit-info (account principal))
  (map-get? deposits account))

(define-read-only (get-total-deposits)
  (var-get total-deposits))

(define-read-only (get-apy)
  ;; Returns basis points (1000 = 10%)
  u1000)
