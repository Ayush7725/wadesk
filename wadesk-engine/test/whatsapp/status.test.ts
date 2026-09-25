import { readFileSync } from 'node:fs';
import { proto, type WAMessageUpdate } from 'baileys';
import { describe, expect, it } from 'vitest';
import { normalizeStatus } from '../../src/whatsapp/normalizer.js';

const contract = (name: string): unknown => JSON.parse(readFileSync(new URL(`../../contract/statuses/${name}.json`, import.meta.url), 'utf8'));
const receipt = (status: proto.WebMessageInfo.Status, key: Partial<WAMessageUpdate['key']> = {}): WAMessageUpdate => ({
  key: { remoteJid: '919876543210@s.whatsapp.net', fromMe: true, id: '3EB0OUT1234567', ...key },
  update: { status },
});
const { Status } = proto.WebMessageInfo;

describe('normalizeStatus', () => {
  it.each([
    ['sent', Status.SERVER_ACK],
    ['delivered', Status.DELIVERY_ACK],
    ['read', Status.READ],
    ['failed', Status.ERROR],
  ] as const)('maps %s to the contract', (name, status) => {
    expect(normalizeStatus(receipt(status))).toEqual(contract(name));
  });

  it('treats a played voice note as read', () => {
    expect(normalizeStatus(receipt(Status.PLAYED))).toEqual(contract('read'));
  });

  it('identifies privacy-ID (LID) recipients', () => {
    expect(normalizeStatus(receipt(Status.READ, { remoteJid: '123456789012345@lid' }))).toEqual(contract('read_lid'));
  });

  it.each([
    ['pending (not yet on WhatsApp servers)', receipt(Status.PENDING)],
    ["receipts for the customer's messages", receipt(Status.READ, { fromMe: false })],
    ['group messages', receipt(Status.READ, { remoteJid: '120363@g.us' })],
    ['updates without a status (edits, reactions)', { key: receipt(Status.READ).key, update: {} }],
  ])('ignores %s', (_name, update) => {
    expect(normalizeStatus(update)).toBeUndefined();
  });
});
