// JSON schemas for the Responses API `text.format` structured outputs
// (AI_proxy.md §4). Strict mode requires every property to appear in `required`
// and `additionalProperties:false`, so the classification item is a single
// superset object with a `type` discriminator and every non-applicable field
// nullable — the function interprets each item by its `type`.

const nullableStr = { type: ["string", "null"] };
const nullableInt = { type: ["integer", "null"] };

const classificationItem = {
  type: "object",
  additionalProperties: false,
  properties: {
    type: {
      type: "string",
      enum: ["todo", "todo_with_time", "idea", "note", "recap"],
    },
    // todo / todo_with_time / idea
    text: nullableStr,
    cat: nullableStr,
    start_year: nullableInt,
    start_month: nullableInt,
    start_day: nullableInt,
    start_hour: nullableInt,
    start_min: nullableInt,
    end_year: nullableInt,
    end_month: nullableInt,
    end_day: nullableInt,
    end_hour: nullableInt,
    end_min: nullableInt,
    // note
    date_key: nullableStr,
    note_cat: nullableStr,
    content: nullableStr,
    attachment_indices: {
      type: ["array", "null"],
      items: { type: "integer" },
    },
    // recap
    title: nullableStr,
    description: nullableStr,
  },
  required: [
    "type",
    "text",
    "cat",
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
    "date_key",
    "note_cat",
    "content",
    "attachment_indices",
    "title",
    "description",
  ],
} as const;

export const CLASSIFY_MULTI_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    items: { type: "array", items: classificationItem },
  },
  required: ["items"],
} as const;

export const CLASSIFY_NOTE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: { cat_id: { type: "string" } },
  required: ["cat_id"],
} as const;

export const FIND_NOTES_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    match_ids: { type: "array", items: { type: "string" } },
  },
  required: ["match_ids"],
} as const;

/** Wraps a raw JSON schema as a Responses API `text.format` block. */
export function jsonFormat(name: string, schema: unknown) {
  return { format: { type: "json_schema", name, strict: true, schema } };
}
