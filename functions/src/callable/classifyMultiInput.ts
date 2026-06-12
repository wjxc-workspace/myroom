// classifyMultiInput (AI_proxy.md §5 + §4a). Multimodal classification of a
// Smart Add submission into the five item types (todo / todo_with_time / idea /
// note / recap). Categories are injected as {id,label} once before the loop;
// the model returns ids, which we validate. The returned items are normalized
// for the client (resolved category ids, filtered/deduped attachment indices,
// year/month defaulted to the current date).
import { onCall } from "firebase-functions/v2/https";

import { REGION } from "../lib/admin";
import {
  loadNoteCats,
  loadTodoCats,
  toOptions,
  validateCatId,
} from "../lib/categories";
import { MODELS, REQ_TIMEOUT } from "../lib/config";
import { todayKey } from "../lib/date";
import { createResponse, extractJson } from "../lib/openai";
import { classifyMultiSystemPrompt } from "../lib/prompts";
import { enforceRateLimit } from "../lib/rateLimit";
import { CLASSIFY_MULTI_SCHEMA, jsonFormat } from "../lib/schemas";
import { loadSettings, requireUid } from "../middleware/auth";

interface AttachmentRef {
  i: number;
  type: string;
  name: string;
}
interface RawItem {
  type?: string;
  text?: string;
  cat?: string;
  start_year?: number | null;
  start_month?: number | null;
  start_day?: number | null;
  start_hour?: number | null;
  start_min?: number | null;
  end_year?: number | null;
  end_month?: number | null;
  end_day?: number | null;
  end_hour?: number | null;
  end_min?: number | null;
  date_key?: string | null;
  note_cat?: string | null;
  content?: string | null;
  attachment_indices?: number[] | null;
  title?: string | null;
  description?: string | null;
}

const s = (v: unknown): string => (typeof v === "string" ? v : "");
const n = (v: unknown, d: number): number =>
  typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : d;

export const classifyMultiInput = onCall(
  {
    region: REGION,
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: ["OPENAI_API_KEY"],
  },
  async (req) => {
    const uid = requireUid(req);
    await enforceRateLimit(uid);

    const data = (req.data ?? {}) as {
      text?: string;
      images?: string[];
      fileText?: string;
      attachments?: AttachmentRef[];
      userSpecifiedCat?: string;
    };

    const { tz } = await loadSettings(uid);
    const today = todayKey(tz);
    const [todoCats, noteCats] = await Promise.all([
      loadTodoCats(uid),
      loadNoteCats(uid),
    ]);

    const system = classifyMultiSystemPrompt({
      today,
      todoCats: toOptions(todoCats),
      noteCats: toOptions(noteCats),
      userSpecifiedCat: data.userSpecifiedCat ?? "",
    });

    // Combined text + attachment manifest, then the base64 images.
    const attachments = data.attachments ?? [];
    let combined = data.text ?? "";
    if (data.fileText && data.fileText.trim()) {
      combined += `\n\n[檔案內容]\n${data.fileText.trim()}`;
    }
    if (attachments.length > 0) {
      const manifest = attachments
        .map((a) => `[${a.i}:${a.type}:${a.name}]`)
        .join(" ");
      combined += `\n\n附件清單：${manifest}`;
    }

    const content: Array<Record<string, unknown>> = [
      { type: "input_text", text: combined.trim() || "（無文字輸入）" },
    ];
    for (const img of data.images ?? []) {
      const url = img.startsWith("data:")
        ? img
        : `data:image/jpeg;base64,${img}`;
      content.push({ type: "input_image", image_url: url, detail: "low" });
    }

    const res = await createResponse(
      {
        model: MODELS.classify,
        instructions: system,
        input: [{ role: "user", content }],
        temperature: 0.2,
        max_output_tokens: 800,
        text: jsonFormat("classification", CLASSIFY_MULTI_SCHEMA),
      },
      REQ_TIMEOUT.classify
    );

    const parsed = extractJson<{ items?: RawItem[] }>(res.output_text) ?? {
      items: [],
    };

    const [defaultYear, defaultMonth] = today
      .split("-")
      .map((x) => parseInt(x, 10));
    const attCount = attachments.length;

    const items = (parsed.items ?? [])
      .map((raw) =>
        normalizeItem(raw, {
          todoCats,
          noteCats,
          today,
          defaultYear,
          defaultMonth,
          attCount,
        })
      )
      .filter((it): it is Record<string, unknown> => it !== null);

    return { items };
  }
);

function normalizeItem(
  raw: RawItem,
  ctx: {
    todoCats: ReadonlyArray<{ id: string }>;
    noteCats: ReadonlyArray<{ id: string }>;
    today: string;
    defaultYear: number;
    defaultMonth: number;
    attCount: number;
  }
): Record<string, unknown> | null {
  switch (raw.type) {
    case "todo":
      return {
        type: "todo",
        text: s(raw.text),
        catId: validateCatId(raw.cat, ctx.todoCats),
      };
    case "todo_with_time": {
      const start = {
        year: n(raw.start_year, ctx.defaultYear),
        month: n(raw.start_month, ctx.defaultMonth),
        day: n(raw.start_day, 1),
        hour: n(raw.start_hour, 0),
        minute: n(raw.start_min, 0),
      };
      const hasEnd = raw.end_day != null && raw.end_hour != null;
      const end = hasEnd
        ? {
            year: n(raw.end_year, start.year),
            month: n(raw.end_month, start.month),
            day: n(raw.end_day, start.day),
            hour: n(raw.end_hour, start.hour),
            minute: n(raw.end_min, start.minute),
          }
        : addHour(start);
      return {
        type: "todo_with_time",
        text: s(raw.text),
        catId: validateCatId(raw.cat, ctx.todoCats),
        start,
        end,
      };
    }
    case "idea":
      return { type: "idea", text: s(raw.text) };
    case "note":
      return {
        type: "note",
        dateKey: s(raw.date_key) || ctx.today,
        noteCatId: validateCatId(raw.note_cat, ctx.noteCats),
        content: s(raw.content),
        attachmentIndices: dedupeIndices(raw.attachment_indices, ctx.attCount),
      };
    case "recap":
      return {
        type: "recap",
        title: s(raw.title),
        description: s(raw.description),
      };
    default:
      return null;
  }
}

function addHour(t: {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}) {
  const d = new Date(t.year, t.month - 1, t.day, t.hour + 1, t.minute);
  return {
    year: d.getFullYear(),
    month: d.getMonth() + 1,
    day: d.getDate(),
    hour: d.getHours(),
    minute: d.getMinutes(),
  };
}

function dedupeIndices(
  raw: number[] | null | undefined,
  count: number
): number[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<number>();
  for (const v of raw) {
    if (typeof v === "number" && Number.isInteger(v) && v >= 0 && v < count) {
      seen.add(v);
    }
  }
  return [...seen];
}
