import {
  getContentType,
  isJidBroadcast,
  isJidGroup,
  isJidNewsletter,
  isJidStatusBroadcast,
  jidDecode,
  normalizeMessageContent,
  proto,
  type WAMessage,
  type WAMessageUpdate,
} from 'baileys';

// Payload shapes sent to Chatwoot. They follow the WhatsApp Cloud API webhook format that Chatwoot's
// incoming pipeline already parses (docs/wadesk/02-architecture.md §4.2). Shared fixtures in contract/.
export interface IncomingContact {
  wa_id?: string; // phone number digits, when WhatsApp exposes it
  user_id?: string; // privacy ID (LID), when present
  profile?: { name: string };
}

export interface IncomingMessage {
  id: string;
  from: string;
  timestamp: string;
  type: string;
  context?: { id: string };
  [body: string]: unknown;
}

export interface MessagesEvent {
  event: 'messages';
  contacts: IncomingContact[];
  messages: IncomingMessage[];
}

export type DeliveryStatus = 'sent' | 'delivered' | 'read' | 'failed';

export interface StatusesEvent {
  event: 'statuses';
  statuses: [{ id: string; status: DeliveryStatus; recipient_id: string }];
}

// Message kinds that carry no conversation content for the inbox.
const IGNORED_TYPES = new Set<keyof proto.IMessage>([
  'protocolMessage',
  'senderKeyDistributionMessage',
  'reactionMessage',
  'keepInChatMessage',
  'pollUpdateMessage',
  'messageContextInfo',
]);

const phoneOf = (jid: string | null | undefined) => (jid?.endsWith('@s.whatsapp.net') ? jidDecode(jid)?.user : undefined);
const lidOf = (jid: string | null | undefined) => (jid?.endsWith('@lid') ? jid : undefined);
const seconds = (value: WAMessage['messageTimestamp']) => String(typeof value === 'number' ? value : (value?.toNumber() ?? 0));

// Only 1:1 chats with customers reach the inbox in Step 1 (WW-FR-15).
const isCustomerChat = (jid: string) =>
  !isJidGroup(jid) && !isJidBroadcast(jid) && !isJidStatusBroadcast(jid) && !isJidNewsletter(jid);

// Phone numbers from a vCard: prefer WhatsApp's waid parameter, else the TEL value.
const vcardPhones = (vcard: string | null | undefined) =>
  (vcard ?? '')
    .split(/\r?\n/)
    .filter((line) => line.toUpperCase().startsWith('TEL'))
    .map((line) => ({ phone: /waid=(\d+)/i.exec(line)?.[1] ?? line.slice(line.lastIndexOf(':') + 1).replace(/[^\d+]/g, '') }))
    .filter(({ phone }) => phone.length > 0);

const contactCard = (card: proto.Message.IContactMessage) => ({
  name: { formatted_name: card.displayName ?? '' },
  phones: vcardPhones(card.vcard),
});

interface Body {
  type: string;
  [part: string]: unknown;
}

// Maps one message's content to a Cloud API message body (without id/from/timestamp).
function body(id: string, content: proto.IMessage, type: keyof proto.IMessage): Body {
  const media = (kind: string, part: { mimetype?: string | null; caption?: string | null }, extra: object = {}): Body => ({
    type: kind,
    [kind]: { id, mime_type: part.mimetype ?? 'application/octet-stream', ...(part.caption ? { caption: part.caption } : {}), ...extra },
  });

  switch (type) {
    case 'conversation':
      return { type: 'text', text: { body: content.conversation ?? '' } };
    case 'extendedTextMessage':
      return { type: 'text', text: { body: content.extendedTextMessage?.text ?? '' } };
    case 'imageMessage':
      return media('image', content.imageMessage ?? {});
    case 'videoMessage':
      return media('video', content.videoMessage ?? {});
    case 'ptvMessage':
      return media('video', content.ptvMessage ?? {});
    case 'audioMessage':
      return media('audio', content.audioMessage ?? {}, { voice: Boolean(content.audioMessage?.ptt) });
    case 'documentMessage': {
      const document = content.documentMessage ?? {};
      return media('document', document, document.fileName ? { filename: document.fileName } : {});
    }
    case 'stickerMessage':
      return media('sticker', content.stickerMessage ?? {});
    case 'locationMessage':
    case 'liveLocationMessage': {
      const location = content.locationMessage ?? content.liveLocationMessage ?? {};
      const named = content.locationMessage ?? {};
      return {
        type: 'location',
        location: {
          latitude: location.degreesLatitude ?? 0,
          longitude: location.degreesLongitude ?? 0,
          ...(named.name ? { name: named.name } : {}),
          ...(named.address ? { address: named.address } : {}),
          ...(named.url ? { url: named.url } : {}),
        },
      };
    }
    case 'contactMessage':
      return { type: 'contacts', contacts: [contactCard(content.contactMessage ?? {})] };
    case 'contactsArrayMessage':
      return { type: 'contacts', contacts: (content.contactsArrayMessage?.contacts ?? []).map(contactCard) };
    default:
      return { type: 'unsupported' };
  }
}

// The message being replied to, from whichever part of the content carries contextInfo.
function replyTo(content: proto.IMessage, type: keyof proto.IMessage): string | undefined {
  const part = content[type] as { contextInfo?: proto.IContextInfo | null } | string | null | undefined;
  return typeof part === 'object' ? (part?.contextInfo?.stanzaId ?? undefined) : undefined;
}

// Converts an incoming WhatsApp Web message into a Chatwoot "messages" event, or undefined when the
// message does not belong in the inbox (own messages, groups, status, broadcasts, protocol messages).
export function normalizeIncoming(message: WAMessage): MessagesEvent | undefined {
  const { key } = message;
  const jid = key.remoteJid;
  if (!jid || !key.id || key.fromMe || !isCustomerChat(jid)) return undefined;

  // Checked before unwrapping: normalizeMessageContent would turn an edit into a look-alike new message.
  if (message.message?.editedMessage) return undefined;

  const content = normalizeMessageContent(message.message);
  const type = getContentType(content);
  if (!content || !type || IGNORED_TYPES.has(type)) return undefined;

  const phone = phoneOf(jid) ?? phoneOf(key.remoteJidAlt);
  const lid = lidOf(jid) ?? lidOf(key.remoteJidAlt);
  const from = phone ?? lid;
  if (!from) return undefined;

  const contact: IncomingContact = {
    ...(phone ? { wa_id: phone } : {}),
    ...(lid ? { user_id: lid } : {}),
    ...(message.pushName ? { profile: { name: message.pushName } } : {}),
  };
  const context = replyTo(content, type);

  return {
    event: 'messages',
    contacts: [contact],
    messages: [
      {
        id: key.id,
        from,
        timestamp: seconds(message.messageTimestamp),
        ...body(key.id, content, type),
        ...(context ? { context: { id: context } } : {}),
      },
    ],
  };
}

const DELIVERY_STATUSES: Partial<Record<proto.WebMessageInfo.Status, DeliveryStatus>> = {
  [proto.WebMessageInfo.Status.ERROR]: 'failed',
  [proto.WebMessageInfo.Status.SERVER_ACK]: 'sent',
  [proto.WebMessageInfo.Status.DELIVERY_ACK]: 'delivered',
  [proto.WebMessageInfo.Status.READ]: 'read',
  [proto.WebMessageInfo.Status.PLAYED]: 'read', // voice notes: played implies read
};

// Converts a receipt for one of the business's own 1:1 messages into a Chatwoot "statuses" event (WW-FR-23).
// One status per event: Chatwoot applies only the first status of each event.
export function normalizeStatus({ key, update }: WAMessageUpdate): StatusesEvent | undefined {
  const jid = key.remoteJid;
  if (!jid || !key.id || !key.fromMe || !isCustomerChat(jid) || update.status == null) return undefined;

  const status = DELIVERY_STATUSES[update.status];
  const recipient = phoneOf(jid) ?? phoneOf(key.remoteJidAlt) ?? lidOf(jid);
  if (!status || !recipient) return undefined;

  return { event: 'statuses', statuses: [{ id: key.id, status, recipient_id: recipient }] };
}
