import Fastify, { type FastifyInstance, type FastifyServerOptions } from 'fastify';
import { registerSessionRoutes, type SessionService } from './api/sessions.js';
import type { Pool } from './db/pool.js';

export interface AppDeps {
  pool: Pool;
  sessions: SessionService;
  apiToken: string;
}

export function buildApp(deps: AppDeps, options: FastifyServerOptions = {}): FastifyInstance {
  // Reject undocumented fields instead of silently dropping them (Fastify's default).
  const app = Fastify({ ajv: { customOptions: { removeAdditional: false } }, ...options });

  // Unauthenticated on purpose: liveness probe on the internal network only.
  app.get('/health', async (_request, reply) => {
    try {
      await deps.pool.query('SELECT 1');
      return { status: 'ok' };
    } catch {
      return reply.code(503).send({ status: 'unavailable', database: 'down' });
    }
  });

  registerSessionRoutes(app, deps.sessions, deps.apiToken);

  return app;
}
