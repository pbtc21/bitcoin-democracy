import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

// Helper to setup a user with tokens
function setupVoter(chain: Chain, deployer: Account, voter: Account, amount: number) {
  // First authorize treasury to mint
  chain.mineBlock([
    Tx.contractCall('city-btc-token', 'set-authorized-minter', [
      types.principal(`${deployer.address}.treasury`),
    ], deployer.address),
  ]);

  // Get mock sBTC and deposit
  chain.mineBlock([
    Tx.contractCall('mock-sbtc', 'faucet', [
      types.uint(amount),
      types.principal(voter.address),
    ], voter.address),
  ]);

  return chain.mineBlock([
    Tx.contractCall('treasury', 'deposit', [types.uint(amount)], voter.address),
  ]);
}

Clarinet.test({
  name: "election: can register as candidate",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    const isCandidate = chain.callReadOnlyFn('election', 'is-candidate', [
      types.principal(wallet1.address),
    ], wallet1.address);
    isCandidate.result.expectBool(true);
  },
});

Clarinet.test({
  name: "election: cannot register twice",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);

    let block = chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(102); // err-already-registered
  },
});

Clarinet.test({
  name: "election: can delegate to candidate",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    // Setup wallet1 with tokens
    setupVoter(chain, deployer, wallet1, 100000000);

    // wallet2 registers as candidate
    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet2.address),
    ]);

    // wallet1 delegates to wallet2
    let block = chain.mineBlock([
      Tx.contractCall('election', 'delegate', [
        types.principal(wallet2.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectOk();

    // Check delegation
    const delegation = chain.callReadOnlyFn('election', 'get-delegation', [
      types.principal(wallet1.address),
    ], wallet1.address);
    delegation.result.expectSome().expectPrincipal(wallet2.address);

    // Check candidate votes
    const votes = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(wallet2.address),
    ], wallet1.address);
    votes.result.expectUint(1000000000000); // 1 sBTC worth of tokens
  },
});

Clarinet.test({
  name: "election: cannot delegate to non-candidate",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    setupVoter(chain, deployer, wallet1, 100000000);

    // wallet2 is NOT a candidate
    let block = chain.mineBlock([
      Tx.contractCall('election', 'delegate', [
        types.principal(wallet2.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(101); // err-not-registered
  },
});

Clarinet.test({
  name: "election: cannot self-delegate",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    setupVoter(chain, deployer, wallet1, 100000000);

    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);

    let block = chain.mineBlock([
      Tx.contractCall('election', 'delegate', [
        types.principal(wallet1.address),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(103); // err-self-delegation
  },
});

Clarinet.test({
  name: "election: can undelegate",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    setupVoter(chain, deployer, wallet1, 100000000);

    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet2.address),
    ]);

    chain.mineBlock([
      Tx.contractCall('election', 'delegate', [
        types.principal(wallet2.address),
      ], wallet1.address),
    ]);

    let block = chain.mineBlock([
      Tx.contractCall('election', 'undelegate', [], wallet1.address),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    // Check delegation removed
    const delegation = chain.callReadOnlyFn('election', 'get-delegation', [
      types.principal(wallet1.address),
    ], wallet1.address);
    delegation.result.expectNone();

    // Check votes removed
    const votes = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(wallet2.address),
    ], wallet1.address);
    votes.result.expectUint(0);
  },
});

Clarinet.test({
  name: "election: changing delegation updates votes correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;

    setupVoter(chain, deployer, wallet1, 100000000);

    // Register both as candidates
    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet2.address),
      Tx.contractCall('election', 'register-candidate', [], wallet3.address),
    ]);

    // Delegate to wallet2
    chain.mineBlock([
      Tx.contractCall('election', 'delegate', [
        types.principal(wallet2.address),
      ], wallet1.address),
    ]);

    // Change delegation to wallet3
    chain.mineBlock([
      Tx.contractCall('election', 'delegate', [
        types.principal(wallet3.address),
      ], wallet1.address),
    ]);

    // wallet2 should have 0 votes
    const votes2 = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(wallet2.address),
    ], wallet1.address);
    votes2.result.expectUint(0);

    // wallet3 should have the votes
    const votes3 = chain.callReadOnlyFn('election', 'get-candidate-votes', [
      types.principal(wallet3.address),
    ], wallet1.address);
    votes3.result.expectUint(1000000000000);
  },
});

Clarinet.test({
  name: "election: deployer can tally election",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;
    const wallet3 = accounts.get('wallet_3')!;
    const wallet4 = accounts.get('wallet_4')!;
    const wallet5 = accounts.get('wallet_5')!;

    // Register 5 candidates
    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
      Tx.contractCall('election', 'register-candidate', [], wallet2.address),
      Tx.contractCall('election', 'register-candidate', [], wallet3.address),
      Tx.contractCall('election', 'register-candidate', [], wallet4.address),
      Tx.contractCall('election', 'register-candidate', [], wallet5.address),
    ]);

    // Tally with top 5
    let block = chain.mineBlock([
      Tx.contractCall('election', 'tally-election', [
        types.list([
          types.principal(wallet1.address),
          types.principal(wallet2.address),
          types.principal(wallet3.address),
          types.principal(wallet4.address),
          types.principal(wallet5.address),
        ]),
      ], deployer.address),
    ]);

    block.receipts[0].result.expectOk();

    // Check council members
    const isMember1 = chain.callReadOnlyFn('election', 'is-council-member', [
      types.principal(wallet1.address),
    ], deployer.address);
    isMember1.result.expectBool(true);

    const isMember5 = chain.callReadOnlyFn('election', 'is-council-member', [
      types.principal(wallet5.address),
    ], deployer.address);
    isMember5.result.expectBool(true);
  },
});

Clarinet.test({
  name: "election: non-deployer cannot tally",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('election', 'tally-election', [
        types.list([types.principal(wallet1.address)]),
      ], wallet1.address),
    ]);

    block.receipts[0].result.expectErr().expectUint(100); // err-owner-only
  },
});

Clarinet.test({
  name: "election: can vote to recall council member",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    const wallet2 = accounts.get('wallet_2')!;

    // Setup voter with tokens
    setupVoter(chain, deployer, wallet2, 100000000);

    // Make wallet1 a council member
    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);
    chain.mineBlock([
      Tx.contractCall('election', 'tally-election', [
        types.list([types.principal(wallet1.address)]),
      ], deployer.address),
    ]);

    // Vote to recall
    let block = chain.mineBlock([
      Tx.contractCall('election', 'vote-recall', [
        types.principal(wallet1.address),
      ], wallet2.address),
    ]);

    block.receipts[0].result.expectOk();

    const recallVotes = chain.callReadOnlyFn('election', 'get-recall-votes', [
      types.principal(wallet1.address),
    ], deployer.address);
    recallVotes.result.expectUint(1000000000000);
  },
});

Clarinet.test({
  name: "election: epoch increments after tally",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    let epoch = chain.callReadOnlyFn('election', 'get-election-epoch', [], deployer.address);
    epoch.result.expectUint(1);

    chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);
    chain.mineBlock([
      Tx.contractCall('election', 'tally-election', [
        types.list([types.principal(wallet1.address)]),
      ], deployer.address),
    ]);

    epoch = chain.callReadOnlyFn('election', 'get-election-epoch', [], deployer.address);
    epoch.result.expectUint(2);
  },
});

Clarinet.test({
  name: "election: can pause and resume elections",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;

    // Pause
    chain.mineBlock([
      Tx.contractCall('election', 'set-election-active', [types.bool(false)], deployer.address),
    ]);

    // Cannot register when paused
    let block = chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);
    block.receipts[0].result.expectErr().expectUint(105); // err-election-not-active

    // Resume
    chain.mineBlock([
      Tx.contractCall('election', 'set-election-active', [types.bool(true)], deployer.address),
    ]);

    // Can register again
    block = chain.mineBlock([
      Tx.contractCall('election', 'register-candidate', [], wallet1.address),
    ]);
    block.receipts[0].result.expectOk();
  },
});
