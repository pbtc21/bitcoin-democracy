import { generateWallet } from '@stacks/wallet-sdk';
import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  stringAsciiCV,
  noneCV,
  principalCV,
  PostConditionMode
} from '@stacks/transactions';
import { STACKS_TESTNET } from '@stacks/network';

const MNEMONIC = "drama conduct illegal senior any inhale impact rain stereo hood lens long foster fluid erosion creek morning laugh shaft horror digital actor false soldier";
const DEPLOYER = "ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF";

async function getNonce(address) {
  const response = await fetch(`https://api.testnet.hiro.so/v2/accounts/${address}`);
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
    fee: BigInt(10000), // 0.01 STX
    anchorMode: AnchorMode.Any,
    postConditionMode: PostConditionMode.Allow,
  };

  const transaction = await makeContractCall(txOptions);
  console.log(`Broadcasting ${contractName}.${functionName}...`);

  const result = await broadcastTransaction({ transaction, network: STACKS_TESTNET });
  console.log(`  TX: ${result.txid}`);
  return result.txid;
}

async function main() {
  let nonce = await getNonce(DEPLOYER);
  console.log(`Starting nonce: ${nonce}\n`);

  // Step 1: Initialize all 30 cities in democracy-factory-hardened
  console.log("1. Initializing 30 cities...");
  await callContract(
    "democracy-factory-hardened",
    "initialize-all-cities",
    [],
    nonce++
  );

  // Step 2: Initialize token metadata
  console.log("\n2. Initializing token metadata...");
  await callContract(
    "city-btc-token-hardened",
    "initialize",
    [
      stringAsciiCV("CityBTC"),
      stringAsciiCV("CBTC"),
      noneCV()
    ],
    nonce++
  );

  // Step 3: Set treasury as authorized minter
  console.log("\n3. Setting treasury as authorized minter...");
  await callContract(
    "city-btc-token-hardened",
    "set-authorized-minter",
    [principalCV(`${DEPLOYER}.treasury-hardened`)],
    nonce++
  );

  // Step 4: Set board contract in treasury
  console.log("\n4. Setting board contract in treasury...");
  await callContract(
    "treasury-hardened",
    "set-board-contract",
    [principalCV(`${DEPLOYER}.board-hardened`)],
    nonce++
  );

  console.log("\n✅ Initialization complete!");
  console.log("\nContracts are now linked. Test before calling burn-admin-forever()");
}

main().catch(console.error);
