export interface Config {
  port: number;
  /** The iOS app's bundle ID. Sign in with Apple tokens must be issued for it. */
  appleBundleId: string;
  /** HMAC key for the session tokens this server issues. */
  sessionSecret: Uint8Array;
  /** Chat requests allowed per user per minute. */
  chatRequestsPerMinute: number;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const appleBundleId = env.APPLE_BUNDLE_ID;
  if (!appleBundleId) {
    throw new Error("APPLE_BUNDLE_ID is required");
  }

  const secret = env.SESSION_SECRET ?? "";
  if (secret.length < 32) {
    throw new Error("SESSION_SECRET must be at least 32 characters");
  }

  return {
    port: Number(env.PORT ?? 8787),
    appleBundleId,
    sessionSecret: new TextEncoder().encode(secret),
    chatRequestsPerMinute: Number(env.CHAT_REQUESTS_PER_MINUTE ?? 20),
  };
}
