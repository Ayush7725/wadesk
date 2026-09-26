import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { createPool } from '../../src/db/pool.js';
import { countingSink, createMetrics } from '../../src/observability/metrics.js';
import { SessionNotConnectedError } from '../../src/sessions/errors.js';
import { API_TOKEN, AUTH, unusedSessions } from '../support/app.js';
import { databaseUrl } from '../support/db.js';

describe('metrics', () => {
  const pool = createPool(databaseUrl);
  afterAll(() => pool.end());

  let metrics: ReturnType<typeof createMetrics>;
  const send = vi.fn();
  const app = () =>
    buildApp({
      pool,
      sessions: { ...unusedSessions, send },
      apiToken: API_TOKEN,
      metrics: { registry: metrics.registry, onSend: (result) => metrics.sends.inc({ result }) },
    });
  const scrape = async () => (await app().inject({ method: 'GET', url: '/metrics', headers: AUTH })).body;

  beforeEach(async () => {
    await pool.query('DELETE FROM wadesk_engine.outbox');
    metrics = createMetrics(pool, () => ({ connected: 2, qr_pending: 1 }));
    send.mockReset();
  });

  it('requires the API token', async () => {
    const response = await app().inject({ method: 'GET', url: '/metrics' });
    expect(response.statusCode).toBe(401);
  });

  it('reports sessions by state and the outbox backlog', async () => {
    await pool.query("INSERT INTO wadesk_engine.outbox (session_id, webhook_url, payload, created_at) VALUES ('x', 'http://x', '{}', now() - interval '90 seconds')");

    const body = await scrape();

    expect(body).toContain('wadesk_engine_sessions{state="connected"} 2');
    expect(body).toContain('wadesk_engine_sessions{state="qr_pending"} 1');
    expect(body).toContain('wadesk_engine_outbox_pending 1');
    expect(body).toMatch(/wadesk_engine_outbox_oldest_seconds (8|9)\d/);
    expect(body).toContain('wadesk_engine_process_resident_memory_bytes');
  });

  it('counts send results', async () => {
    send.mockResolvedValueOnce('ID').mockRejectedValueOnce(new SessionNotConnectedError('1'));
    const form = () => {
      const data = new FormData();
      data.append('to', '919876543210');
      data.append('text', 'hi');
      return data;
    };

    await app().inject({ method: 'POST', url: '/sessions/1/messages', headers: AUTH, payload: form() });
    await app().inject({ method: 'POST', url: '/sessions/1/messages', headers: AUTH, payload: form() });

    const body = await scrape();
    expect(body).toContain('wadesk_engine_sends_total{result="sent"} 1');
    expect(body).toContain('wadesk_engine_sends_total{result="not_connected"} 1');
  });

  it('counts events queued for Chatwoot by type', async () => {
    const sink = countingSink({ emit: () => Promise.resolve() }, metrics.registry);

    await sink.emit('1', { event: 'connection', state: 'connected' });
    await sink.emit('1', { event: 'statuses', statuses: [{ id: 'A', status: 'read', recipient_id: '9' }] });

    const body = await scrape();
    expect(body).toContain('wadesk_engine_events_total{event="connection"} 1');
    expect(body).toContain('wadesk_engine_events_total{event="statuses"} 1');
  });
});
