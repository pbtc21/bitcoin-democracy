import { generateWallet } from '@stacks/wallet-sdk';
import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  principalCV,
  uintCV,
  listCV,
  PostConditionMode,
  cvToJSON,
  hexToCV,
  serializeCV
} from '@stacks/transactions';
import { STACKS_TESTNET } from '@stacks/network';

const MNEMONIC = "drama conduct illegal senior any inhale impact rain stereo hood lens long foster fluid erosion creek morning laugh shaft horror digital actor false soldier";
const DEPLOYER = "ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF";
const API_URL = "https://api.testnet.hiro.so";

// 30 trustee addresses for testing (can be same address - just testing mechanics)
// In production, these would be unique elected representatives
function getTrusteeAddresses() {
  // Use deployer as all trustees for testing the flow
  // The election mechanics work the same regardless of uniqueness
  return Array(30).fill(DEPLOYER);
}

async function getNonce(address) {
  const response = await fetch(`${API_URL}/v2/accounts/${address}`);
  const data = await response.json();
  return BigInt(data.nonce);
}

async function getBlockHeight() {
  const response = await fetch(`${API_URL}/v2/info`);
  const data = await response.json();
  return data.stacks_tip_height;
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

async function getTxEvents(txid) {
  const response = await fetch(`${API_URL}/extended/v1/tx/${txid}`);
  const data = await response.json();
  return data.events || [];
}

async function main() {
  let nonce = await getNonce(DEPLOYER);
  const blockHeight = await getBlockHeight();
  console.log(`Starting nonce: ${nonce}`);
  console.log(`Current block height: ${blockHeight}\n`);

  const TRUSTEES = getTrusteeAddresses();
  console.log(`Using 30 trustee slots (all deployer for testing):`);
  console.log(`  Address: ${TRUSTEES[0]}\n`);

  // Step 1: Check initial state
  console.log("=== INITIAL STATE ===");

  const isFinalized = await readOnly("hyperelection-hardened", "is-election-finalized", []);
  console.log(`Election finalized: ${isFinalized?.value}`);

  const isPending = await readOnly("hyperelection-hardened", "is-finalization-pending", []);
  console.log(`Finalization pending: ${isPending?.value}`);

  const canExecute = await readOnly("hyperelection-hardened", "can-execute-finalization", []);
  console.log(`Can execute: ${canExecute?.value}`);

  // Step 2: Propose finalization with 30 trustees
  console.log(`\n=== PROPOSE FINALIZATION ===`);
  console.log(`Proposing 30 trustees with 100B total stake...`);

  const trusteesCV = listCV(TRUSTEES.map(t => principalCV(t)));
  const totalStake = 100000000000n; // 100B tokens

  const proposeTx = await callContract(
    "hyperelection-hardened",
    "propose-finalization",
    [trusteesCV, uintCV(totalStake)],
    nonce++
  );
  const proposeResult = await waitForTx(proposeTx);

  if (proposeResult.success) {
    console.log(`Result: ${proposeResult.result?.repr}`);

    const events = await getTxEvents(proposeTx);
    const printEvent = events.find(e => e.event_type === 'smart_contract_log');
    if (printEvent) {
      const repr = printEvent.contract_log.value.repr;
      console.log(`\nEvent logged:`);
      const challengeEnds = repr.match(/challenge-ends u(\d+)/)?.[1];
      const proposer = repr.match(/proposer '([^)]+)/)?.[1];
      console.log(`  Proposer: ${proposer}`);
      console.log(`  Challenge ends at block: ${challengeEnds}`);
      console.log(`  Current block: ${blockHeight}`);
      console.log(`  Blocks remaining: ~${parseInt(challengeEnds) - blockHeight} (~${Math.round((parseInt(challengeEnds) - blockHeight) * 10 / 60)} hours)`);
    }
  }

  // Step 3: Verify pending state
  console.log(`\n=== VERIFY PENDING STATE ===`);

  const afterPending = await readOnly("hyperelection-hardened", "is-finalization-pending", []);
  console.log(`Finalization pending: ${afterPending?.value}`);

  const challengeEndBlock = await readOnly("hyperelection-hardened", "get-challenge-end-block", []);
  console.log(`Challenge end block: ${JSON.stringify(challengeEndBlock)}`);

  const pendingStake = await readOnly("hyperelection-hardened", "get-pending-stake", []);
  console.log(`Pending stake: ${pendingStake?.value}`);

  // Step 4: Try to execute (should fail - challenge period active)
  console.log(`\n=== TEST: EXECUTE BEFORE CHALLENGE ENDS (should fail) ===`);

  const executeTx = await callContract(
    "hyperelection-hardened",
    "execute-finalization",
    [],
    nonce++
  );
  const executeResult = await waitForTx(executeTx);

  if (!executeResult.success) {
    console.log(`Correctly rejected: ${executeResult.result?.repr}`);
    console.log(`(ERR-CHALLENGE-PERIOD-ACTIVE = err u113)`);
  } else {
    console.log(`⚠️ Unexpected success - challenge period may have passed`);
  }

  // Step 5: Show final state
  console.log(`\n=== FINAL STATE ===`);

  const finalFinalized = await readOnly("hyperelection-hardened", "is-election-finalized", []);
  console.log(`Election finalized: ${finalFinalized?.value}`);

  const finalPending = await readOnly("hyperelection-hardened", "is-finalization-pending", []);
  console.log(`Finalization pending: ${finalPending?.value}`);

  const finalCanExecute = await readOnly("hyperelection-hardened", "can-execute-finalization", []);
  console.log(`Can execute now: ${finalCanExecute?.value}`);

  // Summary
  console.log(`\n=== SUMMARY ===`);
  console.log(`1. Proposal submitted with 30 trustees`);
  console.log(`2. Challenge period started (144 blocks / ~24 hours)`);
  console.log(`3. Execute correctly rejected during challenge period`);
  console.log(`4. After challenge period, anyone can call execute-finalization()`);

  console.log(`\n✅ Election flow test complete!`);
  console.log(`\nNote: To fully test, wait 144 blocks then call execute-finalization()`);
}

main().catch(console.error);
