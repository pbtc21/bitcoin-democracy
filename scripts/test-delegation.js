import { generateWallet } from '@stacks/wallet-sdk';
import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  principalCV,
  PostConditionMode,
  cvToJSON,
  hexToCV,
  serializeCV
} from '@stacks/transactions';
import { STACKS_TESTNET } from '@stacks/network';

const MNEMONIC = "drama conduct illegal senior any inhale impact rain stereo hood lens long foster fluid erosion creek morning laugh shaft horror digital actor false soldier";
const DEPLOYER = "ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF";
const API_URL = "https://api.testnet.hiro.so";

// Test delegate addresses (random testnet addresses)
const DELEGATE_1 = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
const DELEGATE_2 = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG";

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
      console.error(`Read-only call failed:`, data);
      return null;
    }
    const cv = hexToCV(data.result);
    return cvToJSON(cv);
  } catch (e) {
    console.error(`Failed to parse response:`, text.slice(0, 100));
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

async function getTxEvents(txid) {
  const response = await fetch(`${API_URL}/extended/v1/tx/${txid}`);
  const data = await response.json();
  return data.events || [];
}

async function main() {
  let nonce = await getNonce(DEPLOYER);
  console.log(`Starting nonce: ${nonce}\n`);

  // Step 1: Check initial state
  console.log("=== INITIAL STATE ===");

  const isFinalized = await readOnly("hyperelection-hardened", "is-election-finalized", []);
  console.log(`Election finalized: ${isFinalized?.value}`);

  const epoch = await readOnly("hyperelection-hardened", "get-election-epoch", []);
  console.log(`Election epoch: ${epoch?.value}`);

  // Check if already delegated
  const currentDelegation = await readOnly("hyperelection-hardened", "get-delegation", [principalCV(DEPLOYER)]);
  console.log(`Current delegation: ${currentDelegation?.value || 'none'}`);

  // Step 2: Delegate to DELEGATE_1
  console.log(`\n=== DELEGATE ===`);
  console.log(`Delegating to ${DELEGATE_1}...`);

  const delegateTx = await callContract(
    "hyperelection-hardened",
    "delegate",
    [principalCV(DELEGATE_1)],
    nonce++
  );
  const delegateResult = await waitForTx(delegateTx);

  if (delegateResult.success) {
    console.log(`Result: ${delegateResult.result?.repr}`);

    // Check events
    const events = await getTxEvents(delegateTx);
    const printEvent = events.find(e => e.event_type === 'smart_contract_log');
    if (printEvent) {
      console.log(`Event: ${printEvent.contract_log.value.repr}`);
    }
  }

  // Step 3: Verify delegation
  console.log(`\n=== VERIFY DELEGATION ===`);

  const newDelegation = await readOnly("hyperelection-hardened", "get-delegation", [principalCV(DEPLOYER)]);
  console.log(`Delegation: ${newDelegation?.value || 'none'}`);

  // Check delegation chain
  const chain = await readOnly("hyperelection-hardened", "get-delegation-chain", [principalCV(DEPLOYER)]);
  console.log(`Delegation chain: ${JSON.stringify(chain)}`);

  // Step 4: Try to delegate again (should fail - already delegated)
  console.log(`\n=== TEST: DOUBLE DELEGATE (should fail) ===`);

  const doubleDelegateTx = await callContract(
    "hyperelection-hardened",
    "delegate",
    [principalCV(DELEGATE_2)],
    nonce++
  );
  const doubleResult = await waitForTx(doubleDelegateTx);

  if (!doubleResult.success) {
    console.log(`Correctly rejected: ${doubleResult.result?.repr}`);
  }

  // Step 5: Undelegate
  console.log(`\n=== UNDELEGATE ===`);

  const undelegateTx = await callContract(
    "hyperelection-hardened",
    "undelegate",
    [],
    nonce++
  );
  const undelegateResult = await waitForTx(undelegateTx);

  if (undelegateResult.success) {
    console.log(`Result: ${undelegateResult.result?.repr}`);

    const events = await getTxEvents(undelegateTx);
    const printEvent = events.find(e => e.event_type === 'smart_contract_log');
    if (printEvent) {
      console.log(`Event: ${printEvent.contract_log.value.repr}`);
    }
  }

  // Step 6: Verify undelegation
  console.log(`\n=== VERIFY UNDELEGATION ===`);

  const afterUndelegate = await readOnly("hyperelection-hardened", "get-delegation", [principalCV(DEPLOYER)]);
  console.log(`Delegation after undelegate: ${afterUndelegate?.value || 'none'}`);

  // Step 7: Re-delegate (should work now)
  console.log(`\n=== RE-DELEGATE ===`);

  const reDelegateTx = await callContract(
    "hyperelection-hardened",
    "delegate",
    [principalCV(DELEGATE_1)],
    nonce++
  );
  const reResult = await waitForTx(reDelegateTx);

  if (reResult.success) {
    console.log(`Result: ${reResult.result?.repr}`);
  }

  // Final state
  console.log(`\n=== FINAL STATE ===`);
  const finalDelegation = await readOnly("hyperelection-hardened", "get-delegation", [principalCV(DEPLOYER)]);
  console.log(`Final delegation: ${finalDelegation?.value || 'none'}`);

  console.log(`\n✅ Delegation flow test complete!`);
}

main().catch(console.error);
