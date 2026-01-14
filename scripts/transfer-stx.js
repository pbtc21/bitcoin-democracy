import { generateWallet, getStxAddress } from '@stacks/wallet-sdk';
import { makeSTXTokenTransfer, broadcastTransaction, AnchorMode } from '@stacks/transactions';
import { STACKS_TESTNET } from '@stacks/network';

const OLD_MNEMONIC = "square armor pledge excess staff explain midnight final hungry dose cinnamon buzz total dad purity alert gather zero rain paper swap bar rhythm cradle";
const NEW_ADDRESS = "ST2J6CYV7YEBQANTA668TVB2PE30EE09J2WWT8RRF";
const AMOUNT = 10_000_000; // 10 STX in micro-STX

async function main() {
  const network = STACKS_TESTNET;

  // Generate wallet from old mnemonic
  const wallet = await generateWallet({ secretKey: OLD_MNEMONIC, password: '' });
  const senderKey = wallet.accounts[0].stxPrivateKey;
  const senderAddress = "ST1734723Q6206N1BAWQCJ5H9YFQBEPB96F8CY7KP";

  console.log("Sender:", senderAddress);
  console.log("Recipient:", NEW_ADDRESS);
  console.log("Amount:", AMOUNT / 1_000_000, "STX");

  // Get nonce
  const nonceResponse = await fetch(`https://api.testnet.hiro.so/v2/accounts/${senderAddress}`);
  const nonceData = await nonceResponse.json();
  const nonce = BigInt(nonceData.nonce);
  console.log("Nonce:", nonce.toString());

  // Create transaction
  const txOptions = {
    recipient: NEW_ADDRESS,
    amount: BigInt(AMOUNT),
    senderKey: senderKey,
    network,
    nonce,
    fee: BigInt(2000), // 0.002 STX fee
    anchorMode: AnchorMode.Any,
  };

  const transaction = await makeSTXTokenTransfer(txOptions);
  console.log("Transaction created");

  // Broadcast
  const broadcastResponse = await broadcastTransaction({ transaction, network });
  console.log("Broadcast result:", broadcastResponse);
}

main().catch(console.error);
