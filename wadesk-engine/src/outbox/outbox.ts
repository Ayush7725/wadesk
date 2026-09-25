import type { Pool } from '../db/pool.js';
import type { SessionRepository } from '../sessions/repository.js';
import type { EventSink } from '../sessions/types.js';

// Persists events for Chatwoot before anything is sent (at-least-once delivery, WW-NFR-02).
export class OutboxSink implements EventSink {
  constructor(
    private readonly pool: Pool,
    private readonly repository: SessionRepository,
    private readonly onEnqueued: () => void,
  ) {}

  async emit(sessionId: string, event: object): Promise<void> {
    const session = await this.repository.find(sessionId);
    if (!session) throw new Error(`Cannot enqueue event for unknown session ${sessionId}`);
    await this.pool.query('INSERT INTO wadesk_engine.outbox (session_id, webhook_url, payload) VALUES ($1, $2, $3)', [
      sessionId,
      session.webhookUrl,
      JSON.stringify(event),
    ]);
    this.onEnqueued();
  }
}
