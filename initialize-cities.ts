import {
  makeContractCall,
  broadcastTransaction,
  AnchorMode,
  PostConditionMode,
} from "@stacks/transactions";
import { generateWallet } from "@stacks/wallet-sdk";

const MNEMONIC = "square armor pledge excess staff explain midnight final hungry dose cinnamon buzz total dad purity alert gather zero rain paper swap bar rhythm cradle";
const CONTRACT_ADDRESS = "ST1734723Q6206N1BAWQCJ5H9YFQBEPB96F8CY7KP";
const CONTRACT_NAME = "democracy-factory";
const FUNCTION_NAME = "initialize-all-cities";

async function main() {
  console.log("Initializing all 30 cities...\n");

  // Generate wallet from mnemonic
  const wallet = await generateWallet({ secretKey: MNEMONIC, password: "" });
  const account = wallet.accounts[0];

  // Create the contract call transaction
  const txOptions = {
    contractAddress: CONTRACT_ADDRESS,
    contractName: CONTRACT_NAME,
    functionName: FUNCTION_NAME,
    functionArgs: [],
    senderKey: account.stxPrivateKey,
    validateWithAbi: false,
    network: "testnet" as const,
    anchorMode: AnchorMode.Any,
    postConditionMode: PostConditionMode.Allow,
    fee: 1000000n, // 1 STX fee for this complex transaction (30 city creations)
  };

  console.log("Building transaction...");
  const transaction = await makeContractCall(txOptions);

  console.log("Broadcasting transaction...");
  // broadcastTransaction takes (transaction, network, attachment) as positional args
  const broadcastResponse = await broadcastTransaction(transaction, "testnet");

  if (typeof broadcastResponse === 'string') {
    console.log("\n✓ Transaction broadcasted successfully!");
    console.log(`TX ID: ${broadcastResponse}`);
    console.log(`\nView on explorer: https://explorer.hiro.so/txid/${broadcastResponse}?chain=testnet`);
  } else if ('error' in broadcastResponse) {
    console.error("\n✗ Broadcast failed:", broadcastResponse.error);
    console.error("Reason:", broadcastResponse.reason);
    if ('reason_data' in broadcastResponse) {
      console.error("Reason data:", JSON.stringify(broadcastResponse.reason_data, null, 2));
    }
  } else if ('txid' in broadcastResponse) {
    console.log("\n✓ Transaction broadcasted successfully!");
    console.log(`TX ID: ${broadcastResponse.txid}`);
    console.log(`\nView on explorer: https://explorer.hiro.so/txid/${broadcastResponse.txid}?chain=testnet`);
  } else {
    console.log("\nBroadcast response:", JSON.stringify(broadcastResponse, null, 2));
  }
}

main().catch(console.error);
