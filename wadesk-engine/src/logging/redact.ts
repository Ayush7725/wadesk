// Phone numbers and WhatsApp IDs (phone JIDs, privacy IDs) are personal data: logs keep only the last
// 4 digits (docs/wadesk/02-architecture.md §6, WW-NFR-07). Message ids are hex and never match.
const LONG_DIGIT_RUN = /\b\d{4,16}(\d{4})\b/g;

export const maskDigits = (text: string): string => text.replace(LONG_DIGIT_RUN, (_match, last: string) => `****${last}`);

const MAX_DEPTH = 8;

const isPlainObject = (value: object): boolean => {
  const prototype = Object.getPrototypeOf(value) as unknown;
  return prototype === Object.prototype || prototype === null;
};

// Masks strings inside a log record's plain objects and arrays. Class instances (requests, sockets,
// errors) are left to pino's serializers: they can be circular and huge.
export function maskRecord(value: unknown, depth = 0, seen = new WeakSet<object>()): unknown {
  if (typeof value === 'string') return maskDigits(value);
  if (!value || typeof value !== 'object' || depth >= MAX_DEPTH || seen.has(value)) return value;
  if (!Array.isArray(value) && !isPlainObject(value)) return value;

  seen.add(value);
  if (Array.isArray(value)) return value.map((entry) => maskRecord(entry, depth + 1, seen));
  return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, maskRecord(entry, depth + 1, seen)]));
}

// Messages Baileys logs as errors/warnings during normal operation, e.g. WhatsApp's routine
// "restart after linking" (stream error 515). Dropped so real problems stand out.
export function isBenignLibraryNoise(args: unknown[]): boolean {
  const [first, second] = args;
  const message = typeof first === 'string' ? first : typeof second === 'string' ? second : '';
  if (message.startsWith('no name present, ignoring presence update request')) return true;
  const node = (first as { fullErrorNode?: { attrs?: { code?: string } } } | undefined)?.fullErrorNode;
  return message === 'stream errored out' && node?.attrs?.code === '515';
}
