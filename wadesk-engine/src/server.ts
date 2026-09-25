import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { migrate } from './db/migrate.js';
import { createPool } from './db/pool.js';

const config = loadConfig();
const pool = createPool(config.databaseUrl);
const app = buildApp(
  { pool },
  {
    logger: {
      level: config.logLevel,
      // Never log message content, credentials or tokens (WW-NFR-07).
      redact: ['req.headers.authorization', 'req.body', 'res.body'],
    },
  },
);

await migrate(config.databaseUrl, (message) => {
  app.log.info({ migration: message.trim() });
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    void app
      .close()
      .then(() => pool.end())
      .then(() => process.exit(0));
  });
}

await app.listen({ port: config.port, host: config.host });
