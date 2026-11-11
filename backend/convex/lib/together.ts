import type { Doc } from "../_generated/dataModel";
import { findCoupleDayAt, resolveCoupleDayAnchorAt } from "./coupleDays";
import type { ReaderCtx, WriterCtx } from "./db";
import { addDaysToDate, addMs } from "./time";

// A together day is a couple-local date on which the partners are together:
//
// - a `together_days` row exists for it (written when location showed them together, or kept when
//   a visit or a location run that covered it changed after the day ended),
// - a visit covers it, from the visit's `together_from` on, or
// - a location run (`together_location_runs`) has been open since that date or earlier.
//
// A day that ended keeps what it was. Every write that could change an ended day writes its row
// first (`keepVisitDays`, `endLocationRun`), and a visit only reaches days from the day its dates
// were saved, so a visit planned with past dates changes nothing that ended.
//
// The first MAX_TOGETHER_PAUSE_DAYS together days in a row pause the streak and the reminders. From
// the next one the ordinary rules apply until the couple has had a day apart.

/** Partners closer than this are together. The Lock Screen distance widget draws the same line. */
export const TOGETHER_RADIUS_METERS = 1000;
/** Together days in a row that pause the streak and the reminders. */
export const MAX_TOGETHER_PAUSE_DAYS = 14;
/**
 * How long a `together_days` row is kept. A live streak can read back this far: 14 paused days, a
 * missed day the free freeze covers and 14 more paused days after its last day, and the 14 days
 * before that day, which decide how long the pause may still run.
 */
export const TOGETHER_DAYS_KEPT = 45;

/** A fix this old or newer can start a together day. */
const FIX_MAX_AGE_MS = 60 * 60_000;
/** The partner's latest fix can be this old, since a phone at rest sends nothing. */
const PARTNER_FIX_MAX_AGE_MS = 12 * 3_600_000;
/** A fix less precise than this, or without a known accuracy, cannot start a together day. */
const FIX_MAX_ACCURACY_METERS = 500;

const EARTH_RADIUS_METERS = 6_371_000;

type Coordinates = { latitude: number; longitude: number };

/** Great-circle distance between two coordinates in whole meters (haversine). */
export function distanceMeters(a: Coordinates, b: Coordinates): number {
  const rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad;
  const dLon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) ** 2;
  return Math.round(2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(h))));
}

type Fix = Pick<Doc<"latest_partner_locations">, "latitude" | "longitude" | "accuracy_m" | "captured_at">;

const isPrecise = (fix: Fix) => fix.accuracy_m !== undefined && fix.accuracy_m <= FIX_MAX_ACCURACY_METERS;

/**
 * The later capture time of the two fixes, which dates a new together day, when `fix` arrived
 * fresh, the partner's fix is recent, both are precise and they are closer than the radius. Null
 * otherwise.
 */
export function togetherCaptureAt(fix: Fix, partnerFix: Fix, now: string): string | null {
  const fresh =
    fix.captured_at >= addMs(now, -FIX_MAX_AGE_MS) && partnerFix.captured_at >= addMs(now, -PARTNER_FIX_MAX_AGE_MS);
  const close = isPrecise(fix) && isPrecise(partnerFix) && distanceMeters(fix, partnerFix) < TOGETHER_RADIUS_METERS;
  if (!fresh || !close) return null;
  return fix.captured_at > partnerFix.captured_at ? fix.captured_at : partnerFix.captured_at;
}

/** What the couple's together days look like from `floor` on, read once. */
export type TogetherDays = {
  floor: string;
  rows: ReadonlySet<string>;
  visits: readonly Pick<Doc<"visits">, "start_date" | "end_date" | "together_from">[];
  runSince: string | null;
};

/** The couple's together days that can matter for `from` and later days. */
export async function readTogetherDays(ctx: ReaderCtx, coupleId: string, from: string): Promise<TogetherDays> {
  const floor = addDaysToDate(from, -MAX_TOGETHER_PAUSE_DAYS);
  const rows = await ctx.db
    .query("together_days")
    .withIndex("by_couple_id_local_date", (q) => q.eq("couple_id", coupleId).gte("local_date", floor))
    .collect();
  const visits = await ctx.db
    .query("visits")
    .withIndex("by_couple_id_deleted_at_end_date", (q) =>
      q.eq("couple_id", coupleId).eq("deleted_at", undefined).gte("end_date", floor),
    )
    .collect();
  const run = await locationRun(ctx, coupleId);
  return { floor, rows: new Set(rows.map((row) => row.local_date)), visits, runSince: run?.since ?? null };
}

const hasTogetherDays = (days: TogetherDays) => days.rows.size > 0 || days.visits.length > 0 || days.runSince !== null;

/** True when the partners are together on `date`, which must not be before `days.floor`. */
function isTogether(days: TogetherDays, date: string): boolean {
  if (date < days.floor) throw new Error(`together days were read from ${days.floor}, not ${date}`);
  return (
    days.rows.has(date) ||
    (days.runSince !== null && date >= days.runSince) ||
    days.visits.some((visit) => visit.start_date <= date && date <= visit.end_date && date >= visit.together_from)
  );
}

/** The first day of the together days in a row that end on `date`, looking back at most the pause. */
function runStart(days: TogetherDays, date: string): string {
  let start = date;
  for (let back = 0; back < MAX_TOGETHER_PAUSE_DAYS && isTogether(days, addDaysToDate(start, -1)); back++) {
    start = addDaysToDate(start, -1);
  }
  return start;
}

/** True when `date` pauses the streak: a together day within the first MAX_TOGETHER_PAUSE_DAYS of its run. */
export function pausesOn(days: TogetherDays, date: string): boolean {
  if (!isTogether(days, date)) return false;
  for (let back = 1; back <= MAX_TOGETHER_PAUSE_DAYS; back++) {
    if (!isTogether(days, addDaysToDate(date, -back))) return true;
  }
  return false;
}

/** The first `count` days after `after` that the streak needs, earliest first. */
export function neededDaysAfter(days: TogetherDays, after: string, count: number): string[] {
  const needed: string[] = [];
  for (let date = addDaysToDate(after, 1); needed.length < count; date = addDaysToDate(date, 1)) {
    if (!pausesOn(days, date)) needed.push(date);
  }
  return needed;
}

export type PauseSpan = { from: string; until: string };

/** The paused days in a row from `from`, which pauses. */
function spanFrom(days: TogetherDays, from: string): PauseSpan {
  let until = from;
  while (pausesOn(days, addDaysToDate(until, 1))) until = addDaysToDate(until, 1);
  return { from, until };
}

/**
 * The paused days in a row that hold `today`, or else the next ones a planned visit makes. Null
 * when neither exists. A location run that is still open counts as going on.
 */
export function pauseAround(days: TogetherDays, today: string): PauseSpan | null {
  if (pausesOn(days, today)) return spanFrom(days, runStart(days, today));
  const starts = days.visits
    .map((visit) => (visit.start_date > visit.together_from ? visit.start_date : visit.together_from))
    .filter((start) => start > today)
    .sort();
  const next = starts.find((start) => !isTogether(days, addDaysToDate(start, -1)) && pausesOn(days, start));
  return next === undefined ? null : spanFrom(days, next);
}

/** The couple's local date at `at`: the couple day that holds it, or else the one the partners' zones give. */
export async function coupleDateAt(ctx: ReaderCtx, coupleId: string, at: string): Promise<string> {
  const day = await findCoupleDayAt(ctx, coupleId, at);
  return day?.local_date ?? (await resolveCoupleDayAnchorAt(ctx, coupleId, at)).local_date;
}

/**
 * The couple's together days around `at` and its local date then, or null when it has none or no
 * longer has members. Reads no date for a couple without together days. `read` is together days
 * the caller read from the couple's date at `at`, or earlier. The date comes from the partners'
 * zones, so a query that calls this picks no rows by the clock.
 */
async function togetherDaysAt(
  ctx: ReaderCtx,
  coupleId: string,
  at: string,
  read?: TogetherDays,
): Promise<{ days: TogetherDays; today: string } | null> {
  // The couple's date is at most a day from the UTC date, so this reads enough before it.
  const days = read ?? (await readTogetherDays(ctx, coupleId, addDaysToDate(at.slice(0, 10), -1)));
  if (!hasTogetherDays(days)) return null;
  // A reminder queued before the relationship ended can still ask.
  const member = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .first();
  return member === null ? null : { days, today: (await resolveCoupleDayAnchorAt(ctx, coupleId, at)).local_date };
}

/** True when the partners are together on the couple's local day at `at`, by a visit or by location. */
export async function isCoupleTogetherAt(ctx: ReaderCtx, coupleId: string, at: string): Promise<boolean> {
  const found = await togetherDaysAt(ctx, coupleId, at);
  return found !== null && isTogether(found.days, found.today);
}

/** True when the couple's local day at `at` pauses the streak and the reminders. */
export async function pausedTogetherAt(ctx: ReaderCtx, coupleId: string, at: string): Promise<boolean> {
  const found = await togetherDaysAt(ctx, coupleId, at);
  return found !== null && pausesOn(found.days, found.today);
}

/** The paused days around the couple's local day at `at` (`pauseAround`). `read` is as for `togetherDaysAt`. */
export async function pauseAroundAt(
  ctx: ReaderCtx,
  coupleId: string,
  at: string,
  read?: TogetherDays,
): Promise<PauseSpan | null> {
  const found = await togetherDaysAt(ctx, coupleId, at, read);
  return found === null ? null : pauseAround(found.days, found.today);
}

/** Stores `date` as a together day. Returns false when it already was one. */
async function insertTogetherDay(
  ctx: WriterCtx,
  coupleId: string,
  date: string,
  source: Doc<"together_days">["source"],
  now: string,
): Promise<boolean> {
  const stored = await ctx.db
    .query("together_days")
    .withIndex("by_couple_id_local_date", (q) => q.eq("couple_id", coupleId).eq("local_date", date))
    .first();
  if (stored) return false;
  await ctx.db.insert("together_days", { couple_id: coupleId, local_date: date, source, created_at: now });
  return true;
}

/** Stores the days from `from` to `through` that are kept (`TOGETHER_DAYS_KEPT`) and not stored yet. */
async function keepDays(
  ctx: WriterCtx,
  coupleId: string,
  from: string,
  through: string,
  source: Doc<"together_days">["source"],
  today: string,
  now: string,
): Promise<void> {
  const oldestKept = addDaysToDate(today, -TOGETHER_DAYS_KEPT);
  for (let date = from > oldestKept ? from : oldestKept; date <= through; date = addDaysToDate(date, 1)) {
    await insertTogetherDay(ctx, coupleId, date, source, now);
  }
}

/**
 * Keeps the together days that `visit` made of days that ended, so changing its dates or deleting
 * it changes only today and later. Call before every change to a visit's dates.
 */
export async function keepVisitDays(ctx: WriterCtx, visit: Doc<"visits">, now: string): Promise<void> {
  const today = await coupleDateAt(ctx, visit.couple_id, now);
  const from = visit.start_date > visit.together_from ? visit.start_date : visit.together_from;
  const yesterday = addDaysToDate(today, -1);
  const through = visit.end_date < yesterday ? visit.end_date : yesterday;
  await keepDays(ctx, visit.couple_id, from, through, "visit", today, now);
}

const locationRun = (ctx: ReaderCtx, coupleId: string) =>
  ctx.db
    .query("together_location_runs")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();

/**
 * Ends the couple's location run, if one is open. Its days that ended become stored days, and today
 * stops being a together day unless a fix already made it one. Returns true when a run was open.
 */
export async function endLocationRun(ctx: WriterCtx, coupleId: string, now: string): Promise<boolean> {
  const run = await locationRun(ctx, coupleId);
  if (!run) return false;
  const today = await coupleDateAt(ctx, coupleId, now);
  await keepDays(ctx, coupleId, run.since, addDaysToDate(today, -1), "location", today, now);
  await ctx.db.delete(run._id);
  return true;
}

/**
 * Updates the together days after `fix` was stored, given the partner's latest fix, or null when
 * the partner does not share now. Fixes that show the partners together store that day and open a
 * location run, unless one is open already. Fixes that show them apart, or a partner who does not
 * share, end the run. Returns true when the together days changed, so the caller refreshes the streak.
 */
export async function noteLocationFix(
  ctx: WriterCtx,
  coupleId: string,
  fix: Fix,
  partnerFix: Fix | null,
  now: string,
): Promise<boolean> {
  if (partnerFix === null || distanceMeters(fix, partnerFix) >= TOGETHER_RADIUS_METERS) {
    return await endLocationRun(ctx, coupleId, now);
  }
  const capturedAt = togetherCaptureAt(fix, partnerFix, now);
  if (capturedAt === null || (await locationRun(ctx, coupleId)) !== null) return false;
  const date = await coupleDateAt(ctx, coupleId, capturedAt);
  // A day that already ended keeps what it was.
  if (date !== (await coupleDateAt(ctx, coupleId, now))) return false;
  await insertTogetherDay(ctx, coupleId, date, "location", now);
  await ctx.db.insert("together_location_runs", { couple_id: coupleId, since: date, created_at: now });
  return true;
}
