// AI model ids, per-OpenAI-request timeouts, and shared constants
// (AI_proxy.md §1/§4/§5). The Cloud Function wall-clock `timeoutSeconds` is set
// separately on each function (AI_proxy.md §7).

/** OpenAI model ids. The demo's split (`-search-preview`, DALL-E) collapses to
 *  gpt-4o-mini on the Responses API, with `web_search` as a tool. */
export const MODELS = {
  chat: "gpt-4o-mini",
  classify: "gpt-4o",
  recommend: "gpt-4o-mini",
  enrich: "gpt-4o-mini",
  eraInsight: "gpt-4o-mini",
  noteClassify: "gpt-4o-mini",
  findNotes: "gpt-4o-mini",
  whisper: "whisper-1",
} as const;

/** Per-OpenAI-request HTTP timeout in ms (each call retried 3×; AI_proxy.md §5/§8). */
export const REQ_TIMEOUT = {
  chat: 30_000,
  classify: 30_000,
  recommend: 30_000,
  eraInsight: 20_000,
  transcribe: 60_000,
  enrich: 20_000,
  noteClassify: 15_000,
  findNotes: 20_000,
} as const;

/** `user_location` for web-search calls (AI_proxy.md §4). */
export const USER_LOCATION = {
  type: "approximate",
  country: "TW",
  city: "Taipei",
  region: "Taipei",
  timezone: "Asia/Taipei",
} as const;

/**
 * Hosted web-search tool for the Responses API (`enrichIdea` + `fetchRecommendations`).
 * The guide names this `web_search`, but the pinned `openai@4.104` SDK / the
 * gpt-4o-mini Responses endpoint only accept `web_search_preview` (a bare
 * `web_search` is rejected with a 400). Use the SDK-supported type.
 */
export const WEB_SEARCH_TOOL = {
  type: "web_search_preview",
  user_location: USER_LOCATION,
} as const;

/** Default IANA tz when `settings/app.tz` is unset (AI_proxy.md §2). */
export const DEFAULT_TZ = "Asia/Taipei";

/** Fixed id of the `無分類` sentinel category (both category types). */
export const UNDEFINED_CAT = "undefined";

/** AI callable cap: 60 invocations / user / hour (AI_proxy.md §9). */
export const RATE_LIMIT = 60;
export const RATE_WINDOW_MS = 60 * 60 * 1000;

/** Canned reply when the chat tool loop exhausts its rounds (AI_proxy.md §2). */
export const LOOP_LIMIT_REPLY = "（AI 運算超出輪數限制，請再試）";
export const MAX_CHAT_ROUNDS = 6;
