// chat (AI_proxy.md §2). Runs the full tool loop server-side (≤6 rounds),
// executing mutations via the Admin SDK, then appends the user + assistant turns
// to chat_messages. The client only reads its chat_messages stream; the UI
// updates reactively from the writes the tools make.
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";

import { db, REGION } from "../lib/admin";
import { findNoteCat, loadNoteCats, loadTodoCats } from "../lib/categories";
import {
  CHAT_HISTORY_LIMIT,
  LOOP_LIMIT_REPLY,
  MAX_CHAT_ROUNDS,
  MODELS,
  REQ_TIMEOUT,
} from "../lib/config";
import { buildContext } from "../lib/context";
import { todayKey } from "../lib/date";
import { createResponse, ResponsesParams } from "../lib/openai";
import { chatSystemPrompt } from "../lib/prompts";
import { enforceRateLimit } from "../lib/rateLimit";
import { buildChatTools, isWriteTool, runToolCall, ToolContext } from "../lib/tools";
import { loadSettings, requireUid } from "../middleware/auth";

interface FunctionCall {
  name: string;
  arguments: string;
  call_id: string;
}

function functionCalls(output: Array<Record<string, unknown>>): FunctionCall[] {
  return output
    .filter((o) => o.type === "function_call")
    .map((o) => ({
      name: String(o.name ?? ""),
      arguments: String(o.arguments ?? ""),
      call_id: String(o.call_id ?? ""),
    }));
}

interface HistoryTurn {
  role: "user" | "assistant";
  content: string;
}

/** Loads the most recent chat turns (chronological) to seed the model input so
 *  it remembers the conversation across separate `chat` calls. */
async function loadHistory(
  uid: string,
  limit: number
): Promise<HistoryTurn[]> {
  const snap = await db
    .collection(`users/${uid}/chat_messages`)
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();
  return snap.docs
    .map((d) => ({
      role: String(d.get("role") ?? "assistant"),
      content: String(d.get("content") ?? ""),
    }))
    .filter(
      (m): m is HistoryTurn =>
        m.content.length > 0 && (m.role === "user" || m.role === "assistant")
    )
    .reverse();
}

export const chat = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "512MiB",
    secrets: ["OPENAI_API_KEY"],
  },
  async (req) => {
    const uid = requireUid(req);
    await enforceRateLimit(uid);

    const message = String((req.data as { message?: string })?.message ?? "").trim();
    if (!message) throw new HttpsError("invalid-argument", "訊息不可為空");

    const settings = await loadSettings(uid);
    const tz = settings.tz;
    // Loaded before the current user turn is appended below, so `history` holds
    // only prior conversation (the new message is added explicitly to the input).
    const [todoCats, noteCats, contextSummary, history] = await Promise.all([
      loadTodoCats(uid),
      loadNoteCats(uid),
      buildContext(uid, tz),
      loadHistory(uid, CHAT_HISTORY_LIMIT),
    ]);

    const toolCtx: ToolContext = {
      uid,
      tz,
      todoCats,
      undefinedNoteCat: findNoteCat("undefined", noteCats),
    };

    const instructions = chatSystemPrompt({
      contextSummary,
      selfIntro: settings.selfIntro,
      rules: settings.rules,
      today: todayKey(tz),
    });
    const tools = buildChatTools(todoCats);

    // Append the user turn first so it shows in the stream while the AI runs and
    // is guaranteed to sort before the assistant turn (distinct serverTs).
    const col = db.collection(`users/${uid}/chat_messages`);
    await col.add({
      role: "user",
      content: message,
      createdAt: FieldValue.serverTimestamp(),
    });

    let reply = "";
    let prevId: string | undefined;
    // Write tools are NOT executed here: each add_*/delete_* call is captured as
    // a proposed action and returned to the client, which shows a confirm card
    // and only applies them (via `applyChatActions`) once the user accepts.
    const proposed: { name: string; arguments: string }[] = [];
    // Responses-API continuation: the first turn sends the recent history + the
    // new user message; each tool round then sends only the function_call_output
    // items + previous_response_id (which carries that first input forward).
    let nextInput: unknown = [
      ...history.map((m) => ({ role: m.role, content: m.content })),
      { role: "user", content: message },
    ];

    for (let round = 0; round < MAX_CHAT_ROUNDS; round++) {
      const params: ResponsesParams = {
        model: MODELS.chat,
        instructions,
        input: nextInput,
        tools,
        tool_choice: "auto",
        temperature: 0.7,
        max_output_tokens: 600,
      };
      if (prevId) params.previous_response_id = prevId;

      const res = await createResponse(params, REQ_TIMEOUT.chat);
      prevId = res.id;

      const calls = functionCalls(res.output);
      if (calls.length === 0) {
        reply = res.output_text.trim() || "（無回應）";
        break;
      }

      const outputs: unknown[] = [];
      for (const c of calls) {
        // Defer mutations for user confirmation; run read tools (list_*) live.
        const output = isWriteTool(c.name)
          ? (proposed.push({ name: c.name, arguments: c.arguments }),
            "（已暫存此變更，正等待使用者點擊確認；請勿重複呼叫，僅需用一句話告知準備了哪些變更並請使用者確認）")
          : await runToolCall(c.name, c.arguments, toolCtx);
        outputs.push({
          type: "function_call_output",
          call_id: c.call_id,
          output,
        });
      }
      nextInput = outputs;

      // Loop guard: on exhaustion return the fixed reply with no extra call.
      if (round === MAX_CHAT_ROUNDS - 1) reply = LOOP_LIMIT_REPLY;
    }
    if (!reply) reply = LOOP_LIMIT_REPLY;

    // Append the assistant turn (single flat thread; createdAt = serverTs).
    await col.add({
      role: "assistant",
      content: reply,
      createdAt: FieldValue.serverTimestamp(),
    });

    // proposed (if any) drives the client confirm card; the writes only happen
    // once the user accepts and the client calls `applyChatActions`.
    return { reply, proposedActions: proposed };
  }
);
