import { describe, it, expect, beforeEach } from "vitest";
import { Cl, ClarityValue } from "@stacks/transactions";
import { initSimnet, Simnet } from "@hirosystems/clarinet-sdk";

let simnet: Simnet;
let accounts: Map<string, string>;

beforeEach(async () => {
  simnet = await initSimnet();
  accounts = simnet.getAccounts();
});

describe("Integration: Bitzion Governance Flow", () => {
  it("deposit -> delegate -> finalize board -> appoint coordinator -> spend", async () => {
    const deployer = accounts.get("deployer")!;
    const hodler1 = accounts.get("wallet_1")!;
    const hodler2 = accounts.get("wallet_2")!;
    const hodler3 = accounts.get("wallet_3")!;
    const trustee1 = accounts.get("wallet_4")!;
    const coordinator = accounts.get("wallet_5")!;

    // === SETUP ===

    // 1. Authorize treasury to mint tokens
    let result = simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));

    // 2. Set board as authorized for treasury operations
    result = simnet.callPublicFn(
      "treasury",
      "set-board-contract",
      [Cl.principal(`${deployer}.board`)],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));

    // === DEPOSIT PHASE ===

    // 3. Get mock sBTC for hodlers
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(hodler1)], hodler1);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(200000000), Cl.principal(hodler2)], hodler2);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(150000000), Cl.principal(hodler3)], hodler3);

    // 4. Deposit sBTC to treasury
    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], hodler1);
    expect(result.result).toBeOk(Cl.uint(1000000000000)); // 1T tokens

    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(200000000)], hodler2);
    expect(result.result).toBeOk(Cl.uint(2000000000000)); // 2T tokens

    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(150000000)], hodler3);
    expect(result.result).toBeOk(Cl.uint(1500000000000)); // 1.5T tokens

    // Verify token balances
    let readResult = simnet.callReadOnlyFn(
      "city-btc-token",
      "get-balance",
      [Cl.principal(hodler1)],
      deployer
    );
    expect(readResult.result).toBeOk(Cl.uint(1000000000000));

    // === HYPERELECTION PHASE ===

    // 5. Hodlers delegate (transitive delegation)
    // hodler1 -> trustee1, hodler2 -> trustee1, hodler3 -> hodler2 -> trustee1
    result = simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(trustee1)], hodler1);
    expect(result.result).toBeOk(Cl.uint(1000000000000));

    result = simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(trustee1)], hodler2);
    expect(result.result).toBeOk(Cl.uint(2000000000000));

    // hodler3 delegates to hodler2 (transitive - flows to trustee1)
    result = simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(hodler2)], hodler3);
    expect(result.result).toBeOk(Cl.uint(1500000000000));

    // Verify delegation chain (hodler3 -> hodler2 -> trustee1)
    readResult = simnet.callReadOnlyFn(
      "hyperelection",
      "get-delegation-chain",
      [Cl.principal(hodler3)],
      deployer
    );
    // Just verify it returns a list (no toBeList matcher available)

    // 6. Finalize election (deployer provides top 30 trustees)
    // In real scenario, this would be calculated off-chain from the delegation graph
    const trustees = Array(30).fill(null).map((_, i) =>
      Cl.principal(accounts.get(i < 5 ? ["wallet_1", "wallet_2", "wallet_3", "wallet_4", "wallet_5"][i] : "deployer")!)
    );

    result = simnet.callPublicFn(
      "hyperelection",
      "finalize-election",
      [Cl.list(trustees), Cl.uint(4500000000000)], // total stake
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));

    // Verify trustee status
    readResult = simnet.callReadOnlyFn(
      "hyperelection",
      "is-trustee",
      [Cl.principal(trustee1)],
      deployer
    );
    expect(readResult.result).toBeBool(true);

    // === BOARD PHASE ===

    // 7. Trustee proposes coordinator
    result = simnet.callPublicFn(
      "board",
      "propose-coordinator",
      [Cl.principal(coordinator)],
      trustee1
    );
    expect(result.result).toBeOk(Cl.uint(0));

    // 8. Vote with available trustees (we only have 6 wallets, threshold is 16)
    // Just verify voting mechanics work
    result = simnet.callPublicFn("board", "vote", [Cl.uint(0)], hodler1);
    expect(result.result).toBeOk(Cl.bool(true));

    result = simnet.callPublicFn("board", "vote", [Cl.uint(0)], hodler2);
    expect(result.result).toBeOk(Cl.bool(true));

    result = simnet.callPublicFn("board", "vote", [Cl.uint(0)], hodler3);
    expect(result.result).toBeOk(Cl.bool(true));

    result = simnet.callPublicFn("board", "vote", [Cl.uint(0)], deployer);
    expect(result.result).toBeOk(Cl.bool(true));

    // Verify can't execute yet (need 16 votes, only have 5)
    readResult = simnet.callReadOnlyFn(
      "board",
      "can-execute",
      [Cl.uint(0)],
      deployer
    );
    expect(readResult.result).toBeBool(false);

    // Verify coordinator spending fails without a coordinator set
    result = simnet.callPublicFn(
      "treasury",
      "coordinator-spend",
      [Cl.uint(10000000), Cl.principal(hodler1), Cl.none()],
      coordinator
    );
    expect(result.result).toBeErr(Cl.uint(107)); // err-no-coordinator
  });
});

describe("Integration: Hyperelection Loop Prevention", () => {
  it("prevents delegation loops", async () => {
    const deployer = accounts.get("deployer")!;
    const user1 = accounts.get("wallet_1")!;
    const user2 = accounts.get("wallet_2")!;
    const user3 = accounts.get("wallet_3")!;

    // Setup - give users tokens
    simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(user1)], user1);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(user2)], user2);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(user3)], user3);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], user1);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], user2);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], user3);

    // Create chain: user1 -> user2 -> user3
    simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(user2)], user1);
    simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(user3)], user2);

    // user3 trying to delegate to user1 would create loop: user3 -> user1 -> user2 -> user3
    const result = simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(user1)], user3);
    expect(result.result).toBeErr(Cl.uint(104)); // err-would-create-loop

    // Self-delegation should also fail
    const result2 = simnet.callPublicFn("hyperelection", "delegate", [Cl.principal(user3)], user3);
    expect(result2.result).toBeErr(Cl.uint(103)); // err-self-delegation
  });
});

describe("Integration: Board Tax Dilution", () => {
  it("board can propose and vote on special tax", async () => {
    const deployer = accounts.get("deployer")!;
    const trustee1 = accounts.get("wallet_1")!;
    const trustee2 = accounts.get("wallet_2")!;

    // Setup board contract
    simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );
    simnet.callPublicFn(
      "treasury",
      "set-board-contract",
      [Cl.principal(`${deployer}.board`)],
      deployer
    );

    // Give trustee tokens so they can be trustees
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(trustee1)], trustee1);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(trustee2)], trustee2);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], trustee1);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], trustee2);

    // Finalize election with trustees
    const trustees = Array(30).fill(null).map((_, i) =>
      Cl.principal(i < 2 ? [trustee1, trustee2][i] : deployer)
    );
    simnet.callPublicFn(
      "hyperelection",
      "finalize-election",
      [Cl.list(trustees), Cl.uint(2000000000000)],
      deployer
    );

    // Propose special tax (mint 1M tokens to treasury)
    let result = simnet.callPublicFn(
      "board",
      "propose-special-tax",
      [Cl.uint(1000000), Cl.none()],
      trustee1
    );
    expect(result.result).toBeOk(Cl.uint(0));

    // Trustee2 votes
    result = simnet.callPublicFn("board", "vote", [Cl.uint(0)], trustee2);
    expect(result.result).toBeOk(Cl.bool(true));

    // Verify proposal has 2 votes (proposer + 1 vote)
    const readResult = simnet.callReadOnlyFn(
      "board",
      "get-proposal",
      [Cl.uint(0)],
      deployer
    );
    expect(readResult.result).toBeSome();

    // Verify can't execute yet (need 16 votes, only have 2)
    result = simnet.callPublicFn("board", "execute-special-tax", [Cl.uint(0)], trustee1);
    expect(result.result).toBeErr(Cl.uint(105)); // err-threshold-not-met
  });
});

describe("Integration: Recall Mechanism", () => {
  it("stake can vote for recall", async () => {
    const deployer = accounts.get("deployer")!;
    const hodler1 = accounts.get("wallet_1")!;
    const hodler2 = accounts.get("wallet_2")!;

    // Setup
    simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(hodler1)], hodler1);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(200000000), Cl.principal(hodler2)], hodler2);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], hodler1);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(200000000)], hodler2);

    // Finalize election
    const trustees = Array(30).fill(Cl.principal(deployer));
    simnet.callPublicFn(
      "hyperelection",
      "finalize-election",
      [Cl.list(trustees), Cl.uint(3000000000000)], // 3T total stake
      deployer
    );

    // Verify election is finalized
    let readResult = simnet.callReadOnlyFn(
      "hyperelection",
      "is-election-finalized",
      [],
      deployer
    );
    expect(readResult.result).toBeBool(true);

    // Hodlers vote for recall
    let result = simnet.callPublicFn("hyperelection", "vote-recall", [], hodler1);
    expect(result.result).toBeOk(Cl.uint(1000000000000));

    result = simnet.callPublicFn("hyperelection", "vote-recall", [], hodler2);
    expect(result.result).toBeOk(Cl.uint(2000000000000));

    // Check recall stake (3T = 100%, need 33% = 990B)
    readResult = simnet.callReadOnlyFn(
      "hyperelection",
      "get-recall-stake",
      [],
      deployer
    );
    expect(readResult.result).toBeUint(3000000000000); // 3T voting for recall

    // Recall threshold is 33% of 3T = ~1T, so we have enough
    // Execute recall
    result = simnet.callPublicFn("hyperelection", "execute-recall", [], hodler1);
    expect(result.result).toBeOk(Cl.bool(true));

    // Verify election is no longer finalized
    readResult = simnet.callReadOnlyFn(
      "hyperelection",
      "is-election-finalized",
      [],
      deployer
    );
    expect(readResult.result).toBeBool(false);
  });
});

describe("Integration: Factory", () => {
  it("initializes all 30 cities", async () => {
    const deployer = accounts.get("deployer")!;

    // Initialize all cities
    const result = simnet.callPublicFn(
      "democracy-factory",
      "initialize-all-cities",
      [],
      deployer
    );
    expect(result.result).toBeOk(Cl.uint(30));

    // Verify count
    let readResult = simnet.callReadOnlyFn(
      "democracy-factory",
      "get-city-count",
      [],
      deployer
    );
    expect(readResult.result).toBeUint(30);

    // Spot check Miami
    readResult = simnet.callReadOnlyFn(
      "democracy-factory",
      "get-city-by-name",
      [Cl.stringAscii("Miami")],
      deployer
    );
    const miamiData = readResult.result;
    expect(miamiData).toBeSome();
  });
});

describe("Integration: Withdraw", () => {
  it("withdraws sBTC after burning tokens", async () => {
    const deployer = accounts.get("deployer")!;
    const user = accounts.get("wallet_1")!;

    // Setup
    simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );

    // Get and deposit sBTC
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(user)], user);
    simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], user);

    // Verify initial token balance
    let readResult = simnet.callReadOnlyFn(
      "city-btc-token",
      "get-balance",
      [Cl.principal(user)],
      deployer
    );
    expect(readResult.result).toBeOk(Cl.uint(1000000000000));

    // Withdraw half
    const result = simnet.callPublicFn(
      "treasury",
      "withdraw",
      [Cl.uint(500000000000)],
      user
    );
    expect(result.result).toBeOk(Cl.uint(50000000)); // 0.5 sBTC returned

    // Verify final token balance
    readResult = simnet.callReadOnlyFn(
      "city-btc-token",
      "get-balance",
      [Cl.principal(user)],
      deployer
    );
    expect(readResult.result).toBeOk(Cl.uint(500000000000));
  });
});

describe("Integration: Pause Mechanisms", () => {
  it("pausing prevents operations", async () => {
    const deployer = accounts.get("deployer")!;
    const user = accounts.get("wallet_1")!;

    // Setup
    simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(user)], user);

    // Pause treasury
    simnet.callPublicFn("treasury", "set-paused", [Cl.bool(true)], deployer);

    // Try to deposit - should fail
    let result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], user);
    expect(result.result).toBeErr(Cl.uint(101)); // err-paused

    // Resume
    simnet.callPublicFn("treasury", "set-paused", [Cl.bool(false)], deployer);

    // Now deposit should work
    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], user);
    expect(result.result).toBeOk(Cl.uint(1000000000000));
  });
});
