import { createHmac } from 'node:crypto';
import type { Logger } from 'pino';
import type { Pool } from '../db/pool.js';

export interface DispatcherOptions {
  secret: string;
  batchSize: number;
  pollIntervalMs: number;
  leaseSeconds: number; // how long a claimed event is hidden from other workers
  maxBackoffSeconds: number;
  giveUpAfterHours: number;
  requestTimeoutMs: number;
}

export const DEFAULT_DISPATCHER_OPTIONS: Omit<DispatcherOptions, 'secret'> = {
  batchSize: 50,
  pollIntervalMs: 1_000,
  leaseSeconds: 60,
  maxBackoffSeconds: 600,
  giveUpAfterHours: 48,
  requestTimeoutMs: 10_000,
};

interface OutboxRow {
  id: string;
  session_id: string;
  webhook_url: string;
  payload: unknown;
  attempts: number;
  expired: boolean;
}

// Signature Chatwoot verifies: sha256=HMAC(secret, "<timestamp>.<body>") (02-architecture §4.2).
export function sign(secret: string, timestamp: string, body: string): string {
  return `sha256=${createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex')}`;
}

// Delivers outbox events to Chatwoot. Only the oldest pending event of each session is eligible,
// so events for one number always arrive in order. Claims use a lease, so several engine
// instances can run dispatchers without delivering the same event twice concurrently.
export class Dispatcher {
  private timer: NodeJS.Timeout | undefined;
  private running: Promise<void> | undefined;
  private rerun = false;
  private active = false; // started and not stopped: polling and kicks run passes
  private stopping = false; // shutdown requested: finish the current batch, then stop

  constructor(
    private readonly pool: Pool,
    private readonly options: DispatcherOptions,
    private readonly logger: Logger,
  ) {}

  start(): void {
    this.active = true;
    this.stopping = false;
    this.timer = setInterval(() => {
      this.kick();
    }, this.options.pollIntervalMs);
    this.kick();
  }

  async stop(): Promise<void> {
    this.active = false;
    this.stopping = true;
    clearInterval(this.timer);
    await this.running;
  }

  // Runs a delivery pass now (or right after the current one finishes).
  kick(): void {
    if (!this.active) return;
    if (this.running) {
      this.rerun = true;
      return;
    }
    this.running = this.drain()
      .catch((error: unknown) => this.logger.error({ err: error }, 'outbox delivery pass failed'))
      .finally(() => {
        this.running = undefined;
        if (this.rerun) {
          this.rerun = false;
          this.kick();
        }
      });
  }

  // Delivers until nothing is due. Exposed for tests.
  async drain(): Promise<void> {
    for (;;) {
      const rows = await this.claim();
      if (rows.length === 0) return;
      await Promise.all(rows.map((row) => this.deliver(row)));
      if (this.stopping) return;
    }
  }

  private async claim(): Promise<OutboxRow[]> {
    const { rows } = await this.pool.query<OutboxRow>(
      `UPDATE wadesk_engine.outbox o
       SET next_attempt_at = now() + make_interval(secs => $2), attempts = o.attempts + 1
       WHERE o.id IN (
         SELECT h.id FROM wadesk_engine.outbox h
         WHERE h.next_attempt_at <= now()
           AND NOT EXISTS (SELECT 1 FROM wadesk_engine.outbox e WHERE e.session_id = h.session_id AND e.id < h.id)
         ORDER BY h.id
         LIMIT $1
         FOR UPDATE SKIP LOCKED)
       RETURNING o.id, o.session_id, o.webhook_url, o.payload, o.attempts,
                 o.created_at < now() - make_interval(hours => $3) AS expired`,
      [this.options.batchSize, this.options.leaseSeconds, this.options.giveUpAfterHours],
    );
    return rows;
  }

  private async deliver(row: OutboxRow): Promise<void> {
    const body = JSON.stringify(row.payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    let failure: string;
    try {
      const response = await fetch(row.webhook_url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-wadesk-timestamp': timestamp, 'x-wadesk-signature': sign(this.options.secret, timestamp, body) },
        body,
        signal: AbortSignal.timeout(this.options.requestTimeoutMs),
      });
      if (response.ok) {
        await this.pool.query('DELETE FROM wadesk_engine.outbox WHERE id = $1', [row.id]);
        return;
      }
      failure = `HTTP ${String(response.status)}`;
    } catch (error) {
      failure = error instanceof Error ? error.message : String(error);
    }

    if (row.expired) {
      await this.pool.query('DELETE FROM wadesk_engine.outbox WHERE id = $1', [row.id]);
      this.logger.error({ sessionId: row.session_id, outboxId: row.id, attempts: row.attempts, failure }, 'outbox event dropped after retry window');
      return;
    }
    const backoff = Math.min(2 ** row.attempts, this.options.maxBackoffSeconds);
    await this.pool.query('UPDATE wadesk_engine.outbox SET next_attempt_at = now() + make_interval(secs => $2) WHERE id = $1', [row.id, backoff]);
    this.logger.warn({ sessionId: row.session_id, outboxId: row.id, attempts: row.attempts, failure, retryInSeconds: backoff }, 'outbox delivery failed');
  }
}
