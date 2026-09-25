import type { Logger } from 'pino';

type Method = 'log' | 'info' | 'debug' | 'trace' | 'warn' | 'error';
const LEVELS: Record<Method, 'debug' | 'warn' | 'error'> = {
  log: 'debug',
  info: 'debug',
  debug: 'debug',
  trace: 'debug',
  warn: 'warn',
  error: 'error',
};

// Libraries (notably libsignal, used by Baileys) write straight to the console and pass whole Signal
// session records - including private keys - as extra arguments. Route console output through the
// logger, keeping only text and numbers, so key material can never reach the logs (WW-NFR-07).
export function guardConsole(logger: Logger): void {
  const library = logger.child({ component: 'library' });
  for (const [method, level] of Object.entries(LEVELS) as [Method, (typeof LEVELS)[Method]][]) {
    console[method] = (...args: unknown[]) => {
      const text = args.filter((arg) => typeof arg === 'string' || typeof arg === 'number').join(' ');
      if (text) library[level](text);
    };
  }
}
