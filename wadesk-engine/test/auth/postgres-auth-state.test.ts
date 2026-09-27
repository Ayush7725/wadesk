import { randomBytes } from 'node:crypto';
import { proto } from 'baileys';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { createCipher, DecryptionError } from '../../src/auth/cipher.js';
import { usePostgresAuthState } from '../../src/auth/postgres-auth-state.js';
import { createPool } from '../../src/db/pool.js';
import { databaseUrl } from '../support/db.js';

describe('usePostgresAuthState', () => {
  const pool = createPool(databaseUrl);
  const cipher = createCipher(randomBytes(32).toString('base64'));
  afterAll(() => pool.end());

  beforeEach(async () => {
    await pool.query("DELETE FROM wadesk_engine.sessions WHERE id IN ('a', 'b')");
    await pool.query(
      "INSERT INTO wadesk_engine.sessions (id, expected_phone, webhook_url) VALUES ('a', '919800000001', 'http://x'), ('b', '919800000002', 'http://x')",
    );
  });

  it('starts a new session with fresh credentials', async () => {
    const { state } = await usePostgresAuthState(pool, 'a', cipher);

    expect(state.creds.registered).toBe(false);
    expect(state.creds.noiseKey.private).toHaveLength(32);
  });

  it('persists credentials encrypted and restores them exactly', async () => {
    const first = await usePostgresAuthState(pool, 'a', cipher);
    await first.saveCreds();

    const { rows } = await pool.query<{ value: Buffer }>("SELECT value FROM wadesk_engine.auth_keys WHERE session_id = 'a'");
    expect(rows[0]?.value.includes(Buffer.from(first.state.creds.advSecretKey))).toBe(false);

    const restored = await usePostgresAuthState(pool, 'a', cipher);
    expect(restored.state.creds).toEqual(first.state.creds);
  });

  it('stores, reads and deletes signal keys', async () => {
    const { state } = await usePostgresAuthState(pool, 'a', cipher);
    const keyPair = { public: randomBytes(32), private: randomBytes(32) };

    await state.keys.set({ 'pre-key': { '1': keyPair, '2': keyPair }, session: { 'jid.0': randomBytes(8) } });
    expect(await state.keys.get('pre-key', ['1', '2', '3'])).toEqual({ '1': keyPair, '2': keyPair });

    await state.keys.set({ 'pre-key': { '1': null } });
    expect(Object.keys(await state.keys.get('pre-key', ['1', '2']))).toEqual(['2']);
  });

  it('restores app-state sync keys as protobuf objects', async () => {
    const { state } = await usePostgresAuthState(pool, 'a', cipher);
    const syncKey = proto.Message.AppStateSyncKeyData.fromObject({ keyData: randomBytes(32), timestamp: 1 });

    await state.keys.set({ 'app-state-sync-key': { k1: syncKey } });
    const { k1 } = await state.keys.get('app-state-sync-key', ['k1']);

    expect(k1).toBeInstanceOf(proto.Message.AppStateSyncKeyData);
    expect(Buffer.from(k1?.keyData ?? [])).toEqual(Buffer.from(syncKey.keyData ?? []));
  });

  it('keeps sessions isolated and clears only its own keys', async () => {
    const a = await usePostgresAuthState(pool, 'a', cipher);
    const b = await usePostgresAuthState(pool, 'b', cipher);
    await a.state.keys.set({ 'sender-key': { x: randomBytes(4) } });
    await b.state.keys.set({ 'sender-key': { x: randomBytes(4) } });

    await a.clear();

    expect(await a.state.keys.get('sender-key', ['x'])).toEqual({});
    expect(Object.keys(await b.state.keys.get('sender-key', ['x']))).toEqual(['x']);
  });

  it('ignores writes that arrive after it was cleared, including ones already in flight', async () => {
    const a = await usePostgresAuthState(pool, 'a', cipher);
    await a.saveCreds();
    const inFlight = a.state.keys.set({ 'lid-mapping': { early: 'x' } });

    await a.clear();
    await inFlight;
    await a.state.keys.set({ 'lid-mapping': { late: 'x' }, 'device-list': { late: ['1'] } });
    await a.saveCreds();

    const { rows } = await pool.query("SELECT 1 FROM wadesk_engine.auth_keys WHERE session_id = 'a'");
    expect(rows).toHaveLength(0);
  });

  it('refuses to load credentials encrypted with a different key', async () => {
    await (await usePostgresAuthState(pool, 'a', cipher)).saveCreds();
    const otherCipher = createCipher(randomBytes(32).toString('base64'));

    await expect(usePostgresAuthState(pool, 'a', otherCipher)).rejects.toThrow(DecryptionError);
  });
});
