import Fastify, { type FastifyInstance, type FastifyServerOptions } from 'fastify';
import type { Pool } from './db/pool.js';

export interface AppDeps {
  pool: Pool;
}

export function buildApp(deps: AppDeps, options: FastifyServerOptions = {}): FastifyInstance {
  const app = Fastify(options);

  app.get('/health', async (_request, reply) => {
    try {
      await deps.pool.query('SELECT 1');
      return { status: 'ok' };
    } catch {
      return reply.code(503).send({ status: 'unavailable', database: 'down' });
    }
  });

  return app;
}
