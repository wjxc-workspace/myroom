// fetchRecommendations (AI_proxy.md §5). Web-search-backed resource suggestions
// from up to 5 idea texts. Items whose title is empty are filtered.
import { onCall } from "firebase-functions/v2/https";

import { REGION } from "../lib/admin";
import { MODELS, REQ_TIMEOUT, WEB_SEARCH_TOOL } from "../lib/config";
import { createResponse, extractJson } from "../lib/openai";
import { RECOMMEND_SYSTEM } from "../lib/prompts";
import { enforceRateLimit } from "../lib/rateLimit";
import { requireUid } from "../middleware/auth";

interface RawResource {
  title?: string;
  type?: string;
  desc?: string;
  description?: string;
  url?: string;
}

export const fetchRecommendations = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: ["OPENAI_API_KEY"],
  },
  async (req) => {
    const uid = requireUid(req);
    await enforceRateLimit(uid);

    const data = (req.data ?? {}) as { ideaTexts?: string[] };
    const texts = (data.ideaTexts ?? [])
      .filter((t): t is string => typeof t === "string" && t.trim().length > 0)
      .slice(0, 5);
    if (texts.length === 0) return { resources: [] };

    const userContent =
      "我的靈感清單：\n" + texts.map((t, i) => `${i + 1}. ${t}`).join("\n");

    const res = await createResponse(
      {
        model: MODELS.recommend,
        instructions: RECOMMEND_SYSTEM,
        input: userContent,
        max_output_tokens: 600,
        tools: [WEB_SEARCH_TOOL],
      },
      REQ_TIMEOUT.recommend
    );

    const parsed =
      extractJson<{ resources?: RawResource[] }>(res.output_text) ?? {};
    const resources = (parsed.resources ?? [])
      .filter((r) => r && typeof r.title === "string" && r.title.trim())
      .map((r) => ({
        title: (r.title ?? "").trim(),
        type: (r.type ?? "").trim(),
        description: (r.description ?? r.desc ?? "").trim(),
        url: (r.url ?? "").trim(),
      }));

    return { resources };
  }
);
