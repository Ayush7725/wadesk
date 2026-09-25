import { pino } from 'pino';
import { buildApp } from './app.js';
import { createCipher } from './auth/cipher.js';
import { usePostgresAuthState } from './auth/postgres-auth-state.js';
import { loadConfig } from './config.js';
import { migrate } from './db/migrate.js';
import { MessageStore } from './messages/store.js';
import { DEFAULT_DISPATCHER_OPTIONS, Dispatcher } from './outbox/dispatcher.js';
import { OutboxSink } from './outbox/outbox.js';
import { createPool } from './db/pool.js';
import { SessionManager } from './sessions/manager.js';
import { SessionRepository } from './sessions/repository.js';
import { DEFAULT_TIMING } from './sessions/session.js';
import { createBaileysSocket } from './whatsapp/socket.js';

const config = loadConfig();
const logger = pino({
  level: config.logLevel,
  // Never log message content, credentials or tokens (WW-NFR-07).
  redact: ['req.headers.authorization', 'req.body', 'res.body'],
});
const pool = createPool(config.databaseUrl);
const cipher = createCipher(config.encryptionKey);

await migrate(config.databaseUrl, (message) => {
  logger.info({ migration: message.trim() });
});

const repository = new SessionRepository(pool);
const messages = new MessageStore(pool, cipher);
const dispatcher = new Dispatcher(pool, { ...DEFAULT_DISPATCHER_OPTIONS, secret: config.webhookSecret }, logger.child({ component: 'outbox' }));

const sessions = new SessionManager({
  repository,
  createAuthState: (id) => usePostgresAuthState(pool, id, cipher),
  createSocket: createBaileysSocket,
  events: new OutboxSink(pool, repository, () => {
    dispatcher.kick();
  }),
  // Baileys is verbose below "warn"; it also receives this logger.
  messages,
  logger: logger.child({ component: 'sessions' }, { level: 'warn' }),
  timing: DEFAULT_TIMING,
});

const app = buildApp({ pool, sessions, apiToken: config.apiToken }, { loggerInstance: logger });

// Media metadata is only kept for the retention window.
const pruneTimer = setInterval(() => {
  messages.prune().catch((error: unknown) => logger.error({ err: error }, 'pruning message metadata failed'));
}, 60 * 60_000);

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    clearInterval(pruneTimer);
    sessions.shutdown();
    void dispatcher
      .stop()
      .then(() => app.close())
      .then(() => pool.end())
      .then(() => process.exit(0));
  });
}

dispatcher.start();
await sessions.resumeAll();
await app.listen({ port: config.port, host: config.host });
