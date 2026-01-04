# Bitcoin Democracy

A network of 30 sBTC-funded city-states on Stacks with plutocratic governance.

## Overview

Bitcoin Democracy allows users to:
- Deposit testnet sBTC into city treasuries
- Receive CityBTC governance tokens (1 sBTC = 1M tokens)
- Delegate voting power to council candidates
- Elect city councils via token-weighted voting
- Govern treasury spending through 3-of-5 multisig

## Cities (30 Total)

| Region | Cities |
|--------|--------|
| North America | Austin, Las Vegas, Los Angeles, Mexico City, Miami, NYC, SF, Toronto |
| Europe | Amsterdam, Berlin, London, Lisbon, Paris, Stockholm, Tallinn, Zürich |
| Oceania | Auckland, Melbourne, Sydney |
| Asia | Bangalore, Bangkok, Dubai, Ho Chi Minh, Seoul, Singapore, Tel Aviv, Tokyo |
| Africa | Lagos, Cairo, Cape Town |

Token format: `[City]BTC` / `[TICKER]BTC` (e.g., MiamiBTC / MIABTC)

## Contracts

| Contract | Purpose |
|----------|---------|
| `city-btc-token.clar` | SIP-010 governance token |
| `treasury.clar` | sBTC deposits, token minting |
| `election.clar` | Delegation, voting, tallying, recall |
| `council.clar` | 3-of-5 multisig governance |
| `democracy-factory.clar` | City deployment and metadata |
| `mock-sbtc.clar` | Testnet sBTC mock |

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)

### Run Tests

```bash
clarinet test
```

### Deploy to Devnet

```bash
clarinet integrate
```

## Governance Flow

```
1. DEPOSIT: User deposits sBTC → receives CityBTC tokens
2. DELEGATE: Token holder delegates to council candidate
3. ELECT: Top 5 candidates form the council
4. PROPOSE: Council member proposes treasury action
5. APPROVE: 3-of-5 council members vote yes
6. EXECUTE: Approved proposal is executed
```

## Key Parameters

| Parameter | Value |
|-----------|-------|
| Council Size | 5 members |
| Approval Threshold | 3-of-5 |
| Recall Threshold | 51% of token supply |
| Proposal Duration | ~24 hours (144 blocks) |
| Token Decimals | 6 |

## Security Features

- Emergency pause on treasury
- Recall mechanism for council members
- Proposal expiration
- Owner-only admin functions
- Token-weighted voting (no sybil)

## License

MIT
