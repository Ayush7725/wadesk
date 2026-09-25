import { pino } from 'pino';
import { buildApp } from './app.js';
import { createCipher } from './auth/cipher.js';
import { usePostgresAuthState } from './auth/postgres-auth-state.js';
import { loadConfig } from './config.js';
import { migrate } from './db/migrate.js';
import { createPool } from './db/pool.js';
import { logSink } from './sessions/log-sink.js';
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

const sessions = new SessionManager({
  repository: new SessionRepository(pool),
  createAuthState: (id) => usePostgresAuthState(pool, id, cipher),
  createSocket: createBaileysSocket,
  events: logSink(logger),
  // Baileys is verbose below "warn"; it also receives this logger.
  logger: logger.child({ component: 'sessions' }, { level: 'warn' }),
  timing: DEFAULT_TIMING,
});

const app = buildApp({ pool, sessions, apiToken: config.apiToken }, { loggerInstance: logger });

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    sessions.shutdown();
    void app
      .close()
      .then(() => pool.end())
      .then(() => process.exit(0));
  });
}

await sessions.resumeAll();
await app.listen({ port: config.port, host: config.host });
