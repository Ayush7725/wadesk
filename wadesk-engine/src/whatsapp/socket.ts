import makeWASocket, {
  downloadMediaMessage,
  makeCacheableSignalKeyStore,
  type AnyMessageContent,
  type AuthenticationState,
  type ConnectionState,
  type MessageUpsertType,
  type MiscMessageGenerationOptions,
  type WAMessage,
} from 'baileys';
import type { Readable } from 'node:stream';
import type { Logger } from 'pino';
import type { LinkMethod } from '../sessions/types.js';

// The only module that creates Baileys sockets. Everything else depends on WaSocket, so tests can use a fake
// and Baileys upgrades stay contained here (ADR-0002).
export interface WaSocket {
  readonly user?: { id: string; lid?: string | undefined } | undefined;
  onConnectionUpdate(listener: (update: Partial<ConnectionState>) => void): void;
  onCredsUpdate(listener: () => void): void;
  onMessagesUpsert(listener: (messages: WAMessage[], type: MessageUpsertType) => void): void;
  // Downloads and decrypts a message's media; asks the phone to re-upload expired media.
  downloadMedia(message: WAMessage): Promise<Readable>;
  sendMessage(jid: string, content: AnyMessageContent, options?: MiscMessageGenerationOptions): Promise<WAMessage | undefined>;
  requestPairingCode(phoneNumber: string): Promise<string>;
  logout(): Promise<void>;
  end(): void;
}

export type SocketFactory = (auth: AuthenticationState, logger: Logger, linkMethod: LinkMethod) => WaSocket;

// Device label shown under Linked devices on the business's phone (ADR-0007). QR links show "WaDesk".
// WhatsApp's pairing-code flow rejects custom labels, so code links use a standard browser label;
// the setup screen tells the admin which name to expect.
const BROWSERS: Record<LinkMethod, [string, string, string]> = {
  qr: ['WaDesk', 'Chrome', '1.0'],
  code: ['Ubuntu', 'Chrome', '22.04.4'],
};

export const createBaileysSocket: SocketFactory = (auth, logger, linkMethod) => {
  const socket = makeWASocket({
    auth: { creds: auth.creds, keys: makeCacheableSignalKeyStore(auth.keys, logger) },
    logger,
    browser: BROWSERS[linkMethod],
    markOnlineOnConnect: false,
    syncFullHistory: false,
  });

  return {
    get user() {
      return socket.user;
    },
    onConnectionUpdate: (listener) => socket.ev.on('connection.update', listener),
    onCredsUpdate: (listener) => socket.ev.on('creds.update', listener),
    onMessagesUpsert: (listener) =>
      socket.ev.on('messages.upsert', ({ messages, type }) => {
        listener(messages, type);
      }),
    sendMessage: (jid, content, options) => socket.sendMessage(jid, content, options),
    downloadMedia: (message) =>
      downloadMediaMessage(message, 'stream', {}, { logger, reuploadRequest: socket.updateMediaMessage }),
    requestPairingCode: (phoneNumber) => socket.requestPairingCode(phoneNumber),
    logout: () => socket.logout(),
    end: () => {
      void socket.end(undefined);
    },
  };
};
