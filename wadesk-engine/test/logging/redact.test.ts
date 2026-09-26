import { Writable } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { createLogger } from '../../src/logging/logger.js';
import { isBenignLibraryNoise, maskDigits, maskRecord } from '../../src/logging/redact.js';

describe('maskDigits', () => {
  it.each([
    ['919876543210', '****3210'],
    ['919876543210@s.whatsapp.net', '****3210@s.whatsapp.net'],
    ['123456789012345@lid', '****2345@lid'],
    ['sending to 919876543210 failed', 'sending to ****3210 failed'],
  ])('masks %s', (input, expected) => {
    expect(maskDigits(input)).toBe(expected);
  });

  it.each(['3EB0620331FCA85C263A2D', 'session 1001', 'retry in 600 s', 'HTTP 429'])('leaves "%s" alone', (input) => {
    expect(maskDigits(input)).toBe(input);
  });

  it('survives circular records and leaves class instances to their serializers', () => {
    const circular: Record<string, unknown> = { jid: '919876543210@s.whatsapp.net' };
    circular.self = circular;
    class Request {
      url = '/sessions/919876543210';
    }
    const request = new Request();

    const masked = maskRecord({ circular, request }) as { circular: { jid: string }; request: Request };

    expect(masked.circular.jid).toBe('****3210@s.whatsapp.net');
    expect(masked.request).toBe(request);
  });

  it('masks nested strings in log records', () => {
    expect(maskRecord({ key: { remoteJid: '919876543210@s.whatsapp.net', id: '3EB0AB' }, list: ['919812345678'], n: 5 })).toEqual({
      key: { remoteJid: '****3210@s.whatsapp.net', id: '3EB0AB' },
      list: ['****5678'],
      n: 5,
    });
  });
});

describe('isBenignLibraryNoise', () => {
  it("recognises WhatsApp's routine restart after linking", () => {
    expect(isBenignLibraryNoise([{ fullErrorNode: { tag: 'stream:error', attrs: { code: '515' } } }, 'stream errored out'])).toBe(true);
  });

  it('keeps other stream errors', () => {
    expect(isBenignLibraryNoise([{ fullErrorNode: { attrs: { code: '401' } } }, 'stream errored out'])).toBe(false);
  });
});

describe('createLogger', () => {
  const capture = () => {
    const lines: Record<string, unknown>[] = [];
    const stream = new Writable({
      write(chunk: Buffer, _encoding, done) {
        lines.push(JSON.parse(chunk.toString()) as Record<string, unknown>);
        done();
      },
    });
    return { lines, logger: createLogger('debug', stream) };
  };

  it('masks phone numbers in messages and fields', () => {
    const { lines, logger } = capture();

    logger.warn({ jid: '919876543210@s.whatsapp.net' }, 'send to 919876543210 failed');

    expect(lines[0]).toMatchObject({ jid: '****3210@s.whatsapp.net', msg: 'send to ****3210 failed' });
  });

  it('drops benign library noise but keeps real errors', () => {
    const { lines, logger } = capture();

    logger.error({ fullErrorNode: { attrs: { code: '515' } } }, 'stream errored out');
    logger.error({ fullErrorNode: { attrs: { code: '401' } } }, 'stream errored out');

    expect(lines).toHaveLength(1);
  });
});
