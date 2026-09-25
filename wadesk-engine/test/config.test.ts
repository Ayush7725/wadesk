import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const DATABASE_URL = 'postgres://user@db:5432/engine';

describe('loadConfig', () => {
  it('requires a database URL', () => {
    expect(() => loadConfig({})).toThrow('WADESK_ENGINE_DATABASE_URL is required');
  });

  it('uses defaults for optional values', () => {
    expect(loadConfig({ WADESK_ENGINE_DATABASE_URL: DATABASE_URL })).toEqual({
      port: 4000,
      host: '0.0.0.0',
      logLevel: 'info',
      databaseUrl: DATABASE_URL,
    });
  });

  it('reads the environment', () => {
    const config = loadConfig({
      WADESK_ENGINE_DATABASE_URL: DATABASE_URL,
      WADESK_ENGINE_PORT: '4100',
      WADESK_ENGINE_HOST: '127.0.0.1',
      WADESK_ENGINE_LOG_LEVEL: 'debug',
    });

    expect(config).toEqual({ port: 4100, host: '127.0.0.1', logLevel: 'debug', databaseUrl: DATABASE_URL });
  });
});
