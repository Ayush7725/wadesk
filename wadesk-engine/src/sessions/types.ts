// How the admin links the number: scan a QR code, or type a pairing code on the phone (for phone-only owners).
import type { MessagesEvent } from '../whatsapp/normalizer.js';

export type LinkMethod = 'qr' | 'code';

export type SessionState = 'connecting' | 'qr_pending' | 'connected' | 'disconnected' | 'logged_out' | 'failed';

export interface SessionRecord {
  id: string;
  expectedPhone: string;
  webhookUrl: string;
  linkMethod: LinkMethod;
  state: SessionState;
  meJid: string | null;
  meLid: string | null;
  lastError: string | null;
}

// Connection events for Chatwoot (delivered through the outbox in M1.5).
export interface ConnectionEvent {
  event: 'connection';
  state: SessionState;
  me?: { phone: string };
  reason?: string;
}

// Everything the engine sends to Chatwoot.
export type EngineEvent = ConnectionEvent | MessagesEvent;

export interface EventSink {
  emit(sessionId: string, event: EngineEvent): Promise<void>;
}
