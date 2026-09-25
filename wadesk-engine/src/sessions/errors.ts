export class SessionNotFoundError extends Error {
  readonly code = 'session_not_found';
  constructor(id: string) {
    super(`Session ${id} not found`);
    this.name = 'SessionNotFoundError';
  }
}
