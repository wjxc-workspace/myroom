// Bounded chat context, built server-side from windowed queries (AI_proxy.md §3,
// firebase_port_extraction.md §11.4): pending todos, done-count, events
// −3…+30 days, notes updated in the last 7 days (deduped by dateKey), latest 20
// ideas, the latest achievement's current+future content, and recent recaps.
import { Timestamp } from "firebase-admin/firestore";

import { db } from "./admin";
import { daysFromNow } from "./date";

function fmt(ts: unknown, tz: string): string {
  if (!(ts instanceof Timestamp)) return "";
  return new Intl.DateTimeFormat("zh-TW", {
    timeZone: tz,
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(ts.toDate());
}

function clip(s: string, n = 40): string {
  const t = (s ?? "").replace(/\s+/g, " ").trim();
  return t.length > n ? `${t.slice(0, n)}…` : t;
}

export async function buildContext(uid: string, tz: string): Promise<string> {
  const root = db.collection("users").doc(uid);
  const sections: string[] = [];

  // Pending todos + done count.
  const [pending, doneCount] = await Promise.all([
    root.collection("todos").where("isCompleted", "==", false).get(),
    root
      .collection("todos")
      .where("isCompleted", "==", true)
      .count()
      .get()
      .then((s) => s.data().count)
      .catch(() => 0),
  ]);
  if (pending.size > 0) {
    const lines = pending.docs
      .slice(0, 30)
      .map((d) => `  - [${d.id}] ${clip(d.get("title") as string)}`)
      .join("\n");
    sections.push(`待辦（未完成 ${pending.size}）：\n${lines}`);
  } else {
    sections.push("待辦（未完成 0）");
  }
  sections.push(`已完成待辦數：${doneCount}`);

  // Events −3…+30 days.
  const events = await root
    .collection("events")
    .where("startTime", ">=", Timestamp.fromDate(daysFromNow(-3)))
    .where("startTime", "<=", Timestamp.fromDate(daysFromNow(30)))
    .orderBy("startTime")
    .get();
  if (events.size > 0) {
    const lines = events.docs
      .map(
        (d) =>
          `  - [${d.id}] ${fmt(d.get("startTime"), tz)} ${clip(
            d.get("title") as string
          )}`
      )
      .join("\n");
    sections.push(`近期行程：\n${lines}`);
  }

  // Notes updated in the last 7 days, deduped by dateKey.
  const recentNotes = await root
    .collection("notes")
    .where("updatedAt", ">=", Timestamp.fromDate(daysFromNow(-7)))
    .orderBy("updatedAt", "desc")
    .get();
  const seenDates = new Set<string>();
  const noteLines: string[] = [];
  for (const d of recentNotes.docs) {
    const dateKey = (d.get("dateKey") as string) ?? "";
    if (seenDates.has(dateKey)) continue;
    seenDates.add(dateKey);
    noteLines.push(`  - [${d.id}] ${dateKey} ${clip(d.get("content") as string)}`);
  }
  if (noteLines.length > 0) {
    sections.push(`近 7 天札記：\n${noteLines.join("\n")}`);
  }

  // Latest 20 ideas (users/{uid}/ideas/data/user_ideas).
  const ideas = await root
    .collection("ideas")
    .doc("data")
    .collection("user_ideas")
    .orderBy("createdAt", "desc")
    .limit(20)
    .get();
  if (ideas.size > 0) {
    const lines = ideas.docs
      .map((d) => {
        const summary = (d.get("aiSummary") as string | undefined) ?? "";
        const base = clip(d.get("text") as string);
        return `  - [${d.id}] ${base}${summary ? `（摘要：${clip(summary)}）` : ""}`;
      })
      .join("\n");
    sections.push(`靈感（最新 20）：\n${lines}`);
  }

  // Latest achievement's current + future content.
  const ach = await root
    .collection("achievements")
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();
  if (!ach.empty) {
    const a = ach.docs[0];
    const cur = clip((a.get("currentContent") as string) ?? "", 80);
    const fut = clip((a.get("futureContent") as string) ?? "", 80);
    if (cur || fut) {
      sections.push(`階段回顧：現在「${cur}」未來「${fut}」`);
    }
  }

  // Recent recaps.
  const recaps = await root
    .collection("recaps")
    .orderBy("createdAt", "desc")
    .limit(5)
    .get();
  if (recaps.size > 0) {
    const lines = recaps.docs
      .map((d) => `  - [${d.id}] ${clip(d.get("title") as string)}`)
      .join("\n");
    sections.push(`回顧紀錄：\n${lines}`);
  }

  return sections.join("\n\n");
}
