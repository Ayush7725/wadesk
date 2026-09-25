import { DisconnectReason, jidDecode, type ConnectionState } from 'baileys';
import type { Logger } from 'pino';
import type { PostgresAuthState } from '../auth/postgres-auth-state.js';
import type { SocketFactory, WaSocket } from '../whatsapp/socket.js';
import { SessionStateError } from './errors.js';
import type { SessionRepository } from './repository.js';
import type { ConnectionEvent, EventSink, SessionRecord, SessionState } from './types.js';

export interface SessionTiming {
  baseBackoffMs: number;
  maxBackoffMs: number; // keeps reconnects within WW-NFR-02's 60 s
  qrTimeoutMs: number; // stop offering QR codes nobody scans
}

export const DEFAULT_TIMING: SessionTiming = { baseBackoffMs: 1_000, maxBackoffMs: 30_000, qrTimeoutMs: 10 * 60_000 };

export interface SessionDeps {
  repository: SessionRepository;
  createAuthState: (sessionId: string) => Promise<PostgresAuthState>;
  createSocket: SocketFactory;
  events: EventSink;
  logger: Logger;
  timing: SessionTiming;
}

export interface SessionSnapshot {
  state: SessionState;
  qr?: string;
  me?: { phone: string };
  lastError?: string;
}

const statusCode = (error: unknown): number | undefined =>
  (error as { output?: { statusCode?: number } } | undefined)?.output?.statusCode;

// One WhatsApp Web connection. Owns reconnects and the expected-number check (WW-FR-04/05/08, WW-NFR-02).
export class Session {
  private state: SessionState;
  private socket: WaSocket | undefined;
  private auth: PostgresAuthState | undefined;
  private qr: string | undefined;
  private qrDeadline: number | undefined;
  private attempts = 0;
  private credsSaving: Promise<void> = Promise.resolve();
  private reconnectTimer: NodeJS.Timeout | undefined;
  private stopped = false;
  private mePhone: string | undefined;
  private lastError: string | undefined;

  constructor(
    private readonly record: SessionRecord,
    private readonly deps: SessionDeps,
  ) {
    this.state = record.state;
    this.mePhone = record.meJid ? jidDecode(record.meJid)?.user : undefined;
  }

  get id(): string {
    return this.record.id;
  }

  get expectedPhone(): string {
    return this.record.expectedPhone;
  }

  get currentState(): SessionState {
    return this.state;
  }

  snapshot(): SessionSnapshot {
    return {
      state: this.state,
      ...(this.state === 'qr_pending' && this.qr ? { qr: this.qr } : {}),
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

  async requestPairingCode(): Promise<string> {
    if (this.state !== 'qr_pending' || !this.socket) {
      throw new SessionStateError('not_pending', 'A pairing code can only be requested while the session is waiting to be linked');
    }
    return this.socket.requestPairingCode(this.record.expectedPhone);
  }

  // Unlinks the device from the phone. Credentials are removed with the session row by the manager.
  async logout(): Promise<void> {
    const socket = this.halt();
    if (socket) await socket.logout().catch((error: unknown) => this.deps.logger.warn({ err: error }, 'logout failed'));
    socket?.end();
    await this.credsSaving;
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
    const socket = this.deps.createSocket(auth.state, this.deps.logger);
    this.socket = socket;

    // Saves run one at a time and stop once the socket is gone, so a late save can never
    // bring back credentials that were just wiped.
    socket.onCredsUpdate(() => {
      this.credsSaving = this.credsSaving
        .then(() => (socket === this.socket ? auth.saveCreds() : undefined))
        .catch((error: unknown) => this.deps.logger.error({ err: error }, 'saving credentials failed'));
    });
    socket.onConnectionUpdate((update) => {
      this.handleUpdate(socket, update).catch((error: unknown) => this.deps.logger.error({ err: error }, 'connection update failed'));
    });
  }

  private async handleUpdate(socket: WaSocket, update: Partial<ConnectionState>): Promise<void> {
    if (socket !== this.socket) return; // late event from a replaced socket

    if (update.qr) {
      this.qr = update.qr;
      this.qrDeadline ??= Date.now() + this.deps.timing.qrTimeoutMs;
      await this.transition('qr_pending');
    }
    if (update.connection === 'open') await this.onOpen(socket);
    if (update.connection === 'close') await this.onClose(statusCode(update.lastDisconnect?.error));
  }

  private async onOpen(socket: WaSocket): Promise<void> {
    const phone = jidDecode(socket.user?.id)?.user;
    this.qr = undefined;
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

    if (code === DisconnectReason.loggedOut) {
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
      await this.transition('disconnected', { reason: 'qr_expired', lastError: 'qr_expired' });
      return;
    }

    if (this.state === 'connected') await this.transition('disconnected', { reason: 'connection_lost' });
    const delay = Math.min(this.deps.timing.baseBackoffMs * 2 ** this.attempts, this.deps.timing.maxBackoffMs);
    this.attempts += 1;
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
