import pg from 'pg';
import { migrate } from '../../src/db/migrate.js';
import { databaseUrl, silent } from './db.js';

// Creates the test database on first run, then applies all migrations.
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

  await migrate(databaseUrl, silent);
}
