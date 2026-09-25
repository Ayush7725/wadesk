import { timingSafeEqual } from 'node:crypto';
import multipart from '@fastify/multipart';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { Readable } from 'node:stream';
import type { WAMessage } from 'baileys';
import {
  MediaNotFoundError,
  MediaUnavailableError,
  RateLimitedError,
  SessionNotConnectedError,
  SessionNotFoundError,
} from '../sessions/errors.js';
import { InvalidRecipientError, type OutgoingMessage } from '../whatsapp/outgoing.js';
import type { SessionSnapshot } from '../sessions/session.js';
import type { LinkMethod } from '../sessions/types.js';

// What the API needs from the session layer (implemented by SessionManager).
export interface SessionService {
  upsert(id: string, expectedPhone: string, webhookUrl: string, linkMethod: LinkMethod): Promise<SessionSnapshot>;
  get(id: string): Promise<SessionSnapshot>;
  downloadMedia(id: string, messageId: string): Promise<{ stream: Readable; message: WAMessage }>;
  send(id: string, outgoing: OutgoingMessage): Promise<string>;
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

const MAX_FILE_BYTES = 100 * 1024 * 1024; // WhatsApp's document limit
const MAX_TEXT_LENGTH = 65_536;
// Reading an upload must finish within this time: some malformed multipart bodies make the parser wait forever.
export const UPLOAD_DEADLINE_MS = 30_000;

class InvalidSendRequestError extends Error {
  readonly code = 'invalid_request';
}

// Reads the multipart send request within the deadline, so a stalled parse gets a clear 422 instead of hanging.
async function readOutgoingWithin(request: FastifyRequest, deadlineMs: number): Promise<OutgoingMessage> {
  let timer: NodeJS.Timeout | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => {
      reject(new InvalidSendRequestError('Upload was not completed in time (malformed multipart body?)'));
    }, deadlineMs);
  });
  try {
    return await Promise.race([readOutgoing(request), deadline]);
  } finally {
    clearTimeout(timer);
  }
}

// Reads the multipart send request: fields to, text, reply_to_id, reply_to_text, reply_to_from_me and at most one file.
async function readOutgoing(request: FastifyRequest): Promise<OutgoingMessage> {
  const fields: Record<string, string> = {};
  let file: OutgoingMessage['file'];
  try {
    for await (const part of request.parts()) {
      if (part.type === 'file') {
        file = { data: await part.toBuffer(), mimetype: part.mimetype, filename: part.filename };
      } else {
        fields[part.fieldname] = String(part.value);
      }
    }
  } catch (error) {
    // A body that is not valid multipart is the caller's mistake, not a server error.
    if ((error as { code?: string }).code === 'FST_REQ_FILE_TOO_LARGE') throw error;
    throw new InvalidSendRequestError(`Malformed multipart body: ${(error as Error).message}`);
  }

  const { to, text, reply_to_id: replyToId, reply_to_text: replyToText = '', reply_to_from_me: replyToFromMe } = fields;
  if (!to) throw new InvalidSendRequestError('"to" is required');
  if (!text && !file) throw new InvalidSendRequestError('A text or a file is required');
  if (text && text.length > MAX_TEXT_LENGTH) throw new InvalidSendRequestError('Text is too long');

  return {
    to,
    ...(text ? { text } : {}),
    ...(file ? { file } : {}),
    ...(replyToId ? { replyTo: { id: replyToId, text: replyToText, fromMe: replyToFromMe === 'true' } } : {}),
  };
}

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
export function registerSessionRoutes(
  app: FastifyInstance,
  sessions: SessionService,
  apiToken: string,
  uploadDeadlineMs = UPLOAD_DEADLINE_MS,
): void {
  const token = Buffer.from(apiToken);

  void app.register(async (scope) => {
    await scope.register(multipart, { limits: { fileSize: MAX_FILE_BYTES, files: 1, fields: 10 }, throwFileSizeLimit: true });

    scope.addHook('onRequest', async (request: FastifyRequest, reply: FastifyReply) => {
      if (!tokenMatches(request.headers.authorization, token)) await sendError(reply, 401, 'unauthorized', 'Invalid API token');
    });

    scope.setErrorHandler((error, _request, reply) => {
      if (error instanceof SessionNotFoundError || error instanceof MediaNotFoundError) return sendError(reply, 404, error.code, error.message);
      if (error instanceof MediaUnavailableError) return sendError(reply, 502, error.code, error.message);
      if (error instanceof SessionNotConnectedError) return sendError(reply, 409, error.code, error.message);
      if (error instanceof InvalidRecipientError || error instanceof InvalidSendRequestError) {
        return sendError(reply, 422, error.code, error.message);
      }
      if (error instanceof RateLimitedError) {
        return reply
          .code(429)
          .header('retry-after', String(Math.ceil(error.retryAfterMs / 1000)))
          .send({ error: { code: error.code, message: error.message, retry_after_ms: error.retryAfterMs } });
      }
      if ((error as { code?: string }).code === 'FST_REQ_FILE_TOO_LARGE') return sendError(reply, 413, 'file_too_large', 'File exceeds 100 MB');
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

    scope.post<IdRequest>('/sessions/:id/messages', { schema: { params: idParams } }, async (request, reply) => {
      const id = await sessions.send(request.params.id, await readOutgoingWithin(request, uploadDeadlineMs));
      return reply.code(201).send({ id });
    });

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

  });
}
