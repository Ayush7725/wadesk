import { describe, expect, it } from 'vitest';
import { RateLimiter } from '../../src/sessions/rate-limiter.js';

describe('RateLimiter', () => {
  it('allows the configured number per rolling minute, then reports the wait', () => {
    let now = 1_000_000;
    const limiter = new RateLimiter(2, () => now);

    expect(limiter.take()).toBe(0);
    now += 10_000;
    expect(limiter.take()).toBe(0);
    expect(limiter.take()).toBe(50_000); // the first send leaves the window in 50 s

    now += 50_000;
    expect(limiter.take()).toBe(0);
  });
});
