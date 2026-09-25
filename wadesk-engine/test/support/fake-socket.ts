import type { ConnectionState } from 'baileys';
import type { LinkMethod } from '../../src/sessions/types.js';
import type { SocketFactory, WaSocket } from '../../src/whatsapp/socket.js';

// In-memory stand-in for a Baileys socket; tests drive it with connection updates.
export class FakeSocket implements WaSocket {
  user: { id: string; lid?: string } | undefined;
  loggedOut = false;
  ended = false;
  pairingRequests: string[] = [];
  constructor(readonly linkMethod: LinkMethod) {}
  private connectionListeners: ((update: Partial<ConnectionState>) => void)[] = [];
  private credsListeners: (() => void)[] = [];

  onConnectionUpdate(listener: (update: Partial<ConnectionState>) => void): void {
    this.connectionListeners.push(listener);
  }

  onCredsUpdate(listener: () => void): void {
    this.credsListeners.push(listener);
  }

  requestPairingCode(phoneNumber: string): Promise<string> {
    this.pairingRequests.push(phoneNumber);
    return Promise.resolve(`CODE${String(this.pairingRequests.length).padStart(4, '0')}`);
  }

  logout(): Promise<void> {
    this.loggedOut = true;
    return Promise.resolve();
  }

  end(): void {
    this.ended = true;
  }

  update(update: Partial<ConnectionState>): void {
    for (const listener of this.connectionListeners) listener(update);
  }

  credsChanged(): void {
    for (const listener of this.credsListeners) listener();
  }

  open(phone: string): void {
    this.user = { id: `${phone}:7@s.whatsapp.net`, lid: '123456789:7@lid' };
    this.update({ connection: 'open' });
  }

  close(statusCode: number): void {
    this.update({ connection: 'close', lastDisconnect: { error: Object.assign(new Error('closed'), { output: { statusCode } }), date: new Date() } });
  }
}

export function fakeSocketFactory(): { factory: SocketFactory; sockets: FakeSocket[] } {
  const sockets: FakeSocket[] = [];
  const factory: SocketFactory = (_auth, _logger, linkMethod) => {
    const socket = new FakeSocket(linkMethod);
    sockets.push(socket);
    return socket;
  };
  return { factory, sockets };
}
