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
