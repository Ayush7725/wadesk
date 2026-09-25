import {
  BufferJSON,
  initAuthCreds,
  proto,
  type AuthenticationCreds,
  type AuthenticationState,
  type SignalDataSet,
  type SignalDataTypeMap,
} from 'baileys';
import type { Pool } from '../db/pool.js';
import type { Cipher } from './cipher.js';

const CREDS = 'creds';

export interface PostgresAuthState {
  state: AuthenticationState;
  saveCreds(): Promise<void>;
  clear(): Promise<void>;
}

// Baileys AuthenticationState backed by wadesk_engine.auth_keys, encrypted at rest (ADR-0004).
// Serialisation matches Baileys' reference store (BufferJSON), so values round-trip exactly.
// The session row must already exist in wadesk_engine.sessions.
export async function usePostgresAuthState(pool: Pool, sessionId: string, cipher: Cipher): Promise<PostgresAuthState> {
  const encode = (value: unknown) => cipher.encrypt(Buffer.from(JSON.stringify(value, BufferJSON.replacer)));
  const decode = (blob: Buffer): unknown => JSON.parse(cipher.decrypt(blob).toString(), BufferJSON.reviver);

  const readCreds = async (): Promise<AuthenticationCreds | undefined> => {
    const { rows } = await pool.query<{ value: Buffer }>(
      "SELECT value FROM wadesk_engine.auth_keys WHERE session_id = $1 AND category = $2 AND key_id = ''",
      [sessionId, CREDS],
    );
    return rows[0] && (decode(rows[0].value) as AuthenticationCreds);
  };

  const creds = (await readCreds()) ?? initAuthCreds();

  const get = async <T extends keyof SignalDataTypeMap>(type: T, ids: string[]) => {
    const { rows } = await pool.query<{ key_id: string; value: Buffer }>(
      'SELECT key_id, value FROM wadesk_engine.auth_keys WHERE session_id = $1 AND category = $2 AND key_id = ANY($3)',
      [sessionId, type, ids],
    );
    const result: Record<string, SignalDataTypeMap[T]> = {};
    for (const row of rows) {
      const value = decode(row.value);
      result[row.key_id] = (
        type === 'app-state-sync-key' ? proto.Message.AppStateSyncKeyData.fromObject(value as object) : value
      ) as SignalDataTypeMap[T];
    }
    return result;
  };

  // Applies all changes in one transaction: null deletes a key, anything else upserts it.
  const set = async (data: SignalDataSet) => {
    const upserts: { category: string; keyId: string; value: Buffer }[] = [];
    const deletes: { category: string; keyId: string }[] = [];
    for (const [category, entries] of Object.entries(data)) {
      for (const [keyId, value] of Object.entries(entries)) {
        if (value) upserts.push({ category, keyId, value: encode(value) });
        else deletes.push({ category, keyId });
      }
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      if (upserts.length) {
        await client.query(
          `INSERT INTO wadesk_engine.auth_keys (session_id, category, key_id, value)
           SELECT $1, * FROM unnest($2::text[], $3::text[], $4::bytea[])
           ON CONFLICT (session_id, category, key_id) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
          [sessionId, upserts.map((u) => u.category), upserts.map((u) => u.keyId), upserts.map((u) => u.value)],
        );
      }
      if (deletes.length) {
        await client.query(
          `DELETE FROM wadesk_engine.auth_keys k USING unnest($2::text[], $3::text[]) AS d(category, key_id)
           WHERE k.session_id = $1 AND k.category = d.category AND k.key_id = d.key_id`,
          [sessionId, deletes.map((d) => d.category), deletes.map((d) => d.keyId)],
        );
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  };

  return {
    state: { creds, keys: { get, set } },
    saveCreds: async () => {
      await pool.query(
        `INSERT INTO wadesk_engine.auth_keys (session_id, category, key_id, value) VALUES ($1, $2, '', $3)
         ON CONFLICT (session_id, category, key_id) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
        [sessionId, CREDS, encode(creds)],
      );
    },
    clear: async () => {
      await pool.query('DELETE FROM wadesk_engine.auth_keys WHERE session_id = $1', [sessionId]);
    },
  };
}
