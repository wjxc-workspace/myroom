// Timezone-aware date helpers. The demo emitted local-device `YYYY-MM-DD` with
// no tz handling and even shipped a `$todayKey()` interpolation bug
// (firebase_port_extraction.md §3.1 / §11.8). On the server we compute the real
// date from the user's `settings/app.tz` (default Asia/Taipei).

/** Today's date as `YYYY-MM-DD` in [tz]. */
export function todayKey(tz: string): string {
  // en-CA renders ISO `YYYY-MM-DD`.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

/** Offset (ms) between wall-clock time in [tz] and UTC at the given instant. */
function tzOffsetMs(at: Date, tz: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(at);
  const map: Record<string, number> = {};
  for (const p of parts) {
    if (p.type !== "literal") map[p.type] = Number(p.value);
  }
  // `hour` can come back as 24 at midnight in some runtimes — normalise.
  const hour = map.hour === 24 ? 0 : map.hour;
  const asUtc = Date.UTC(
    map.year,
    map.month - 1,
    map.day,
    hour,
    map.minute,
    map.second
  );
  return asUtc - at.getTime();
}

/**
 * Converts a wall-clock time expressed in [tz] (the y/m/d/h/min the model emits)
 * into the correct UTC instant. Used by the chat `add_event` tool so an event
 * the user says is at 10:00 lands at 10:00 Taipei, not 10:00 UTC.
 */
export function zonedToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  tz: string
): Date {
  const utcGuess = Date.UTC(year, month - 1, day, hour, minute);
  const offset = tzOffsetMs(new Date(utcGuess), tz);
  return new Date(utcGuess - offset);
}

/** `now ± days` as a JS Date, for windowed context queries. */
export function daysFromNow(days: number): Date {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
}
