import { pino, type DestinationStream, type Logger } from 'pino';
import { isBenignLibraryNoise, maskDigits, maskRecord } from './redact.js';

// The engine's logger: no message content, credentials or tokens (WW-NFR-07), phone numbers masked,
// and known-benign library noise dropped.
export function createLogger(level: string, destination?: DestinationStream): Logger {
  return pino(
    {
      level,
      redact: ['req.headers.authorization', 'req.body', 'res.body'],
      formatters: { log: (record) => maskRecord(record) as Record<string, unknown> },
      hooks: {
        logMethod(args, method) {
          if (isBenignLibraryNoise(args)) return;
          method.apply(this, args.map((arg) => (typeof arg === 'string' ? maskDigits(arg) : arg)) as Parameters<typeof method>);
        },
      },
    },
    destination,
  );
}
