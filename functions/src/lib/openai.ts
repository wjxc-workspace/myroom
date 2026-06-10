// OpenAI client + Responses API / Whisper wrappers (AI_proxy.md §4/§8).
//
// All text functions go through the Responses API (`/v1/responses`); Whisper
// stays on `/v1/audio/transcriptions`. Every call is retried 3× with
// exponential backoff and a per-request timeout, then mapped to an HttpsError
// (AI_proxy.md §8): OpenAI timeout → `deadline-exceeded`, OpenAI 5xx/429 after
// retries → `unavailable`, otherwise → `internal`.
import OpenAI from "openai";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import { MODELS } from "./config";

let _client: OpenAI | null = null;

function client(): OpenAI {
  if (_client) return _client;
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new HttpsError("internal", "OPENAI_API_KEY is not configured");
  }
  // maxRetries: 0 — we run our own retry loop so the timeout/backoff is explicit.
  _client = new OpenAI({ apiKey, maxRetries: 0 });
  return _client;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function isRetryable(err: unknown): boolean {
  if (err instanceof OpenAI.APIError) {
    const status = err.status ?? 0;
    return status === 429 || status === 408 || status >= 500;
  }
  const name = (err as { name?: string })?.name ?? "";
  return (
    name === "APIConnectionError" ||
    name === "APIConnectionTimeoutError" ||
    name === "AbortError"
  );
}

function toHttpsError(err: unknown): HttpsError {
  if (err instanceof HttpsError) return err;
  if (err instanceof OpenAI.APIError) {
    const status = err.status ?? 0;
    if (status === 408) {
      return new HttpsError("deadline-exceeded", "AI 服務逾時");
    }
    if (status === 429 || status >= 500) {
      return new HttpsError("unavailable", "AI 服務暫時無法使用");
    }
    return new HttpsError("internal", `OpenAI error (${status})`);
  }
  const name = (err as { name?: string })?.name ?? "";
  if (name === "APIConnectionTimeoutError" || name === "AbortError") {
    return new HttpsError("deadline-exceeded", "AI 服務逾時");
  }
  if (name === "APIConnectionError") {
    return new HttpsError("unavailable", "AI 服務暫時無法使用");
  }
  logger.error("OpenAI call failed", err);
  return new HttpsError("internal", "AI 內部錯誤");
}

/** Retry [fn] up to 3× with exponential backoff; rethrow as HttpsError. */
async function withRetry<T>(fn: () => Promise<T>): Promise<T> {
  const backoff = [400, 1000, 2500];
  let lastErr: unknown;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (!isRetryable(err) || attempt === 2) break;
      await sleep(backoff[attempt]);
    }
  }
  throw toHttpsError(lastErr);
}

// The Responses API request shape varies by call (tools, web_search,
// text.format, multimodal input), so we type the body loosely and let the
// callers build exact, spec-conformant params.
export type ResponsesParams = Record<string, unknown>;
export type OpenAIResponse = {
  output_text: string;
  output: Array<Record<string, unknown>>;
  id: string;
};

/** One Responses API call with retry + per-request timeout. */
export async function createResponse(
  params: ResponsesParams,
  timeoutMs: number
): Promise<OpenAIResponse> {
  return withRetry(async () => {
    const res = await client().responses.create(
      params as unknown as Parameters<OpenAI["responses"]["create"]>[0],
      { timeout: timeoutMs }
    );
    return res as unknown as OpenAIResponse;
  });
}

/** Whisper transcription (multipart). Returns the plain-text transcript. */
export async function transcribeAudio(
  bytes: Buffer,
  filename: string,
  timeoutMs: number
): Promise<string> {
  return withRetry(async () => {
    const file = await OpenAI.toFile(bytes, filename || "audio.m4a");
    const res = await client().audio.transcriptions.create(
      {
        model: MODELS.whisper,
        file,
        language: "zh",
        response_format: "text",
      },
      { timeout: timeoutMs }
    );
    // response_format:"text" → SDK returns the raw string.
    if (typeof res === "string") return res.trim();
    return ((res as { text?: string }).text ?? "").trim();
  });
}

/**
 * Tolerant JSON extraction: strips ```json fences and trims to the outermost
 * braces before parsing (the demo's `_extractJson`; firebase_port_extraction.md
 * §3.2). Returns null on failure so callers can fall back gracefully.
 */
export function extractJson<T = unknown>(text: string): T | null {
  let t = (text ?? "").trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    return JSON.parse(t) as T;
  } catch {
    return null;
  }
}
