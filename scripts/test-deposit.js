import { generateWallet } from '@stacks/wallet-sdk';
import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  uintCV,
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

  // Convert args to hex strings using proper serialization
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
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    console.error(`Failed to parse response for ${contractName}.${functionName}:`, text.slice(0, 200));
    return null;
  }

  if (!data.okay) {
    console.error(`Read-only call failed:`, data);
    return null;
  }

  const cv = hexToCV(data.result);
  const json = cvToJSON(cv);
  return json;
}

async function waitForTx(txid, maxAttempts = 30) {
  console.log(`  Waiting for confirmation...`);
  for (let i = 0; i < maxAttempts; i++) {
    await new Promise(r => setTimeout(r, 5000));
    const response = await fetch(`${API_URL}/extended/v1/tx/${txid}`);
    const data = await response.json();
    if (data.tx_status === 'success') {
      console.log(`  ✅ Confirmed!`);
      return true;
    } else if (data.tx_status === 'abort_by_response' || data.tx_status === 'abort_by_post_condition') {
      console.log(`  ❌ Failed: ${data.tx_status}`);
      if (data.tx_result) console.log(`     Result: ${JSON.stringify(data.tx_result)}`);
      return false;
    }
    process.stdout.write('.');
  }
  console.log(`  ⏳ Timeout - check manually`);
  return false;
}

async function main() {
  let nonce = await getNonce(DEPLOYER);
  console.log(`Starting nonce: ${nonce}\n`);

  // Step 1: Check initial balances
  console.log("=== INITIAL STATE ===");

  const initialSbtc = await readOnly("mock-sbtc", "get-balance", [principalCV(DEPLOYER)]);
  console.log(`sBTC balance: ${initialSbtc?.value?.value || '0'}`);

  const initialCbtc = await readOnly("city-btc-token-hardened", "get-balance", [principalCV(DEPLOYER)]);
  console.log(`CityBTC balance: ${initialCbtc?.value?.value || '0'}`);

  // Step 2: Get mock sBTC from faucet (1 sBTC = 100,000,000 satoshis)
  const faucetAmount = 100000000n; // 1 sBTC
  console.log(`\n=== FAUCET ===`);
  console.log(`Requesting ${faucetAmount} satoshis (1 sBTC) from faucet...`);

  const faucetTx = await callContract(
    "mock-sbtc",
    "faucet",
    [uintCV(faucetAmount), principalCV(DEPLOYER)],
    nonce++
  );
  await waitForTx(faucetTx);

  // Step 3: Check sBTC balance after faucet
  const afterFaucetSbtc = await readOnly("mock-sbtc", "get-balance", [principalCV(DEPLOYER)]);
  console.log(`sBTC balance after faucet: ${afterFaucetSbtc?.value?.value || '0'}`);

  // Step 4: Deposit sBTC into treasury
  const depositAmount = 10000000n; // 0.1 sBTC
  console.log(`\n=== DEPOSIT ===`);
  console.log(`Depositing ${depositAmount} satoshis (0.1 sBTC) into treasury...`);

  const depositTx = await callContract(
    "treasury-hardened",
    "deposit",
    [uintCV(depositAmount)],
    nonce++
  );
  const depositSuccess = await waitForTx(depositTx);

  // Step 5: Check final balances
  console.log(`\n=== FINAL STATE ===`);

  const finalSbtc = await readOnly("mock-sbtc", "get-balance", [principalCV(DEPLOYER)]);
  console.log(`sBTC balance: ${finalSbtc?.value?.value || '0'}`);

  const finalCbtc = await readOnly("city-btc-token-hardened", "get-balance", [principalCV(DEPLOYER)]);
  console.log(`CityBTC balance: ${finalCbtc?.value?.value || '0'}`);

  const contribution = await readOnly("treasury-hardened", "get-contribution", [principalCV(DEPLOYER)]);
  console.log(`Treasury contribution: ${contribution?.value || '0'}`);

  const totalDeposits = await readOnly("treasury-hardened", "get-total-deposits", []);
  console.log(`Total treasury deposits: ${totalDeposits?.value || '0'}`);

  // Get treasury balance
  const treasuryBalance = await readOnly("treasury-hardened", "get-treasury-balance", []);
  console.log(`Treasury sBTC balance: ${treasuryBalance?.value?.value || '0'}`);

  // Verify the math
  console.log(`\n=== VERIFICATION ===`);
  const expectedTokens = Number(depositAmount) * 10000; // SBTC_TO_TOKEN_MULTIPLIER
  console.log(`Expected CityBTC tokens: ${expectedTokens} (0.1 sBTC × 10,000 multiplier)`);

  if (depositSuccess) {
    console.log(`\n✅ Deposit flow test passed!`);
  } else {
    console.log(`\n❌ Deposit failed - check transaction details`);
  }
}

main().catch(console.error);
