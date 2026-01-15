import { getPublicKey, getSharedSecret, keygen } from '@noble/secp256k1';
import { hkdf } from '@noble/hashes/hkdf.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { gcm } from '@noble/ciphers/aes.js';
import { randomBytes } from '@noble/ciphers/utils.js';

// Generate test keypair
const { secretKey: privKey, publicKey: pubKey } = keygen();

console.log('=== TEST KEYPAIR ===');
console.log('Private:', Buffer.from(privKey).toString('hex'));
console.log('Public:', Buffer.from(pubKey).toString('hex'));

// Encryption function
function encryptECIES(publicKeyHex, plaintext) {
  const { secretKey: ephemeralPriv, publicKey: ephemeralPub } = keygen();
  const recipientPub = Buffer.from(publicKeyHex, 'hex');
  const sharedPoint = getSharedSecret(ephemeralPriv, recipientPub, true);
  const encryptionKey = hkdf(sha256, sharedPoint, new Uint8Array(0), new TextEncoder().encode('ecies-aes-gcm'), 32);
  const nonce = randomBytes(12);
  const plainBuffer = new TextEncoder().encode(plaintext);
  const aes = gcm(encryptionKey, nonce);
  const ciphertext = aes.encrypt(plainBuffer);
  const result = new Uint8Array(33 + 12 + ciphertext.length);
  result.set(ephemeralPub, 0);
  result.set(nonce, 33);
  result.set(ciphertext, 45);
  return Buffer.from(result);
}

// Decryption function
function decryptECIES(privateKeyHex, ciphertextHex) {
  const ciphertext = Buffer.from(ciphertextHex, 'hex');
  const ephemeralPubKey = ciphertext.slice(0, 33);
  const nonce = ciphertext.slice(33, 45);
  const encrypted = ciphertext.slice(45);
  const privateKey = Buffer.from(privateKeyHex, 'hex');
  const sharedPoint = getSharedSecret(privateKey, ephemeralPubKey, true);
  const decryptionKey = hkdf(sha256, sharedPoint, new Uint8Array(0), new TextEncoder().encode('ecies-aes-gcm'), 32);
  const aes = gcm(decryptionKey, nonce);
  const decrypted = aes.decrypt(encrypted);
  return new TextDecoder().decode(decrypted);
}

// Test
const testMsg = 'Key is at ipfs://QmTest123456789';
console.log('\n=== ENCRYPTION TEST ===');
console.log('Original:', testMsg);

const pubKeyHex = Buffer.from(pubKey).toString('hex');
const privKeyHex = Buffer.from(privKey).toString('hex');

const encrypted = encryptECIES(pubKeyHex, testMsg);
console.log('Encrypted (hex):', encrypted.toString('hex').substring(0, 60) + '...');
console.log('Size:', encrypted.length, 'bytes');

const decrypted = decryptECIES(privKeyHex, encrypted.toString('hex'));
console.log('Decrypted:', decrypted);

console.log('\n' + (testMsg === decrypted ? '✓ TEST PASSED' : '✗ TEST FAILED'));
