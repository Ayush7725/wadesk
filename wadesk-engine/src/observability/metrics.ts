import { collectDefaultMetrics, Counter, Gauge, Registry } from 'prom-client';
import type { Pool } from '../db/pool.js';
import type { EngineEvent, EventSink, SessionState } from '../sessions/types.js';

export interface Metrics {
  registry: Registry;
  sends: Counter<'result'>;
}

// Prometheus metrics for operators (WW-NFR-09). Session states and outbox backlog are read at scrape time.
export function createMetrics(pool: Pool, sessionStates: () => Partial<Record<SessionState, number>>): Metrics {
  const registry = new Registry();
  collectDefaultMetrics({ register: registry, prefix: 'wadesk_engine_' });

  new Gauge({
    name: 'wadesk_engine_sessions',
    help: 'WhatsApp Web sessions on this engine, by state',
    labelNames: ['state'],
    registers: [registry],
    collect() {
      this.reset();
      for (const [state, count] of Object.entries(sessionStates())) this.set({ state }, count);
    },
  });

  new Gauge({
    name: 'wadesk_engine_outbox_pending',
    help: 'Events waiting to be delivered to Chatwoot',
    registers: [registry],
    async collect() {
      const { rows } = await pool.query<{ n: string }>('SELECT count(*) AS n FROM wadesk_engine.outbox');
      this.set(Number(rows[0]?.n ?? 0));
    },
  });

  new Gauge({
    name: 'wadesk_engine_outbox_oldest_seconds',
    help: 'Age of the oldest undelivered event (0 when the outbox is empty)',
    registers: [registry],
    async collect() {
      const { rows } = await pool.query<{ age: string | null }>(
        'SELECT extract(epoch FROM now() - min(created_at)) AS age FROM wadesk_engine.outbox',
      );
      this.set(Number(rows[0]?.age ?? 0));
    },
  });

  return {
    registry,
    sends: new Counter({
      name: 'wadesk_engine_sends_total',
      help: 'Send requests by result',
      labelNames: ['result'],
      registers: [registry],
    }),
  };
}

// Counts events by type on their way to Chatwoot (messages, statuses, connection changes).
export function countingSink(sink: EventSink, registry: Registry): EventSink {
  const events = new Counter({
    name: 'wadesk_engine_events_total',
    help: 'Events queued for Chatwoot, by type',
    labelNames: ['event'],
    registers: [registry],
  });
  return {
    async emit(sessionId: string, event: EngineEvent) {
      await sink.emit(sessionId, event);
      events.inc({ event: event.event });
    },
  };
}
