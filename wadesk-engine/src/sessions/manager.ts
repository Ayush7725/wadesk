import { SessionNotFoundError } from './errors.js';
import { Session, type SessionDeps, type SessionSnapshot } from './session.js';
import type { LinkMethod, SessionRecord } from './types.js';

const LIVE_STATES = new Set(['connecting', 'qr_pending', 'connected']);

// Owns all sessions of this engine instance. Failures stay inside their session (WW-NFR-06).
export class SessionManager {
  private readonly sessions = new Map<string, Session>();

  constructor(private readonly deps: SessionDeps) {}

  // Resumes every session that has credentials and was not deliberately ended (WW-NFR-01).
  async resumeAll(): Promise<void> {
    for (const record of await this.deps.repository.listResumable()) {
      await this.launch(record).catch((error: unknown) =>
        this.deps.logger.error({ err: error, sessionId: record.id }, 'resume failed'),
      );
    }
  }

  // Creates or restarts a session. Idempotent while the same number is live with the same link method,
  // and while connected (the link method only matters until the number is linked) (WW-FR-01/03/06).
  async upsert(id: string, expectedPhone: string, webhookUrl: string, linkMethod: LinkMethod): Promise<SessionSnapshot> {
    const running = this.sessions.get(id);
    if (
      running &&
      running.expectedPhone === expectedPhone &&
      LIVE_STATES.has(running.currentState) &&
      (running.linkMethod === linkMethod || running.currentState === 'connected')
    ) {
      await this.deps.repository.upsert(id, expectedPhone, webhookUrl, running.linkMethod);
      return running.snapshot();
    }

    if (running) {
      // Same number: reconnect with the stored credentials. New number: unlink the old device first.
      if (running.expectedPhone === expectedPhone) running.stop();
      else await running.logout();
      this.sessions.delete(id);
    }
    const existing = await this.deps.repository.find(id);
    if (existing && existing.expectedPhone !== expectedPhone) {
      await this.deps.repository.delete(id); // credentials belong to the old number
    }
    const record = await this.deps.repository.upsert(id, expectedPhone, webhookUrl, linkMethod);
    return (await this.launch(record)).snapshot();
  }

  async get(id: string): Promise<SessionSnapshot> {
    const running = this.sessions.get(id);
    if (running) return running.snapshot();

    const record = await this.deps.repository.find(id);
    if (!record) throw new SessionNotFoundError(id);
    return { state: record.state, ...(record.lastError ? { lastError: record.lastError } : {}) };
  }

  async downloadMedia(id: string, messageId: string) {
    const running = this.sessions.get(id);
    if (!running) throw new SessionNotFoundError(id);
    return running.downloadMedia(messageId);
  }

  // Logs out and wipes the session and its credentials (WW-FR-07).
  async remove(id: string): Promise<void> {
    const running = this.sessions.get(id);
    if (running) {
      await running.logout();
      this.sessions.delete(id);
    } else if (!(await this.deps.repository.find(id))) {
      throw new SessionNotFoundError(id);
    }
    await this.deps.repository.delete(id);
  }

  shutdown(): void {
    for (const session of this.sessions.values()) session.stop();
    this.sessions.clear();
  }

  private async launch(record: SessionRecord): Promise<Session> {
    const session = new Session(record, this.deps);
    this.sessions.set(record.id, session);
    await session.start();
    return session;
  }
}
