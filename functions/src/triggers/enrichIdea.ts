// enrichIdea (AI_proxy.md §6). onCreate + on text-update of an idea doc. If
// `settings/app.autoEnrich`, set aiStatus=processing, call OpenAI (web search),
// then write aiSummary + links[] + aiStatus=completed; on failure aiStatus=error.
// Runs only when `text` changed and aiStatus != processing — so the function's
// own writes (which never change `text`) never re-trigger it.
//
// Path note: ideas live at users/{uid}/ideas/data/user_ideas/{id}
// (Firestore needs the intervening `data` doc; DataModel.md / Phase 1).
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";

import { REGION } from "../lib/admin";
import { MODELS, REQ_TIMEOUT, WEB_SEARCH_TOOL } from "../lib/config";
import { createResponse, extractJson } from "../lib/openai";
import { ENRICH_IDEA_SYSTEM } from "../lib/prompts";
import { loadSettings } from "../middleware/auth";

interface RawLink {
  title?: string;
  url?: string;
}

export const enrichIdea = onDocumentWritten(
  {
    document: "users/{uid}/ideas/data/user_ideas/{ideaId}",
    region: REGION,
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after || !after.exists) return; // deleted

    const data = after.data() ?? {};
    const text = ((data.text as string) ?? "").trim();
    const aiStatus = (data.aiStatus as string) ?? "none";
    if (!text || aiStatus === "processing") return;

    // Skip if `text` is unchanged on an update (only run on create or text edit).
    const before = event.data?.before;
    if (before?.exists) {
      const prevText = ((before.data()?.text as string) ?? "").trim();
      if (prevText === text) return;
    }

    const uid = event.params.uid as string;
    const settings = await loadSettings(uid);
    if (!settings.autoEnrich) return;

    await after.ref.update({ aiStatus: "processing" });
    try {
      const res = await createResponse(
        {
          model: MODELS.enrich,
          instructions: ENRICH_IDEA_SYSTEM,
          input: text,
          max_output_tokens: 300,
          tools: [WEB_SEARCH_TOOL],
        },
        REQ_TIMEOUT.enrich
      );
      const parsed =
        extractJson<{ summary?: string; links?: RawLink[] }>(res.output_text) ??
        {};
      const links = (parsed.links ?? [])
        .filter((l) => l && l.title && l.url)
        .slice(0, 3)
        .map((l) => ({ title: String(l.title), url: String(l.url) }));
      await after.ref.update({
        aiSummary: (parsed.summary ?? "").trim(),
        links,
        aiStatus: "completed",
      });
    } catch (err) {
      logger.error("enrichIdea failed", err);
      await after.ref.update({ aiStatus: "error" });
    }
  }
);
