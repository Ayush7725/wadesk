import {
  DisconnectReason,
  generateMessageIDV2,
  jidDecode,
  type ConnectionState,
  type MessageUpsertType,
  type WAMessage,
  type WAMessageUpdate,
} from 'baileys';
import type { Readable } from 'node:stream';
import type { Logger } from 'pino';
import type { PostgresAuthState } from '../auth/postgres-auth-state.js';
import type { MessageStore } from '../messages/store.js';
import { normalizeEcho, normalizeIncoming, normalizeStatus } from '../whatsapp/normalizer.js';
import { messageContent, quotedMessage, recipientJid, type OutgoingMessage } from '../whatsapp/outgoing.js';
import { MediaNotFoundError, MediaUnavailableError, RateLimitedError, SessionNotConnectedError } from './errors.js';
import { RateLimiter } from './rate-limiter.js';
import type { SocketFactory, WaSocket } from '../whatsapp/socket.js';
import type { SessionRepository } from './repository.js';
import type { ConnectionEvent, EventSink, LinkMethod, SessionRecord, SessionState } from './types.js';

export interface SessionTiming {
  baseBackoffMs: number;
  maxBackoffMs: number; // keeps reconnects within WW-NFR-02's 60 s
  qrTimeoutMs: number; // stop offering QR codes nobody scans
  sendsPerMinute: number; // SAFE-FR-03
}

export const DEFAULT_TIMING: SessionTiming = { baseBackoffMs: 1_000, maxBackoffMs: 30_000, qrTimeoutMs: 10 * 60_000, sendsPerMinute: 20 };

export interface SessionDeps {
  repository: SessionRepository;
  createAuthState: (sessionId: string) => Promise<PostgresAuthState>;
  createSocket: SocketFactory;
  events: EventSink;
  messages: MessageStore;
  logger: Logger;
  timing: SessionTiming;
}

export interface SessionSnapshot {
  state: SessionState;
  qr?: string;
  pairingCode?: string;
  me?: { phone: string };
  lastError?: string;
}

const MEDIA_TYPES = new Set(['image', 'video', 'audio', 'document', 'sticker']);
// How long WaDesk remembers ids it sent, to skip their echoes from WhatsApp.
const SENT_ID_TTL_MS = 10 * 60_000;

const statusCode = (error: unknown): number | undefined =>
  (error as { output?: { statusCode?: number } } | undefined)?.output?.statusCode;

// One WhatsApp Web connection. Owns reconnects and the expected-number check (WW-FR-04/05/08, WW-NFR-02).
export class Session {
  private state: SessionState;
  private socket: WaSocket | undefined;
  private auth: PostgresAuthState | undefined;
  private qr: string | undefined;
  private pairingCode: string | undefined;
  private qrDeadline: number | undefined;
  private attempts = 0;
  private credsSaving: Promise<void> = Promise.resolve();
  private updates: Promise<void> = Promise.resolve();
  private readonly limiter: RateLimiter;
  private readonly sentIds = new Map<string, number>();
  private reconnectTimer: NodeJS.Timeout | undefined;
  private stopped = false;
  private mePhone: string | undefined;
  private lastError: string | undefined;

  constructor(
    private readonly record: SessionRecord,
    private readonly deps: SessionDeps,
  ) {
    this.state = record.state;
    this.limiter = new RateLimiter(deps.timing.sendsPerMinute);
    this.mePhone = record.meJid ? jidDecode(record.meJid)?.user : undefined;
  }

  get id(): string {
    return this.record.id;
  }

  get expectedPhone(): string {
    return this.record.expectedPhone;
  }

  get linkMethod(): LinkMethod {
    return this.record.linkMethod;
  }

  get currentState(): SessionState {
    return this.state;
  }

  snapshot(): SessionSnapshot {
    return {
      state: this.state,
      ...(this.state === 'qr_pending' && this.record.linkMethod === 'qr' && this.qr ? { qr: this.qr } : {}),
      ...(this.state === 'qr_pending' && this.pairingCode ? { pairingCode: this.pairingCode } : {}),
      ...(this.mePhone ? { me: { phone: this.mePhone } } : {}),
      ...(this.lastError ? { lastError: this.lastError } : {}),
    };
  }

  async start(): Promise<void> {
    this.stopped = false;
    this.lastError = undefined;
    await this.transition('connecting');
    await this.connect();
  }

  // Unlinks the device from the phone. Credentials are removed with the session row by the manager.
  async logout(): Promise<void> {
    const socket = this.halt();
    if (socket) await socket.logout().catch((error: unknown) => this.deps.logger.warn({ err: error }, 'logout failed'));
    socket?.end();
    await this.credsSaving;
  }

  // Abandons a linking attempt that was never completed. Nothing is linked yet, so its half-registered credentials
  // (e.g. from a requested pairing code) are dropped; reusing them makes WhatsApp answer 401 as if unlinked.
  async cancelLinking(): Promise<void> {
    this.halt()?.end();
    await this.forgetCredentials();
  }

  // Closes the connection without changing state (engine shutdown); the session resumes on next boot.
  stop(): void {
    this.halt()?.end();
  }

  private halt(): WaSocket | undefined {
    this.stopped = true;
    clearTimeout(this.reconnectTimer);
    const socket = this.socket;
    this.socket = undefined;
    return socket;
  }

  private async connect(): Promise<void> {
    const auth = await this.deps.createAuthState(this.id);
    if (this.stopped) return;
    this.auth = auth;
    const socket = this.deps.createSocket(auth.state, this.deps.logger, this.record.linkMethod);
    this.socket = socket;
    this.pairingCode = undefined; // a pairing code is only valid on the connection that requested it

    // Saves run one at a time and stop once the socket is gone, so a late save can never
    // bring back credentials that were just wiped.
    socket.onCredsUpdate(() => {
      this.credsSaving = this.credsSaving
        .then(() => (socket === this.socket ? auth.saveCreds() : undefined))
        .catch((error: unknown) => this.deps.logger.error({ err: error }, 'saving credentials failed'));
    });
    // Updates are handled strictly one at a time, in arrival order, so stored state and emitted
    // events can never be reordered (e.g. "connected" landing after "disconnected", or a message
    // overtaking the connection event before it).
    socket.onConnectionUpdate((update) => {
      this.enqueue(() => this.handleUpdate(socket, update), 'connection update failed');
    });
    socket.onMessagesUpsert((messages, type) => {
      this.enqueue(() => this.handleMessages(socket, messages, type), 'incoming messages failed');
    });
    socket.onMessagesUpdate((updates) => {
      this.enqueue(() => this.handleStatuses(socket, updates), 'message status updates failed');
    });
  }

  // Sends a text or one file (optionally quoting a message) and returns WhatsApp's message id (WW-FR-20/21/22).
  async send(outgoing: OutgoingMessage): Promise<string> {
    const jid = recipientJid(outgoing.to);
    if (this.state !== 'connected' || !this.socket) throw new SessionNotConnectedError(this.id);
    const wait = this.limiter.take();
    if (wait > 0) throw new RateLimitedError(wait);

    // The id is chosen before sending, so the echo WhatsApp sends back for it is recognised and skipped.
    const messageId = generateMessageIDV2(this.socket.user?.id);
    this.rememberSent(messageId);
    const sent = await this.socket.sendMessage(jid, messageContent(outgoing), {
      messageId,
      ...(outgoing.replyTo ? { quoted: quotedMessage(jid, outgoing.replyTo) } : {}),
    });
    return sent?.key.id ?? messageId;
  }

  // Streams a stored incoming message's media (served to Chatwoot for attachments).
  async downloadMedia(messageId: string): Promise<{ stream: Readable; message: WAMessage }> {
    const message = await this.deps.messages.find(this.id, messageId);
    if (!message) throw new MediaNotFoundError(messageId);
    if (!this.socket) throw new MediaUnavailableError(messageId, new Error('session is not connected'));
    try {
      return { stream: await this.socket.downloadMedia(message), message };
    } catch (error) {
      throw new MediaUnavailableError(messageId, error);
    }
  }

  private enqueue(work: () => Promise<void>, failure: string): void {
    this.updates = this.updates.then(work).catch((error: unknown) => this.deps.logger.error({ err: error }, failure));
  }

  // New customer messages ("notify"; "append" is history/own-device sync) go to Chatwoot in order.
  private async handleMessages(socket: WaSocket, messages: WAMessage[], type: MessageUpsertType): Promise<void> {
    if (socket !== this.socket || type !== 'notify') return;

    for (const message of messages) {
      const event = message.key.fromMe ? this.echoFor(message) : normalizeIncoming(message);
      if (!event) continue;
      const type = ('messages' in event ? event.messages[0] : event.message_echoes[0])?.type ?? '';
      if (MEDIA_TYPES.has(type)) await this.deps.messages.save(this.id, message);
      await this.deps.events.emit(this.id, event);
    }
  }

  // Messages the business sent from its phone become echoes (WW-FR-16); messages WaDesk sent are skipped.
  private echoFor(message: WAMessage) {
    if (!this.mePhone || this.sentIds.has(message.key.id ?? '')) return undefined;
    return normalizeEcho(message, this.mePhone);
  }

  private rememberSent(id: string): void {
    const now = Date.now();
    for (const [sentId, at] of this.sentIds) {
      if (now - at < SENT_ID_TTL_MS) break; // insertion order = time order
      this.sentIds.delete(sentId);
    }
    this.sentIds.set(id, now);
  }

  // Delivery receipts for messages the business sent: sent → delivered → read, or failed (WW-FR-23).
  private async handleStatuses(socket: WaSocket, updates: WAMessageUpdate[]): Promise<void> {
    if (socket !== this.socket) return;

    for (const update of updates) {
      const event = normalizeStatus(update);
      if (event) await this.deps.events.emit(this.id, event);
    }
  }

  private async handleUpdate(socket: WaSocket, update: Partial<ConnectionState>): Promise<void> {
    if (socket !== this.socket) return; // late event from a replaced socket

    if (update.qr) {
      this.qr = update.qr;
      this.qrDeadline ??= Date.now() + this.deps.timing.qrTimeoutMs;
      // Code mode: one code per connection, requested automatically so the admin always sees a valid one.
      if (this.record.linkMethod === 'code' && !this.pairingCode) {
        this.pairingCode = await socket.requestPairingCode(this.record.expectedPhone);
      }
      await this.transition('qr_pending');
    }
    if (update.connection === 'open') await this.onOpen(socket);
    if (update.connection === 'close') await this.onClose(statusCode(update.lastDisconnect?.error));
  }

  private async onOpen(socket: WaSocket): Promise<void> {
    const phone = jidDecode(socket.user?.id)?.user;
    this.qr = undefined;
    this.pairingCode = undefined;
    this.qrDeadline = undefined;

    if (phone !== this.record.expectedPhone) {
      // Wrong phone scanned the QR code: unlink it and forget its credentials (WW-FR-04).
      this.halt();
      await socket.logout().catch(() => undefined);
      socket.end();
      await this.forgetCredentials();
      this.mePhone = undefined;
      await this.transition('failed', { reason: 'number_mismatch', lastError: 'number_mismatch' });
      return;
    }

    this.attempts = 0;
    this.mePhone = phone;
    await this.transition('connected', { meJid: socket.user?.id ?? null, meLid: socket.user?.lid ?? null });
  }

  private async onClose(code: number | undefined): Promise<void> {
    this.socket = undefined;
    if (this.stopped) return;

    if (code === DisconnectReason.loggedOut && this.state === 'qr_pending') {
      // Never linked, so nothing was unlinked: WhatsApp closes an expired pairing-code attempt with 401.
      // Drop the half-registered credentials and retry below with a fresh connection (and code).
      await this.forgetCredentials();
    } else if (code === DisconnectReason.loggedOut) {
      this.stopped = true;
      await this.forgetCredentials();
      await this.transition('logged_out', { reason: 'unlinked_from_phone', lastError: 'unlinked_from_phone' });
      return;
    }
    if (code === DisconnectReason.forbidden) {
      this.stopped = true;
      await this.transition('failed', { reason: 'forbidden', lastError: 'forbidden' });
      return;
    }
    if (code === DisconnectReason.restartRequired) {
      await this.connect(); // expected right after a successful QR scan
      return;
    }
    if (this.qrDeadline !== undefined && Date.now() >= this.qrDeadline) {
      this.stopped = true;
      this.qrDeadline = undefined;
      await this.forgetCredentials(); // never linked: the next attempt must start clean
      await this.transition('disconnected', { reason: 'qr_expired', lastError: 'qr_expired' });
      return;
    }

    if (this.state === 'connected') await this.transition('disconnected', { reason: 'connection_lost' });
    // While waiting to be linked, WhatsApp routinely ends QR/code attempts: reconnect promptly with a fresh one.
    // Real connection failures back off exponentially.
    const waitingToLink = this.state === 'qr_pending';
    const delay = waitingToLink
      ? this.deps.timing.baseBackoffMs
      : Math.min(this.deps.timing.baseBackoffMs * 2 ** this.attempts, this.deps.timing.maxBackoffMs);
    if (!waitingToLink) this.attempts += 1;
    this.reconnectTimer = setTimeout(() => {
      this.connect().catch((error: unknown) => this.deps.logger.error({ err: error }, 'reconnect failed'));
    }, delay);
  }

  private async forgetCredentials(): Promise<void> {
    await this.credsSaving;
    await this.auth?.clear();
  }

  private async transition(
    state: SessionState,
    options: { reason?: string; lastError?: string; meJid?: string | null; meLid?: string | null } = {},
  ): Promise<void> {
    if (state === this.state && options.reason === undefined) return;
    this.state = state;
    this.lastError = options.lastError;
    await this.deps.repository.update(this.id, {
      state,
      lastError: options.lastError ?? null,
      ...('meJid' in options ? { meJid: options.meJid ?? null } : {}),
      ...('meLid' in options ? { meLid: options.meLid ?? null } : {}),
    });

    const event: ConnectionEvent = {
      event: 'connection',
      state,
      ...(this.mePhone ? { me: { phone: this.mePhone } } : {}),
      ...(options.reason ? { reason: options.reason } : {}),
    };
    await this.deps.events.emit(this.id, event);
  }
}
