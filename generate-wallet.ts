import { generateWallet, getStxAddress } from "@stacks/wallet-sdk";
import { generateMnemonic } from "@scure/bip39";
import { wordlist } from "@scure/bip39/wordlists/english.js";
import { c32addressDecode, c32address } from "c32check";
import { TransactionVersion } from "@stacks/transactions";

const mnemonic = generateMnemonic(wordlist, 256);
console.log("=== TESTNET WALLET ===");
console.log("Mnemonic:");
console.log(mnemonic);
console.log("");

const wallet = await generateWallet({ secretKey: mnemonic, password: "" });
const account = wallet.accounts[0];

// Get mainnet address
const mainnetAddr = getStxAddress({ account, transactionVersion: TransactionVersion.Mainnet });
console.log("Mainnet address:", mainnetAddr);

// Decode the mainnet address and re-encode as testnet
const [version, hash] = c32addressDecode(mainnetAddr);
// Testnet single-sig version is 26
const testnetAddr = c32address(26, hash);

console.log("Testnet Address:", testnetAddr);
console.log("");
console.log("Fund at: https://explorer.hiro.so/sandbox/faucet?chain=testnet");
