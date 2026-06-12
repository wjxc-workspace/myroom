// Callable auth + settings loading (AI_proxy.md §2); here we assert an authenticated user and
// load the `settings/app` singleton (selfIntro / rules / tz / autoEnrich).
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

import { db } from "../lib/admin";
import { DEFAULT_TZ } from "../lib/config";

export function requireUid(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "請先登入");
  return uid;
}

export interface UserSettings {
  selfIntro: string;
  rules: string;
  tz: string;
  autoEnrich: boolean;
}

export async function loadSettings(uid: string): Promise<UserSettings> {
  const snap = await db.doc(`users/${uid}/settings/app`).get();
  const d = snap.data() ?? {};
  return {
    selfIntro: (d.selfIntro as string | undefined) ?? "",
    rules: (d.rules as string | undefined) ?? "",
    tz: (d.tz as string | undefined) ?? DEFAULT_TZ,
    autoEnrich: (d.autoEnrich as boolean | undefined) ?? true,
  };
}
