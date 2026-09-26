import Fastify, { type FastifyInstance, type FastifyServerOptions } from 'fastify';
import type { Registry } from 'prom-client';
import { registerSessionRoutes, tokenMatches, type SendResult, type SessionService } from './api/sessions.js';
import type { Pool } from './db/pool.js';

export interface AppDeps {
  pool: Pool;
  sessions: SessionService;
  apiToken: string;
  uploadDeadlineMs?: number;
  metrics?: { registry: Registry; onSend: (result: SendResult) => void };
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

  registerSessionRoutes(app, deps.sessions, deps.apiToken, deps.uploadDeadlineMs, deps.metrics?.onSend);

  const { metrics } = deps;
  if (metrics) {
    const token = Buffer.from(deps.apiToken);
    // Prometheus exposition; same bearer token as the API (Prometheus supports bearer auth).
    app.get('/metrics', async (request, reply) => {
      if (!tokenMatches(request.headers.authorization, token)) {
        return reply.code(401).send({ error: { code: 'unauthorized', message: 'Invalid API token' } });
      }
      return reply.header('content-type', metrics.registry.contentType).send(await metrics.registry.metrics());
    });
  }

  return app;
}
