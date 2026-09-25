export interface Config {
  port: number;
  host: string;
  logLevel: string;
  databaseUrl: string;
  apiToken: string;
  encryptionKey: string;
}

const MIN_TOKEN_LENGTH = 32;

const required = (env: NodeJS.ProcessEnv, name: string): string => {
  const value = env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

// Reads configuration from the environment. Missing required values fail loudly at boot.
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const apiToken = required(env, 'WADESK_ENGINE_API_TOKEN');
  if (apiToken.length < MIN_TOKEN_LENGTH) throw new Error(`WADESK_ENGINE_API_TOKEN must be at least ${String(MIN_TOKEN_LENGTH)} characters`);

  return {
    port: Number(env.WADESK_ENGINE_PORT ?? 4000),
    host: env.WADESK_ENGINE_HOST ?? '0.0.0.0',
    logLevel: env.WADESK_ENGINE_LOG_LEVEL ?? 'info',
    databaseUrl: required(env, 'WADESK_ENGINE_DATABASE_URL'),
    apiToken,
    encryptionKey: required(env, 'WADESK_ENGINE_ENCRYPTION_KEY'),
  };
}
