#!/usr/bin/env node
/**
 * Encrypt location text for a city election winner using ECIES
 *
 * Usage:
 *   bun encrypt-location.js <winner-public-key-hex> "<location-text>"
 *
 * The winner provides their compressed public key (33 bytes hex) when they win.
 * Output: Hex-encoded ECIES ciphertext for set-winner contract call.
 */

import { getPublicKey, getSharedSecret, keygen } from '@noble/secp256k1';
import { hkdf } from '@noble/hashes/hkdf.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { gcm } from '@noble/ciphers/aes.js';
import { randomBytes } from '@noble/ciphers/utils.js';

const args = process.argv.slice(2);

if (args.length < 2) {
  console.log(`
╔════════════════════════════════════════════════════════════╗
║              CITY KEY LOCATION ENCRYPTOR                   ║
╚════════════════════════════════════════════════════════════╝

Usage:
  bun encrypt-location.js <winner-public-key> "<location-text>"

Arguments:
  winner-public-key  Compressed secp256k1 public key (66 hex chars)
                     Winner provides this when they win city election
  location-text      The secret location of their trustee key

Example:
  bun encrypt-location.js 02a1b2c3... "Key stored at: ipfs://Qm..."

Output: Hex ciphertext for set-winner() contract call

Note: Winner gets their public key from their wallet.
`);
  process.exit(1);
}

const publicKeyHex = args[0];
const locationText = args.slice(1).join(' ');

/**
 * ECIES Encryption using secp256k1
 * Format: ephemeralPubKey (33) + nonce (12) + ciphertext + authTag (16)
 */
function encryptECIES(publicKeyHex, plaintext) {
  // Generate ephemeral keypair
  const { secretKey: ephemeralPriv, publicKey: ephemeralPub } = keygen();

  // Get recipient public key
  const recipientPub = Buffer.from(publicKeyHex, 'hex');

  // Derive shared secret via ECDH
  const sharedPoint = getSharedSecret(ephemeralPriv, recipientPub, true);

  // Derive encryption key using HKDF-SHA256
  const encryptionKey = hkdf(sha256, sharedPoint, new Uint8Array(0), new TextEncoder().encode('ecies-aes-gcm'), 32);

  // Encrypt with AES-256-GCM
  const nonce = randomBytes(12);
  const plainBuffer = new TextEncoder().encode(plaintext);
  const aes = gcm(encryptionKey, nonce);
  const ciphertext = aes.encrypt(plainBuffer);

  // Combine: ephemeralPubKey (33) + nonce (12) + ciphertext (includes authTag)
  const result = new Uint8Array(33 + 12 + ciphertext.length);
  result.set(ephemeralPub, 0);
  result.set(nonce, 33);
  result.set(ciphertext, 45);

  return Buffer.from(result);
}

try {
  // Validate public key format
  if (!/^(02|03)[0-9a-fA-F]{64}$/.test(publicKeyHex)) {
    console.error('Error: Invalid compressed public key format');
    console.error('Expected: 02 or 03 prefix + 64 hex chars (33 bytes total)');
    process.exit(1);
  }

  console.log(`\nEncrypting location for public key: ${publicKeyHex.substring(0, 20)}...`);
  console.log(`Location: "${locationText.substring(0, 50)}${locationText.length > 50 ? '...' : ''}"`);

  const ciphertext = encryptECIES(publicKeyHex, locationText);
  const hexOutput = '0x' + ciphertext.toString('hex');

  console.log(`\n${'─'.repeat(60)}`);
  console.log('ECIES CIPHERTEXT (hex):');
  console.log(`${'─'.repeat(60)}`);
  console.log(hexOutput);
  console.log(`${'─'.repeat(60)}`);

  console.log(`\nSize: ${ciphertext.length} bytes`);

  if (ciphertext.length > 512) {
    console.log(`\nWARNING: Exceeds 512 byte contract limit!`);
    console.log(`   Shorten location text or use IPFS hash.`);
    process.exit(1);
  }

  console.log(`\nReady for set-winner() call`);

} catch (error) {
  console.error('Encryption error:', error.message);
  process.exit(1);
}
