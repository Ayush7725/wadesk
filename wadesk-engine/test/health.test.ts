import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { createPool } from '../src/db/pool.js';
import { databaseUrl } from './support/db.js';

describe('GET /health', () => {
  const pool = createPool(databaseUrl);
  afterAll(() => pool.end());

  it('reports ok when the database is reachable', async () => {
    const app = buildApp({ pool });
    const response = await app.inject({ method: 'GET', url: '/health' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'ok' });
    await app.close();
  });

  it('reports 503 when the database is unreachable', async () => {
    const deadPool = createPool('postgres://postgres@127.0.0.1:1/none');
    const app = buildApp({ pool: deadPool });
    const response = await app.inject({ method: 'GET', url: '/health' });

    expect(response.statusCode).toBe(503);
    expect(response.json()).toEqual({ status: 'unavailable', database: 'down' });
    await app.close();
    await deadPool.end();
  });
});
