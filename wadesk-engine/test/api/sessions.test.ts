import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { SessionService } from '../../src/api/sessions.js';
import { buildApp } from '../../src/app.js';
import { createPool } from '../../src/db/pool.js';
import { SessionNotFoundError, SessionStateError } from '../../src/sessions/errors.js';
import { API_TOKEN, AUTH } from '../support/app.js';
import { databaseUrl } from '../support/db.js';

describe('session API', () => {
  const pool = createPool(databaseUrl);
  afterAll(() => pool.end());

  let sessions: { [K in keyof SessionService]: ReturnType<typeof vi.fn> };
  const app = () => buildApp({ pool, sessions: sessions as unknown as SessionService, apiToken: API_TOKEN });
  const body = { phone_number: '919812345678', webhook_url: 'http://chatwoot:3000/webhooks/whatsapp_web/12' };

  beforeEach(() => {
    sessions = { upsert: vi.fn(), get: vi.fn(), requestPairingCode: vi.fn(), remove: vi.fn() };
  });

  it.each([undefined, 'Bearer wrong-token', API_TOKEN])('rejects requests with authorization %s', async (authorization) => {
    const response = await app().inject({ method: 'GET', url: '/sessions/12', headers: authorization ? { authorization } : {} });

    expect(response.statusCode).toBe(401);
    expect(response.json()).toEqual({ error: { code: 'unauthorized', message: 'Invalid API token' } });
    expect(sessions.get).not.toHaveBeenCalled();
  });

  it('keeps /health public', async () => {
    const response = await app().inject({ method: 'GET', url: '/health' });
    expect(response.statusCode).toBe(200);
  });

  it('creates or restarts a session', async () => {
    sessions.upsert.mockResolvedValue({ state: 'connecting' });

    const response = await app().inject({ method: 'PUT', url: '/sessions/12', headers: AUTH, payload: body });

    expect(response.statusCode).toBe(202);
    expect(response.json()).toEqual({ state: 'connecting' });
    expect(sessions.upsert).toHaveBeenCalledWith('12', '919812345678', body.webhook_url);
  });

  it.each([
    ['a phone number with "+"', { ...body, phone_number: '+919812345678' }],
    ['a too-short phone number', { ...body, phone_number: '12345' }],
    ['a non-http webhook', { ...body, webhook_url: 'ftp://chatwoot/x' }],
    ['unknown fields', { ...body, extra: true }],
    ['a missing webhook', { phone_number: body.phone_number }],
  ])('rejects %s with 422', async (_name, payload) => {
    const response = await app().inject({ method: 'PUT', url: '/sessions/12', headers: AUTH, payload });

    expect(response.statusCode).toBe(422);
    expect(response.json()).toMatchObject({ error: { code: 'invalid_request' } });
    expect(sessions.upsert).not.toHaveBeenCalled();
  });

  it('rejects non-numeric session ids', async () => {
    const response = await app().inject({ method: 'GET', url: '/sessions/abc', headers: AUTH });
    expect(response.statusCode).toBe(422);
  });

  it('returns the session state with QR code in API field names', async () => {
    sessions.get.mockResolvedValue({ state: 'qr_pending', qr: '2@abc', lastError: 'qr_expired' });

    const response = await app().inject({ method: 'GET', url: '/sessions/12', headers: AUTH });

    expect(response.json()).toEqual({ state: 'qr_pending', qr: '2@abc', last_error: 'qr_expired' });
  });

  it('returns 404 for unknown sessions', async () => {
    sessions.get.mockRejectedValue(new SessionNotFoundError('12'));

    const response = await app().inject({ method: 'GET', url: '/sessions/12', headers: AUTH });

    expect(response.statusCode).toBe(404);
    expect(response.json()).toEqual({ error: { code: 'session_not_found', message: 'Session 12 not found' } });
  });

  it('returns a pairing code', async () => {
    sessions.requestPairingCode.mockResolvedValue('ABCD1234');

    const response = await app().inject({ method: 'POST', url: '/sessions/12/pairing-code', headers: AUTH });

    expect(response.json()).toEqual({ code: 'ABCD1234' });
  });

  it('returns 409 when a pairing code is requested at the wrong time', async () => {
    sessions.requestPairingCode.mockRejectedValue(new SessionStateError('not_pending', 'not waiting'));

    const response = await app().inject({ method: 'POST', url: '/sessions/12/pairing-code', headers: AUTH });

    expect(response.statusCode).toBe(409);
    expect(response.json()).toEqual({ error: { code: 'not_pending', message: 'not waiting' } });
  });

  it('deletes a session', async () => {
    sessions.remove.mockResolvedValue(undefined);

    const response = await app().inject({ method: 'DELETE', url: '/sessions/12', headers: AUTH });

    expect(response.statusCode).toBe(204);
    expect(sessions.remove).toHaveBeenCalledWith('12');
  });
});
