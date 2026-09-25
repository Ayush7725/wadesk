import makeWASocket, { makeCacheableSignalKeyStore, type AuthenticationState, type ConnectionState } from 'baileys';
import type { Logger } from 'pino';

// The only module that creates Baileys sockets. Everything else depends on WaSocket, so tests can use a fake
// and Baileys upgrades stay contained here (ADR-0002).
export interface WaSocket {
  readonly user?: { id: string; lid?: string | undefined } | undefined;
  onConnectionUpdate(listener: (update: Partial<ConnectionState>) => void): void;
  onCredsUpdate(listener: () => void): void;
  requestPairingCode(phoneNumber: string): Promise<string>;
  logout(): Promise<void>;
  end(): void;
}

export type SocketFactory = (auth: AuthenticationState, logger: Logger) => WaSocket;

// Honest device name: the business sees "WaDesk" under Linked devices on the phone.
const BROWSER: [string, string, string] = ['WaDesk', 'Chrome', '1.0'];

export const createBaileysSocket: SocketFactory = (auth, logger) => {
  const socket = makeWASocket({
    auth: { creds: auth.creds, keys: makeCacheableSignalKeyStore(auth.keys, logger) },
    logger,
    browser: BROWSER,
    markOnlineOnConnect: false,
    syncFullHistory: false,
  });

  return {
    get user() {
      return socket.user;
    },
    onConnectionUpdate: (listener) => socket.ev.on('connection.update', listener),
    onCredsUpdate: (listener) => socket.ev.on('creds.update', listener),
    requestPairingCode: (phoneNumber) => socket.requestPairingCode(phoneNumber),
    logout: () => socket.logout(),
    end: () => {
      void socket.end(undefined);
    },
  };
};
