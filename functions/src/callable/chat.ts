// chat (AI_proxy.md §2). Runs the full tool loop server-side (≤6 rounds),
// executing mutations via the Admin SDK. Messages are not persisted to Firestore;
// the client holds the thread in memory for the session only.
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { REGION } from "../lib/admin";
import { findNoteCat, loadNoteCats, loadTodoCats } from "../lib/categories";
import { LOOP_LIMIT_REPLY, MAX_CHAT_ROUNDS, MODELS, REQ_TIMEOUT } from "../lib/config";
import { buildContext } from "../lib/context";
import { todayKey } from "../lib/date";
import { createResponse, ResponsesParams } from "../lib/openai";
import { chatSystemPrompt } from "../lib/prompts";
import { enforceRateLimit } from "../lib/rateLimit";
import { buildChatTools, runToolCall, ToolContext } from "../lib/tools";
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

    const { message: rawMessage, previousResponseId } =
      req.data as { message?: string; previousResponseId?: string };
    const message = String(rawMessage ?? "").trim();
    if (!message) throw new HttpsError("invalid-argument", "訊息不可為空");

    const settings = await loadSettings(uid);
    const tz = settings.tz;
    const [todoCats, noteCats, contextSummary] = await Promise.all([
      loadTodoCats(uid),
      loadNoteCats(uid),
      buildContext(uid, tz),
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

    let reply = "";
    let prevId: string | undefined = previousResponseId || undefined;
    // Responses-API continuation: first turn sends the user message; each tool
    // round sends only the function_call_output items + previous_response_id.
    let nextInput: unknown = [{ role: "user", content: message }];

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
        const output = await runToolCall(c.name, c.arguments, toolCtx);
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

    return { reply, responseId: prevId ?? "" };
  }
);
