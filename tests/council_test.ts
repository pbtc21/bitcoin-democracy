import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

// Helper to setup council with 5 members
function setupCouncil(chain: Chain, deployer: Account, members: Account[]) {
  // Register all as candidates
  chain.mineBlock(
    members.map((m) =>
      Tx.contractCall('election', 'register-candidate', [], m.address)
    )
  );

  // Tally election
  chain.mineBlock([
    Tx.contractCall('election', 'tally-election', [
      types.list(members.map((m) => types.principal(m.address))),
    ], deployer.address),
  ]);
}

// Helper to fund treasury
function fundTreasury(chain: Chain, deployer: Account, funder: Account, amount: number) {
  // Authorize treasury to mint tokens
  chain.mineBlock([
    Tx.contractCall('city-btc-token', 'set-authorized-minter', [
      types.principal(`${deployer.address}.treasury`),
    ], deployer.address),
  ]);

  // Get mock sBTC
  chain.mineBlock([
    Tx.contractCall('mock-sbtc', 'faucet', [
      types.uint(amount),
      types.principal(funder.address),
    ], funder.address),
  ]);

  // Deposit to treasury
  chain.mineBlock([
    Tx.contractCall('treasury', 'deposit', [types.uint(amount)], funder.address),
  ]);

  // Set council contract as authorized for spending
  chain.mineBlock([
    Tx.contractCall('treasury', 'set-council-contract', [
      types.principal(`${deployer.address}.council`),
    ], deployer.address),
  ]);
}

Clarinet.test({
  name: "council: council member can create spend proposal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    let block = chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000000),
        types.none(),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectUint(0);

    const proposal = chain.callReadOnlyFn('council', 'get-proposal', [
      types.uint(0),
    ], deployer.address);

    const result = proposal.result.expectSome().expectTuple();
    assertEquals(result['proposal-type'], types.uint(1)); // spend
    assertEquals(result['amount'], types.uint(1000000));
    assertEquals(result['approval-count'], types.uint(1)); // proposer auto-votes
  },
});

Clarinet.test({
  name: "council: non-council member cannot create proposal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet5 = accounts.get('wallet_5')!;

    // wallet1 is NOT on council
    let block = chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000000),
        types.none(),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(101); // err-not-council-member
  },
});

Clarinet.test({
  name: "council: council members can vote on proposal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    // Create proposal
    chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000000),
        types.none(),
      ], wallet1.address),
    ]);

    // wallet2 votes
    let block = chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet2.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const proposal = chain.callReadOnlyFn('council', 'get-proposal', [
      types.uint(0),
    ], deployer.address);

    const result = proposal.result.expectSome().expectTuple();
    assertEquals(result['approval-count'], types.uint(2));
  },
});

Clarinet.test({
  name: "council: cannot vote twice",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000000),
        types.none(),
      ], wallet1.address),
    ]);

    // wallet1 already voted as proposer, try again
    let block = chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(103); // err-already-voted
  },
});

Clarinet.test({
  name: "council: can execute spend with 3 approvals",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);
    fundTreasury(chain, deployer, deployer, 100000000);

    // Create proposal
    chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(10000000), // 0.1 sBTC
        types.none(),
      ], wallet1.address),
    ]);

    // Get 2 more votes (total 3)
    chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet2.address),
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet3.address),
    ]);

    // Check it's approved
    const isApproved = chain.callReadOnlyFn('council', 'is-proposal-approved', [
      types.uint(0),
    ], deployer.address);
    isApproved.result.expectBool(true);

    // Execute
    let block = chain.mineBlock([
      Tx.contractCall('council', 'execute-spend', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    // Check proposal marked executed
    const proposal = chain.callReadOnlyFn('council', 'get-proposal', [
      types.uint(0),
    ], deployer.address);
    const result = proposal.result.expectSome().expectTuple();
    assertEquals(result['executed'], types.bool(true));
  },
});

Clarinet.test({
  name: "council: cannot execute without enough approvals",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000000),
        types.none(),
      ], wallet1.address),
    ]);

    // Only 1 vote (proposer), need 3
    let block = chain.mineBlock([
      Tx.contractCall('council', 'execute-spend', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(108); // err-threshold-not-met
  },
});

Clarinet.test({
  name: "council: can appoint coordinator",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    // Propose coordinator
    chain.mineBlock([
      Tx.contractCall('council', 'propose-coordinator', [
        types.principal(wallet5.address),
      ], wallet1.address),
    ]);

    // Get approvals
    chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet2.address),
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet3.address),
    ]);

    // Execute
    let block = chain.mineBlock([
      Tx.contractCall('council', 'execute-coordinator', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const coordinator = chain.callReadOnlyFn('council', 'get-coordinator', [], deployer.address);
    coordinator.result.expectSome().expectPrincipal(wallet5.address);
  },
});

Clarinet.test({
  name: "council: cannot execute twice",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    chain.mineBlock([
      Tx.contractCall('council', 'propose-coordinator', [
        types.principal(wallet5.address),
      ], wallet1.address),
    ]);

    chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet2.address),
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet3.address),
    ]);

    chain.mineBlock([
      Tx.contractCall('council', 'execute-coordinator', [types.uint(0)], wallet1.address),
    ]);

    // Try to execute again
    let block = chain.mineBlock([
      Tx.contractCall('council', 'execute-coordinator', [types.uint(0)], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(106); // err-proposal-already-executed
  },
});

Clarinet.test({
  name: "council: proposal nonce increments",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    let nonce = chain.callReadOnlyFn('council', 'get-proposal-nonce', [], deployer.address);
    nonce.result.expectUint(0);

    chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000),
        types.none(),
      ], wallet1.address),
    ]);

    nonce = chain.callReadOnlyFn('council', 'get-proposal-nonce', [], deployer.address);
    nonce.result.expectUint(1);

    chain.mineBlock([
      Tx.contractCall('council', 'propose-coordinator', [
        types.principal(wallet5.address),
      ], wallet2.address),
    ]);

    nonce = chain.callReadOnlyFn('council', 'get-proposal-nonce', [], deployer.address);
    nonce.result.expectUint(2);
  },
});

Clarinet.test({
  name: "council: can check if proposal can be executed",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    setupCouncil(chain, deployer, [wallet1, wallet2, wallet3, wallet4, wallet5]);

    chain.mineBlock([
      Tx.contractCall('council', 'propose-spend', [
        types.principal(wallet5.address),
        types.uint(1000),
        types.none(),
      ], wallet1.address),
    ]);

    // Not enough votes yet
    let canExecute = chain.callReadOnlyFn('council', 'can-execute', [
      types.uint(0),
    ], deployer.address);
    canExecute.result.expectBool(false);

    // Add more votes
    chain.mineBlock([
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet2.address),
      Tx.contractCall('council', 'vote', [types.uint(0)], wallet3.address),
    ]);

    canExecute = chain.callReadOnlyFn('council', 'can-execute', [
      types.uint(0),
    ], deployer.address);
    canExecute.result.expectBool(true);
  },
});
