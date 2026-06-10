// Recap / achievement export rendering (Storage.md §6, AI_proxy.md §5).
//
// The visual deliverable is a self-contained SVG "graphic" (the guide allows a
// PDF *or* graphic). SVG is chosen deliberately: the content is zh-TW, and SVG
// renders CJK via the viewer's own fonts, so no CJK font binary has to be
// bundled into the functions image (which a server-side PDF rasteriser would
// require). The file is content-text only — no inline images (DALL-E dropped).
import { storage } from "./admin";

const WIDTH = 800;
const PAD = 56;
const TITLE_SIZE = 34;
const BODY_SIZE = 20;
const BODY_LH = 34;
const MAX_CHARS = 30; // wrap width (CJK-friendly)

function esc(s: string): string {
  return (s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Greedy wrap that respects explicit newlines and a max char width. */
function wrap(text: string): string[] {
  const out: string[] = [];
  for (const para of (text ?? "").split(/\r?\n/)) {
    if (para.length === 0) {
      out.push("");
      continue;
    }
    for (let i = 0; i < para.length; i += MAX_CHARS) {
      out.push(para.slice(i, i + MAX_CHARS));
    }
  }
  return out;
}

function buildSvg(title: string, content: string): string {
  const lines = wrap(content);
  const bodyTop = PAD + TITLE_SIZE + 28;
  const height = Math.max(360, bodyTop + lines.length * BODY_LH + PAD);
  const tspans = lines
    .map(
      (l, i) =>
        `<tspan x="${PAD}" y="${bodyTop + i * BODY_LH}">${esc(l) || " "}</tspan>`
    )
    .join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${height}" viewBox="0 0 ${WIDTH} ${height}">
  <rect width="${WIDTH}" height="${height}" fill="#F5F1EA"/>
  <rect x="20" y="20" width="${WIDTH - 40}" height="${height - 40}" rx="24" fill="#FFFFFF" stroke="#E7E0D6"/>
  <rect x="20" y="20" width="6" height="${height - 40}" rx="3" fill="#C57A8A"/>
  <text x="${PAD}" y="${PAD + TITLE_SIZE - 8}" font-family="'Noto Sans TC','Microsoft JhengHei',sans-serif" font-size="${TITLE_SIZE}" font-weight="600" fill="#3A332C">${esc(
    title
  )}</text>
  <text font-family="'Noto Sans TC','Microsoft JhengHei',sans-serif" font-size="${BODY_SIZE}" fill="#5C5247">${tspans}</text>
</svg>`;
}

async function upload(path: string, svg: string): Promise<void> {
  await storage
    .bucket()
    .file(path)
    .save(Buffer.from(svg, "utf8"), {
      contentType: "image/svg+xml",
      resumable: false,
    });
}

export async function renderRecapExport(
  uid: string,
  recapId: string,
  title: string,
  content: string
): Promise<string> {
  const path = `users/${uid}/recaps/${recapId}/export.svg`;
  await upload(path, buildSvg(title || "回顧", content));
  return path;
}

export async function renderAchievementExport(
  uid: string,
  achievementId: string,
  era: "past" | "current" | "future",
  eraLabel: string,
  content: string
): Promise<string> {
  const path = `users/${uid}/achievements/${achievementId}/${era}_export.svg`;
  await upload(path, buildSvg(eraLabel, content));
  return path;
}
