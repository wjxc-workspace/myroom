// Zero-dependency unit tests for the side-effect-free helpers, run against the
// compiled output with Node's built-in test runner (`npm test` builds first).
// These cover the most bug-prone pure logic — timezone conversion and the
// tolerant JSON extraction — without needing the emulator or an OpenAI key.
// Emulator-based callable/trigger/rules tests (firebase-functions-test) are the
// remaining Test.md layer and require a running Emulator Suite.
const test = require("node:test");
const assert = require("node:assert/strict");

const { zonedToUtc, todayKey, daysFromNow } = require("../lib/lib/date");
const { extractJson } = require("../lib/lib/openai");

test("zonedToUtc converts Taipei wall-clock to the correct UTC instant", () => {
  // 10:00 in Asia/Taipei (UTC+8) is 02:00 UTC.
  const d = zonedToUtc(2026, 6, 10, 10, 0, "Asia/Taipei");
  assert.equal(d.toISOString(), "2026-06-10T02:00:00.000Z");
});

test("zonedToUtc handles UTC identity", () => {
  const d = zonedToUtc(2026, 1, 1, 0, 0, "UTC");
  assert.equal(d.toISOString(), "2026-01-01T00:00:00.000Z");
});

test("todayKey returns a YYYY-MM-DD string", () => {
  assert.match(todayKey("Asia/Taipei"), /^\d{4}-\d{2}-\d{2}$/);
});

test("daysFromNow shifts by whole days", () => {
  const delta = daysFromNow(2).getTime() - daysFromNow(0).getTime();
  assert.equal(delta, 2 * 24 * 60 * 60 * 1000);
});

test("extractJson strips ```json fences", () => {
  assert.deepEqual(extractJson('```json\n{"a":1}\n```'), { a: 1 });
});

test("extractJson trims to the outermost braces", () => {
  assert.deepEqual(extractJson('前綴 {"b":2} 後綴'), { b: 2 });
});

test("extractJson returns null on non-JSON", () => {
  assert.equal(extractJson("just some text"), null);
  assert.equal(extractJson(""), null);
});
