// Chat tool definitions (Responses API function tools) + server-side executors
// (AI_proxy.md §2). The 9 write tools (`add_*`/`delete_*` + `add_recap`) plus the
// 4 real `list_*` read tools the demo referenced but never defined
// (firebase_port_extraction.md §4/§10). All mutations run via the Admin SDK
// against `/users/{uid}/…`; the client UI updates reactively from its streams.
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { db } from "./admin";
import {
  NoteCatSnapshot,
  TodoCatSnapshot,
  todoCatByLabel,
} from "./categories";
import { todayKey, zonedToUtc } from "./date";

const SAGE = 0xff7b9e87; // default event color (matches the demo theme token)

export interface ToolContext {
  uid: string;
  tz: string;
  todoCats: TodoCatSnapshot[];
  undefinedNoteCat: NoteCatSnapshot;
}

type Args = Record<string, unknown>;
const str = (v: unknown): string => (typeof v === "string" ? v : "");
const int = (v: unknown, d = 0): number =>
  typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : d;

function clip(s: string, n = 30): string {
  const t = (s ?? "").trim();
  return t.length > n ? `${t.slice(0, n)}…` : t;
}

/** Builds the tool list, injecting the user's todo category labels into
 *  `add_todo.cat` so no names are hard-coded (AI_proxy.md §4a H2). */
export function buildChatTools(todoCats: TodoCatSnapshot[]) {
  const labels = todoCats.map((c) => c.label).join("、");
  return [
    fn("delete_event", "刪除一個行程（取消某個 event）", {
      id: prop("string", "行程的資料庫 id"),
    }, ["id"]),
    fn(
      "add_event",
      "新增一個行程",
      {
        title: prop("string", "行程標題"),
        start_year: prop("integer", "開始年份"),
        start_month: prop("integer", "開始月份"),
        start_day: prop("integer", "開始日"),
        start_hour: prop("integer", "開始小時（24h）"),
        start_min: prop("integer", "開始分鐘"),
        end_year: prop("integer", "結束年份"),
        end_month: prop("integer", "結束月份"),
        end_day: prop("integer", "結束日"),
        end_hour: prop("integer", "結束小時（24h）"),
        end_min: prop("integer", "結束分鐘"),
        description: prop("string", "詳細說明"),
        location: prop("string", "地點"),
      },
      [
        "title",
        "start_year",
        "start_month",
        "start_day",
        "start_hour",
        "start_min",
        "end_year",
        "end_month",
        "end_day",
        "end_hour",
        "end_min",
      ]
    ),
    fn("delete_todo", "刪除一個待辦事項", {
      id: prop("string", "待辦的資料庫 id"),
    }, ["id"]),
    fn(
      "add_todo",
      "新增一個待辦事項",
      {
        text: prop("string", "待辦內容"),
        cat: prop("string", `分類名稱，可選：${labels}`),
      },
      ["text", "cat"]
    ),
    fn("delete_idea", "刪除一個靈感", {
      id: prop("string", "靈感的資料庫 id"),
    }, ["id"]),
    fn("delete_note", "刪除一則筆記", {
      id: prop("string", "筆記的資料庫 id"),
    }, ["id"]),
    fn(
      "add_idea",
      "新增一個靈感或想法（儲存後 AI 會自動生成摘要與資源連結）",
      { text: prop("string", "靈感內容") },
      ["text"]
    ),
    fn(
      "add_note",
      "新增一則筆記（儲存後 AI 會自動分類）",
      {
        date_key: prop("string", "日期 YYYY-MM-DD，預設今天"),
        content: prop("string", "筆記內容"),
      },
      ["content"]
    ),
    fn(
      "add_recap",
      "新增一則回顧（為一段時光寫下標題與回顧內容）",
      {
        title: prop("string", "標題"),
        content: prop("string", "回顧內容"),
      },
      ["title"]
    ),
    fn("list_todos", "列出待辦事項（含 id）", {}, []),
    fn("list_events", "列出近期行程（含 id）", {}, []),
    fn("list_ideas", "列出靈感（含 id）", {}, []),
    fn("list_notes", "列出近期筆記（含 id）", {}, []),
  ];
}

function fn(
  name: string,
  description: string,
  properties: Record<string, unknown>,
  required: string[]
) {
  return {
    type: "function",
    name,
    description,
    strict: false,
    parameters: {
      type: "object",
      properties,
      required,
    },
  };
}

function prop(type: string, description: string) {
  return { type, description };
}

/** Executes one tool call and returns a short result string fed back to the
 *  model as a `function_call_output`. */
export async function runToolCall(
  name: string,
  argsJson: string,
  ctx: ToolContext
): Promise<string> {
  let args: Args;
  try {
    args = argsJson ? (JSON.parse(argsJson) as Args) : {};
  } catch {
    return "工具參數格式錯誤";
  }
  const { uid, tz } = ctx;

  switch (name) {
    case "add_event":
      return addEvent(ctx, args);
    case "delete_event":
      return del(`users/${uid}/events/${str(args.id)}`, "行程", args.id);
    case "add_todo":
      return addTodo(ctx, args);
    case "delete_todo":
      return del(`users/${uid}/todos/${str(args.id)}`, "待辦", args.id);
    case "add_idea":
      return addIdea(ctx, args);
    case "delete_idea":
      return del(
        `users/${uid}/ideas/data/user_ideas/${str(args.id)}`,
        "靈感",
        args.id
      );
    case "add_note":
      return addNote(ctx, args);
    case "delete_note":
      return del(`users/${uid}/notes/${str(args.id)}`, "筆記", args.id);
    case "add_recap":
      return addRecap(ctx, args);
    case "list_todos":
      return listTodos(uid);
    case "list_events":
      return listEvents(uid, tz);
    case "list_ideas":
      return listIdeas(uid);
    case "list_notes":
      return listNotes(uid);
    default:
      return `未知工具：${name}`;
  }
}

// ── write tools ────────────────────────────────────────────────────────────

async function addEvent(ctx: ToolContext, a: Args): Promise<string> {
  const { uid, tz } = ctx;
  const start = zonedToUtc(
    int(a.start_year),
    int(a.start_month, 1),
    int(a.start_day, 1),
    int(a.start_hour),
    int(a.start_min),
    tz
  );
  const hasEnd = a.end_day != null && a.end_hour != null;
  const end = hasEnd
    ? zonedToUtc(
        int(a.end_year, int(a.start_year)),
        int(a.end_month, int(a.start_month, 1)),
        int(a.end_day, int(a.start_day, 1)),
        int(a.end_hour),
        int(a.end_min),
        tz
      )
    : new Date(start.getTime() + 60 * 60 * 1000);
  await db.collection(`users/${uid}/pending_events`).add({
    title: str(a.title),
    description: a.description != null ? str(a.description) : null,
    location: a.location != null ? str(a.location) : null,
    startTime: Timestamp.fromDate(start),
    endTime: Timestamp.fromDate(end),
    isAllDay: false,
    color: SAGE,
    createdAt: FieldValue.serverTimestamp(),
  });
  return `已建議新增行程「${clip(str(a.title))}」，等待使用者確認`;
}

async function addTodo(ctx: ToolContext, a: Args): Promise<string> {
  const { uid, todoCats } = ctx;
  const cat = todoCatByLabel(str(a.cat) || undefined, todoCats);
  const countSnap = await db.collection(`users/${uid}/todos`).count().get();
  await db.collection(`users/${uid}/todos`).add({
    title: str(a.text),
    isCompleted: false,
    sortOrder: countSnap.data().count,
    category: { id: cat.id, label: cat.label, colorVal: cat.colorVal },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return `已新增待辦：${clip(str(a.text))}`;
}

async function addIdea(ctx: ToolContext, a: Args): Promise<string> {
  const { uid } = ctx;
  // Idea doc only — the enrichIdea trigger fills aiSummary/links.
  await db.collection(`users/${uid}/ideas/data/user_ideas`).add({
    text: str(a.text),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return `已新增靈感：${clip(str(a.text))}`;
}

async function addNote(ctx: ToolContext, a: Args): Promise<string> {
  const { uid, tz, undefinedNoteCat: c } = ctx;
  // No title on AI-created notes → the '無標題' default. classifyNote
  // categorises it from the undefined sentinel.
  await db.collection(`users/${uid}/notes`).add({
    dateKey: str(a.date_key) || todayKey(tz),
    title: "無標題",
    content: str(a.content),
    category: {
      id: c.id,
      label: c.label,
      colorVal: c.colorVal,
      iconName: c.iconName,
    },
    attachments: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return "已新增筆記";
}

async function addRecap(ctx: ToolContext, a: Args): Promise<string> {
  const { uid } = ctx;
  await db.collection(`users/${uid}/recaps`).add({
    title: str(a.title),
    content: str(a.content),
    createdAt: FieldValue.serverTimestamp(),
  });
  return `已新增回顧：${clip(str(a.title))}`;
}

async function del(path: string, label: string, id: unknown): Promise<string> {
  if (!id || typeof id !== "string") return `刪除${label}失敗：缺少 id`;
  await db.doc(path).delete();
  return `已刪除${label}`;
}

// ── read tools (list_*) ────────────────────────────────────────────────────

async function listTodos(uid: string): Promise<string> {
  const snap = await db
    .collection(`users/${uid}/todos`)
    .orderBy("sortOrder")
    .limit(100)
    .get();
  const rows = snap.docs.map((d) => ({
    id: d.id,
    title: d.get("title") as string,
    done: (d.get("isCompleted") as boolean) ?? false,
    cat: (d.get("category") as { label?: string } | undefined)?.label ?? "",
  }));
  return JSON.stringify(rows);
}

async function listEvents(uid: string, tz: string): Promise<string> {
  const snap = await db
    .collection(`users/${uid}/events`)
    .orderBy("startTime")
    .limit(100)
    .get();
  const rows = snap.docs.map((d) => ({
    id: d.id,
    title: d.get("title") as string,
    start: tsIso(d.get("startTime"), tz),
    end: tsIso(d.get("endTime"), tz),
  }));
  return JSON.stringify(rows);
}

async function listIdeas(uid: string): Promise<string> {
  const snap = await db
    .collection(`users/${uid}/ideas/data/user_ideas`)
    .orderBy("createdAt", "desc")
    .limit(20)
    .get();
  const rows = snap.docs.map((d) => ({
    id: d.id,
    text: d.get("text") as string,
  }));
  return JSON.stringify(rows);
}

async function listNotes(uid: string): Promise<string> {
  const snap = await db
    .collection(`users/${uid}/notes`)
    .orderBy("createdAt", "desc")
    .limit(50)
    .get();
  const rows = snap.docs.map((d) => ({
    id: d.id,
    dateKey: d.get("dateKey") as string,
    content: clip(d.get("content") as string, 50),
    cat: (d.get("category") as { label?: string } | undefined)?.label ?? "",
  }));
  return JSON.stringify(rows);
}

function tsIso(ts: unknown, tz: string): string {
  if (!(ts instanceof Timestamp)) return "";
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(ts.toDate());
}
