import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

/**
 * Integration Tests
 * Full flow: deposit → mint → delegate → elect → execute
 */

Clarinet.test({
  name: "integration: full governance flow - deposit to council execution",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const voter1 = accounts.get('wallet_1')!;
    const voter2 = accounts.get('wallet_2')!;
    const voter3 = accounts.get('wallet_3')!;
    const candidate1 = accounts.get('wallet_4')!;
    const candidate2 = accounts.get('wallet_5')!;

    // === SETUP ===

    // 1. Authorize treasury to mint tokens
    let block = chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);
    block.receipts[0].result.expectOk();

    // 2. Set council as authorized for treasury spending
    block = chain.mineBlock([
      Tx.contractCall('treasury', 'set-council-contract', [
        types.principal(`${deployer.address}.council`),
      ], deployer.address),
    ]);
    block.receipts[0].result.expectOk();

    // === DEPOSIT PHASE ===

    // 3. Get mock sBTC for voters
    block = chain.mineBlock([
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(100000000), types.principal(voter1.address)], voter1.address),
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(200000000), types.principal(voter2.address)], voter2.address),
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(150000000), types.principal(voter3.address)], voter3.address),
    ]);
    assertEquals(block.receipts.length, 3);

    // 4. Deposit sBTC to treasury
    block = chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], voter1.address),
      Tx.contractCall('treasury', 'deposit', [types.uint(200000000)], voter2.address),
      Tx.contractCall('treasury', 'deposit', [types.uint(150000000)], voter3.address),
    ]);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectOk();
    block.receipts[2].result.expectOk();

    // Verify token balances
    let balance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(voter1.address),
    ], deployer.address);
    balance.result.expectOk().expectUint(1000000000000); // 1T tokens

    balance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(voter2.address),
    ], deployer.address);
    balance.result.expectOk().expectUint(2000000000000); // 2T tokens

    // === ELECTION PHASE ===

    // 5. Register candidates
    block = chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], candidate1.address),
      Tx.contractCall('election', 'register-candidate', [], candidate2.address),
      Tx.contractCall('election', 'register-candidate', [], voter1.address),
      Tx.contractCall('election', 'register-candidate', [], voter2.address),
      Tx.contractCall('election', 'register-candidate', [], voter3.address),
    ]);
    assertEquals(block.receipts.length, 5);

    // 6. Delegate votes
    // voter1 (1T) → candidate1
    // voter2 (2T) → candidate1
    // voter3 (1.5T) → candidate2
    block = chain.mineBlock([
      Tx.contractCall('election', 'delegate', [types.principal(candidate1.address)], voter1.address),
      Tx.contractCall('election', 'delegate', [types.principal(candidate1.address)], voter2.address),
      Tx.contractCall('election', 'delegate', [types.principal(candidate2.address)], voter3.address),
    ]);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectOk();
    block.receipts[2].result.expectOk();

    // Verify vote totals
    let votes = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(candidate1.address),
    ], deployer.address);
    votes.result.expectUint(3000000000000); // 3T votes

    votes = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(candidate2.address),
    ], deployer.address);
    votes.result.expectUint(1500000000000); // 1.5T votes

    // 7. Tally election - form council
    block = chain.mineBlock([
      Tx.contractCall('election', 'tally-election', [
        types.list([
          types.principal(candidate1.address),
          types.principal(candidate2.address),
          types.principal(voter1.address),
          types.principal(voter2.address),
          types.principal(voter3.address),
        ]),
      ], deployer.address),
    ]);
    block.receipts[0].result.expectOk();

    // Verify council membership
    let isMember = chain.callReadOnlyFn('election', 'is-council-member', [
      types.principal(candidate1.address),
    ], deployer.address);
    isMember.result.expectBool(true);

    isMember = chain.callReadOnlyFn('election', 'is-council-member', [
      types.principal(candidate2.address),
    ], deployer.address);
    isMember.result.expectBool(true);

    // === COUNCIL EXECUTION PHASE ===

    // 8. Council proposes spending (council member proposes)
    block = chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(candidate1.address), // recipient
        types.uint(10000000), // 0.1 sBTC
        types.none(),
      ], candidate1.address),
    ]);
    block.receipts[0].result.expectOk().expectUint(0);

    // 9. Get 2 more approvals (need 3 total)
    block = chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], candidate2.address),
      Tx.contractCall('council', 'vote', [types.uint(0)], voter1.address),
    ]);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectOk();

    // Verify proposal is approved
    let isApproved = chain.callReadOnlyFn('council', 'is-proposal-approved', [
      types.uint(0),
    ], deployer.address);
    isApproved.result.expectBool(true);

    // 10. Execute the spend
    block = chain.mineBlock([
      Tx.contractCall('council', 'execute-spend', [types.uint(0)], candidate1.address),
    ]);
    block.receipts[0].result.expectOk().expectBool(true);

    // Verify recipient received sBTC
    let sbtcBalance = chain.callReadOnlyFn('mock-sbtc', 'get-balance', [
      types.principal(candidate1.address),
    ], deployer.address);
    sbtcBalance.result.expectOk().expectUint(10000000);

    console.log("✅ Full governance flow completed successfully!");
  },
});

Clarinet.test({
  name: "integration: recall council member with supermajority",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const voter1 = accounts.get('wallet_1')!;
    const voter2 = accounts.get('wallet_2')!;
    const voter3 = accounts.get('wallet_3')!;
    const councilMember = accounts.get('wallet_4')!;

    // Setup
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);

    // Fund voters
    chain.mineBlock([
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(300000000), types.principal(voter1.address)], voter1.address),
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(300000000), types.principal(voter2.address)], voter2.address),
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(200000000), types.principal(voter3.address)], voter3.address),
    ]);

    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(300000000)], voter1.address),
      Tx.contractCall('treasury', 'deposit', [types.uint(300000000)], voter2.address),
      Tx.contractCall('treasury', 'deposit', [types.uint(200000000)], voter3.address),
    ]);

    // Make councilMember a council member
    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], councilMember.address),
    ]);
    chain.mineBlock([
      Tx.contractCall('election', 'tally-election', [
        types.list([types.principal(councilMember.address)]),
      ], deployer.address),
    ]);

    // Vote to recall (need 51% of total supply)
    // Total supply = 8T tokens (8 sBTC worth)
    // voter1 has 3T, voter2 has 3T = 6T (75%)

    let block = chain.mineBlock([
      Tx.contractCall('election', 'vote-recall', [types.principal(councilMember.address)], voter1.address),
      Tx.contractCall('election', 'vote-recall', [types.principal(councilMember.address)], voter2.address),
    ]);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectOk();

    // Execute recall
    block = chain.mineBlock([
      Tx.contractCall('election', 'execute-recall', [types.principal(councilMember.address)], voter1.address),
    ]);
    block.receipts[0].result.expectOk();

    // Verify member is removed
    let isMember = chain.callReadOnlyFn('election', 'is-council-member', [
      types.principal(councilMember.address),
    ], deployer.address);
    isMember.result.expectBool(false);

    console.log("✅ Recall mechanism working!");
  },
});

Clarinet.test({
  name: "integration: factory initializes all 30 cities",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;

    // Initialize all cities
    let block = chain.mineBlock([
      Tx.contractCall('democracy-factory', 'initialize-all-cities', [], deployer.address),
    ]);

    block.receipts[0].result.expectOk().expectUint(30);

    // Verify count
    let count = chain.callReadOnlyFn('democracy-factory', 'get-city-count', [], deployer.address);
    count.result.expectUint(30);

    // Spot check a few cities
    let miami = chain.callReadOnlyFn('democracy-factory', 'get-city-by-name', [
      types.ascii("Miami"),
    ], deployer.address);
    let miamiData = miami.result.expectSome().expectTuple();
    assertEquals(miamiData['token-name'], types.ascii("MiamiBTC"));
    assertEquals(miamiData['ticker'], types.ascii("MIABTC"));

    let tokyo = chain.callReadOnlyFn('democracy-factory', 'get-city-by-name', [
      types.ascii("Tokyo"),
    ], deployer.address);
    let tokyoData = tokyo.result.expectSome().expectTuple();
    assertEquals(tokyoData['token-name'], types.ascii("TokyoBTC"));
    assertEquals(tokyoData['ticker'], types.ascii("TOKBTC"));

    let lagos = chain.callReadOnlyFn('democracy-factory', 'get-city-by-name', [
      types.ascii("Lagos"),
    ], deployer.address);
    let lagosData = lagos.result.expectSome().expectTuple();
    assertEquals(lagosData['token-name'], types.ascii("LagosBTC"));
    assertEquals(lagosData['ticker'], types.ascii("LAGBTC"));

    // Check regional groupings
    let naCity = chain.callReadOnlyFn('democracy-factory', 'get-north-america-cities', [], deployer.address);
    let naCities = naCity.result.expectList();
    assertEquals(naCities.length, 8);

    let asiaCities = chain.callReadOnlyFn('democracy-factory', 'get-asia-cities', [], deployer.address);
    assertEquals(asiaCities.result.expectList().length, 8);

    console.log("✅ All 30 cities initialized correctly!");
  },
});

Clarinet.test({
  name: "integration: withdraw sBTC after burning tokens",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;

    // Setup
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);

    // Get and deposit sBTC
    chain.mineBlock([
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(100000000), types.principal(user.address)], user.address),
    ]);

    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], user.address),
    ]);

    // Verify initial state
    let tokenBalance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(user.address),
    ], deployer.address);
    tokenBalance.result.expectOk().expectUint(1000000000000);

    let sbtcBalance = chain.callReadOnlyFn('mock-sbtc', 'get-balance', [
      types.principal(user.address),
    ], deployer.address);
    sbtcBalance.result.expectOk().expectUint(0);

    // Withdraw half
    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'withdraw', [types.uint(500000000000)], user.address),
    ]);
    block.receipts[0].result.expectOk().expectUint(50000000); // 0.5 sBTC

    // Verify final state
    tokenBalance = chain.callReadOnlyFn('city-btc-token', 'get-balance', [
      types.principal(user.address),
    ], deployer.address);
    tokenBalance.result.expectOk().expectUint(500000000000);

    sbtcBalance = chain.callReadOnlyFn('mock-sbtc', 'get-balance', [
      types.principal(user.address),
    ], deployer.address);
    sbtcBalance.result.expectOk().expectUint(50000000);

    console.log("✅ Deposit/withdraw cycle works correctly!");
  },
});

Clarinet.test({
  name: "integration: delegation updates when balance changes",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const voter = accounts.get('wallet_1')!;
    const candidate = accounts.get('wallet_2')!;

    // Setup
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
    ]);

    // Initial deposit
    chain.mineBlock([
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(100000000), types.principal(voter.address)], voter.address),
    ]);
    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], voter.address),
    ]);

    // Register and delegate
    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], candidate.address),
    ]);
    chain.mineBlock([
      Tx.contractCall('election', 'delegate', [types.principal(candidate.address)], voter.address),
    ]);

    // Check initial votes
    let votes = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(candidate.address),
    ], deployer.address);
    votes.result.expectUint(1000000000000);

    // Deposit more sBTC
    chain.mineBlock([
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(100000000), types.principal(voter.address)], voter.address),
    ]);
    chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], voter.address),
    ]);

    // Refresh delegation
    let block = chain.mineBlock([
      Tx.contractCall('election', 'refresh-delegation', [], voter.address),
    ]);
    block.receipts[0].result.expectOk();

    // Votes should double
    votes = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(candidate.address),
    ], deployer.address);
    votes.result.expectUint(2000000000000);

    console.log("✅ Delegation refresh works correctly!");
  },
});

Clarinet.test({
  name: "integration: pausing prevents operations",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;

    // Setup
    chain.mineBlock([
      Tx.contractCall('city-btc-token', 'set-authorized-minter', [
        types.principal(`${deployer.address}.treasury`),
      ], deployer.address),
      Tx.contractCall('mock-sbtc', 'faucet', [types.uint(100000000), types.principal(user.address)], user.address),
    ]);

    // Pause treasury
    chain.mineBlock([
      Tx.contractCall('treasury', 'set-paused', [types.bool(true)], deployer.address),
    ]);

    // Try to deposit - should fail
    let block = chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], user.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(101); // err-paused

    // Pause elections
    chain.mineBlock([
      Tx.contractCall('election', 'set-election-active', [types.bool(false)], deployer.address),
    ]);

    // Try to register - should fail
    block = chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], user.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(105); // err-election-not-active

    // Resume both
    chain.mineBlock([
      Tx.contractCall('treasury', 'set-paused', [types.bool(false)], deployer.address),
      Tx.contractCall('election', 'set-election-active', [types.bool(true)], deployer.address),
    ]);

    // Now operations should work
    block = chain.mineBlock([
      Tx.contractCall('treasury', 'deposit', [types.uint(100000000)], user.address),
      Tx.contractCall('election', 'register-candidate', [], user.address),
    ]);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectOk();

    console.log("✅ Pause/resume mechanisms work correctly!");
  },
});
