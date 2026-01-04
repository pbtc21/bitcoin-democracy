import { describe, it, expect, beforeEach } from "vitest";
import { Cl, ClarityValue } from "@stacks/transactions";
import { initSimnet, Simnet } from "@hirosystems/clarinet-sdk";

let simnet: Simnet;
let accounts: Map<string, string>;

beforeEach(async () => {
  simnet = await initSimnet();
  accounts = simnet.getAccounts();
});

describe("Integration: Full Governance Flow", () => {
  it("deposit → mint → delegate → elect → execute", async () => {
    const deployer = accounts.get("deployer")!;
    const voter1 = accounts.get("wallet_1")!;
    const voter2 = accounts.get("wallet_2")!;
    const voter3 = accounts.get("wallet_3")!;
    const candidate1 = accounts.get("wallet_4")!;
    const candidate2 = accounts.get("wallet_5")!;

    // === SETUP ===

    // 1. Authorize treasury to mint tokens
    let result = simnet.callPublicFn(
      "city-btc-token",
      "set-authorized-minter",
      [Cl.principal(`${deployer}.treasury`)],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));

    // 2. Set council as authorized for treasury spending
    result = simnet.callPublicFn(
      "treasury",
      "set-council-contract",
      [Cl.principal(`${deployer}.council`)],
      deployer
    );
    expect(result.result).toBeOk(Cl.bool(true));

    // === DEPOSIT PHASE ===

    // 3. Get mock sBTC for voters
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(100000000), Cl.principal(voter1)], voter1);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(200000000), Cl.principal(voter2)], voter2);
    simnet.callPublicFn("mock-sbtc", "faucet", [Cl.uint(150000000), Cl.principal(voter3)], voter3);

    // 4. Deposit sBTC to treasury
    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(100000000)], voter1);
    expect(result.result).toBeOk(Cl.uint(1000000000000)); // 1T tokens

    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(200000000)], voter2);
    expect(result.result).toBeOk(Cl.uint(2000000000000)); // 2T tokens

    result = simnet.callPublicFn("treasury", "deposit", [Cl.uint(150000000)], voter3);
    expect(result.result).toBeOk(Cl.uint(1500000000000)); // 1.5T tokens

    // Verify token balances
    let readResult = simnet.callReadOnlyFn(
      "city-btc-token",
      "get-balance",
      [Cl.principal(voter1)],
      deployer
    );
    expect(readResult.result).toBeOk(Cl.uint(1000000000000));

    // === ELECTION PHASE ===

    // 5. Register candidates
    simnet.callPublicFn("election", "register-candidate", [], candidate1);
    simnet.callPublicFn("election", "register-candidate", [], candidate2);
    simnet.callPublicFn("election", "register-candidate", [], voter1);
    simnet.callPublicFn("election", "register-candidate", [], voter2);
    simnet.callPublicFn("election", "register-candidate", [], voter3);

    // 6. Delegate votes
    result = simnet.callPublicFn("election", "delegate", [Cl.principal(candidate1)], voter1);
    expect(result.result).toBeOk(Cl.uint(1000000000000));

    result = simnet.callPublicFn("election", "delegate", [Cl.principal(candidate1)], voter2);
    expect(result.result).toBeOk(Cl.uint(2000000000000));

    result = simnet.callPublicFn("election", "delegate", [Cl.principal(candidate2)], voter3);
    expect(result.result).toBeOk(Cl.uint(1500000000000));

    // Verify vote totals
    readResult = simnet.callReadOnlyFn(
      "election",
      "get-candidate-votes",
      [Cl.principal(candidate1)],
      deployer
    );
    expect(readResult.result).toBeUint(3000000000000);

    // 7. Tally election - form council
    result = simnet.callPublicFn(
      "election",
      "tally-election",
      [Cl.list([
        Cl.principal(candidate1),
        Cl.principal(candidate2),
        Cl.principal(voter1),
        Cl.principal(voter2),
        Cl.principal(voter3),
      ])],
      deployer
    );
    expect(result.result).toBeOk(Cl.list([
      Cl.principal(candidate1),
      Cl.principal(candidate2),
      Cl.principal(voter1),
      Cl.principal(voter2),
      Cl.principal(voter3),
    ]));

    // Verify council membership
    readResult = simnet.callReadOnlyFn(
      "election",
      "is-council-member",
      [Cl.principal(candidate1)],
      deployer
    );
    expect(readResult.result).toBeBool(true);

    // === COUNCIL EXECUTION PHASE ===

    // 8. Council proposes spending
    result = simnet.callPublicFn(
      "council",
      "propose-spend",
      [Cl.principal(candidate1), Cl.uint(10000000), Cl.none()],
      candidate1
    );
    expect(result.result).toBeOk(Cl.uint(0));

    // 9. Get 2 more approvals (need 3 total)
    result = simnet.callPublicFn("council", "vote", [Cl.uint(0)], candidate2);
    expect(result.result).toBeOk(Cl.bool(true));

    result = simnet.callPublicFn("council", "vote", [Cl.uint(0)], voter1);
    expect(result.result).toBeOk(Cl.bool(true));

    // Verify proposal is approved
    readResult = simnet.callReadOnlyFn(
      "council",
      "is-proposal-approved",
      [Cl.uint(0)],
      deployer
    );
    expect(readResult.result).toBeBool(true);

    // 10. Execute the spend
    result = simnet.callPublicFn("council", "execute-spend", [Cl.uint(0)], candidate1);
    expect(result.result).toBeOk(Cl.bool(true));

    // Verify recipient received sBTC
    readResult = simnet.callReadOnlyFn(
      "mock-sbtc",
      "get-balance",
      [Cl.principal(candidate1)],
      deployer
    );
    expect(readResult.result).toBeOk(Cl.uint(10000000));
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
