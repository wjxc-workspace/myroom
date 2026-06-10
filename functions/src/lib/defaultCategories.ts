// Default categories created by `provisionUser` (Auth.md §3).
//
// Colors are ARGB ints (Flutter `Color.toARGB32()`), matching the demo theme
// tokens so the palette stays coherent:
//   blue 0xFF8B9EC5 · rose 0xFFC57A8A · sage 0xFF7B9E87 · amber 0xFFC5956A
//   muted/grey 0xFF9A8A7E (neutral for the 無分類 sentinel)
// The 學業 note category reuses the demo's academic color (0xFFBF7A8E) + the
// `pencil` icon; 社團 is new (teal 0xFF26A69A, `users` icon).

export const UNDEFINED_CATEGORY_ID = "undefined";

const GREY = 0xff9a8a7e;
const BLUE = 0xff8b9ec5;
const ROSE = 0xffc57a8a;
const ACADEMIC = 0xffbf7a8e;
const TEAL = 0xff26a69a;

export interface TodoCategorySeed {
  id?: string; // omit → Firestore auto-id
  label: string;
  colorVal: number;
  sortOrder: number;
}

export interface NoteCategorySeed {
  id?: string;
  label: string;
  colorVal: number;
  iconName: string;
  sortOrder: number;
}

export const DEFAULT_TODO_CATEGORIES: TodoCategorySeed[] = [
  { id: UNDEFINED_CATEGORY_ID, label: "無分類", colorVal: GREY, sortOrder: 0 },
  { label: "工作", colorVal: BLUE, sortOrder: 1 },
  { label: "個人", colorVal: ROSE, sortOrder: 2 },
];

export const DEFAULT_NOTE_CATEGORIES: NoteCategorySeed[] = [
  {
    id: UNDEFINED_CATEGORY_ID,
    label: "無分類",
    colorVal: GREY,
    iconName: "tag",
    sortOrder: 0,
  },
  { label: "學業", colorVal: ACADEMIC, iconName: "pencil", sortOrder: 1 },
  { label: "社團", colorVal: TEAL, iconName: "users", sortOrder: 2 },
];
