import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { resolveMemberStreakTimeZone } from "./streakDeadlines";
import { addDaysToDate, addMs, localDateOf, startOfLocalDay } from "./time";

// A together day is a date on the streak's clock (`StreakClock`) on which the partners are
// together: a `together_days` row spans it, or a visit covers it from the visit's `together_from`.
//
// A day that ended on that clock keeps what it was. Writes reach only today and later: a location
// match stores today, a visit counts from the day its dates were saved, and `keepVisitDays` stores
// the ended days a visit covered before its dates change or it goes.
//
// The first MAX_TOGETHER_PAUSE_DAYS together days in a row rest the streak and the reminders. From
// the next one the ordinary rules apply until the couple has had a day apart.

/** Partners closer than this are together. The Lock Screen distance widget draws the same line. */
export const TOGETHER_RADIUS_METERS = 1000;
/** Together days in a row that rest the streak and the reminders. */
export const MAX_TOGETHER_PAUSE_DAYS = 14;
/**
 * How long a date in `together_days` is kept. The streak reads back to 16 days before its last
 * qualified day, which a live streak reached at most 16 days ago.
 */
export const TOGETHER_DAYS_KEPT = 45;
/** Days before a streak's last qualified date that its read covers: the pause before it, and the clock's slack. */
export const TOGETHER_LOOKBACK_DAYS = MAX_TOGETHER_PAUSE_DAYS + 2;

const later = (a: string, b: string) => (b > a ? b : a);

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
 * The later capture time of the two fixes, which dates the together day, when `fix` arrived
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

/**
 * The streak's clock: the zones its deadline uses, one per partner (`resolveMemberStreakTimeZone`).
 * A date ends at its latest local midnight among them, so an instant is on the earliest of the
 * partners' local dates. `dayOf` and `dayEnd` answer, for everything about together days, which
 * day an instant is on and when a day has ended.
 */
export type StreakClock = readonly string[];

/** The couple's streak clock. A couple without active members reads UTC, so nothing here throws. */
export async function streakClock(ctx: ReaderCtx, coupleId: string): Promise<StreakClock> {
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
  const zones = await Promise.all(members.map((member) => resolveMemberStreakTimeZone(ctx, member.user_id)));
  return zones.length > 0 ? zones : ["UTC"];
}

/** The date `at` falls on: the earliest local date among the clock's zones. */
export function dayOf(clock: StreakClock, at: string): string {
  return clock.map((zone) => localDateOf(at, zone)).reduce((a, b) => (b < a ? b : a));
}

/** When `date` ends: its latest local midnight among the clock's zones. `date` has ended once `dayOf` is past it. */
export function dayEnd(clock: StreakClock, date: string): string {
  return clock.map((zone) => startOfLocalDay(addDaysToDate(date, 1), zone)).reduce(later);
}

/** Together days in a row, `start_date` to `end_date`, both dates on the streak's clock. */
type Span = { start_date: string; end_date: string };

/** The couple's together days from `from` on, read once, with the clock their dates are on. */
export type TogetherDays = {
  clock: StreakClock;
  /** A date before this was not read and counts as a day apart. */
  from: string;
  spans: readonly Span[];
};

/**
 * The couple's together days from `from` on: its `together_days` rows, and its visits from each
 * one's `together_from`. Null when it has none, which costs two empty index reads and no document,
 * so a couple that is never together reads what it did before.
 */
export async function readTogetherDays(ctx: ReaderCtx, coupleId: string, from: string): Promise<TogetherDays | null> {
  const rows = await ctx.db
    .query("together_days")
    .withIndex("by_couple_id_end_date", (q) => q.eq("couple_id", coupleId).gte("end_date", from))
    .collect();
  const visits = await ctx.db
    .query("visits")
    .withIndex("by_couple_id_deleted_at_end_date", (q) =>
      q.eq("couple_id", coupleId).eq("deleted_at", undefined).gte("end_date", from),
    )
    .collect();
  if (rows.length === 0 && visits.length === 0) return null;
  const spans = [
    ...rows,
    ...visits.map((visit) => ({ ...visit, start_date: later(visit.start_date, visit.together_from) })),
  ];
  return { clock: await streakClock(ctx, coupleId), from, spans };
}

export function isTogether(days: TogetherDays, date: string): boolean {
  return date >= days.from && days.spans.some((span) => span.start_date <= date && date <= span.end_date);
}

/** True when `date` rests the streak: a together day among the first MAX_TOGETHER_PAUSE_DAYS of its run. */
export function pausesOn(days: TogetherDays, date: string): boolean {
  if (!isTogether(days, date)) return false;
  for (let back = 1; back <= MAX_TOGETHER_PAUSE_DAYS; back++) {
    if (!isTogether(days, addDaysToDate(date, -back))) return true;
  }
  return false;
}

/** The first day after `date` that does not rest the streak. It is at most MAX_TOGETHER_PAUSE_DAYS + 1 days on. */
export function nextNeededDay(days: TogetherDays, date: string): string {
  let next = addDaysToDate(date, 1);
  while (pausesOn(days, next)) next = addDaysToDate(next, 1);
  return next;
}

/** Days in a row that rest the streak, `from` to `until`, both dates on the streak's clock. */
export type RestSpan = { from: string; until: string };

/**
 * The resting days after `after` that hold `today`, or else the next ones, or null. Days after
 * today rest only by a visit, since location stores today at the latest.
 */
export function restSpan(days: TogetherDays, after: string, today: string): RestSpan | null {
  let from: string | undefined;
  const first = today > after ? today : addDaysToDate(after, 1);
  if (pausesOn(days, first)) {
    from = first;
    while (from > addDaysToDate(after, 1) && pausesOn(days, addDaysToDate(from, -1))) from = addDaysToDate(from, -1);
  } else {
    from = days.spans
      .map((span) => later(span.start_date, addDaysToDate(first, 1)))
      .filter((start) => pausesOn(days, start))
      .sort()[0];
  }
  if (from === undefined) return null;
  let until = from;
  while (pausesOn(days, addDaysToDate(until, 1))) until = addDaysToDate(until, 1);
  return { from, until };
}

/** The couple's together days around `at` and the date `at` is on, or null when it has none. */
async function togetherDaysAt(ctx: ReaderCtx, coupleId: string, at: string) {
  const days = await readTogetherDays(ctx, coupleId, addDaysToDate(at.slice(0, 10), -TOGETHER_LOOKBACK_DAYS));
  return days === null ? null : { days, today: dayOf(days.clock, at) };
}

/** True when the partners are together on the day `at` is on, by a visit or by location. */
export async function isCoupleTogetherAt(ctx: ReaderCtx, coupleId: string, at: string): Promise<boolean> {
  const found = await togetherDaysAt(ctx, coupleId, at);
  return found !== null && isTogether(found.days, found.today);
}

/** True when the day `at` is on rests the streak and the reminders. */
export async function pausedTogetherAt(ctx: ReaderCtx, coupleId: string, at: string): Promise<boolean> {
  const found = await togetherDaysAt(ctx, coupleId, at);
  return found !== null && pausesOn(found.days, found.today);
}

/** The date `now` is on, on the couple's streak clock. */
export async function todayOnStreakClock(ctx: ReaderCtx, coupleId: string, now: string): Promise<string> {
  return dayOf(await streakClock(ctx, coupleId), now);
}

/** The couple's `together_days` rows that end on `date` or later, latest end first. */
const rowsEndingFrom = (ctx: ReaderCtx, coupleId: string, date: string) =>
  ctx.db
    .query("together_days")
    .withIndex("by_couple_id_end_date", (q) => q.eq("couple_id", coupleId).gte("end_date", date))
    .order("desc");

/**
 * Keeps the together days that `visit` made of days that ended before `today`, so changing its
 * dates or deleting it changes only today and later. Call before every such change. The days join
 * a row the visit's earlier change kept when they follow it.
 */
export async function keepVisitDays(ctx: WriterCtx, visit: Doc<"visits">, today: string, now: string): Promise<void> {
  const firstDay = [visit.start_date, visit.together_from, addDaysToDate(today, -TOGETHER_DAYS_KEPT)].reduce(later);
  const yesterday = addDaysToDate(today, -1);
  const lastDay = visit.end_date < yesterday ? visit.end_date : yesterday;
  if (lastDay < firstDay) return;
  const kept = (await rowsEndingFrom(ctx, visit.couple_id, addDaysToDate(firstDay, -1)).collect()).find(
    (row) => row.source === "visit" && row.start_date <= firstDay,
  );
  if (kept === undefined) {
    const row = { couple_id: visit.couple_id, start_date: firstDay, end_date: lastDay, source: "visit" as const };
    await ctx.db.insert("together_days", { ...row, created_at: now, updated_at: now });
  } else if (kept.end_date < lastDay) {
    await ctx.db.patch(kept._id, { end_date: lastDay, updated_at: now });
  }
}

/**
 * Stores `date` as a day location showed the partners together, after `latest`, the couple's row
 * that ends last. It runs at most once per couple and date: the first match of the day, and never
 * for a date already stored.
 */
async function recordLocationTogetherDay(
  ctx: WriterCtx,
  coupleId: string,
  date: string,
  latest: Doc<"together_days"> | null,
  now: string,
): Promise<void> {
  if (latest?.source === "location" && latest.end_date === addDaysToDate(date, -1)) {
    await ctx.db.patch(latest._id, { end_date: date, updated_at: now });
  } else {
    const row = { couple_id: coupleId, start_date: date, end_date: date, source: "location" as const };
    await ctx.db.insert("together_days", { ...row, created_at: now, updated_at: now });
  }
}

/**
 * Stores today as a together day when `fix`, just stored, and the partner's latest fix show the
 * partners together (`togetherCaptureAt`). The day is the one the later capture is on, and only
 * today counts, so a fix sent after its day ended marks nothing. Nothing else a fix, a pause or
 * turning sharing off does changes a stored day. `partnerFix` is null when the partner has
 * sharing off, and a paused partner's last fix counts. Returns whether the two fixes show the
 * partners together, also when the day was already stored.
 */
export async function noteLocationFix(
  ctx: WriterCtx,
  coupleId: string,
  fix: Fix,
  partnerFix: Fix | null,
  now: string,
): Promise<boolean> {
  const capturedAt = partnerFix === null ? null : togetherCaptureAt(fix, partnerFix, now);
  if (capturedAt === null) return false;
  const clock = await streakClock(ctx, coupleId);
  const date = dayOf(clock, capturedAt);
  if (date !== dayOf(clock, now)) return true;
  // Only location stores today, so a row that reaches today is a match from earlier today.
  const latest = await rowsEndingFrom(ctx, coupleId, addDaysToDate(date, -1)).first();
  if (latest !== null && latest.end_date >= date) return true;
  await recordLocationTogetherDay(ctx, coupleId, date, latest, now);
  return true;
}
