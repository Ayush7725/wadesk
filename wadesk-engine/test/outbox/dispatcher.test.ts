import { createServer, type IncomingMessage, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { pino } from 'pino';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createPool } from '../../src/db/pool.js';
import { DEFAULT_DISPATCHER_OPTIONS, Dispatcher, sign } from '../../src/outbox/dispatcher.js';
import { OutboxSink } from '../../src/outbox/outbox.js';
import { SessionRepository } from '../../src/sessions/repository.js';
import { databaseUrl } from '../support/db.js';

const SECRET = 's'.repeat(32);

interface Received {
  path: string;
  body: string;
  timestamp: string;
  signature: string;
}

describe('outbox delivery', () => {
  const pool = createPool(databaseUrl);
  const repository = new SessionRepository(pool);
  let server: Server;
  let baseUrl: string;
  let received: Received[];
  let respond: (request: IncomingMessage) => number;
  let dispatchers: Dispatcher[];

  const dispatcher = (overrides: Partial<typeof DEFAULT_DISPATCHER_OPTIONS> = {}) => {
    const created = new Dispatcher(pool, { ...DEFAULT_DISPATCHER_OPTIONS, secret: SECRET, ...overrides }, pino({ level: 'silent' }));
    dispatchers.push(created);
    return created;
  };
  const sink = () => new OutboxSink(pool, repository, () => undefined);
  const pending = async () =>
    (await pool.query<{ session_id: string; attempts: number }>("SELECT session_id, attempts FROM wadesk_engine.outbox WHERE session_id LIKE 'o-%' ORDER BY id")).rows;

  beforeAll(async () => {
    server = createServer((request, response) => {
      let body = '';
      request.on('data', (chunk: Buffer) => (body += chunk.toString()));
      request.on('end', () => {
        received.push({
          path: request.url ?? '',
          body,
          timestamp: String(request.headers['x-wadesk-timestamp']),
          signature: String(request.headers['x-wadesk-signature']),
        });
        response.statusCode = respond(request);
        response.end();
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    baseUrl = `http://127.0.0.1:${String((server.address() as AddressInfo).port)}`;
  });

  beforeEach(async () => {
    received = [];
    respond = () => 200;
    dispatchers = [];
    await pool.query("DELETE FROM wadesk_engine.outbox WHERE session_id LIKE 'o-%'");
    await pool.query("DELETE FROM wadesk_engine.sessions WHERE id LIKE 'o-%'");
    for (const id of ['o-1', 'o-2']) await repository.upsert(id, '919812345678', `${baseUrl}/webhooks/whatsapp_web/${id}`);
  });

  afterEach(async () => {
    for (const created of dispatchers) await created.stop();
  });

  afterAll(async () => {
    await new Promise((resolve) => server.close(resolve));
    await pool.end();
  });

  it('delivers events signed with the webhook secret and removes them', async () => {
    await sink().emit('o-1', { event: 'connection', state: 'connected' });

    await dispatcher().drain();

    expect(received).toHaveLength(1);
    const [delivery] = received;
    expect(delivery?.path).toBe('/webhooks/whatsapp_web/o-1');
    expect(JSON.parse(delivery?.body ?? '')).toEqual({ event: 'connection', state: 'connected' });
    expect(delivery?.signature).toBe(sign(SECRET, delivery?.timestamp ?? '', delivery?.body ?? ''));
    expect(await pending()).toEqual([]);
  });

  it('keeps events of one session in order while another session proceeds', async () => {
    await sink().emit('o-1', { state: 'connecting' });
    await sink().emit('o-1', { state: 'connected' });
    await sink().emit('o-2', { state: 'connecting' });
    respond = (request) => (request.url?.endsWith('o-1') ? 500 : 200);

    await dispatcher().drain();

    // o-1's first event failed, so its second is held back; o-2 is unaffected.
    expect(received.map((r) => `${r.path.slice(-3)}:${(JSON.parse(r.body) as { state: string }).state}`)).toEqual([
      'o-1:connecting',
      'o-2:connecting',
    ]);
    expect(await pending()).toEqual([
      { session_id: 'o-1', attempts: 1 },
      { session_id: 'o-1', attempts: 0 },
    ]);
  });

  it('retries failed deliveries after a backoff, in order', async () => {
    await sink().emit('o-1', { state: 'connecting' });
    await sink().emit('o-1', { state: 'connected' });
    respond = () => 503;
    await dispatcher().drain();

    await pool.query("UPDATE wadesk_engine.outbox SET next_attempt_at = now() WHERE session_id = 'o-1'");
    respond = () => 200;
    await dispatcher().drain();

    expect(received.map((r) => (JSON.parse(r.body) as { state: string }).state)).toEqual(['connecting', 'connecting', 'connected']);
    expect(await pending()).toEqual([]);
  });

  it('treats unreachable endpoints as failures to retry', async () => {
    await pool.query("UPDATE wadesk_engine.sessions SET webhook_url = 'http://127.0.0.1:1/unreachable' WHERE id = 'o-1'");
    await sink().emit('o-1', { state: 'connecting' });

    await dispatcher().drain();

    expect(await pending()).toEqual([{ session_id: 'o-1', attempts: 1 }]);
  });

  it('drops events that keep failing past the retry window', async () => {
    await sink().emit('o-1', { state: 'connecting' });
    await pool.query("UPDATE wadesk_engine.outbox SET created_at = now() - interval '49 hours' WHERE session_id = 'o-1'");
    respond = () => 404;

    await dispatcher().drain();

    expect(received).toHaveLength(1);
    expect(await pending()).toEqual([]);
  });

  it('still delivers final events after the session was deleted', async () => {
    await sink().emit('o-1', { state: 'logged_out' });
    await repository.delete('o-1');

    await dispatcher().drain();

    expect(received.map((r) => r.path)).toEqual(['/webhooks/whatsapp_web/o-1']);
  });

  it('delivers events left over from before a restart', async () => {
    await sink().emit('o-1', { state: 'connected' });

    const restarted = dispatcher({ pollIntervalMs: 10 });
    restarted.start();

    await expect.poll(() => received.length, { timeout: 5_000 }).toBe(1);
  });

  it('does not let two dispatchers deliver the same event at once', async () => {
    for (let i = 0; i < 5; i++) await sink().emit(i % 2 ? 'o-1' : 'o-2', { n: i });

    await Promise.all([dispatcher().drain(), dispatcher().drain()]);

    expect(received.map((r) => r.body).sort()).toEqual([0, 1, 2, 3, 4].map((n) => JSON.stringify({ n })));
  });
});
