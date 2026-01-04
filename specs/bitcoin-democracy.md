# Spec: Bitcoin Democracy

## Problem
Bitcoin lacks a coherent governance and yield layer. Hodlers have no productive outlet for their BTC beyond holding. Existing DAOs are chaotic, low-stakes experiments. There's no path from Bitcoin savings to Bitcoin sovereignty.

**Who has this problem**: Bitcoin maxis who want yield + governance, anyone seeking digital city-states with skin-in-the-game voting.

## Solution
Bitcoin Democracy is a network of 30 independent city-states on Stacks, each governed by sBTC-weighted plutocracy. Users deposit sBTC into city treasuries, receive governance tokens proportional to their deposit, and earn Bitcoin yield. Cities hold elections where token holders delegate to a Council who appoints a Coordinator. Cities compete and evolve.

## Core Features

### 1. Democracy Factory
- Deploys all 30 cities from single parameterized contract
- Each city gets: Treasury, Token, Election, Council contracts
- All 30 cities deployed at launch

### 2. sBTC Treasury
- Accepts sBTC deposits (testnet sBTC first)
- Mints CityBTC tokens 1:1 with sBTC deposited
- Tracks contributions per user
- Yield distribution (when available)

### 3. CityBTC Token (SIP-010)
- Standard fungible token per city
- Format: [City]BTC / Ticker: [CITY]BTC (e.g., MiamiBTC / MIABTC)
- 1 sBTC deposited = 1,000,000 tokens (micro-units for precision)
- Transferable, tradeable
- Voting power = token balance

### 4. Election System
- Token holders delegate stake to candidates
- Top delegates become Council (pseudonymous board)
- Council appoints public Coordinator
- Coordinator proposes; Council approves
- Recall vote triggers new election

### 5. Council Multisig
- Threshold approvals (e.g., 3-of-5)
- Controls: treasury spending, proposals
- Can be recalled by token holders

## Out of Scope (v1)
- Mainnet sBTC (testnet first)
- Mobile app
- Fiat on-ramps
- Inter-city conquest/merger mechanics
- Yield strategy integrations

## Success Criteria
- All 30 cities deployable from factory
- Users can deposit testnet sBTC → receive tokens
- Treasury tracks all contributions
- Election system functional
- Council can execute treasury actions

## Technical Notes

**Stack**:
- Stacks blockchain (Clarity smart contracts)
- Testnet sBTC for treasury asset
- SIP-010 for governance tokens

**Contracts** (5 total):
1. `democracy-factory.clar` - Deploys city instances
2. `treasury.clar` - sBTC handling, token minting
3. `city-btc-token.clar` - SIP-010 per city
4. `election.clar` - Delegation, voting, recall
5. `council.clar` - Multisig governance

**30 Cities**:
```
North America (8): Austin, Las Vegas, Los Angeles, Mexico City, Miami, NYC, SF, Toronto
Europe (8): Amsterdam, Berlin, London, Lisbon, Paris, Stockholm, Tallinn, Zürich
Oceania (3): Auckland, Melbourne, Sydney
Asia (8): Bangalore, Bangkok, Dubai, Ho Chi Minh, Seoul, Singapore, Tel Aviv, Tokyo
Africa (3): Lagos, Cairo, Cape Town
```

**Token Naming**:
- MiamiBTC (MIABTC), TokyoBTC (TOKBTC), LondonBTC (LONBTC), etc.

---

**Tagline**: Deposit sBTC. Vote with Bitcoin. Build your city.
