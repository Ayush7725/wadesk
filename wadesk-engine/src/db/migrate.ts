import path from 'node:path';
import { runner, type RunnerOption } from 'node-pg-migrate';

export const SCHEMA = 'wadesk_engine';
const MIGRATIONS_DIR = path.resolve(import.meta.dirname, '../../migrations');

type Log = (message: string) => void;

// Applies (or reverts) the engine's SQL migrations under an advisory lock, so concurrent boots are safe.
export async function migrate(databaseUrl: string, log: Log, direction: RunnerOption['direction'] = 'up', count?: number) {
  return runner({
    databaseUrl,
    dir: MIGRATIONS_DIR,
    direction,
    ...(count === undefined ? {} : { count }),
    schema: SCHEMA,
    createSchema: true,
    migrationsSchema: SCHEMA,
    createMigrationsSchema: true,
    migrationsTable: 'schema_migrations',
    singleTransaction: true,
    log,
  });
}
