import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertStringIncludes } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "city-btc-token: can get token metadata",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;

    const nameResult = chain.callReadOnlyFn('city-btc-token', 'get-name', [], deployer.address);
    nameResult.result.expectOk().expectAscii('CityBTC');

    const symbolResult = chain.callReadOnlyFn('city-btc-token', 'get-symbol', [], deployer.address);
    symbolResult.result.expectOk().expectAscii('CITYBTC');

    const decimalsResult = chain.callReadOnlyFn('city-btc-token', 'get-decimals', [], deployer.address);
    decimalsResult.result.expectOk().expectUint(6);
  },
});

Clarinet.test({
  name: "city-btc-token: deployer can initialize token metadata",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;

    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'initialize', [
        types.ascii('MiamiBTC'),
        types.ascii('MIABTC'),
        types.none(),
      ], deployer.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const nameResult = chain.callReadOnlyFn('city-btc-token', 'get-name', [], deployer.address);
    nameResult.result.expectOk().expectAscii('MiamiBTC');

    const symbolResult = chain.callReadOnlyFn('city-btc-token', 'get-symbol', [], deployer.address);
    symbolResult.result.expectOk().expectAscii('MIABTC');
  },
});

Clarinet.test({
  name: "city-btc-token: non-deployer cannot initialize",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'initialize', [
        types.ascii('HackerBTC'),
        types.ascii('HACKBTC'),
        types.none(),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(100); // err-owner-only
  },
});

Clarinet.test({
  name: "city-btc-token: authorized minter can mint tokens",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Deployer is initially the authorized minter
    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet1.address),
      ], deployer.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const balanceResult = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(wallet1.address),
    ], deployer.address);
    balanceResult.result.expectOk().expectUint(1000000);
  },
});

Clarinet.test({
  name: "city-btc-token: unauthorized cannot mint",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet2.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(100); // err-owner-only
  },
});

Clarinet.test({
  name: "city-btc-token: can transfer tokens",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    // Mint tokens first
    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet1.address),
      ], deployer.address),
    ]);

    // Transfer tokens
    block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'transfer', [
        types.uint(500000),
        types.principal(wallet1.address),
        types.principal(wallet2.address),
        types.none(),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    // Check balances
    const balance1 = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(wallet1.address),
    ], deployer.address);
    balance1.result.expectOk().expectUint(500000);

    const balance2 = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(wallet2.address),
    ], deployer.address);
    balance2.result.expectOk().expectUint(500000);
  },
});

Clarinet.test({
  name: "city-btc-token: cannot transfer more than balance",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    // Mint 1M tokens
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet1.address),
      ], deployer.address),
    ]);

    // Try to transfer 2M
    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'transfer', [
        types.uint(2000000),
        types.principal(wallet1.address),
        types.principal(wallet2.address),
        types.none(),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(1); // ft-transfer error
  },
});

Clarinet.test({
  name: "city-btc-token: token holder can burn their tokens",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Mint tokens
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet1.address),
      ], deployer.address),
    ]);

    // Burn half
    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'burn', [
        types.uint(500000),
        types.principal(wallet1.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const balance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(wallet1.address),
    ], deployer.address);
    balance.result.expectOk().expectUint(500000);
  },
});

Clarinet.test({
  name: "city-btc-token: deployer can set new authorized minter",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    // Set wallet1 as new minter
    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(wallet1.address),
      ], deployer.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    // Wallet1 can now mint
    block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet2.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    // Original deployer can no longer mint
    block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet2.address),
      ], deployer.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(100);
  },
});

Clarinet.test({
  name: "city-btc-token: total supply tracks correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Initial supply is 0
    let supply = chain.callReadOnlyFn('city-btc-token', 'get-total-supply', [], deployer.address);
    supply.result.expectOk().expectUint(0);

    // Mint 1M tokens
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'mint', [
        types.uint(1000000),
        types.principal(wallet1.address),
      ], deployer.address),
    ]);

    supply = chain.callReadOnlyFn('city-btc-token', 'get-total-supply', [], deployer.address);
    supply.result.expectOk().expectUint(1000000);

    // Burn 400k tokens
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'burn', [
        types.uint(400000),
        types.principal(wallet1.address),
      ], wallet1.address),
    ]);

    supply = chain.callReadOnlyFn('city-btc-token', 'get-total-supply', [], deployer.address);
    supply.result.expectOk().expectUint(600000);
  },
});
