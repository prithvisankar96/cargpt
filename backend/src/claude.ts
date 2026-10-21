import type Anthropic from "@anthropic-ai/sdk";
import { SYSTEM_PROMPT } from "./prompt.js";

export const MODEL = "claude-opus-5-5";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export type ReplyEvent =
  | { type: "text"; text: string }
  | { type: "done"; stopReason: string | null };

/** Streams one assistant reply. Swapped for a fake in tests. */
export type ReplyStreamer = (messages: ChatMessage[], signal: AbortSignal) => AsyncIterable<ReplyEvent>;

export function claudeReplyStreamer(client: Anthropic): ReplyStreamer {
  return async function* (messages, signal) {
    const stream = client.beta.messages.stream(
      {
        model: MODEL,
        // Thinking counts toward this limit, so leave room beyond the short spoken reply.
        max_tokens: 8192,
        system: SYSTEM_PROMPT,
        // Low effort keeps thinking short, which is what time-to-first-word depends on.
        output_config: { effort: "low" },
        // Caches the conversation so far, so later turns start faster.
        cache_control: { type: "ephemeral" },
        // If a safety classifier declines, retry on Anthropic's recommended model inside this same stream.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        // History is text only. No thinking blocks are replayed, so earlier turns never need
        // to be byte-identical; if tools are added later, keep tool-loop turns' blocks verbatim.
        messages,
      },
      { signal },
    );

    for await (const event of stream) {
      if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
        yield { type: "text", text: event.delta.text };
      }
    }

    const final = await stream.finalMessage();
    yield { type: "done", stopReason: final.stop_reason };
  };
}
