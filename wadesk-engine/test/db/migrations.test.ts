import { afterAll, describe, expect, it } from 'vitest';
import { migrate, SCHEMA } from '../../src/db/migrate.js';
import { createPool } from '../../src/db/pool.js';
import { databaseUrl, silent } from '../support/db.js';

describe('engine migrations', () => {
  const pool = createPool(databaseUrl);
  afterAll(() => pool.end());

  const tables = async (): Promise<string[]> => {
    const { rows } = await pool.query<{ table_name: string }>(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_name <> 'schema_migrations' ORDER BY table_name",
      [SCHEMA],
    );
    return rows.map((row) => row.table_name);
  };

  it('creates the engine tables in their own schema', async () => {
    expect(await tables()).toEqual(['auth_keys', 'messages', 'outbox', 'sessions']);
  });

  it('can be fully reverted and re-applied', async () => {
    await migrate(databaseUrl, silent, 'down', Infinity);
    expect(await tables()).toEqual([]);

    await migrate(databaseUrl, silent);
    expect(await tables()).toEqual(['auth_keys', 'messages', 'outbox', 'sessions']);
  });

  it('deletes a session with its credentials and messages but keeps outbox events', async () => {
    await pool.query("INSERT INTO wadesk_engine.sessions (id, expected_phone, webhook_url) VALUES ('s1', '919800000000', 'http://x')");
    await pool.query("INSERT INTO wadesk_engine.auth_keys (session_id, category, key_id, value) VALUES ('s1', 'creds', '', '\\x00')");
    await pool.query("INSERT INTO wadesk_engine.messages (session_id, message_id, payload) VALUES ('s1', 'm1', '\\x00')");
    await pool.query("INSERT INTO wadesk_engine.outbox (session_id, webhook_url, payload) VALUES ('s1', 'http://x', '{}')");

    await pool.query("DELETE FROM wadesk_engine.sessions WHERE id = 's1'");

    const count = async (table: string) =>
      Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM wadesk_engine.${table} WHERE session_id = 's1'`)).rows[0]?.n);
    expect(await count('auth_keys')).toBe(0);
    expect(await count('messages')).toBe(0);
    expect(await count('outbox')).toBe(1);

    await pool.query("DELETE FROM wadesk_engine.outbox WHERE session_id = 's1'");
  });
});
