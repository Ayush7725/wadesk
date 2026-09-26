import { readFileSync } from 'node:fs';
import type { proto, WAMessage } from 'baileys';
import { describe, expect, it } from 'vitest';
import { normalizeEcho, normalizeIncoming } from '../../src/whatsapp/normalizer.js';

const CUSTOMER = '919876543210@s.whatsapp.net';
const LID = '123456789012345@lid';
const contract = (name: string): unknown => JSON.parse(readFileSync(new URL(`../../contract/messages/${name}.json`, import.meta.url), 'utf8'));

const incoming = (message: proto.IMessage, key: Partial<WAMessage['key']> = {}): WAMessage => ({
  key: { remoteJid: CUSTOMER, fromMe: false, id: '3EB0A1B2C3D4E5F6', ...key },
  message,
  messageTimestamp: 1790000000,
  pushName: 'Ravi Kumar',
});

describe('normalizeIncoming', () => {
  // Each case must match the shared contract fixture that Chatwoot's specs also consume.
  it.each<[string, proto.IMessage, Partial<WAMessage['key']>?]>([
    ['text', { conversation: 'Hi, what is the price of the teak sofa?' }],
    [
      'text_reply',
      { extendedTextMessage: { text: 'Is it available in brown?', contextInfo: { stanzaId: '3EB0FFEEDDCCBBAA' } } },
    ],
    ['image', { imageMessage: { mimetype: 'image/jpeg', caption: 'Like this one' } }],
    ['voice_note', { audioMessage: { mimetype: 'audio/ogg; codecs=opus', ptt: true } }],
    ['document', { documentMessage: { mimetype: 'application/pdf', fileName: 'floor-plan.pdf', caption: 'Our room' } }],
    ['sticker', { stickerMessage: { mimetype: 'image/webp' } }],
    [
      'location',
      { locationMessage: { degreesLatitude: 26.9124, degreesLongitude: 75.7873, name: 'Home', address: 'Jaipur, Rajasthan' } },
    ],
    [
      'contact_card',
      {
        contactMessage: {
          displayName: 'Anita Sharma',
          vcard: 'BEGIN:VCARD\nVERSION:3.0\nFN:Anita Sharma\nTEL;type=CELL;waid=919812300000:+91 98123 00000\nEND:VCARD',
        },
      },
    ],
    ['unsupported', { pollCreationMessage: { name: 'Which colour?' } }],
    ['lid_with_phone', { conversation: 'Hello' }, { remoteJid: LID, remoteJidAlt: CUSTOMER, addressingMode: 'lid' }],
    ['lid_only', { conversation: 'Hello' }, { remoteJid: LID }],
  ])('maps %s to the contract', (name, message, key) => {
    expect(normalizeIncoming(incoming(message, key))).toEqual(contract(name));
  });

  it('unwraps disappearing and view-once messages', () => {
    const wrapped = normalizeIncoming(incoming({ ephemeralMessage: { message: { conversation: 'Hi, what is the price of the teak sofa?' } } }));
    const viewOnce = normalizeIncoming(incoming({ viewOnceMessageV2: { message: { imageMessage: { mimetype: 'image/jpeg', caption: 'Like this one' } } } }));

    expect(wrapped).toEqual(contract('text'));
    expect(viewOnce).toEqual(contract('image'));
  });

  it('reads replies attached to media captions', () => {
    const event = normalizeIncoming(incoming({ imageMessage: { mimetype: 'image/jpeg', contextInfo: { stanzaId: 'QUOTED1' } } }));

    expect(event?.messages[0]?.context).toEqual({ id: 'QUOTED1' });
  });

  it('accepts protobuf Long timestamps', () => {
    const message = { ...incoming({ conversation: 'hi' }), messageTimestamp: { toNumber: () => 1790000001 } as unknown as number };

    expect(normalizeIncoming(message)?.messages[0]?.timestamp).toBe('1790000001');
  });

  it.each([
    ['group chats', { remoteJid: '120363000000000000@g.us', participant: CUSTOMER }],
    ['status updates', { remoteJid: 'status@broadcast' }],
    ['broadcast lists', { remoteJid: '1234567890@broadcast' }],
    ['channels', { remoteJid: '120363000000000000@newsletter' }],
    ['messages sent by the business itself', { fromMe: true }],
  ])('ignores %s', (_name, key) => {
    expect(normalizeIncoming(incoming({ conversation: 'hi' }, key))).toBeUndefined();
  });

  it.each<[string, proto.IMessage]>([
    ['reactions', { reactionMessage: { text: '👍', key: { id: 'X' } } }],
    ['deletions and other protocol messages', { protocolMessage: { type: 0 } }],
    ['edits', { editedMessage: { message: { conversation: 'edited' } } }],
    ['empty messages', {}],
  ])('ignores %s', (_name, message) => {
    expect(normalizeIncoming(incoming(message))).toBeUndefined();
  });
});

describe('normalizeEcho', () => {
  const own = (key: Partial<WAMessage['key']> = {}): WAMessage => ({
    key: { remoteJid: CUSTOMER, fromMe: true, id: '3EB0ECHO000001', ...key },
    message: { conversation: 'Sent from my phone: yes, 45,000' },
    messageTimestamp: 1790000000,
    pushName: 'The business itself',
  });

  it('turns a message typed on the business phone into an echo', () => {
    expect(normalizeEcho(own(), '919828074219')).toEqual(contract('echo_text'));
  });

  it('addresses privacy-ID customers by user id', () => {
    expect(normalizeEcho(own({ remoteJid: LID }), '919828074219')).toEqual(contract('echo_lid'));
  });

  it('ignores customer messages and groups', () => {
    expect(normalizeEcho(own({ fromMe: false }), '919828074219')).toBeUndefined();
    expect(normalizeEcho(own({ remoteJid: '120363@g.us' }), '919828074219')).toBeUndefined();
  });
});
