import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { createCipher, DecryptionError } from '../../src/auth/cipher.js';

const key = () => randomBytes(32).toString('base64');

describe('createCipher', () => {
  const cipher = createCipher(key());
  const plain = Buffer.from('signal session secret');

  it('round-trips data', () => {
    expect(cipher.decrypt(cipher.encrypt(plain))).toEqual(plain);
  });

  it('uses a fresh IV for every encryption', () => {
    expect(cipher.encrypt(plain).equals(cipher.encrypt(plain))).toBe(false);
  });

  it('does not contain the plaintext', () => {
    expect(cipher.encrypt(plain).includes(plain)).toBe(false);
  });

  it('fails loudly with the wrong key', () => {
    expect(() => createCipher(key()).decrypt(cipher.encrypt(plain))).toThrow(DecryptionError);
  });

  it('fails loudly when the data was tampered with', () => {
    const blob = cipher.encrypt(plain);
    blob[blob.length - 1] = (blob[blob.length - 1] ?? 0) ^ 0xff;
    expect(() => cipher.decrypt(blob)).toThrow(DecryptionError);
  });

  it('rejects keys that are not 32 bytes', () => {
    expect(() => createCipher(randomBytes(16).toString('base64'))).toThrow('exactly 32 bytes');
  });
});
