// Category loading + injection helpers (AI_proxy.md §5/§6, DataModel.md).
//
// Categories are injected into the AI as `{id, label}` pairs built from the real
// Firestore auto-ids (plus the fixed `undefined` sentinel). The model chooses by
// label and returns the `id`, which we validate against the injected set — on a
// miss we fall back to the `undefined` sentinel. Prompts never hard-code
// category names or the demo's old `academic`/`sport` ids.
import { db } from "./admin";
import { UNDEFINED_CAT } from "./config";

/** Full denormalized snapshot embedded into todos. */
export interface TodoCatSnapshot {
  id: string;
  label: string;
  colorVal: number;
}

/** Full denormalized snapshot embedded into notes (carries an icon). */
export interface NoteCatSnapshot {
  id: string;
  label: string;
  colorVal: number;
  iconName: string;
}

/** `{id, label}` pair injected into prompts. */
export interface CatOption {
  id: string;
  label: string;
}

const GREY = 0xff9a8a7e;

const FALLBACK_TODO: TodoCatSnapshot = {
  id: UNDEFINED_CAT,
  label: "無分類",
  colorVal: GREY,
};
const FALLBACK_NOTE: NoteCatSnapshot = {
  id: UNDEFINED_CAT,
  label: "無分類",
  colorVal: GREY,
  iconName: "tag",
};

export async function loadTodoCats(uid: string): Promise<TodoCatSnapshot[]> {
  const snap = await db
    .collection(`users/${uid}/todo_categories`)
    .orderBy("sortOrder")
    .get();
  const cats = snap.docs.map((d) => ({
    id: d.id,
    label: (d.get("label") as string) ?? "",
    colorVal: (d.get("colorVal") as number) ?? GREY,
  }));
  return ensureUndefined(cats, FALLBACK_TODO);
}

export async function loadNoteCats(uid: string): Promise<NoteCatSnapshot[]> {
  const snap = await db
    .collection(`users/${uid}/note_categories`)
    .orderBy("sortOrder")
    .get();
  const cats = snap.docs.map((d) => ({
    id: d.id,
    label: (d.get("label") as string) ?? "",
    colorVal: (d.get("colorVal") as number) ?? GREY,
    iconName: (d.get("iconName") as string) ?? "",
  }));
  return ensureUndefined(cats, FALLBACK_NOTE);
}

function ensureUndefined<T extends { id: string }>(cats: T[], fallback: T): T[] {
  return cats.some((c) => c.id === UNDEFINED_CAT) ? cats : [fallback, ...cats];
}

export function toOptions(
  cats: ReadonlyArray<{ id: string; label: string }>
): CatOption[] {
  return cats.map((c) => ({ id: c.id, label: c.label }));
}

/** Returns [id] if present in [cats], else the `undefined` sentinel id. */
export function validateCatId(
  id: string | null | undefined,
  cats: ReadonlyArray<{ id: string }>
): string {
  if (id && cats.some((c) => c.id === id)) return id;
  return UNDEFINED_CAT;
}

export function findTodoCat(
  id: string,
  cats: TodoCatSnapshot[]
): TodoCatSnapshot {
  return cats.find((c) => c.id === id) ?? FALLBACK_TODO;
}

export function findNoteCat(
  id: string,
  cats: NoteCatSnapshot[]
): NoteCatSnapshot {
  return cats.find((c) => c.id === id) ?? FALLBACK_NOTE;
}

/** Resolves a todo category by label (chat `add_todo` passes a label). */
export function todoCatByLabel(
  label: string | undefined,
  cats: TodoCatSnapshot[]
): TodoCatSnapshot {
  if (label) {
    const hit = cats.find((c) => c.label === label);
    if (hit) return hit;
  }
  return findTodoCat(UNDEFINED_CAT, cats);
}

export { FALLBACK_TODO, FALLBACK_NOTE };
