import { describe, expect, it } from 'vitest';
import { InvalidRecipientError, messageContent, quotedMessage, recipientJid } from '../../src/whatsapp/outgoing.js';

const file = (mimetype: string, filename = 'f') => ({ data: Buffer.from('x'), mimetype, filename });

describe('recipientJid', () => {
  it.each([
    ['919876543210', '919876543210@s.whatsapp.net'],
    ['123456789012345@lid', '123456789012345@lid'],
  ])('maps %s', (to, jid) => {
    expect(recipientJid(to)).toBe(jid);
  });

  it.each(['+919876543210', '12345', 'abc', '1203@g.us', 'status@broadcast'])('rejects %s', (to) => {
    expect(() => recipientJid(to)).toThrow(InvalidRecipientError);
  });
});

describe('messageContent', () => {
  it('sends plain text', () => {
    expect(messageContent({ to: '1', text: 'hello' })).toEqual({ text: 'hello' });
  });

  it.each([
    ['image/jpeg', { image: Buffer.from('x'), mimetype: 'image/jpeg', caption: 'cap' }],
    ['video/mp4', { video: Buffer.from('x'), mimetype: 'video/mp4', caption: 'cap' }],
    ['image/svg+xml', { document: Buffer.from('x'), mimetype: 'image/svg+xml', fileName: 'f', caption: 'cap' }],
    ['application/pdf', { document: Buffer.from('x'), mimetype: 'application/pdf', fileName: 'f', caption: 'cap' }],
  ])('sends %s files with the text as caption', (mimetype, expected) => {
    expect(messageContent({ to: '1', text: 'cap', file: file(mimetype) })).toEqual(expected);
  });

  it('sends OGG recordings as voice notes and other audio as audio', () => {
    expect(messageContent({ to: '1', file: file('audio/ogg; codecs=opus') })).toMatchObject({ ptt: true });
    expect(messageContent({ to: '1', file: file('audio/mpeg') })).toMatchObject({ ptt: false });
  });
});

describe('quotedMessage', () => {
  it('builds a minimal quote with the preview text', () => {
    expect(quotedMessage('919876543210@s.whatsapp.net', { id: 'Q1', text: 'Brown?', fromMe: true })).toEqual({
      key: { remoteJid: '919876543210@s.whatsapp.net', id: 'Q1', fromMe: true },
      message: { conversation: 'Brown?' },
    });
  });
});
