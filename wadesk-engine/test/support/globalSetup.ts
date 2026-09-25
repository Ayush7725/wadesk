import pg from 'pg';
import { migrate, SCHEMA } from '../../src/db/migrate.js';
import { databaseUrl, silent } from './db.js';

// Creates the test database on first run, resets the engine schema, then applies all migrations.
export default async function setup(): Promise<void> {
  const target = new URL(databaseUrl);
  const name = target.pathname.slice(1);
  const admin = new URL(databaseUrl);
  admin.pathname = '/postgres';

  const client = new pg.Client({ connectionString: admin.toString() });
  await client.connect();
  const { rowCount } = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [name]);
  if (rowCount === 0) await client.query(`CREATE DATABASE "${name}"`);
  await client.end();

  // Start every run from an empty schema: the test database is disposable, and a schema left over
  // from another branch (with migrations this branch does not have) must not break the run.
  const db = new pg.Client({ connectionString: databaseUrl });
  await db.connect();
  await db.query(`DROP SCHEMA IF EXISTS ${SCHEMA} CASCADE`);
  await db.end();

  await migrate(databaseUrl, silent);
}
