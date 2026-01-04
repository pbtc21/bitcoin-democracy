import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertStringIncludes } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

// Helper to get mock sBTC and approve treasury
function setupDepositor(chain: Chain, depositor: Account, amount: number) {
  return chain.mineBlock([
    // Get mock sBTC from faucet
    Tx.contractCall('mock-sbtc', 'faucet', [
      types.uint(amount),
      types.principal(depositor.address),
    ], depositor.address),
  ]);
}

Clarinet.test({
  name: "treasury: can deposit sBTC and receive governance tokens",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Setup: get mock sBTC
    setupDepositor(chain, wallet1, 100000000); // 1 sBTC

    // First authorize treasury to mint tokens
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);

    // Deposit 1 sBTC
    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [
        types.uint(100000000), // 1 sBTC (8 decimals)
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectUint(1000000000000); // 1M * 10000 = 10B tokens

    // Check token balance
    const tokenBalance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(wallet1.address),
    ], deployer.address);
    tokenBalance.result.expectOk().expectUint(1000000000000);

    // Check contribution tracking
    const contribution = chain.callReadOnlyFn('treasury', 'get-contribution', [
      types.principal(wallet1.address),
    ], deployer.address);
    contribution.result.expectUint(100000000);
  },
});

Clarinet.test({
  name: "treasury: cannot deposit when paused",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    setupDepositor(chain, wallet1, 100000000);

    // Pause treasury
    chain.mineBlock([
      Tx.contractCall('treasury', 'set-paused', [types.bool(true)], deployer.address),
    ]);

    // Try to deposit
    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(101); // err-paused
  },
});

Clarinet.test({
  name: "treasury: can withdraw sBTC by burning tokens",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Setup
    setupDepositor(chain, wallet1, 100000000);
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);

    // Deposit
    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], wallet1.address),
    ]);

    // Withdraw half (500B tokens = 0.5 sBTC)
    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'withdraw', [
        types.uint(500000000000), // 500B tokens
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectUint(50000000); // 0.5 sBTC returned

    // Check remaining token balance
    const tokenBalance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(wallet1.address),
    ], deployer.address);
    tokenBalance.result.expectOk().expectUint(500000000000); // 500B remaining
  },
});

Clarinet.test({
  name: "treasury: tracks total deposits correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    // Setup
    setupDepositor(chain, wallet1, 100000000);
    setupDepositor(chain, wallet2, 200000000);
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);

    // Wallet 1 deposits 1 sBTC
    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], wallet1.address),
    ]);

    let totalDeposits = chain.callReadOnlyFn('treasury', 'get-total-deposits', [], deployer.address);
    totalDeposits.result.expectUint(100000000);

    // Wallet 2 deposits 2 sBTC
    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(200000000)], wallet2.address),
    ]);

    totalDeposits = chain.callReadOnlyFn('treasury', 'get-total-deposits', [], deployer.address);
    totalDeposits.result.expectUint(300000000);
  },
});

Clarinet.test({
  name: "treasury: conversion rate calculation is correct",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;

    // 1 sBTC = 1,000,000,000,000 tokens (1 trillion micro-units)
    // Because multiplier is 10000 and sBTC has 8 decimals
    const tokensFor1sBTC = chain.callReadOnlyFn('treasury', 'calculate-tokens-for-deposit', [
      types.uint(100000000), // 1 sBTC
    ], deployer.address);
    tokensFor1sBTC.result.expectUint(1000000000000);

    // 0.1 sBTC = 100,000,000,000 tokens
    const tokensForPointOne = chain.callReadOnlyFn('treasury', 'calculate-tokens-for-deposit', [
      types.uint(10000000), // 0.1 sBTC
    ], deployer.address);
    tokensForPointOne.result.expectUint(100000000000);

    // Reverse: 1T tokens = 1 sBTC
    const sbtcFor1T = chain.callReadOnlyFn('treasury', 'calculate-sbtc-for-withdrawal', [
      types.uint(1000000000000),
    ], deployer.address);
    sbtcFor1T.result.expectUint(100000000);
  },
});

Clarinet.test({
  name: "treasury: only deployer can pause",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'set-paused', [types.bool(true)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(100); // err-owner-only
  },
});

Clarinet.test({
  name: "treasury: only deployer can set council contract",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Non-owner cannot set
    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'set-council-contract', [
        types.principal(wallet1.address),
      ], wallet1.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(100);

    // Owner can set
    block = chain.mineBlock([
      Tx.contractCall('treasury', 'set-council-contract', [
        types.principal(`${deployer.address}.council`),
      ], deployer.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);
  },
});

Clarinet.test({
  name: "treasury: cannot deposit zero amount",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(103); // err-invalid-amount
  },
});

Clarinet.test({
  name: "treasury: cannot withdraw zero amount",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'withdraw', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(103); // err-invalid-amount
  },
});

Clarinet.test({
  name: "mock-sbtc: faucet works correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('mock-sbtc', 'faucet', [
        types.uint(100000000),
        types.principal(wallet1.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const balance = chain.callReadOnlyFn('mock-sbtc', 'get-balance', [
      types.principal(wallet1.address),
    ], deployer.address);
    balance.result.expectOk().expectUint(100000000);
  },
});
