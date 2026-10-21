import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { streamSSE } from "hono/streaming";
import type { JWTVerifyGetKey } from "jose";
import { z } from "zod";
import {
  issueSessionToken,
  SESSION_TTL_SECONDS,
  verifyAppleIdentityToken,
  verifySessionToken,
} from "./auth.js";
import type { ReplyStreamer } from "./claude.js";
import type { Config } from "./config.js";
import { createRateLimiter } from "./rateLimit.js";

export interface AppDeps {
  config: Config;
  appleKeys: JWTVerifyGetKey;
  streamReply: ReplyStreamer;
}

const AppleAuthRequest = z.object({
  identityToken: z.string().min(1),
});

const ChatRequest = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(["user", "assistant"]),
        content: z.string().min(1).max(8_000),
      }),
    )
    .min(1)
    .max(100)
    .refine((messages) => messages[0]?.role === "user" && messages.at(-1)?.role === "user", {
      message: "conversation must start and end with a user message",
    }),
});

type Env = { Variables: { userId: string } };

export function createApp({ config, appleKeys, streamReply }: AppDeps) {
  const app = new Hono<Env>();
  const allowChat = createRateLimiter(config.chatRequestsPerMinute);

  app.use("*", bodyLimit({ maxSize: 256 * 1024 }));

  app.get("/healthz", (c) => c.text("ok"));

  // Exchanges a Sign in with Apple identity token for a session token.
  app.post("/v1/auth/apple", async (c) => {
    const body = AppleAuthRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) {
      return c.json({ error: "invalid_request" }, 400);
    }
    let userId: string;
    try {
      userId = await verifyAppleIdentityToken(body.data.identityToken, config.appleBundleId, appleKeys);
    } catch {
      return c.json({ error: "invalid_identity_token" }, 401);
    }
    const sessionToken = await issueSessionToken(userId, config.sessionSecret);
    return c.json({ sessionToken, expiresIn: SESSION_TTL_SECONDS });
  });

  app.use("/v1/chat", async (c, next) => {
    const header = c.req.header("Authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
    try {
      c.set("userId", await verifySessionToken(token, config.sessionSecret));
    } catch {
      return c.json({ error: "unauthorized" }, 401);
    }
    await next();
  });

  // Streams one assistant reply as server-sent events: `text` deltas, then `done` or `error`.
  app.post("/v1/chat", async (c) => {
    const body = ChatRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) {
      return c.json({ error: "invalid_request" }, 400);
    }
    if (!allowChat(c.get("userId"))) {
      return c.json({ error: "rate_limited" }, 429);
    }

    return streamSSE(c, async (stream) => {
      const upstream = new AbortController();
      stream.onAbort(() => upstream.abort());
      try {
        for await (const event of streamReply(body.data.messages, upstream.signal)) {
          await stream.writeSSE({ event: event.type, data: JSON.stringify(event) });
        }
      } catch (err) {
        if (upstream.signal.aborted) {
          return;
        }
        console.error("chat stream failed", err);
        await stream.writeSSE({ event: "error", data: JSON.stringify({ type: "error" }) });
      }
    });
  });

  return app;
}
