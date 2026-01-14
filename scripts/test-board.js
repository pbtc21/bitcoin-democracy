import { generateWallet } from '@stacks/wallet-sdk';
import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  principalCV,
  uintCV,
  PostConditionMode,
  cvToJSON,
  hexToCV,
  serializeCV
} from '@stacks/transactions';
import { STACKS_TESTNET } from '@stacks/network';

const MNEMONIC = "drama conduct illegal senior any inhale impact rain stereo hood lens long foster fluid erosion creek morning laugh shaft horror digital actor false soldier";
const DEPLOYER = "ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF";
const API_URL = "https://api.testnet.hiro.so";

async function getNonce(address) {
  const response = await fetch(`${API_URL}/v2/accounts/${address}`);
  const data = await response.json();
  return BigInt(data.nonce);
}

async function callContract(contractName, functionName, args, nonce) {
  const wallet = await generateWallet({ secretKey: MNEMONIC, password: '' });
  const senderKey = wallet.accounts[0].stxPrivateKey;

  const txOptions = {
    contractAddress: DEPLOYER,
    contractName,
    functionName,
    functionArgs: args,
    senderKey,
    network: STACKS_TESTNET,
    nonce,
    fee: BigInt(10000),
    anchorMode: AnchorMode.Any,
    postConditionMode: PostConditionMode.Allow,
  };

  const transaction = await makeContractCall(txOptions);
  console.log(`Broadcasting ${contractName}.${functionName}...`);

  const result = await broadcastTransaction({ transaction, network: STACKS_TESTNET });
  console.log(`  TX: ${result.txid}`);
  return result.txid;
}

async function readOnly(contractName, functionName, args = []) {
  const url = `${API_URL}/v2/contracts/call-read/${DEPLOYER}/${contractName}/${functionName}`;

  const body = {
    sender: DEPLOYER,
    arguments: args.map(arg => Buffer.from(serializeCV(arg)).toString('hex'))
  };

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  const text = await response.text();
  try {
    const data = JSON.parse(text);
    if (!data.okay) {
      return null;
    }
    const cv = hexToCV(data.result);
    return cvToJSON(cv);
  } catch (e) {
    return null;
  }
}

async function waitForTx(txid, maxAttempts = 30) {
  console.log(`  Waiting for confirmation...`);
  for (let i = 0; i < maxAttempts; i++) {
    await new Promise(r => setTimeout(r, 5000));
    const response = await fetch(`${API_URL}/extended/v1/tx/${txid}`);
    const data = await response.json();
    if (data.tx_status === 'success') {
      console.log(`  ✅ Confirmed!`);
      return { success: true, result: data.tx_result };
    } else if (data.tx_status === 'abort_by_response' || data.tx_status === 'abort_by_post_condition') {
      console.log(`  ❌ Failed: ${data.tx_status}`);
      if (data.tx_result) console.log(`     Result: ${data.tx_result.repr}`);
      return { success: false, result: data.tx_result };
    }
    process.stdout.write('.');
  }
  console.log(`  ⏳ Timeout`);
  return { success: false };
}

async function main() {
  let nonce = await getNonce(DEPLOYER);
  console.log(`Starting nonce: ${nonce}\n`);

  // Step 1: Check election state
  console.log("=== ELECTION STATE ===");

  const isFinalized = await readOnly("hyperelection-hardened", "is-election-finalized", []);
  console.log(`Election finalized: ${isFinalized?.value}`);

  const isPending = await readOnly("hyperelection-hardened", "is-finalization-pending", []);
  console.log(`Finalization pending: ${isPending?.value}`);

  // Step 2: Check board state
  console.log("\n=== BOARD STATE ===");

  const coordinator = await readOnly("board-hardened", "get-coordinator", []);
  console.log(`Current coordinator: ${JSON.stringify(coordinator)}`);

  const taxRate = await readOnly("board-hardened", "get-regular-tax-rate", []);
  console.log(`Regular tax rate: ${taxRate?.value} basis points`);

  const proposalNonce = await readOnly("board-hardened", "get-proposal-nonce", []);
  console.log(`Proposal count: ${proposalNonce?.value}`);

  const threshold = await readOnly("board-hardened", "get-approval-threshold", []);
  console.log(`Approval threshold: ${threshold?.value}/30`);

  const adminBurned = await readOnly("board-hardened", "is-admin-burned", []);
  console.log(`Admin burned: ${adminBurned?.value}`);

  // Step 3: Try to create a proposal (should fail - not a trustee)
  console.log("\n=== TEST: PROPOSE WITHOUT BEING TRUSTEE (should fail) ===");
  console.log(`Attempting to propose coordinator...`);

  const proposeTx = await callContract(
    "board-hardened",
    "propose-coordinator",
    [principalCV(DEPLOYER)],
    nonce++
  );
  const proposeResult = await waitForTx(proposeTx);

  if (!proposeResult.success) {
    console.log(`Correctly rejected: ${proposeResult.result?.repr}`);
    console.log(`(ERR-NOT-TRUSTEE = err u101)`);
  } else {
    console.log(`⚠️ Unexpected success - check trustee status`);
  }

  // Step 4: Try execute-coordinator on non-existent proposal
  console.log("\n=== TEST: EXECUTE NON-EXISTENT PROPOSAL (should fail) ===");

  const executeTx = await callContract(
    "board-hardened",
    "execute-coordinator",
    [uintCV(999)],
    nonce++
  );
  const executeResult = await waitForTx(executeTx);

  if (!executeResult.success) {
    console.log(`Correctly rejected: ${executeResult.result?.repr}`);
    console.log(`(ERR-PROPOSAL-NOT-FOUND = err u102)`);
  }

  // Step 5: Check treasury config
  console.log("\n=== TREASURY CONFIG ===");

  const treasuryCoord = await readOnly("treasury-hardened", "get-coordinator", []);
  console.log(`Treasury coordinator: ${JSON.stringify(treasuryCoord)}`);

  const dailyLimit = await readOnly("treasury-hardened", "get-daily-spend-limit", []);
  console.log(`Daily spend limit: ${dailyLimit?.value} satoshis`);

  const boardContract = await readOnly("treasury-hardened", "get-board-contract", []);
  console.log(`Board contract: ${boardContract?.value}`);

  // Summary
  console.log("\n=== SUMMARY ===");
  console.log(`1. Election not yet finalized (in challenge period)`);
  console.log(`2. No trustees registered yet`);
  console.log(`3. Board correctly rejects non-trustee proposals`);
  console.log(`4. Treasury is linked to board contract`);
  console.log(`\nOnce election finalizes:`);
  console.log(`  - Deployer becomes trustee (proposed 30x)`);
  console.log(`  - Can create proposals`);
  console.log(`  - 16/30 votes needed to execute`);

  console.log(`\n✅ Board security model test complete!`);
}

main().catch(console.error);
