import type { AnyMessageContent, WAMessage } from 'baileys';

// An outgoing message as requested by Chatwoot (docs/wadesk/02-architecture.md §4.1).
export interface OutgoingMessage {
  to: string; // phone number digits or a privacy ID ("<digits>@lid")
  text?: string;
  file?: { data: Buffer; mimetype: string; filename: string };
  replyTo?: { id: string; text: string; fromMe: boolean };
}

export class InvalidRecipientError extends Error {
  readonly code = 'invalid_recipient';
  constructor(to: string) {
    super(`Not a WhatsApp phone number or privacy ID: ${to}`);
    this.name = 'InvalidRecipientError';
  }
}

export function recipientJid(to: string): string {
  if (/^[1-9]\d{6,14}$/.test(to)) return `${to}@s.whatsapp.net`;
  if (/^\d{1,20}@lid$/.test(to)) return to;
  throw new InvalidRecipientError(to);
}

// Baileys content for a text or a single file (caption = text). OGG/Opus audio is sent as a voice note,
// like Chatwoot's Official provider does for recordings.
export function messageContent({ text, file }: OutgoingMessage): AnyMessageContent {
  if (!file) return { text: text ?? '' };

  const caption = text ? { caption: text } : {};
  const { data, mimetype, filename } = file;
  if (mimetype.startsWith('image/') && mimetype !== 'image/svg+xml') return { image: data, mimetype, ...caption };
  if (mimetype.startsWith('video/')) return { video: data, mimetype, ...caption };
  if (mimetype.startsWith('audio/')) return { audio: data, mimetype, ptt: mimetype.startsWith('audio/ogg') };
  return { document: data, mimetype, fileName: filename, ...caption };
}

// Minimal quoted message so the customer sees which message is being answered, with its text as preview.
export function quotedMessage(jid: string, replyTo: NonNullable<OutgoingMessage['replyTo']>): WAMessage {
  return { key: { remoteJid: jid, id: replyTo.id, fromMe: replyTo.fromMe }, message: { conversation: replyTo.text } };
}
