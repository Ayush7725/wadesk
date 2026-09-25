import { randomBytes } from 'node:crypto';
import type { WAMessage } from 'baileys';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { createCipher } from '../../src/auth/cipher.js';
import { createPool } from '../../src/db/pool.js';
import { MessageStore } from '../../src/messages/store.js';
import { databaseUrl } from '../support/db.js';

describe('MessageStore', () => {
  const pool = createPool(databaseUrl);
  const store = new MessageStore(pool, createCipher(randomBytes(32).toString('base64')));
  const media: WAMessage = {
    key: { remoteJid: '919876543210@s.whatsapp.net', id: 'P1' },
    message: { imageMessage: { mimetype: 'image/jpeg', mediaKey: Buffer.from('media-key-bytes') } },
  };
  afterAll(() => pool.end());

  beforeEach(async () => {
    await pool.query("DELETE FROM wadesk_engine.sessions WHERE id = 'm-1'");
    await pool.query("INSERT INTO wadesk_engine.sessions (id, expected_phone, webhook_url) VALUES ('m-1', '919800000000', 'http://x')");
  });

  it('round-trips messages including binary media keys', async () => {
    await store.save('m-1', media);

    const found = await store.find('m-1', 'P1');

    expect(Buffer.from(found?.message?.imageMessage?.mediaKey ?? [])).toEqual(Buffer.from('media-key-bytes'));
    expect(await store.find('m-1', 'OTHER')).toBeUndefined();
  });

  it('prunes entries older than the retention window only', async () => {
    await store.save('m-1', media);
    await store.save('m-1', { ...media, key: { ...media.key, id: 'P2' } });
    await pool.query("UPDATE wadesk_engine.messages SET created_at = now() - interval '31 days' WHERE message_id = 'P1'");

    expect(await store.prune()).toBe(1);
    expect(await store.find('m-1', 'P1')).toBeUndefined();
    expect(await store.find('m-1', 'P2')).toBeDefined();
  });
});
