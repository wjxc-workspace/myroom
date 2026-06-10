// Per-user AI rate limit (AI_proxy.md §9). Fixed 1-hour window counter at
// `users/{uid}/_internal/rateLimit` ({windowStart, count}), updated in a
// transaction at the start of each AI callable. The `_internal` subtree is
// fn-only (denied to clients in Security.md).
import { HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "./admin";
import { RATE_LIMIT, RATE_WINDOW_MS } from "./config";

export async function enforceRateLimit(uid: string): Promise<void> {
  const ref = db.doc(`users/${uid}/_internal/rateLimit`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const data = snap.exists ? snap.data() : undefined;
    const windowStart =
      (data?.windowStart as Timestamp | undefined)?.toMillis() ?? 0;
    const count = (data?.count as number | undefined) ?? 0;

    if (!data || now - windowStart >= RATE_WINDOW_MS) {
      tx.set(ref, { windowStart: Timestamp.fromMillis(now), count: 1 });
      return;
    }
    if (count >= RATE_LIMIT) {
      throw new HttpsError("resource-exhausted", "AI 使用次數已達上限，請稍後再試");
    }
    tx.update(ref, { count: count + 1 });
  });
}
