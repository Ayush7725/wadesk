import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { SessionNotFoundError, SessionStateError } from '../sessions/errors.js';
import type { SessionSnapshot } from '../sessions/session.js';

// What the API needs from the session layer (implemented by SessionManager).
export interface SessionService {
  upsert(id: string, expectedPhone: string, webhookUrl: string): Promise<SessionSnapshot>;
  get(id: string): Promise<SessionSnapshot>;
  requestPairingCode(id: string): Promise<string>;
  remove(id: string): Promise<void>;
}

const idParams = {
  type: 'object',
  required: ['id'],
  properties: { id: { type: 'string', pattern: '^[0-9]{1,18}$' } },
} as const;

const upsertBody = {
  type: 'object',
  required: ['phone_number', 'webhook_url'],
  additionalProperties: false,
  properties: {
    phone_number: { type: 'string', pattern: '^[1-9][0-9]{6,14}$' }, // E.164 digits, no "+"
    webhook_url: { type: 'string', format: 'uri', pattern: '^https?://' },
  },
} as const;

interface IdRequest {
  Params: { id: string };
}
interface UpsertRequest extends IdRequest {
  Body: { phone_number: string; webhook_url: string };
}

const toResponse = (snapshot: SessionSnapshot) => ({
  state: snapshot.state,
  ...(snapshot.qr ? { qr: snapshot.qr } : {}),
  ...(snapshot.me ? { me: snapshot.me } : {}),
  ...(snapshot.lastError ? { last_error: snapshot.lastError } : {}),
});

const sendError = (reply: FastifyReply, status: number, code: string, message: string) =>
  reply.code(status).send({ error: { code, message } });

const tokenMatches = (header: string | undefined, token: Buffer): boolean => {
  const presented = Buffer.from(header?.startsWith('Bearer ') ? header.slice(7) : '');
  return presented.length === token.length && timingSafeEqual(presented, token);
};

// Internal session API used by Chatwoot (docs/wadesk/02-architecture.md §4.1).
export function registerSessionRoutes(app: FastifyInstance, sessions: SessionService, apiToken: string): void {
  const token = Buffer.from(apiToken);

  void app.register((scope, _options, done) => {
    scope.addHook('onRequest', async (request: FastifyRequest, reply: FastifyReply) => {
      if (!tokenMatches(request.headers.authorization, token)) await sendError(reply, 401, 'unauthorized', 'Invalid API token');
    });

    scope.setErrorHandler((error, _request, reply) => {
      if (error instanceof SessionNotFoundError) return sendError(reply, 404, error.code, error.message);
      if (error instanceof SessionStateError) return sendError(reply, 409, error.code, error.message);
      if ((error as { validation?: unknown }).validation) return sendError(reply, 422, 'invalid_request', (error as Error).message);
      throw error;
    });

    scope.put<UpsertRequest>('/sessions/:id', { schema: { params: idParams, body: upsertBody } }, async (request, reply) => {
      const snapshot = await sessions.upsert(request.params.id, request.body.phone_number, request.body.webhook_url);
      return reply.code(202).send(toResponse(snapshot));
    });

    scope.get<IdRequest>('/sessions/:id', { schema: { params: idParams } }, async (request) =>
      toResponse(await sessions.get(request.params.id)),
    );

    scope.post<IdRequest>('/sessions/:id/pairing-code', { schema: { params: idParams } }, async (request) => ({
      code: await sessions.requestPairingCode(request.params.id),
    }));

    scope.delete<IdRequest>('/sessions/:id', { schema: { params: idParams } }, async (request, reply) => {
      await sessions.remove(request.params.id);
      return reply.code(204).send();
    });

    done();
  });
}
