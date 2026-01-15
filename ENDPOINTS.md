# Deployed Endpoints

All live endpoints deployed to Cloudflare Workers.

## Core x402 Services

| Endpoint | URL | Description |
|----------|-----|-------------|
| **x402 Registry** | https://registry.pbtc21.dev | Central x402 endpoint registry |
| **x402 Showcase** | https://showcase.pbtc21.dev | Demo x402 endpoints |
| **x402 Endpoint** | https://x402.pbtc21.dev | Main x402 payment endpoint |
| **x402 Alpha** | https://alpha.pbtc21.dev | Alpha testing endpoint |

## Intelligence APIs

| Endpoint | URL | Description |
|----------|-----|-------------|
| **Stacks Intel** | https://stacks-intel.p-d07.workers.dev | Token/wallet intelligence (x402 gated) |
| **sBTC DeFi Intel** | https://sbtc-intel.pbtc21.dev | sBTC DeFi intelligence |
| **Wallet Intel** | https://wallet.pbtc21.dev | Wallet analysis API |
| **Token Health** | https://token-health.p-d07.workers.dev | Token health scoring |

## sBTC Yield Products

| Endpoint | URL | Description |
|----------|-----|-------------|
| **sBTC Yield x402** | https://sbtc-yield.pbtc21.dev | Yield aggregation API |
| **sBTC Yield Vault** | https://vault.pbtc21.dev | Yield vault interface |
| **sBTC Yield Stream** | https://earn.pbtc21.dev | Streaming yield UI |
| **sBTC Print** | https://print.pbtc21.dev | sBTC yield printing |

## Landing Pages & Marketing

| Endpoint | URL | Description |
|----------|-----|-------------|
| **Bitcoin Democracy** | https://bitcoin-democracy.p-d07.workers.dev | Bitcoin Democracy landing |
| **sBTC x402 Marketing** | https://sbtc-x402.p-d07.workers.dev | sBTC x402 marketing site |
| **pBTC21 Landing** | https://pbtc21.dev | Main landing page |

## Partner Sites

All served by `x402-partner-sites` worker:

| Subdomain | URL |
|-----------|-----|
| fleek | https://fleek.pbtc21.dev |
| phala | https://phala.pbtc21.dev |
| akash | https://akash.pbtc21.dev |
| lit | https://lit.pbtc21.dev |
| chainsafe | https://chainsafe.pbtc21.dev |
| audius | https://audius.pbtc21.dev |
| livepeer | https://livepeer.pbtc21.dev |
| saturn | https://saturn.pbtc21.dev |
| render | https://render.pbtc21.dev |
| nodepay | https://nodepay.pbtc21.dev |
| zauth | https://zauth.pbtc21.dev |
| bluepay | https://bluepay.pbtc21.dev |
| heyelsa | https://heyelsa.pbtc21.dev |
| daydreams | https://daydreams.pbtc21.dev |
| heurist | https://heurist.pbtc21.dev |
| gaianet | https://gaianet.pbtc21.dev |
| creatorbuddy | https://creatorbuddy.pbtc21.dev |
| dexter | https://dexter.pbtc21.dev |
| cronos | https://cronos.pbtc21.dev |
| cashie | https://cashie.pbtc21.dev |
| cybercentry | https://cybercentry.pbtc21.dev |
| rgb | https://rgb.pbtc21.dev |
| noble | https://noble.pbtc21.dev |

## Sales & CRM

| Endpoint | URL | Description |
|----------|-----|-------------|
| **x402 CRM** | https://crm.pbtc21.dev | Dev conversion CRM |
| **x402 CRM** | https://x402-crm.p-d07.workers.dev | Dev conversion CRM (workers.dev) |

## Infrastructure

| Endpoint | URL | Description |
|----------|-----|-------------|
| **x402 Partners** | https://partners.pbtc21.dev | Partner management |
| **x402 Jobs** | https://jobs.pbtc21.dev | Job queue |
| **Contract Scout** | https://contract-scout.p-d07.workers.dev | Contract monitoring |
| **Dev Tracker** | https://dev-tracker.p-d07.workers.dev | Developer activity |

## NFTs & Collectibles

| Endpoint | URL | Description |
|----------|-----|-------------|
| **Bitcoin Faces NFT** | https://faces.pbtc21.dev | Bitcoin Faces collection |
| **Wallet ID Card** | https://id.pbtc21.dev | Wallet identity cards |

## Utility Services

| Endpoint | URL | Description |
|----------|-----|-------------|
| **Coin Refill** | https://refill.pbtc21.dev | Testnet faucet |
| **STX Arb Bot** | https://stx-arb-bot.p-d07.workers.dev | Arbitrage bot |
| **Airdrop Cannon** | https://airdrop-cannon.p-d07.workers.dev | Token distribution |
| **Vinyl Flip** | https://shelly.pbtc21.dev | Vinyl marketplace |
| **x402 Meme** | https://meme.pbtc21.dev | Meme generator |
| **Bloombrush** | https://bloombrush.p-d07.workers.dev | Creative tools |
| **Pool Cigars** | https://pool-cigars.p-d07.workers.dev | Pool tools |
| **Nichols Dynasty** | https://nichols-dynasty.p-d07.workers.dev | Dynasty tools |
| **BTC Democracy** | https://democracy.pbtc21.dev | Governance UI |
| **x402 Agents** | https://agents.pbtc21.dev | AI agents |

---

## Smart Contracts

### Mainnet

| Contract | Address |
|----------|---------|
| **x402-sbtc** | `SP2J6CYV7YEBQANTA668TVB2PE30EE09J2XN5SFVS.x402-sbtc` |

### Testnet

| Contract | Address |
|----------|---------|
| **x402-gate** | `ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF.x402-gate` |

---

## Domain Status

| Domain | Status | Provider |
|--------|--------|----------|
| pbtc21.dev | Active | Cloudflare |
| potholela.com | Active | Cloudflare |
| stacksx402.com | Not Added | Needs DNS setup |

---

## Adding stacksx402.com

To add stacksx402.com to Cloudflare:

1. Go to Cloudflare Dashboard > Add Site
2. Enter `stacksx402.com`
3. Update nameservers at your registrar to:
   - `burt.ns.cloudflare.com`
   - `clarissa.ns.cloudflare.com`
4. Once active, add worker routes:
   ```bash
   # Add route for main site
   curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone-id}/workers/routes" \
     -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     -H "Content-Type: application/json" \
     --data '{"pattern": "stacksx402.com/*", "script": "sbtc-x402"}'
   ```

---

*Last updated: 2026-01-15*
