import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const REQUIRED = {
  WADESK_ENGINE_DATABASE_URL: 'postgres://user@db:5432/engine',
  WADESK_ENGINE_API_TOKEN: 'a'.repeat(32),
  WADESK_ENGINE_ENCRYPTION_KEY: 'key',
};

describe('loadConfig', () => {
  it.each(Object.keys(REQUIRED))('requires %s', (name) => {
    expect(() => loadConfig({ ...REQUIRED, [name]: undefined })).toThrow(`${name} is required`);
  });

  it('rejects short API tokens', () => {
    expect(() => loadConfig({ ...REQUIRED, WADESK_ENGINE_API_TOKEN: 'short' })).toThrow('at least 32 characters');
  });

  it('uses defaults for optional values', () => {
    expect(loadConfig(REQUIRED)).toEqual({
      port: 4000,
      host: '0.0.0.0',
      logLevel: 'info',
      databaseUrl: REQUIRED.WADESK_ENGINE_DATABASE_URL,
      apiToken: REQUIRED.WADESK_ENGINE_API_TOKEN,
      encryptionKey: 'key',
    });
  });

  it('reads optional values from the environment', () => {
    const config = loadConfig({ ...REQUIRED, WADESK_ENGINE_PORT: '4100', WADESK_ENGINE_HOST: '127.0.0.1', WADESK_ENGINE_LOG_LEVEL: 'debug' });

    expect(config).toMatchObject({ port: 4100, host: '127.0.0.1', logLevel: 'debug' });
  });
});
