import type { Logger } from 'pino';
import type { EventSink } from './types.js';

// Records connection events in the log only. Replaced by the outbox dispatcher in M1.5.
export const logSink = (logger: Logger): EventSink => ({
  emit: (sessionId, event) => {
    logger.info({ sessionId, state: event.state, reason: event.reason }, 'connection event');
    return Promise.resolve();
  },
});
