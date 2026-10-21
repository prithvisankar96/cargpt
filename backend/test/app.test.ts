import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWTVerifyGetKey } from "jose";
import { beforeAll, describe, expect, it } from "vitest";
import { createApp } from "../src/app.js";
import { issueSessionToken } from "../src/auth.js";
import type { ChatMessage, ReplyEvent, ReplyStreamer } from "../src/claude.js";
import type { Config } from "../src/config.js";
import { createRateLimiter } from "../src/rateLimit.js";

const BUNDLE_ID = "com.example.cargpt";

const config: Config = {
  port: 0,
  appleBundleId: BUNDLE_ID,
  sessionSecret: new TextEncoder().encode("test-secret-that-is-at-least-32-chars"),
  chatRequestsPerMinute: 2,
};

let appleKeys: JWTVerifyGetKey;
let signAppleToken: (claims: { aud?: string; iss?: string; sub?: string }) => Promise<string>;

beforeAll(async () => {
  // A stand-in for Apple's signing key, published through a local JWKS.
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "test-key", alg: "RS256" };
  appleKeys = createLocalJWKSet({ keys: [jwk] });
  signAppleToken = ({ aud = BUNDLE_ID, iss = "https://appleid.apple.com", sub = "apple-user-1" }) =>
    new SignJWT()
      .setProtectedHeader({ alg: "RS256", kid: "test-key" })
      .setIssuer(iss)
      .setAudience(aud)
      .setSubject(sub)
      .setIssuedAt()
      .setExpirationTime("10m")
      .sign(privateKey);
});

function fakeStreamer(events: ReplyEvent[], seen: ChatMessage[][] = []): ReplyStreamer {
  return async function* (messages) {
    seen.push(messages);
    yield* events;
  };
}

function makeApp(streamReply: ReplyStreamer = fakeStreamer([])) {
  return createApp({ config, appleKeys, streamReply });
}

function postJSON(app: ReturnType<typeof makeApp>, path: string, body: unknown, token?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return app.request(path, { method: "POST", headers, body: JSON.stringify(body) });
}

function parseSSE(text: string) {
  return text
    .split("\n\n")
    .filter((chunk) => chunk.trim().length > 0)
    .map((chunk) => {
      const lines = chunk.split("\n");
      const event = lines.find((l) => l.startsWith("event:"))?.slice("event:".length).trim();
      const data = lines.find((l) => l.startsWith("data:"))?.slice("data:".length).trim();
      return { event, data: data ? JSON.parse(data) : undefined };
    });
}

describe("POST /v1/auth/apple", () => {
  it("issues a session token for a valid identity token", async () => {
    const res = await postJSON(makeApp(), "/v1/auth/apple", { identityToken: await signAppleToken({}) });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(typeof body.sessionToken).toBe("string");
    expect(body.expiresIn).toBeGreaterThan(0);
  });

  it("rejects a token issued for a different app", async () => {
    const res = await postJSON(makeApp(), "/v1/auth/apple", {
      identityToken: await signAppleToken({ aud: "com.someone.else" }),
    });
    expect(res.status).toBe(401);
  });

  it("rejects a token from the wrong issuer", async () => {
    const res = await postJSON(makeApp(), "/v1/auth/apple", {
      identityToken: await signAppleToken({ iss: "https://evil.example" }),
    });
    expect(res.status).toBe(401);
  });

  it("rejects a malformed body", async () => {
    const res = await postJSON(makeApp(), "/v1/auth/apple", { nope: true });
    expect(res.status).toBe(400);
  });
});

describe("POST /v1/chat", () => {
  const conversation = { messages: [{ role: "user", content: "How far is the moon?" }] };

  it("requires a session token", async () => {
    const res = await postJSON(makeApp(), "/v1/chat", conversation);
    expect(res.status).toBe(401);
  });

  it("rejects a forged session token", async () => {
    const forged = await issueSessionToken("someone", new TextEncoder().encode("x".repeat(40)));
    const res = await postJSON(makeApp(), "/v1/chat", conversation, forged);
    expect(res.status).toBe(401);
  });

  it("rejects a conversation that does not end with the user", async () => {
    const token = await issueSessionToken("user-a", config.sessionSecret);
    const res = await postJSON(
      makeApp(),
      "/v1/chat",
      { messages: [{ role: "user", content: "hi" }, { role: "assistant", content: "hello" }] },
      token,
    );
    expect(res.status).toBe(400);
  });

  it("streams text deltas and a done event", async () => {
    const seen: ChatMessage[][] = [];
    const app = makeApp(
      fakeStreamer(
        [
          { type: "text", text: "About two hundred " },
          { type: "text", text: "thirty nine thousand miles." },
          { type: "done", stopReason: "end_turn" },
        ],
        seen,
      ),
    );
    const token = await issueSessionToken("user-b", config.sessionSecret);
    const res = await postJSON(app, "/v1/chat", conversation, token);

    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/event-stream");
    expect(parseSSE(await res.text())).toEqual([
      { event: "text", data: { type: "text", text: "About two hundred " } },
      { event: "text", data: { type: "text", text: "thirty nine thousand miles." } },
      { event: "done", data: { type: "done", stopReason: "end_turn" } },
    ]);
    expect(seen).toEqual([conversation.messages]);
  });

  it("sends an error event when the upstream stream fails", async () => {
    const failing: ReplyStreamer = async function* () {
      yield { type: "text", text: "Partial" };
      throw new Error("upstream exploded");
    };
    const token = await issueSessionToken("user-c", config.sessionSecret);
    const res = await postJSON(makeApp(failing), "/v1/chat", conversation, token);
    const events = parseSSE(await res.text());
    expect(events.at(-1)).toEqual({ event: "error", data: { type: "error" } });
  });

  it("rate limits each user separately", async () => {
    const app = makeApp(fakeStreamer([{ type: "done", stopReason: "end_turn" }]));
    const tokenD = await issueSessionToken("user-d", config.sessionSecret);
    const tokenE = await issueSessionToken("user-e", config.sessionSecret);

    expect((await postJSON(app, "/v1/chat", conversation, tokenD)).status).toBe(200);
    expect((await postJSON(app, "/v1/chat", conversation, tokenD)).status).toBe(200);
    expect((await postJSON(app, "/v1/chat", conversation, tokenD)).status).toBe(429);
    expect((await postJSON(app, "/v1/chat", conversation, tokenE)).status).toBe(200);
  });
});

describe("createRateLimiter", () => {
  it("resets after the window passes", () => {
    let t = 0;
    const allow = createRateLimiter(1, 1_000, () => t);
    expect(allow("k")).toBe(true);
    expect(allow("k")).toBe(false);
    t = 1_000;
    expect(allow("k")).toBe(true);
  });
});
