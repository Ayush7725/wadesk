import { buildApp } from './app.js';
import { loadConfig } from './config.js';

const config = loadConfig();
const app = buildApp({
  logger: {
    level: config.logLevel,
    // Never log message content, credentials or tokens (WW-NFR-07).
    redact: ['req.headers.authorization', 'req.body', 'res.body'],
  },
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    void app.close().then(() => process.exit(0));
  });
}

await app.listen({ port: config.port, host: config.host });
