// applyChatActions — applies the write tools the user approved on a chat confirm
// card. `chat` defers every add_*/delete_* call into `proposedActions` instead of
// running it; the client shows a confirm card and, on accept, sends those actions
// here verbatim. We re-use the same tool executors (`runToolCall`) so there is no
// duplicated mutation logic, then append an assistant turn recording the result.
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";

import { db, REGION } from "../lib/admin";
import { findNoteCat, loadNoteCats, loadTodoCats } from "../lib/categories";
import { isWriteTool, runToolCall, ToolContext } from "../lib/tools";
import { loadSettings, requireUid } from "../middleware/auth";

interface ProposedAction {
  name: string;
  arguments: string;
}

export const applyChatActions = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (req) => {
    const uid = requireUid(req);

    const raw = (req.data as { actions?: unknown })?.actions;
    const actions: ProposedAction[] = Array.isArray(raw)
      ? raw.map((a) => ({
          name: String((a as ProposedAction)?.name ?? ""),
          arguments: String((a as ProposedAction)?.arguments ?? ""),
        }))
      : [];
    if (actions.length === 0) {
      throw new HttpsError("invalid-argument", "沒有可套用的變更");
    }

    const settings = await loadSettings(uid);
    const tz = settings.tz;
    const [todoCats, noteCats] = await Promise.all([
      loadTodoCats(uid),
      loadNoteCats(uid),
    ]);
    const toolCtx: ToolContext = {
      uid,
      tz,
      todoCats,
      undefinedNoteCat: findNoteCat("undefined", noteCats),
    };

    const results: string[] = [];
    for (const a of actions) {
      // Guard: only the confirmed mutating tools may run here (never list_*).
      if (!isWriteTool(a.name)) {
        results.push(`已略過未授權的動作：${a.name}`);
        continue;
      }
      results.push(await runToolCall(a.name, a.arguments, toolCtx));
    }

    // Record the outcome as an assistant turn so the thread reflects what ran.
    await db.collection(`users/${uid}/chat_messages`).add({
      role: "assistant",
      content: results.join("\n"),
      createdAt: FieldValue.serverTimestamp(),
    });

    return { results };
  }
);
