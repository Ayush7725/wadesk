export type SessionState = 'connecting' | 'qr_pending' | 'connected' | 'disconnected' | 'logged_out' | 'failed';

export interface SessionRecord {
  id: string;
  expectedPhone: string;
  webhookUrl: string;
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

export interface EventSink {
  emit(sessionId: string, event: ConnectionEvent): Promise<void>;
}
