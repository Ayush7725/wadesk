import { randomBytes } from 'node:crypto';
import { DisconnectReason } from 'baileys';
import { pino } from 'pino';
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createCipher } from '../../src/auth/cipher.js';
import { usePostgresAuthState } from '../../src/auth/postgres-auth-state.js';
import { createPool } from '../../src/db/pool.js';
import { SessionNotFoundError, SessionStateError } from '../../src/sessions/errors.js';
import { SessionManager } from '../../src/sessions/manager.js';
import { SessionRepository } from '../../src/sessions/repository.js';
import type { SessionTiming } from '../../src/sessions/session.js';
import type { ConnectionEvent } from '../../src/sessions/types.js';
import { databaseUrl } from '../support/db.js';
import { fakeSocketFactory } from '../support/fake-socket.js';

const PHONE = '919812345678';
const OTHER_PHONE = '919800000000';
const WEBHOOK = 'http://chatwoot/webhooks/whatsapp_web/1';
const FAST: SessionTiming = { baseBackoffMs: 5, maxBackoffMs: 20, qrTimeoutMs: 150 };
// Generous timeout: these steps take milliseconds, but a busy CI runner or laptop can stall the database briefly.
const eventually = <T>(assertion: () => T | Promise<T>) => vi.waitFor(assertion, { timeout: 5_000, interval: 10 });

describe('SessionManager', () => {
  const pool = createPool(databaseUrl);
  const repository = new SessionRepository(pool);
  const cipher = createCipher(randomBytes(32).toString('base64'));
  let events: { sessionId: string; event: ConnectionEvent }[];
  let managers: SessionManager[];

  const build = (overrides: { failAuthFor?: string } = {}) => {
    const { factory, sockets } = fakeSocketFactory();
    const sink = events; // bound now, so late events from an earlier test never leak into this one
    const manager = new SessionManager({
      repository,
      createAuthState: (id) =>
        id === overrides.failAuthFor ? Promise.reject(new Error('boom')) : usePostgresAuthState(pool, id, cipher),
      createSocket: factory,
      events: {
        emit: (sessionId, event) => {
          sink.push({ sessionId, event });
          return Promise.resolve();
        },
      },
      logger: pino({ level: 'silent' }),
      timing: FAST,
    });
    managers.push(manager);
    return { manager, sockets };
  };

  const socketAt = <T>(sockets: T[], index: number): T => {
    const socket = sockets[index];
    if (!socket) throw new Error(`socket ${String(index)} was not created`);
    return socket;
  };
  const statesOf = (id: string) => events.filter((e) => e.sessionId === id).map((e) => e.event.state);
  const credsCount = async (id: string) =>
    Number((await pool.query<{ n: string }>('SELECT count(*) AS n FROM wadesk_engine.auth_keys WHERE session_id = $1', [id])).rows[0]?.n);

  beforeEach(async () => {
    events = [];
    managers = [];
    await pool.query("DELETE FROM wadesk_engine.sessions WHERE id LIKE 't-%'");
  });
  afterEach(() => {
    for (const manager of managers) manager.shutdown();
  });
  afterAll(() => pool.end());

  it('offers a QR code for a new session', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    expect((await manager.get('t-1')).state).toBe('connecting');

    socketAt(sockets, 0).update({ qr: 'qr-ref-1' });

    await eventually(() => expect(statesOf('t-1')).toEqual(['connecting', 'qr_pending']));
    expect(await manager.get('t-1')).toEqual({ state: 'qr_pending', qr: 'qr-ref-1' });
  });

  it('connects when the expected number links and stores its identity', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).update({ qr: 'qr' });
    socketAt(sockets, 0).open(PHONE);

    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('connected'));
    expect(await manager.get('t-1')).toEqual({ state: 'connected', me: { phone: PHONE } });
    expect(await repository.find('t-1')).toMatchObject({ state: 'connected', meJid: `${PHONE}:7@s.whatsapp.net`, meLid: '123456789:7@lid' });
    expect(events.at(-1)?.event).toEqual({ event: 'connection', state: 'connected', me: { phone: PHONE } });
  });

  it('rejects a different phone, unlinks it and forgets its credentials', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    const socket = socketAt(sockets, 0);
    socket.credsChanged();
    await eventually(async () => expect(await credsCount('t-1')).toBe(1));

    socket.open(OTHER_PHONE);

    // The event is emitted last in a transition, so waiting for it means state and storage are settled.
    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('failed'));
    expect(socket.loggedOut).toBe(true);
    expect(socket.ended).toBe(true);
    expect(await credsCount('t-1')).toBe(0);
    expect(events.at(-1)?.event).toEqual({ event: 'connection', state: 'failed', reason: 'number_mismatch' });
  });

  it('requests a pairing code for the expected number only while waiting to link', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).update({ qr: 'qr' });
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('qr_pending'));

    expect(await manager.requestPairingCode('t-1')).toBe('ABCD1234');
    expect(socketAt(sockets, 0).pairingRequests).toEqual([PHONE]);

    socketAt(sockets, 0).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));
    await expect(manager.requestPairingCode('t-1')).rejects.toThrow(SessionStateError);
  });

  it('restarts the socket when WhatsApp requires it after linking', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).close(DisconnectReason.restartRequired);

    await eventually(() => expect(sockets).toHaveLength(2));
    socketAt(sockets, 1).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));
  });

  it('reconnects automatically after the connection drops', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));

    socketAt(sockets, 0).close(DisconnectReason.connectionLost);

    await eventually(() => expect(sockets).toHaveLength(2));
    socketAt(sockets, 1).open(PHONE);
    await eventually(() => expect(statesOf('t-1')).toEqual(['connecting', 'connected', 'disconnected', 'connected']));
  });

  it('marks the session logged out and wipes credentials when unlinked from the phone', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).credsChanged();
    socketAt(sockets, 0).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));

    socketAt(sockets, 0).close(DisconnectReason.loggedOut);

    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('logged_out'));
    expect(await credsCount('t-1')).toBe(0);
    expect(events.at(-1)?.event).toMatchObject({ state: 'logged_out', reason: 'unlinked_from_phone' });
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(sockets).toHaveLength(1);
  });

  it('stops without reconnecting when WhatsApp forbids the connection', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).close(DisconnectReason.forbidden);

    await eventually(async () => expect(await manager.get('t-1')).toEqual({ state: 'failed', lastError: 'forbidden' }));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(sockets).toHaveLength(1);
  });

  it('stops offering QR codes after the QR timeout', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).update({ qr: 'qr' });
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('qr_pending'));

    await new Promise((resolve) => setTimeout(resolve, FAST.qrTimeoutMs + 10));
    socketAt(sockets, 0).close(DisconnectReason.timedOut);

    await eventually(async () => expect(await manager.get('t-1')).toEqual({ state: 'disconnected', lastError: 'qr_expired' }));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(sockets).toHaveLength(1);
  });

  it('resumes linked sessions after an engine restart without a new QR code', async () => {
    const first = build();
    await first.manager.upsert('t-1', PHONE, WEBHOOK);
    await first.manager.upsert('t-2', OTHER_PHONE, WEBHOOK);
    socketAt(first.sockets, 0).credsChanged();
    socketAt(first.sockets, 0).open(PHONE);
    await eventually(async () => expect(await credsCount('t-1')).toBe(1));
    first.manager.shutdown();

    const second = build();
    await second.manager.resumeAll();

    expect(second.sockets).toHaveLength(1); // t-2 never linked, so it has no credentials to resume
    socketAt(second.sockets, 0).open(PHONE);
    await eventually(async () => expect((await second.manager.get('t-1')).state).toBe('connected'));
  });

  it('keeps other sessions running when one fails to resume', async () => {
    const first = build();
    for (const id of ['t-bad', 't-good']) {
      await first.manager.upsert(id, PHONE, WEBHOOK);
    }
    for (const socket of first.sockets) socket.credsChanged();
    await eventually(async () => expect((await credsCount('t-bad')) + (await credsCount('t-good'))).toBe(2));
    first.manager.shutdown();

    const second = build({ failAuthFor: 't-bad' });
    await second.manager.resumeAll();

    expect(second.sockets).toHaveLength(1);
    expect((await second.manager.get('t-good')).state).toBe('connecting');
  });

  it('is idempotent while the same number is live', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    await manager.upsert('t-1', PHONE, 'http://new-webhook');

    expect(sockets).toHaveLength(1);
    expect((await repository.find('t-1'))?.webhookUrl).toBe('http://new-webhook');
  });

  it('reconnects a dropped session with its stored credentials instead of unlinking it', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).update({ qr: 'qr' });
    await new Promise((resolve) => setTimeout(resolve, FAST.qrTimeoutMs + 10));
    socketAt(sockets, 0).close(DisconnectReason.timedOut);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('disconnected'));

    await manager.upsert('t-1', PHONE, WEBHOOK);

    expect(socketAt(sockets, 0).loggedOut).toBe(false);
    expect(sockets).toHaveLength(2);
  });

  it('unlinks the old device when the number changes', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).credsChanged();
    socketAt(sockets, 0).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));

    await manager.upsert('t-1', OTHER_PHONE, WEBHOOK);

    expect(socketAt(sockets, 0).loggedOut).toBe(true);
    expect((await repository.find('t-1'))?.expectedPhone).toBe(OTHER_PHONE);
    expect(await credsCount('t-1')).toBe(0);
  });

  it('removes a session, logging it out and deleting its credentials', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK);
    socketAt(sockets, 0).credsChanged();
    await eventually(async () => expect(await credsCount('t-1')).toBe(1));

    await manager.remove('t-1');

    expect(socketAt(sockets, 0).loggedOut).toBe(true);
    expect(await credsCount('t-1')).toBe(0);
    await expect(manager.get('t-1')).rejects.toThrow(SessionNotFoundError);
    await expect(manager.remove('t-1')).rejects.toThrow(SessionNotFoundError);
  });
});
