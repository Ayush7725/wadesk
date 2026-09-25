import { randomBytes } from 'node:crypto';
import { DisconnectReason, type proto, type WAMessage } from 'baileys';
import { pino } from 'pino';
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createCipher } from '../../src/auth/cipher.js';
import { usePostgresAuthState } from '../../src/auth/postgres-auth-state.js';
import { createPool } from '../../src/db/pool.js';
import { MessageStore } from '../../src/messages/store.js';
import {
  MediaNotFoundError,
  MediaUnavailableError,
  RateLimitedError,
  SessionNotConnectedError,
  SessionNotFoundError,
} from '../../src/sessions/errors.js';
import { SessionManager } from '../../src/sessions/manager.js';
import { SessionRepository } from '../../src/sessions/repository.js';
import type { SessionTiming } from '../../src/sessions/session.js';
import type { EngineEvent } from '../../src/sessions/types.js';
import { databaseUrl } from '../support/db.js';
import { fakeSocketFactory } from '../support/fake-socket.js';

const PHONE = '919812345678';
const OTHER_PHONE = '919800000000';
const WEBHOOK = 'http://chatwoot/webhooks/whatsapp_web/1';
// Long QR limit by default so slow CI runners never hit it by accident; QR-expiry tests use SHORT_QR explicitly.
const FAST: SessionTiming = { baseBackoffMs: 5, maxBackoffMs: 20, qrTimeoutMs: 60_000, sendsPerMinute: 20 };
const SHORT_QR: SessionTiming = { ...FAST, qrTimeoutMs: 150 };
// Generous timeout: these steps take milliseconds, but a busy CI runner or laptop can stall the database briefly.
const eventually = <T>(assertion: () => T | Promise<T>) => vi.waitFor(assertion, { timeout: 5_000, interval: 10 });

describe('SessionManager', () => {
  const pool = createPool(databaseUrl);
  const repository = new SessionRepository(pool);
  const cipher = createCipher(randomBytes(32).toString('base64'));
  const messages = new MessageStore(pool, cipher);
  let events: { sessionId: string; event: EngineEvent }[];
  let managers: SessionManager[];

  const build = (overrides: { failAuthFor?: string; timing?: SessionTiming } = {}) => {
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
      messages,
      logger: pino({ level: 'silent' }),
      timing: overrides.timing ?? FAST,
    });
    managers.push(manager);
    return { manager, sockets };
  };

  const socketAt = <T>(sockets: T[], index: number): T => {
    const socket = sockets[index];
    if (!socket) throw new Error(`socket ${String(index)} was not created`);
    return socket;
  };
  const statesOf = (id: string) =>
    events.flatMap(({ sessionId, event }) => (sessionId === id && event.event === 'connection' ? [event.state] : []));
  const messageEventsOf = (id: string) => events.filter(({ sessionId, event }) => sessionId === id && event.event === 'messages');
  const credsCount = async (id: string) =>
    Number((await pool.query<{ n: string }>('SELECT count(*) AS n FROM wadesk_engine.auth_keys WHERE session_id = $1', [id])).rows[0]?.n);

  beforeEach(async () => {
    events = [];
    managers = [];
    await pool.query("DELETE FROM wadesk_engine.sessions WHERE id LIKE 't-%'"); // cascades to stored messages
  });
  afterEach(() => {
    for (const manager of managers) manager.shutdown();
  });
  afterAll(() => pool.end());

  it('offers a QR code for a new session', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    expect((await manager.get('t-1')).state).toBe('connecting');

    socketAt(sockets, 0).update({ qr: 'qr-ref-1' });

    await eventually(() => expect(statesOf('t-1')).toEqual(['connecting', 'qr_pending']));
    expect(await manager.get('t-1')).toEqual({ state: 'qr_pending', qr: 'qr-ref-1' });
  });

  it('connects when the expected number links and stores its identity', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).update({ qr: 'qr' });
    socketAt(sockets, 0).open(PHONE);

    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('connected'));
    expect(await manager.get('t-1')).toEqual({ state: 'connected', me: { phone: PHONE } });
    expect(await repository.find('t-1')).toMatchObject({ state: 'connected', meJid: `${PHONE}:7@s.whatsapp.net`, meLid: '123456789:7@lid' });
    expect(events.at(-1)?.event).toEqual({ event: 'connection', state: 'connected', me: { phone: PHONE } });
  });

  it('rejects a different phone, unlinks it and forgets its credentials', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
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

  it('labels QR-linked devices as WaDesk and never shows pairing codes in QR mode', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).update({ qr: 'qr' });

    await eventually(() => expect(statesOf('t-1')).toEqual(['connecting', 'qr_pending']));
    expect(socketAt(sockets, 0).linkMethod).toBe('qr');
    expect(socketAt(sockets, 0).pairingRequests).toEqual([]);
  });

  it('requests a pairing code automatically in code mode, once per connection', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'code');
    const socket = socketAt(sockets, 0);
    socket.update({ qr: 'qr-1' });
    socket.update({ qr: 'qr-2' }); // QR rotation on the same connection keeps the same code

    await eventually(async () => expect(await manager.get('t-1')).toEqual({ state: 'qr_pending', pairingCode: 'CODE0001' }));
    expect(socket.linkMethod).toBe('code');
    expect(socket.pairingRequests).toEqual([PHONE]);
  });

  it('issues a fresh pairing code after the connection is replaced', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'code');
    socketAt(sockets, 0).update({ qr: 'qr' });
    await eventually(async () => expect((await manager.get('t-1')).pairingCode).toBe('CODE0001'));

    socketAt(sockets, 0).close(DisconnectReason.timedOut);
    await eventually(() => expect(sockets).toHaveLength(2));
    socketAt(sockets, 1).update({ qr: 'qr' });

    await eventually(async () => expect((await manager.get('t-1')).pairingCode).toBe('CODE0001'));
    expect(socketAt(sockets, 1).pairingRequests).toEqual([PHONE]);
  });

  it('retries with fresh credentials when an unused link attempt expires', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'code');
    socketAt(sockets, 0).credsChanged();
    socketAt(sockets, 0).update({ qr: 'qr' });
    await eventually(async () => expect(await credsCount('t-1')).toBe(1));
    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('qr_pending'));

    socketAt(sockets, 0).close(DisconnectReason.loggedOut); // how WhatsApp ends an expired pairing code

    await eventually(() => expect(sockets).toHaveLength(2));
    expect(await credsCount('t-1')).toBe(0);
    socketAt(sockets, 1).update({ qr: 'qr' });
    await eventually(async () => expect(await manager.get('t-1')).toEqual({ state: 'qr_pending', pairingCode: 'CODE0001' }));
    expect(statesOf('t-1')).not.toContain('logged_out');
  });

  it('clears the pairing code once linked', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'code');
    socketAt(sockets, 0).update({ qr: 'qr' });
    socketAt(sockets, 0).open(PHONE);

    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('connected'));
    expect(await manager.get('t-1')).toEqual({ state: 'connected', me: { phone: PHONE } });
  });

  it('restarts linking when the admin switches method before linking', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');

    await manager.upsert('t-1', PHONE, WEBHOOK, 'code');

    expect(sockets.map((socket) => socket.linkMethod)).toEqual(['qr', 'code']);
    expect(socketAt(sockets, 0).loggedOut).toBe(false);
    expect((await repository.find('t-1'))?.linkMethod).toBe('code');
  });

  it('ignores a method switch once connected and reconnects with the method it was linked by', async () => {
    const first = build();
    await first.manager.upsert('t-1', PHONE, WEBHOOK, 'code');
    socketAt(first.sockets, 0).credsChanged();
    socketAt(first.sockets, 0).open(PHONE);
    await eventually(() => expect(statesOf('t-1').at(-1)).toBe('connected'));

    await first.manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    expect(first.sockets).toHaveLength(1);
    first.manager.shutdown();

    const second = build();
    await second.manager.resumeAll();
    expect(socketAt(second.sockets, 0).linkMethod).toBe('code');
  });

  it('restarts the socket when WhatsApp requires it after linking', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).close(DisconnectReason.restartRequired);

    await eventually(() => expect(sockets).toHaveLength(2));
    socketAt(sockets, 1).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));
  });

  it('reconnects automatically after the connection drops', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));

    socketAt(sockets, 0).close(DisconnectReason.connectionLost);

    await eventually(() => expect(sockets).toHaveLength(2));
    socketAt(sockets, 1).open(PHONE);
    await eventually(() => expect(statesOf('t-1')).toEqual(['connecting', 'connected', 'disconnected', 'connected']));
  });

  it('marks the session logged out and wipes credentials when unlinked from the phone', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
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
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).close(DisconnectReason.forbidden);

    await eventually(async () => expect(await manager.get('t-1')).toEqual({ state: 'failed', lastError: 'forbidden' }));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(sockets).toHaveLength(1);
  });

  it('stops offering QR codes after the QR timeout', async () => {
    const { manager, sockets } = build({ timing: SHORT_QR });
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).update({ qr: 'qr' });
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('qr_pending'));

    await new Promise((resolve) => setTimeout(resolve, SHORT_QR.qrTimeoutMs + 10));
    socketAt(sockets, 0).close(DisconnectReason.timedOut);

    await eventually(async () => expect(await manager.get('t-1')).toEqual({ state: 'disconnected', lastError: 'qr_expired' }));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(sockets).toHaveLength(1);
  });

  it('resumes linked sessions after an engine restart without a new QR code', async () => {
    const first = build();
    await first.manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    await first.manager.upsert('t-2', OTHER_PHONE, WEBHOOK, 'qr');
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
      await first.manager.upsert(id, PHONE, WEBHOOK, 'qr');
    }
    for (const socket of first.sockets) socket.credsChanged();
    await eventually(async () => expect((await credsCount('t-bad')) + (await credsCount('t-good'))).toBe(2));
    first.manager.shutdown();

    const second = build({ failAuthFor: 't-bad' });
    await second.manager.resumeAll();

    expect(second.sockets).toHaveLength(1);
    expect((await second.manager.get('t-good')).state).toBe('connecting');
  });

  describe('incoming messages', () => {
    const customerMessage = (id: string, message: proto.IMessage): WAMessage => ({
      key: { remoteJid: '919876543210@s.whatsapp.net', fromMe: false, id },
      message,
      messageTimestamp: 1790000000,
      pushName: 'Ravi',
    });
    const storedCount = async () =>
      Number((await pool.query<{ n: string }>("SELECT count(*) AS n FROM wadesk_engine.messages WHERE session_id = 't-1'")).rows[0]?.n);

    const connected = async () => {
      const built = build();
      await built.manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
      socketAt(built.sockets, 0).open(PHONE);
      await eventually(() => expect(statesOf('t-1').at(-1)).toBe('connected'));
      return built;
    };

    it('forwards new customer messages to Chatwoot after the connection event, in order', async () => {
      const { sockets } = await connected();

      socketAt(sockets, 0).receive([customerMessage('M1', { conversation: 'first' }), customerMessage('M2', { conversation: 'second' })]);

      await eventually(() => expect(messageEventsOf('t-1')).toHaveLength(2));
      expect(messageEventsOf('t-1').map(({ event }) => (event.event === 'messages' ? event.messages[0]?.id : undefined))).toEqual(['M1', 'M2']);
      expect(events.findIndex(({ event }) => event.event === 'messages')).toBeGreaterThan(
        events.findIndex(({ event }) => event.event === 'connection' && event.state === 'connected'),
      );
    });

    it('ignores history sync and messages that do not belong in the inbox', async () => {
      const { sockets } = await connected();

      socketAt(sockets, 0).receive([customerMessage('H1', { conversation: 'old' })], 'append');
      socketAt(sockets, 0).receive([{ ...customerMessage('G1', { conversation: 'group' }), key: { remoteJid: '1203@g.us', id: 'G1' } }]);
      socketAt(sockets, 0).receive([customerMessage('M1', { conversation: 'real' })]);

      await eventually(() => expect(messageEventsOf('t-1')).toHaveLength(1));
    });

    it('stores media details encrypted for later download, but not text messages', async () => {
      const { sockets } = await connected();

      socketAt(sockets, 0).receive([
        customerMessage('T1', { conversation: 'text only' }),
        customerMessage('P1', { imageMessage: { mimetype: 'image/jpeg', caption: 'secret caption', mediaKey: Buffer.from('k') } }),
      ]);

      await eventually(() => expect(messageEventsOf('t-1')).toHaveLength(2));
      expect(await storedCount()).toBe(1);
      const { rows } = await pool.query<{ payload: Buffer }>("SELECT payload FROM wadesk_engine.messages WHERE session_id = 't-1'");
      expect(rows[0]?.payload.includes(Buffer.from('secret caption'))).toBe(false);
    });

    it('forwards delivery receipts for the business\'s messages, one status per event', async () => {
      const { sockets } = await connected();

      socketAt(sockets, 0).receipts([
        { key: { remoteJid: '919876543210@s.whatsapp.net', fromMe: true, id: 'OUT1' }, update: { status: 3 } },
        { key: { remoteJid: '919876543210@s.whatsapp.net', fromMe: true, id: 'OUT1' }, update: { status: 4 } },
      ]);

      await eventually(() => expect(events.filter(({ event }) => event.event === 'statuses')).toHaveLength(2));
      expect(events.flatMap(({ event }) => (event.event === 'statuses' ? event.statuses.map((s) => s.status) : []))).toEqual(['delivered', 'read']);
    });

    it('downloads stored media through the connected socket', async () => {
      const { manager, sockets } = await connected();
      socketAt(sockets, 0).receive([customerMessage('P1', { imageMessage: { mimetype: 'image/jpeg' } })]);
      await eventually(async () => expect(await storedCount()).toBe(1));

      const { stream, message } = await manager.downloadMedia('t-1', 'P1');

      expect(Buffer.concat(await stream.toArray()).toString()).toBe('media:P1');
      expect(message.message?.imageMessage?.mimetype).toBe('image/jpeg');
    });

    it('reports unknown or expired media clearly', async () => {
      const { manager, sockets } = await connected();
      socketAt(sockets, 0).receive([customerMessage('P1', { imageMessage: { mimetype: 'image/jpeg' } })]);
      await eventually(async () => expect(await storedCount()).toBe(1));

      await expect(manager.downloadMedia('t-1', 'NOPE')).rejects.toThrow(MediaNotFoundError);
      socketAt(sockets, 0).failDownloads = true;
      await expect(manager.downloadMedia('t-1', 'P1')).rejects.toThrow(MediaUnavailableError);
    });
  });

  describe('sending', () => {
    const linked = async (timing: SessionTiming = FAST) => {
      const built = build({ timing });
      await built.manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
      socketAt(built.sockets, 0).open(PHONE);
      await eventually(() => expect(statesOf('t-1').at(-1)).toBe('connected'));
      return built;
    };

    it('sends a text and returns WhatsApp\'s message id', async () => {
      const { manager, sockets } = await linked();

      expect(await manager.send('t-1', { to: '919876543210', text: 'Price is ₹45,000' })).toBe('SENT1');
      expect(socketAt(sockets, 0).sent).toEqual([{ jid: '919876543210@s.whatsapp.net', content: { text: 'Price is ₹45,000' }, options: {} }]);
    });

    it('quotes the message being answered', async () => {
      const { manager, sockets } = await linked();

      await manager.send('t-1', { to: '123456789012345@lid', text: 'Yes', replyTo: { id: 'IN1', text: 'Brown?', fromMe: false } });

      expect(socketAt(sockets, 0).sent[0]?.options).toEqual({
        quoted: { key: { remoteJid: '123456789012345@lid', id: 'IN1', fromMe: false }, message: { conversation: 'Brown?' } },
      });
    });

    it('refuses to send while not connected', async () => {
      const { manager } = build();
      await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');

      await expect(manager.send('t-1', { to: '919876543210', text: 'hi' })).rejects.toThrow(SessionNotConnectedError);
    });

    it('limits sends per minute per number and reports when to retry', async () => {
      const { manager, sockets } = await linked({ ...FAST, sendsPerMinute: 2 });
      await manager.send('t-1', { to: '919876543210', text: '1' });
      await manager.send('t-1', { to: '919876543210', text: '2' });

      const error = await manager.send('t-1', { to: '919876543210', text: '3' }).catch((caught: unknown) => caught);

      expect(error).toBeInstanceOf(RateLimitedError);
      expect((error as RateLimitedError).retryAfterMs).toBeGreaterThan(55_000);
      expect(socketAt(sockets, 0).sent).toHaveLength(2);
    });
  });

  it('is idempotent while the same number is live', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    await manager.upsert('t-1', PHONE, 'http://new-webhook', 'qr');

    expect(sockets).toHaveLength(1);
    expect((await repository.find('t-1'))?.webhookUrl).toBe('http://new-webhook');
  });

  it('reconnects a dropped session with its stored credentials instead of unlinking it', async () => {
    const { manager, sockets } = build({ timing: SHORT_QR });
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).update({ qr: 'qr' });
    await new Promise((resolve) => setTimeout(resolve, SHORT_QR.qrTimeoutMs + 10));
    socketAt(sockets, 0).close(DisconnectReason.timedOut);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('disconnected'));

    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');

    expect(socketAt(sockets, 0).loggedOut).toBe(false);
    expect(sockets).toHaveLength(2);
  });

  it('unlinks the old device when the number changes', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).credsChanged();
    socketAt(sockets, 0).open(PHONE);
    await eventually(async () => expect((await manager.get('t-1')).state).toBe('connected'));

    await manager.upsert('t-1', OTHER_PHONE, WEBHOOK, 'qr');

    expect(socketAt(sockets, 0).loggedOut).toBe(true);
    expect((await repository.find('t-1'))?.expectedPhone).toBe(OTHER_PHONE);
    expect(await credsCount('t-1')).toBe(0);
  });

  it('removes a session, logging it out and deleting its credentials', async () => {
    const { manager, sockets } = build();
    await manager.upsert('t-1', PHONE, WEBHOOK, 'qr');
    socketAt(sockets, 0).credsChanged();
    await eventually(async () => expect(await credsCount('t-1')).toBe(1));

    await manager.remove('t-1');

    expect(socketAt(sockets, 0).loggedOut).toBe(true);
    expect(await credsCount('t-1')).toBe(0);
    await expect(manager.get('t-1')).rejects.toThrow(SessionNotFoundError);
    await expect(manager.remove('t-1')).rejects.toThrow(SessionNotFoundError);
  });
});
