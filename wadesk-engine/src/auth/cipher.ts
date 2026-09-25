import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

// Blob layout: version (1 byte) | IV (12 bytes) | auth tag (16 bytes) | ciphertext.
// The version byte leaves room for key rotation (ADR-0004).
const VERSION = 1;
const IV_LENGTH = 12;
const TAG_LENGTH = 16;
const HEADER_LENGTH = 1 + IV_LENGTH + TAG_LENGTH;

export interface Cipher {
  encrypt(plain: Buffer): Buffer;
  decrypt(blob: Buffer): Buffer;
}

export class DecryptionError extends Error {
  constructor() {
    super('Cannot decrypt stored credentials: wrong WADESK_ENGINE_ENCRYPTION_KEY or corrupted data');
    this.name = 'DecryptionError';
  }
}

// key: base64 encoding of exactly 32 random bytes (generate with `openssl rand -base64 32`).
export function createCipher(base64Key: string): Cipher {
  const key = Buffer.from(base64Key, 'base64');
  if (key.length !== 32) throw new Error('WADESK_ENGINE_ENCRYPTION_KEY must be base64 of exactly 32 bytes');

  return {
    encrypt(plain) {
      const iv = randomBytes(IV_LENGTH);
      const cipher = createCipheriv('aes-256-gcm', key, iv);
      const ciphertext = Buffer.concat([cipher.update(plain), cipher.final()]);
      return Buffer.concat([Buffer.from([VERSION]), iv, cipher.getAuthTag(), ciphertext]);
    },
    decrypt(blob) {
      if (blob.length < HEADER_LENGTH || blob[0] !== VERSION) throw new DecryptionError();
      const iv = blob.subarray(1, 1 + IV_LENGTH);
      const tag = blob.subarray(1 + IV_LENGTH, HEADER_LENGTH);
      const decipher = createDecipheriv('aes-256-gcm', key, iv);
      decipher.setAuthTag(tag);
      try {
        return Buffer.concat([decipher.update(blob.subarray(HEADER_LENGTH)), decipher.final()]);
      } catch {
        throw new DecryptionError();
      }
    },
  };
}
