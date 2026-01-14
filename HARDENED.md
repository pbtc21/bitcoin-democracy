# Bitcoin Democracy: Hardened Edition

## Threat Model
A nation-state actor wants to shut this down.

## Attack Vectors & Mitigations

### 1. Yield Protocol Freeze
**Attack**: Government pressures Zest/ALEX to freeze treasury assets.
**Mitigation**: **No external yield dependencies.**
- Treasury holds raw sBTC only
- No DeFi integrations that can freeze
- Yield = 0%, but unstoppable
- Users accept this tradeoff

### 2. sBTC Signer Coercion
**Attack**: 11/15 sBTC signers are pressured to blacklist addresses.
**Mitigation**: **This is the hardest problem.**
- sBTC is the weak link - 15 known entities
- Options:
  - Wait for signer rotation (Q2-Q3 2025) - more signers, harder to coerce all
  - Support alternative BTC bridges (tBTC, threshold sig with more signers)
  - Accept the risk - attacking 11 entities in different jurisdictions is hard
  - Ultimate: native BTC on Stacks post-sBTC decentralization

### 3. Deployer Liability
**Attack**: Government subpoenas deployer to upgrade/pause contracts.
**Mitigation**: **Burn all admin keys at deployment.**
```clarity
;; One-time irreversible admin burn
(define-public (burn-admin)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-owner 'SP000000000000000000002Q6VF78) ;; burn address
    (ok true)))
```
- No pause functions
- No upgrade paths
- No owner functions after burn
- Deployer becomes legally irrelevant

### 4. Coordinator Targeting
**Attack**: Government arrests/pressures the "king".
**Mitigation**: **Coordinator is replaceable by design.**
- Board can fire and hire new coordinator instantly (16/30 vote)
- Coordinator has spending limits (can't drain treasury quickly)
- Multiple coordinator candidates can be pre-approved
- Coordinator can be a multisig or even a smart contract
- Geographic distribution of trustees makes coordination hard

### 5. Frontend/API Censorship
**Attack**: Hiro API blocked, websites taken down.
**Mitigation**: **Multiple access paths.**
- Contracts work without frontend
- Direct contract calls via any Stacks node
- Run your own node
- IPFS-hosted frontend
- Multiple API providers (Hiro, self-hosted, etc.)

### 6. Stacks Network Attack
**Attack**: Pressure Stacks miners/validators.
**Mitigation**: **Stacks inherits Bitcoin security.**
- Stacks blocks anchor to Bitcoin
- Would need to attack Bitcoin itself
- 21M+ Bitcoin hashrate protects finality

---

## Hardened Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    USERS                                 │
│   Hold sBTC → Get voting power → Elect trustees          │
│   (Accept: 0% yield, maximum censorship resistance)      │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│              treasury-hardened.clar                      │
│  - Accepts sBTC deposits                                 │
│  - NO yield integrations (removes freeze risk)           │
│  - NO pause function                                     │
│  - NO admin after deployment                             │
│  - Coordinator spending with limits                      │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│              hyperelection-hardened.clar                 │
│  - Stake-weighted delegation                             │
│  - NO admin functions                                    │
│  - Challenge period (trustless)                          │
│  - Anyone can trigger finalization                       │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                 board-hardened.clar                      │
│  - 30 trustees, 16/30 approval                          │
│  - Can hire/fire coordinator                            │
│  - Can adjust spending limits                           │
│  - NO pause function                                    │
│  - NO admin override                                    │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                 THE COORDINATOR                          │
│  - Replaceable at any time by board                     │
│  - Daily spending limits                                │
│  - Can be individual, multisig, or contract             │
│  - No special privileges beyond spending                │
└─────────────────────────────────────────────────────────┘
```

---

## Code Changes Required

### 1. Remove from treasury.clar:
- All yield functions (deploy-to-yield, harvest, claim)
- mock-zest dependency
- yield-trait dependency

### 2. Remove from all contracts:
- `set-paused` functions
- `contract-owner` admin powers (after burn)
- Any upgrade mechanisms

### 3. Add to all contracts:
```clarity
;; Permanent admin burn - call once after deployment
(define-data-var admin-burned bool false)

(define-public (burn-admin-forever)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get admin-burned)) err-already-burned)
    (var-set admin-burned true)
    (var-set contract-owner 'SP000000000000000000002Q6VF78)
    (print {event: "admin-burned-forever", block: block-height})
    (ok true)))
```

### 4. Ensure all critical functions are permissionless:
- `execute-finalization` - anyone can call after challenge period
- `execute-recall` - anyone can call if threshold met
- `execute-coordinator` - anyone can call if votes met
- Deposit/withdraw - anyone with tokens

---

## Remaining Risks (Honest Assessment)

| Risk | Severity | Mitigation |
|------|----------|------------|
| sBTC signer coercion | HIGH | Wait for decentralization, geographic distribution |
| Stacks consensus attack | LOW | Bitcoin-anchored, would need 51% BTC hashrate |
| Smart contract bug | MED | Audits, bug bounty, but no pause = no fix |
| Coordinator goes rogue | LOW | Daily limits, instant replacement |
| All 30 trustees coerced | LOW | Geographic distribution, pseudonymous allowed |

---

## The Tradeoff

**Pauseless = No emergency brake**

If there's a bug:
- Funds could be drained
- No admin can stop it
- Only fix is social coordination (trustees vote to migrate)

This is the price of censorship resistance.

---

## Deployment Checklist

1. [ ] Deploy contracts
2. [ ] Initialize cities
3. [ ] Set board contract in treasury
4. [ ] Verify all functions work
5. [ ] **BURN ADMIN KEYS** (irreversible)
6. [ ] Announce to community
7. [ ] First election cycle begins

After step 5, nobody can stop this. Not you, not governments, not anyone.
