import { fail } from "./errors";

const DAY_MS = 86_400_000;
const HOUR_MS = 3_600_000;

/** Current time as a `toISOString()` string. */
export function nowIso(): string {
  return new Date().toISOString();
}

/** `iso` shifted by `ms` milliseconds, as a `toISOString()` string. */
export function addMs(iso: string, ms: number): string {
  return new Date(Date.parse(iso) + ms).toISOString();
}

export function addHours(iso: string, hours: number): string {
  return addMs(iso, hours * HOUR_MS);
}

/** Adds whole 24-hour days to an instant, like `timestamptz + interval 'N days'` in a UTC session. */
export function addDaysToInstant(iso: string, days: number): string {
  return addMs(iso, days * DAY_MS);
}

/** Adds calendar days to a YYYY-MM-DD string. */
export function addDaysToDate(date: string, days: number): string {
  const [year, month, day] = parseDate(date);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function parseDate(date: string): [number, number, number] {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!match) {
    return fail("22007", `invalid input syntax for type date: "${date}"`);
  }
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

const formatters = new Map<string, Intl.DateTimeFormat | null>();

function formatterFor(timeZone: string): Intl.DateTimeFormat | null {
  let formatter = formatters.get(timeZone);
  if (formatter === undefined) {
    try {
      formatter = new Intl.DateTimeFormat("en-US", {
        timeZone,
        hourCycle: "h23",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });
    } catch {
      formatter = null;
    }
    formatters.set(timeZone, formatter);
  }
  return formatter;
}

/** True when `timeZone` is an IANA zone name the runtime knows. Replaces `pg_timezone_names` lookups. */
export function isValidTimeZone(timeZone: string | null | undefined): timeZone is string {
  return typeof timeZone === "string" && timeZone.length > 0 && formatterFor(timeZone) !== null;
}

/** `timeZone` when valid, otherwise 'UTC'. Mirrors joining against `pg_timezone_names` with a UTC fallback. */
export function validTimeZoneOrUtc(timeZone: string | null | undefined): string {
  return isValidTimeZone(timeZone) ? timeZone : "UTC";
}

/** Throws 22023 for an unknown zone. */
export function assertValidTimeZone(timeZone: string): void {
  if (!isValidTimeZone(timeZone)) {
    fail("22023", `time zone "${timeZone}" not recognized`);
  }
}

/**
 * The local wall clock of an instant in a zone, expressed as milliseconds as if
 * that wall clock were UTC. Equal wall clocks give equal numbers, which is the
 * ordering Postgres uses for `timestamp without time zone`.
 */
export function localWallClockMs(instantMs: number, timeZone: string): number {
  const formatter = formatterFor(timeZone);
  if (!formatter) {
    return fail("22023", `time zone "${timeZone}" not recognized`);
  }
  const values: Record<string, number> = {};
  for (const part of formatter.formatToParts(new Date(instantMs))) {
    if (part.type !== "literal") {
      values[part.type] = Number(part.value);
    }
  }
  return Date.UTC(
    values.year,
    values.month - 1,
    values.day,
    values.hour % 24,
    values.minute,
    values.second,
  );
}

/** Offset of the zone from UTC at an instant, in milliseconds (east is positive). */
export function zoneOffsetMs(instantMs: number, timeZone: string): number {
  const wholeSecondMs = Math.floor(instantMs / 1000) * 1000;
  return localWallClockMs(wholeSecondMs, timeZone) - wholeSecondMs;
}

/** The local calendar date (YYYY-MM-DD) of an instant in a zone. */
export function localDateOf(instant: string | number, timeZone: string): string {
  const ms = typeof instant === "number" ? instant : Date.parse(instant);
  return new Date(localWallClockMs(ms, timeZone)).toISOString().slice(0, 10);
}

/**
 * The UTC instant for a local date and time in a zone, as milliseconds.
 *
 * Follows the Postgres rules for `timestamp at time zone`. A time inside a
 * spring-forward gap uses the offset from before the gap. An ambiguous time in
 * a fall-back overlap resolves to the later instant (standard time).
 */
export function zonedLocalToUtcMs(
  localDate: string,
  timeZone: string,
  hour = 0,
  minute = 0,
  second = 0,
): number {
  const [year, month, day] = parseDate(localDate);
  const wall = Date.UTC(year, month - 1, day, hour, minute, second);
  const before = zoneOffsetMs(wall - DAY_MS, timeZone);
  const after = zoneOffsetMs(wall + DAY_MS, timeZone);
  const valid = [before, after]
    .map((offset) => wall - offset)
    .filter((instant) => zoneOffsetMs(instant, timeZone) === wall - instant);
  if (valid.length > 0) {
    return Math.max(...valid);
  }
  return wall - before;
}

/** UTC instant of local midnight at the start of `localDate` in the zone. */
export function startOfLocalDay(localDate: string, timeZone: string): string {
  return new Date(zonedLocalToUtcMs(localDate, timeZone)).toISOString();
}

/** UTC instant of local midnight at the end of `localDate` (the start of the next local day). */
export function endOfLocalDay(localDate: string, timeZone: string): string {
  return startOfLocalDay(addDaysToDate(localDate, 1), timeZone);
}

/** The instant that is local midnight `daysAfter` local days after the local date of `instant`. */
export function localMidnightAfter(instant: string, timeZone: string, daysAfter: number): string {
  return startOfLocalDay(addDaysToDate(localDateOf(instant, timeZone), daysAfter), timeZone);
}
