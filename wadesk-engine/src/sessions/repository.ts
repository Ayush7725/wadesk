import type { Pool } from '../db/pool.js';
import type { SessionRecord, SessionState } from './types.js';

interface Row {
  id: string;
  expected_phone: string;
  webhook_url: string;
  state: SessionState;
  me_jid: string | null;
  me_lid: string | null;
  last_error: string | null;
}

const toRecord = (row: Row): SessionRecord => ({
  id: row.id,
  expectedPhone: row.expected_phone,
  webhookUrl: row.webhook_url,
  state: row.state,
  meJid: row.me_jid,
  meLid: row.me_lid,
  lastError: row.last_error,
});

export class SessionRepository {
  constructor(private readonly pool: Pool) {}

  async upsert(id: string, expectedPhone: string, webhookUrl: string): Promise<SessionRecord> {
    const { rows } = await this.pool.query<Row>(
      `INSERT INTO wadesk_engine.sessions (id, expected_phone, webhook_url) VALUES ($1, $2, $3)
       ON CONFLICT (id) DO UPDATE SET expected_phone = EXCLUDED.expected_phone, webhook_url = EXCLUDED.webhook_url, updated_at = now()
       RETURNING *`,
      [id, expectedPhone, webhookUrl],
    );
    return toRecord(rows[0] as Row);
  }

  async find(id: string): Promise<SessionRecord | undefined> {
    const { rows } = await this.pool.query<Row>('SELECT * FROM wadesk_engine.sessions WHERE id = $1', [id]);
    return rows[0] && toRecord(rows[0]);
  }

  async update(id: string, fields: { state: SessionState; meJid?: string | null; meLid?: string | null; lastError?: string | null }) {
    await this.pool.query(
      `UPDATE wadesk_engine.sessions SET state = $2,
         me_jid = CASE WHEN $3 THEN $4 ELSE me_jid END,
         me_lid = CASE WHEN $5 THEN $6 ELSE me_lid END,
         last_error = $7, updated_at = now()
       WHERE id = $1`,
      [id, fields.state, 'meJid' in fields, fields.meJid ?? null, 'meLid' in fields, fields.meLid ?? null, fields.lastError ?? null],
    );
  }

  // Sessions that have stored credentials and were not deliberately ended: resumed at boot (WW-NFR-01).
  async listResumable(): Promise<SessionRecord[]> {
    const { rows } = await this.pool.query<Row>(
      `SELECT s.* FROM wadesk_engine.sessions s
       WHERE s.state NOT IN ('logged_out', 'failed')
         AND EXISTS (SELECT 1 FROM wadesk_engine.auth_keys k WHERE k.session_id = s.id AND k.category = 'creds')
       ORDER BY s.id`,
    );
    return rows.map(toRecord);
  }

  async delete(id: string): Promise<void> {
    await this.pool.query('DELETE FROM wadesk_engine.sessions WHERE id = $1', [id]);
  }
}
