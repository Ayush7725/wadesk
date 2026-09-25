// Sliding one-minute window of sends per WhatsApp Web number (SAFE-FR-03). Plain throughput control:
// no randomised delays or other behaviour meant to disguise automation (ADR-0006).
export class RateLimiter {
  private readonly sent: number[] = [];

  constructor(
    private readonly perMinute: number,
    private readonly now: () => number = Date.now,
  ) {}

  // Records a send and returns 0, or returns how many ms until a send is allowed.
  take(): number {
    const time = this.now();
    while (this.sent.length > 0 && (this.sent[0] ?? 0) <= time - 60_000) this.sent.shift();
    if (this.sent.length >= this.perMinute) return (this.sent[0] ?? time) + 60_000 - time;
    this.sent.push(time);
    return 0;
  }
}
