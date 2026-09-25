import type { SessionService } from '../../src/api/sessions.js';

export const API_TOKEN = 'test-token-0123456789abcdef0123456789';
export const AUTH = { authorization: `Bearer ${API_TOKEN}` };

export const unusedSessions: SessionService = {
  upsert: () => Promise.reject(new Error('unused')),
  get: () => Promise.reject(new Error('unused')),
  remove: () => Promise.reject(new Error('unused')),
};
