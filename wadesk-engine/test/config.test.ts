import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

describe('loadConfig', () => {
  it('uses defaults', () => {
    expect(loadConfig({})).toEqual({ port: 4000, host: '0.0.0.0', logLevel: 'info' });
  });

  it('reads the environment', () => {
    const config = loadConfig({ WADESK_ENGINE_PORT: '4100', WADESK_ENGINE_HOST: '127.0.0.1', WADESK_ENGINE_LOG_LEVEL: 'debug' });

    expect(config).toEqual({ port: 4100, host: '127.0.0.1', logLevel: 'debug' });
  });
});
