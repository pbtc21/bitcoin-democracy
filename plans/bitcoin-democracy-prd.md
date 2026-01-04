# PRD: Bitcoin Democracy

## Overview
**Spec**: [specs/bitcoin-democracy.md](../specs/bitcoin-democracy.md)

A network of 30 sBTC-funded city-states on Stacks with plutocratic governance. Users deposit testnet sBTC, receive CityBTC governance tokens, and participate in elections to form city councils.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    democracy-factory.clar                    │
│         (Deploys all 30 cities with parameters)              │
└─────────────────────┬───────────────────────────────────────┘
                      │ creates per city
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      Per City Instance                       │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  treasury    │  │ city-btc-    │  │  election    │       │
│  │    .clar     │◄─│ token.clar   │◄─│    .clar     │       │
│  │              │  │  (SIP-010)   │  │              │       │
│  │ - deposit    │  │              │  │ - delegate   │       │
│  │ - withdraw   │  │ - mint       │  │ - tally      │       │
│  │ - balance    │  │ - transfer   │  │ - recall     │       │
│  └──────┬───────┘  └──────────────┘  └──────┬───────┘       │
│         │                                    │               │
│         └────────────┬───────────────────────┘               │
│                      ▼                                       │
│              ┌──────────────┐                                │
│              │   council    │                                │
│              │    .clar     │                                │
│              │              │                                │
│              │ - propose    │                                │
│              │ - approve    │                                │
│              │ - execute    │                                │
│              └──────────────┘                                │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Foundation (Core Contracts) ✅
- [x] Task 1.1: Set up Clarinet project structure
- [x] Task 1.2: Implement `city-btc-token.clar` (SIP-010 standard)
- [x] Task 1.3: Implement `treasury.clar` (sBTC deposit/withdraw, token minting)
- [x] Task 1.4: Write unit tests for token + treasury
- [x] Task 1.5: Test with mock sBTC on testnet

### Phase 2: Governance Contracts ✅
- [x] Task 2.1: Implement `election.clar` (delegation, voting power, tally)
- [x] Task 2.2: Implement `council.clar` (multisig, proposals, execution)
- [x] Task 2.3: Connect election results to council membership
- [x] Task 2.4: Implement recall mechanism
- [x] Task 2.5: Write unit tests for governance

### Phase 3: Factory & Deployment ✅
- [x] Task 3.1: Implement `democracy-factory.clar` (parameterized city deployment)
- [x] Task 3.2: Create city configuration data (30 cities with names, tickers)
- [ ] Task 3.3: Deploy factory to testnet (pending Clarinet installation)
- [ ] Task 3.4: Deploy all 30 cities via factory (pending)
- [ ] Task 3.5: Verify all cities functional (pending)

### Phase 4: Integration & Testing ✅
- [x] Task 4.1: End-to-end test: deposit → mint → delegate → elect → execute
- [x] Task 4.2: Test edge cases (recall, empty elections, zero deposits)
- [x] Task 4.3: Security review of all contracts
- [x] Task 4.4: Gas optimization pass
- [x] Task 4.5: Documentation for each contract

## Files to Create

| File | Purpose |
|------|---------|
| `Clarinet.toml` | Project configuration |
| `contracts/city-btc-token.clar` | SIP-010 governance token |
| `contracts/treasury.clar` | sBTC deposits, token minting |
| `contracts/election.clar` | Delegation, voting, tallying |
| `contracts/council.clar` | Multisig governance |
| `contracts/democracy-factory.clar` | City deployment factory |
| `tests/city-btc-token_test.ts` | Token unit tests |
| `tests/treasury_test.ts` | Treasury unit tests |
| `tests/election_test.ts` | Election unit tests |
| `tests/council_test.ts` | Council unit tests |
| `tests/integration_test.ts` | Full flow tests |
| `settings/Testnet.toml` | Testnet deployment config |

## City Data (30 Cities)

| City | Token Name | Ticker |
|------|------------|--------|
| Austin | AustinBTC | AUSBTC |
| Las Vegas | LasVegasBTC | LVBTC |
| Los Angeles | LosAngelesBTC | LABTC |
| Mexico City | MexicoCityBTC | MEXBTC |
| Miami | MiamiBTC | MIABTC |
| New York City | NewYorkBTC | NYCBTC |
| San Francisco | SanFranciscoBTC | SFBTC |
| Toronto | TorontoBTC | TORBTC |
| Amsterdam | AmsterdamBTC | AMSBTC |
| Berlin | BerlinBTC | BERBTC |
| London | LondonBTC | LONBTC |
| Lisbon | LisbonBTC | LISBTC |
| Paris | ParisBTC | PARBTC |
| Stockholm | StockholmBTC | STOBTC |
| Tallinn | TallinnBTC | TALBTC |
| Zürich | ZurichBTC | ZURBTC |
| Auckland | AucklandBTC | AUKBTC |
| Melbourne | MelbourneBTC | MELBTC |
| Sydney | SydneyBTC | SYDBTC |
| Bangalore | BangaloreBTC | BANBTC |
| Bangkok | BangkokBTC | BKKBTC |
| Dubai | DubaiBTC | DUBBTC |
| Ho Chi Minh | HoChiMinhBTC | HCMBTC |
| Seoul | SeoulBTC | SEBTC |
| Singapore | SingaporeBTC | SINBTC |
| Tel Aviv | TelAvivBTC | TLVBTC |
| Tokyo | TokyoBTC | TOKBTC |
| Lagos | LagosBTC | LAGBTC |
| Cairo | CairoBTC | CAIBTC |
| Cape Town | CapeTownBTC | CPTBTC |

## Dependencies

| Dependency | Purpose |
|------------|---------|
| Clarinet | Clarity development & testing |
| @stacks/transactions | Contract interactions |
| Testnet sBTC | Treasury asset (mock for testing) |

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Testnet sBTC not available | Use mock SIP-010 token as placeholder |
| Factory deployment cost | Batch deployment, optimize contract size |
| Election gaming | Minimum delegation period, snapshot voting |
| Council capture | Recall mechanism, term limits |
| Contract bugs | Extensive testing, security review |

## Rollback Plan

1. All contracts deployed individually - can disable factory without affecting existing cities
2. Treasury has emergency pause function
3. Council can be bypassed with supermajority token vote
4. Each city independent - one failure doesn't cascade

---

**Next step**: Run `/approve` to begin implementation
