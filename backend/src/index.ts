import Anthropic from "@anthropic-ai/sdk";
import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { appleSigningKeys } from "./auth.js";
import { claudeReplyStreamer } from "./claude.js";
import { loadConfig } from "./config.js";

const config = loadConfig();

const app = createApp({
  config,
  appleKeys: appleSigningKeys,
  // Reads ANTHROPIC_API_KEY from the environment. The key never leaves this server.
  streamReply: claudeReplyStreamer(new Anthropic()),
});

serve({ fetch: app.fetch, port: config.port }, (info) => {
  console.log(`cargpt backend listening on :${info.port}`);
});
