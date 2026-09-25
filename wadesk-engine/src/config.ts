export interface Config {
  port: number;
  host: string;
  logLevel: string;
  databaseUrl: string;
  apiToken: string;
  encryptionKey: string;
  webhookSecret: string;
}

const MIN_SECRET_LENGTH = 32;

const required = (env: NodeJS.ProcessEnv, name: string): string => {
  const value = env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

// Reads configuration from the environment. Missing required values fail loudly at boot.
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const secret = (name: string): string => {
    const value = required(env, name);
    if (value.length < MIN_SECRET_LENGTH) throw new Error(`${name} must be at least ${String(MIN_SECRET_LENGTH)} characters`);
    return value;
  };

  return {
    port: Number(env.WADESK_ENGINE_PORT ?? 4000),
    host: env.WADESK_ENGINE_HOST ?? '0.0.0.0',
    logLevel: env.WADESK_ENGINE_LOG_LEVEL ?? 'info',
    databaseUrl: required(env, 'WADESK_ENGINE_DATABASE_URL'),
    apiToken: secret('WADESK_ENGINE_API_TOKEN'),
    encryptionKey: required(env, 'WADESK_ENGINE_ENCRYPTION_KEY'),
    webhookSecret: secret('WADESK_ENGINE_WEBHOOK_SECRET'),
  };
}
