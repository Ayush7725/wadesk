export class SessionNotFoundError extends Error {
  readonly code = 'session_not_found';
  constructor(id: string) {
    super(`Session ${id} not found`);
    this.name = 'SessionNotFoundError';
  }
}

export class SessionStateError extends Error {
  constructor(
    readonly code: 'not_pending' | 'not_connected',
    message: string,
  ) {
    super(message);
    this.name = 'SessionStateError';
  }
}
