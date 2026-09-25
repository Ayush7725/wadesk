import { BufferJSON, type WAMessage } from 'baileys';
import type { Cipher } from '../auth/cipher.js';
import type { Pool } from '../db/pool.js';

export const RETENTION_DAYS = 30;

// Keeps what is needed to download an incoming message's media later (key + media part, incl. media key).
// Encrypted at rest; pruned after RETENTION_DAYS (docs/wadesk/02-architecture.md §5).
export class MessageStore {
  constructor(
    private readonly pool: Pool,
    private readonly cipher: Cipher,
  ) {}

  async save(sessionId: string, message: WAMessage): Promise<void> {
    const payload = this.cipher.encrypt(Buffer.from(JSON.stringify(message, BufferJSON.replacer)));
    await this.pool.query(
      `INSERT INTO wadesk_engine.messages (session_id, message_id, payload) VALUES ($1, $2, $3)
       ON CONFLICT (session_id, message_id) DO UPDATE SET payload = EXCLUDED.payload`,
      [sessionId, message.key.id, payload],
    );
  }

  async find(sessionId: string, messageId: string): Promise<WAMessage | undefined> {
    const { rows } = await this.pool.query<{ payload: Buffer }>(
      'SELECT payload FROM wadesk_engine.messages WHERE session_id = $1 AND message_id = $2',
      [sessionId, messageId],
    );
    return rows[0] && (JSON.parse(this.cipher.decrypt(rows[0].payload).toString(), BufferJSON.reviver) as WAMessage);
  }

  async prune(): Promise<number> {
    const { rowCount } = await this.pool.query(
      'DELETE FROM wadesk_engine.messages WHERE created_at < now() - make_interval(days => $1)',
      [RETENTION_DAYS],
    );
    return rowCount ?? 0;
  }
}
