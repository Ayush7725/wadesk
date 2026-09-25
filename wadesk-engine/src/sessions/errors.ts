export class SessionNotFoundError extends Error {
  readonly code = 'session_not_found';
  constructor(id: string) {
    super(`Session ${id} not found`);
    this.name = 'SessionNotFoundError';
  }
}

export class MediaNotFoundError extends Error {
  readonly code = 'media_not_found';
  constructor(messageId: string) {
    super(`No media stored for message ${messageId}`);
    this.name = 'MediaNotFoundError';
  }
}

export class MediaUnavailableError extends Error {
  readonly code = 'media_unavailable';
  constructor(messageId: string, cause: unknown) {
    super(`Media for message ${messageId} could not be downloaded from WhatsApp`, { cause });
    this.name = 'MediaUnavailableError';
  }
}

export class SessionNotConnectedError extends Error {
  readonly code = 'not_connected';
  constructor(id: string) {
    super(`Session ${id} is not connected to WhatsApp`);
    this.name = 'SessionNotConnectedError';
  }
}

export class RateLimitedError extends Error {
  readonly code = 'rate_limited';
  constructor(readonly retryAfterMs: number) {
    super(`Sending limit reached for this number; retry in ${String(Math.ceil(retryAfterMs / 1000))} s`);
    this.name = 'RateLimitedError';
  }
}
