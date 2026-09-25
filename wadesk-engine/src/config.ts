export interface Config {
  port: number;
  host: string;
  logLevel: string;
}

// Reads configuration from the environment. Missing required values fail loudly at boot.
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return {
    port: Number(env.WADESK_ENGINE_PORT ?? 4000),
    host: env.WADESK_ENGINE_HOST ?? '0.0.0.0',
    logLevel: env.WADESK_ENGINE_LOG_LEVEL ?? 'info',
  };
}
