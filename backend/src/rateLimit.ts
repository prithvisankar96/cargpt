/**
 * Fixed-window rate limiter keyed by user ID. State lives in memory, so it only
 * holds for a single server instance; move it to a shared store (Redis, Durable
 * Objects) before running more than one.
 */
export function createRateLimiter(limit: number, windowMs = 60_000, now: () => number = Date.now) {
  const windows = new Map<string, { start: number; count: number }>();

  return function allow(key: string): boolean {
    const t = now();
    const current = windows.get(key);
    if (!current || t - current.start >= windowMs) {
      windows.set(key, { start: t, count: 1 });
      return true;
    }
    if (current.count >= limit) {
      return false;
    }
    current.count += 1;
    return true;
  };
}
