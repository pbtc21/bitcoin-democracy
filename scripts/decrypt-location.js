#!/usr/bin/env node
/**
 * Decrypt location text using your Stacks private key
 *
 * Usage:
 *   bun decrypt-location.js <your-private-key> <ciphertext-hex>
 *
 * After calling reveal() on the contract, you'll get the encrypted location
 * in the transaction event. Paste that ciphertext here to decrypt.
 */

import { getSharedSecret } from '@noble/secp256k1';
import { hkdf } from '@noble/hashes/hkdf.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { gcm } from '@noble/ciphers/aes.js';

const args = process.argv.slice(2);

if (args.length < 2) {
  console.log(`
╔════════════════════════════════════════════════════════════╗
║              CITY KEY LOCATION DECRYPTOR                   ║
╚════════════════════════════════════════════════════════════╝

Usage:
  bun decrypt-location.js <your-private-key> <ciphertext-hex>

Arguments:
  your-private-key   Your Stacks private key (64 hex chars)
  ciphertext-hex     The encrypted location from reveal() event

Steps:
  1. Call reveal(city-id) on city-key-reveal contract
  2. Get the encrypted-location from the transaction event
  3. Run this script with your private key
  4. Get the plaintext location of your trustee key
  5. Retrieve your key and call abnegate() on hyperelection

Example:
  bun decrypt-location.js abc123... 0x02a1b2...

Security: Run this on a secure, offline machine if possible.
`);
  process.exit(1);
}

const privateKeyHex = args[0];
let ciphertextHex = args[1];

// Remove 0x prefix if present
if (ciphertextHex.startsWith('0x')) {
  ciphertextHex = ciphertextHex.slice(2);
}

/**
 * ECIES Decryption using secp256k1
 * Format: ephemeralPubKey (33) + nonce (12) + ciphertext + authTag (16)
 */
function decryptECIES(privateKeyHex, ciphertextHex) {
  const ciphertext = Buffer.from(ciphertextHex, 'hex');

  // Parse components
  const ephemeralPubKey = ciphertext.slice(0, 33);
  const nonce = ciphertext.slice(33, 45);
  const encrypted = ciphertext.slice(45); // includes authTag

  // Derive shared secret via ECDH
  const privateKey = Buffer.from(privateKeyHex, 'hex');
  const sharedPoint = getSharedSecret(privateKey, ephemeralPubKey, true);

  // Derive decryption key using same HKDF params
  const decryptionKey = hkdf(sha256, sharedPoint, new Uint8Array(0), new TextEncoder().encode('ecies-aes-gcm'), 32);

  // Decrypt with AES-256-GCM
  const aes = gcm(decryptionKey, nonce);
  const decrypted = aes.decrypt(encrypted);

  return new TextDecoder().decode(decrypted);
}

try {
  // Validate private key format
  if (!/^[0-9a-fA-F]{64}$/.test(privateKeyHex)) {
    console.error('Error: Invalid private key format');
    console.error('Expected: 64 hex characters');
    process.exit(1);
  }

  console.log(`\nDecrypting location...`);

  const plaintext = decryptECIES(privateKeyHex, ciphertextHex);

  console.log(`\n${'═'.repeat(60)}`);
  console.log('YOUR TRUSTEE KEY LOCATION:');
  console.log(`${'═'.repeat(60)}`);
  console.log(plaintext);
  console.log(`${'═'.repeat(60)}`);

  console.log(`\nNext steps:`);
  console.log(`  1. Retrieve your trustee private key from the location above`);
  console.log(`  2. Import it into a Stacks wallet`);
  console.log(`  3. Call abnegate(<your-new-address>) on hyperelection-hardened`);
  console.log(`  4. You are now a trustee of Bitcoin Democracy`);

} catch (error) {
  if (error.message.includes('invalid tag')) {
    console.error('Error: Decryption failed - wrong private key or corrupted ciphertext');
  } else {
    console.error('Decryption error:', error.message);
  }
  process.exit(1);
}
