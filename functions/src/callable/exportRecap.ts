// exportRecap (AI_proxy.md §5, Storage.md §6). Server render (no OpenAI): renders
// the recap's title + content to an SVG graphic, uploads it, and writes
// `exportStoragePath` via the Admin SDK. Carries no OPENAI_API_KEY secret.
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { db, REGION } from "../lib/admin";
import { renderRecapExport } from "../lib/render";
import { requireUid } from "../middleware/auth";

export const exportRecap = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (req) => {
    const uid = requireUid(req);
    const recapId = String((req.data as { recapId?: string })?.recapId ?? "");
    if (!recapId) throw new HttpsError("invalid-argument", "缺少 recapId");

    const ref = db.doc(`users/${uid}/recaps/${recapId}`);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "找不到回顧");

    const storagePath = await renderRecapExport(
      uid,
      recapId,
      (snap.get("title") as string) ?? "",
      (snap.get("content") as string) ?? ""
    );
    await ref.update({ exportStoragePath: storagePath });
    return { storagePath };
  }
);
