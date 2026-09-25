import { Writable } from 'node:stream';
import { pino } from 'pino';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { guardConsole } from '../../src/logging/console-guard.js';

describe('guardConsole', () => {
  const original = { ...console };
  let lines: string[];

  beforeEach(() => {
    lines = [];
    const sink = new Writable({
      write(chunk: Buffer, _encoding, done) {
        lines.push(chunk.toString());
        done();
      },
    });
    guardConsole(pino({ level: 'debug' }, sink));
  });

  afterEach(() => {
    Object.assign(console, original);
  });

  it('never writes objects such as Signal session records, only the text', () => {
    const session = { currentRatchet: { rootKey: Buffer.from('ROOT-KEY-SECRET'), ephemeralKeyPair: { privKey: Buffer.from('PRIV') } } };

    console.info('Closing session:', session);

    expect(lines).toHaveLength(1);
    expect(lines[0]).toContain('Closing session:');
    expect(lines[0]).not.toMatch(/ROOT-KEY-SECRET|privKey|rootKey|PRIV/);
  });

  it('keeps library warnings and errors at their level', () => {
    console.warn('Closing open session in favor of incoming prekey bundle');
    console.error('Session error:' + String(new Error('Bad MAC')), 'stack-trace-object');

    const [warning, error] = lines.map((line) => JSON.parse(line) as { level: number; msg: string; component: string });
    expect(warning).toMatchObject({ level: 40, component: 'library', msg: 'Closing open session in favor of incoming prekey bundle' });
    expect(error).toMatchObject({ level: 50, msg: 'Session error:Error: Bad MAC stack-trace-object' });
  });

  it('drops calls that carry no text at all', () => {
    console.log({ privKey: Buffer.from('x') });

    expect(lines).toEqual([]);
  });
});
