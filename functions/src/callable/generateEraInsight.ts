// generateEraInsight (AI_proxy.md §5). Stateless reflective-text generator;
// routing (which era / recap the text belongs to) is decided by the caller.
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { REGION } from "../lib/admin";
import { MODELS, REQ_TIMEOUT } from "../lib/config";
import { createResponse } from "../lib/openai";
import { ERA_INSIGHT_SYSTEM, eraInsightUser } from "../lib/prompts";
import { enforceRateLimit } from "../lib/rateLimit";
import { requireUid } from "../middleware/auth";

export const generateEraInsight = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: ["OPENAI_API_KEY"],
  },
  async (req) => {
    const uid = requireUid(req);
    await enforceRateLimit(uid);

    const data = (req.data ?? {}) as { eraLabel?: string; dataSummary?: string };
    const eraLabel = (data.eraLabel ?? "").trim() || "回顧";
    const dataSummary = data.dataSummary ?? "";
    if (!dataSummary.trim()) {
      throw new HttpsError("invalid-argument", "缺少資料摘要");
    }

    const res = await createResponse(
      {
        model: MODELS.eraInsight,
        instructions: ERA_INSIGHT_SYSTEM,
        input: eraInsightUser(eraLabel, dataSummary),
        temperature: 0.78,
        max_output_tokens: 120,
      },
      REQ_TIMEOUT.eraInsight
    );

    return { text: res.output_text.trim() };
  }
);
