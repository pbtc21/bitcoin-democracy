import { generateWallet } from '@stacks/wallet-sdk';
import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  PostConditionMode,
  cvToJSON,
  hexToCV,
  serializeCV
} from '@stacks/transactions';
import { STACKS_TESTNET } from '@stacks/network';

const MNEMONIC = "drama conduct illegal senior any inhale impact rain stereo hood lens long foster fluid erosion creek morning laugh shaft horror digital actor false soldier";
const DEPLOYER = "ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF";
const API_URL = "https://api.testnet.hiro.so";

// Parse command line args
const args = process.argv.slice(2);
const WATCH_MODE = args.includes('--watch');
const POLL_INTERVAL = 60000; // 1 minute

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
    if (!data.okay) return null;
    const cv = hexToCV(data.result);
    return cvToJSON(cv);
  } catch (e) {
    return null;
  }
}

async function waitForTx(txid, maxAttempts = 60) {
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

async function checkStatus() {
  const blockHeight = await getBlockHeight();
  const isPending = await readOnly("hyperelection-hardened", "is-finalization-pending", []);
  const isFinalized = await readOnly("hyperelection-hardened", "is-election-finalized", []);
  const canExecute = await readOnly("hyperelection-hardened", "can-execute-finalization", []);
  const challengeEnd = await readOnly("hyperelection-hardened", "get-challenge-end-block", []);

  const endBlock = challengeEnd?.value?.value ? parseInt(challengeEnd.value.value) : null;
  const blocksRemaining = endBlock ? endBlock - blockHeight : null;
  const hoursRemaining = blocksRemaining ? Math.round(blocksRemaining * 10 / 60 * 10) / 10 : null;

  return {
    blockHeight,
    isPending: isPending?.value,
    isFinalized: isFinalized?.value,
    canExecute: canExecute?.value,
    endBlock,
    blocksRemaining,
    hoursRemaining
  };
}

async function executeFinalization() {
  const nonce = await getNonce(DEPLOYER);

  console.log(`\n🚀 Executing finalization...`);
  const tx = await callContract(
    "hyperelection-hardened",
    "execute-finalization",
    [],
    nonce
  );

  const result = await waitForTx(tx);

  if (result.success) {
    console.log(`\n🎉 ELECTION FINALIZED!`);
    console.log(`Result: ${result.result?.repr}`);

    // Verify trustees are set
    const trustees = await readOnly("hyperelection-hardened", "get-trustees", []);
    console.log(`\nTrustees set: ${trustees?.value?.length || 0} addresses`);

    const epoch = await readOnly("hyperelection-hardened", "get-election-epoch", []);
    console.log(`Election epoch: ${epoch?.value}`);

    return true;
  }

  return false;
}

async function main() {
  console.log(`╔════════════════════════════════════════╗`);
  console.log(`║     Election Finalization Script       ║`);
  console.log(`╚════════════════════════════════════════╝\n`);

  if (WATCH_MODE) {
    console.log(`Mode: WATCH (polling every ${POLL_INTERVAL/1000}s until ready)\n`);
  } else {
    console.log(`Mode: CHECK (one-time check and execute if ready)\n`);
  }

  while (true) {
    const status = await checkStatus();
    const timestamp = new Date().toISOString().slice(11, 19);

    console.log(`[${timestamp}] Block: ${status.blockHeight}`);

    if (status.isFinalized) {
      console.log(`\n✅ Election already finalized!`);

      const trustees = await readOnly("hyperelection-hardened", "get-trustees", []);
      console.log(`Trustees: ${trustees?.value?.length || 0} addresses`);

      const epoch = await readOnly("hyperelection-hardened", "get-election-epoch", []);
      console.log(`Epoch: ${epoch?.value}`);

      break;
    }

    if (!status.isPending) {
      console.log(`\n⚠️ No finalization pending. Run test-election.js first to propose trustees.`);
      break;
    }

    if (status.canExecute) {
      console.log(`\n✅ Challenge period complete! Ready to execute.`);
      const success = await executeFinalization();
      if (success) {
        console.log(`\n🏛️ The board can now govern!`);
        console.log(`Next: Run test-board.js to create proposals.`);
      }
      break;
    }

    // Not ready yet
    console.log(`   Pending: ${status.isPending}`);
    console.log(`   Challenge ends: block ${status.endBlock}`);
    console.log(`   Blocks remaining: ${status.blocksRemaining} (~${status.hoursRemaining} hours)`);

    if (!WATCH_MODE) {
      console.log(`\n⏳ Challenge period still active.`);
      console.log(`   Run with --watch to poll until ready.`);
      console.log(`   Or wait and run again after block ${status.endBlock}`);
      break;
    }

    // Watch mode - wait and check again
    console.log(`   Waiting ${POLL_INTERVAL/1000}s...`);
    await new Promise(r => setTimeout(r, POLL_INTERVAL));
    console.log('');
  }
}

main().catch(console.error);
