;; yield-trait.clar
;; Abstract interface for yield protocols (Zest, etc.)
;; Allows treasury to swap yield sources without code changes

(define-trait yield-protocol
  (
    ;; Supply assets to earn yield
    ;; Returns: amount of yield-bearing tokens received
    (supply (uint) (response uint uint))

    ;; Withdraw assets (with accumulated yield)
    ;; Returns: amount of underlying assets received
    (withdraw (uint) (response uint uint))

    ;; Claim accumulated rewards without withdrawing principal
    ;; Returns: amount of rewards claimed
    (claim-rewards () (response uint uint))

    ;; Get current balance (principal + yield)
    ;; Returns: total value in underlying asset
    (get-balance (principal) (response uint uint))

    ;; Get pending rewards not yet claimed
    ;; Returns: claimable reward amount
    (get-pending-rewards (principal) (response uint uint))
  ))
