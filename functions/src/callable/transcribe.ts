// transcribe (AI_proxy.md §5). Whisper transcription, called by Smart Add for
// audio before classifyMultiInput. The client stores the transcript in the
// note's extracted_texts.
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { REGION } from "../lib/admin";
import { REQ_TIMEOUT } from "../lib/config";
import { transcribeAudio } from "../lib/openai";
import { enforceRateLimit } from "../lib/rateLimit";
import { requireUid } from "../middleware/auth";

export const transcribe = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "512MiB",
    secrets: ["OPENAI_API_KEY"],
  },
  async (req) => {
    const uid = requireUid(req);
    await enforceRateLimit(uid);

    const data = (req.data ?? {}) as { audioB64?: string; filename?: string };
    if (!data.audioB64) {
      throw new HttpsError("invalid-argument", "缺少音訊資料");
    }
    const bytes = Buffer.from(data.audioB64, "base64");
    const transcript = await transcribeAudio(
      bytes,
      data.filename ?? "audio.m4a",
      REQ_TIMEOUT.transcribe
    );
    return { transcript };
  }
);
