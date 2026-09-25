import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { Readable } from 'node:stream';
import type { WAMessage } from 'baileys';
import { MediaNotFoundError, MediaUnavailableError, SessionNotFoundError } from '../sessions/errors.js';
import type { SessionSnapshot } from '../sessions/session.js';
import type { LinkMethod } from '../sessions/types.js';

// What the API needs from the session layer (implemented by SessionManager).
export interface SessionService {
  upsert(id: string, expectedPhone: string, webhookUrl: string, linkMethod: LinkMethod): Promise<SessionSnapshot>;
  get(id: string): Promise<SessionSnapshot>;
  downloadMedia(id: string, messageId: string): Promise<{ stream: Readable; message: WAMessage }>;
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
    link_method: { type: 'string', enum: ['qr', 'code'] }, // optional, defaults to "qr"
  },
} as const;

interface IdRequest {
  Params: { id: string };
}
interface MediaRequest {
  Params: { id: string; messageId: string };
}

const mediaParams = {
  type: 'object',
  required: ['id', 'messageId'],
  properties: { ...idParams.properties, messageId: { type: 'string', pattern: '^[A-Za-z0-9]{1,64}$' } },
} as const;

// Content type and file name for a stored media message (Chatwoot names the attachment after it).
function mediaDetails(message: WAMessage): { mimetype: string; filename: string } {
  const content = message.message ?? {};
  const part = content.documentMessage ?? content.imageMessage ?? content.videoMessage ?? content.ptvMessage ?? content.audioMessage ?? content.stickerMessage;
  const mimetype = part?.mimetype ?? 'application/octet-stream';
  const extension = mimetype.split(';')[0]?.split('/')[1] ?? 'bin';
  return { mimetype, filename: content.documentMessage?.fileName ?? `${message.key.id ?? 'media'}.${extension}` };
}
interface UpsertRequest extends IdRequest {
  Body: { phone_number: string; webhook_url: string; link_method?: LinkMethod };
}

const toResponse = (snapshot: SessionSnapshot) => ({
  state: snapshot.state,
  ...(snapshot.qr ? { qr: snapshot.qr } : {}),
  ...(snapshot.pairingCode ? { pairing_code: snapshot.pairingCode } : {}),
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
      if (error instanceof SessionNotFoundError || error instanceof MediaNotFoundError) return sendError(reply, 404, error.code, error.message);
      if (error instanceof MediaUnavailableError) return sendError(reply, 502, error.code, error.message);
      if ((error as { validation?: unknown }).validation) return sendError(reply, 422, 'invalid_request', (error as Error).message);
      throw error;
    });

    scope.put<UpsertRequest>('/sessions/:id', { schema: { params: idParams, body: upsertBody } }, async (request, reply) => {
      const { phone_number: phone, webhook_url: webhookUrl, link_method: linkMethod = 'qr' } = request.body;
      const snapshot = await sessions.upsert(request.params.id, phone, webhookUrl, linkMethod);
      return reply.code(202).send(toResponse(snapshot));
    });

    scope.get<IdRequest>('/sessions/:id', { schema: { params: idParams } }, async (request) =>
      toResponse(await sessions.get(request.params.id)),
    );

    scope.get<MediaRequest>('/sessions/:id/media/:messageId', { schema: { params: mediaParams } }, async (request, reply) => {
      const { stream, message } = await sessions.downloadMedia(request.params.id, request.params.messageId);
      const { mimetype, filename } = mediaDetails(message);
      return reply
        .header('content-type', mimetype)
        .header('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`)
        .send(stream);
    });

    scope.delete<IdRequest>('/sessions/:id', { schema: { params: idParams } }, async (request, reply) => {
      await sessions.remove(request.params.id);
      return reply.code(204).send();
    });

    done();
  });
}
