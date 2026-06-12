// exportAchievement (AI_proxy.md §5, Storage.md §6). Server render (no OpenAI):
// renders one era (past/current/future) of an achievement to an SVG graphic,
// uploads it, and writes the matching `{era}ExportStoragePath`.
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { db, REGION } from "../lib/admin";
import { renderAchievementExport } from "../lib/render";
import { requireUid } from "../middleware/auth";

const ERA_LABEL: Record<string, string> = {
  past: "過去",
  current: "現在",
  future: "未來",
};

export const exportAchievement = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (req) => {
    const uid = requireUid(req);
    const data = (req.data ?? {}) as { achievementId?: string; era?: string };
    const achievementId = String(data.achievementId ?? "");
    const era = String(data.era ?? "");
    if (!achievementId) {
      throw new HttpsError("invalid-argument", "缺少 achievementId");
    }
    if (era !== "past" && era !== "current" && era !== "future") {
      throw new HttpsError("invalid-argument", "era 必須是 past/current/future");
    }

    const ref = db.doc(`users/${uid}/achievements/${achievementId}`);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "找不到階段回顧");

    const content = (snap.get(`${era}Content`) as string) ?? "";
    const storagePath = await renderAchievementExport(
      uid,
      achievementId,
      era,
      ERA_LABEL[era],
      content
    );
    await ref.update({ [`${era}ExportStoragePath`]: storagePath });
    return { storagePath };
  }
);
