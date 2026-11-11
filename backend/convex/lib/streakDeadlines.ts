import type { Doc } from "../_generated/dataModel";
import { daysBetweenDates } from "./coupleDates";
import { getByUuid, type ReaderCtx } from "./db";
import { fail } from "./errors";
import {
  addDaysToDate,
  addDaysToInstant,
  addHours,
  isValidTimeZone,
  localDateOf,
  localMidnightAfter,
  localWallClockMs,
  zonedLocalToUtcMs,
} from "./time";
import { neededDaysAfter, readTogetherDays, type TogetherDays } from "./together";

/** Streaks shorter than this restart when they break: no freeze, no free save and no restore offer. */
export const MIN_PROTECTED_STREAK = 3;
/** Days between the couple's free streak freezes. */
export const FREEZE_COOLDOWN_DAYS = 30;
/** Local hour of the evening streak reminder, in the partner's own zone. */
const EVENING_REMINDER_HOUR = 19;
/** The evening reminder comes at least this long before the deadline, ahead of the last-hour reminder. */
export const EVENING_REMINDER_LEAD_HOURS = 2;
/**
 * No last-hour reminder before this local hour. When partners live in different zones, the deadline can
 * fall in one partner's night; that partner already had the evening reminder the day before.
 */
const LAST_HOUR_REMINDER_EARLIEST_HOUR = 8;

/**
 * When to send one partner the evening streak reminder: the latest 19:00 in their
 * zone that is at least two hours before the deadline. When the deadline falls in
 * the partner's early morning, that is the evening before, not the next evening.
 */
export function eveningReminderAt(deadline: string, timeZone: string): string {
  const latest = addHours(deadline, -EVENING_REMINDER_LEAD_HOURS);
  const date = localDateOf(latest, timeZone);
  const sameDay = new Date(zonedLocalToUtcMs(date, timeZone, EVENING_REMINDER_HOUR)).toISOString();
  if (sameDay <= latest) {
    return sameDay;
  }
  return new Date(zonedLocalToUtcMs(addDaysToDate(date, -1), timeZone, EVENING_REMINDER_HOUR)).toISOString();
}

/** True when the last-hour streak reminder may reach someone in `timeZone` at `now`. */
export function lastHourReminderAllowed(now: string, timeZone: string): boolean {
  return new Date(localWallClockMs(Date.parse(now), timeZone)).getUTCHours() >= LAST_HOUR_REMINDER_EARLIEST_HOUR;
}

/**
 * The zone that protects one member's streak: the newest active device with a
 * valid zone, else the profile zone, else UTC.
 */
export async function resolveMemberStreakTimeZone(ctx: ReaderCtx, userId: string): Promise<string> {
  const devices = await ctx.db
    .query("user_devices")
    .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", userId).eq("disabled_at", undefined))
    .collect();
  const latest = devices
    .filter((device) => isValidTimeZone(device.time_zone_id))
    .sort((a, b) => {
      if (a.last_seen_at !== b.last_seen_at) return a.last_seen_at < b.last_seen_at ? 1 : -1;
      if (a.updated_at !== b.updated_at) return a.updated_at < b.updated_at ? 1 : -1;
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    })[0];
  if (latest?.time_zone_id) {
    return latest.time_zone_id;
  }
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
  return isValidTimeZone(profile?.time_zone_id) ? profile.time_zone_id : "UTC";
}

/**
 * Port of `internal.resolve_streak_deadline_at`: local midnight, `localDaysAfter`
 * days after the observed local date, in each active member's zone. The latest
 * of those instants wins, so the streak waits for the last partner to reach midnight.
 */
export async function resolveStreakDeadlineAt(
  ctx: ReaderCtx,
  coupleId: string | null | undefined,
  observedAt: string | null | undefined,
  localDaysAfter: number,
): Promise<string> {
  if (!coupleId || !observedAt) {
    return fail("23514", "couple and observed timestamp are required");
  }
  if (localDaysAfter < 1 || localDaysAfter > 2) {
    return fail("23514", "local deadline offset must be one or two days");
  }
  return await latestMidnightAfter(ctx, coupleId, observedAt, localDaysAfter);
}

/** `resolveStreakDeadlineAt` for any number of days. Together days can put a needed day further away. */
async function latestMidnightAfter(
  ctx: ReaderCtx,
  coupleId: string,
  observedAt: string,
  localDaysAfter: number,
): Promise<string> {
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
  if (members.length === 0) {
    return fail("23514", "active couple members are required");
  }
  let deadline: string | null = null;
  for (const member of members) {
    const timeZone = await resolveMemberStreakTimeZone(ctx, member.user_id);
    const candidate = localMidnightAfter(observedAt, timeZone, localDaysAfter);
    if (deadline === null || candidate > deadline) {
      deadline = candidate;
    }
  }
  return deadline as string;
}

/** When the couple's next free freeze is ready, or null when one is ready now. */
export function freezeReadyAt(state: Pick<Doc<"streak_states">, "freeze_used_at">): string | null {
  return state.freeze_used_at === undefined ? null : addDaysToInstant(state.freeze_used_at, FREEZE_COOLDOWN_DAYS);
}

/** True when a free freeze is ready at `at`. */
export function freezeReadyBy(state: Pick<Doc<"streak_states">, "freeze_used_at">, at: string): boolean {
  const readyAt = freezeReadyAt(state);
  return readyAt === null || readyAt <= at;
}

/**
 * True when the stored freeze covers the missed day after the streak last qualified at `qualifiedAt`.
 * A freeze is stamped with the deadline it covered, which is always after the qualifying moment.
 */
export function freezeCoversGap(state: Pick<Doc<"streak_states">, "freeze_used_at">, qualifiedAt: string): boolean {
  return state.freeze_used_at !== undefined && state.freeze_used_at > qualifiedAt;
}

/** Needed days `streakTiming` finds: two for the deadline and the freeze, three for a free save and two restore days. */
const NEEDED_DAYS = 5;

/**
 * When a streak breaks, worked out the same way for every read and write. A day the partners spend
 * together pauses the streak (`lib/together.ts`), so the days that count here are the needed days
 * after the last qualified day, the ones that do not pause it. Without together days they are the
 * days that follow it.
 */
export type StreakTiming = {
  /** When the last qualified day counts from: when both partners showed up, or its start for a restored day. */
  start: string;
  /** Both partners showed up on the last qualified day. False for a day a restore filled in. */
  observed: boolean;
  /** The needed days after the last qualified day, earliest first. */
  needed: readonly string[];
  /** The end of the first needed day, local midnight in each partner's zone, the latest of them. */
  deadline: string;
  /** A free freeze already covers the first needed day, so the streak lasts to the end of the second. */
  frozen: boolean;
};

/**
 * The timing of `state`'s streak, or null when it cannot be worked out, such as for a couple that
 * ended. Pass `together` when the caller already read the couple's together days from the day after
 * the last qualified one, or earlier.
 */
export async function streakTiming(
  ctx: ReaderCtx,
  coupleId: string,
  state: Pick<Doc<"streak_states">, "last_qualified_date" | "last_qualified_couple_day_id" | "freeze_used_at">,
  together?: TogetherDays,
): Promise<StreakTiming | null> {
  const lastDate = state.last_qualified_date;
  if (lastDate === undefined) return null;
  const qualifiedAt = await getCoupleDayStreakQualifiedAt(ctx, coupleId, state.last_qualified_couple_day_id);
  const start = qualifiedAt ?? (await restoredDayStart(ctx, coupleId, state.last_qualified_couple_day_id));
  if (start === null) return null;
  const days = together ?? (await readTogetherDays(ctx, coupleId, addDaysToDate(lastDate, 1)));
  const needed = neededDaysAfter(days, lastDate, NEEDED_DAYS);
  return {
    start,
    observed: qualifiedAt !== null,
    needed,
    deadline: await latestMidnightAfter(ctx, coupleId, start, daysBetweenDates(lastDate, needed[0]) + 1),
    frozen: freezeCoversGap(state, start),
  };
}

/** The start of a last qualified day without both partners' events: a day a paid restore filled in. */
async function restoredDayStart(
  ctx: ReaderCtx,
  coupleId: string,
  coupleDayId: string | undefined,
): Promise<string | null> {
  const couple = await getByUuid(ctx, "couples", coupleId);
  const day = coupleDayId === undefined ? null : await getByUuid(ctx, "couple_days", coupleDayId);
  return couple?.status === "active" && day ? day.starts_at : null;
}

/**
 * The end of needed day `to` when needed day `from` ends at `deadline` (indexes into
 * `timing.needed`). Without a timing, needed days follow each other.
 */
export function neededDayEnd(
  ctx: ReaderCtx,
  coupleId: string,
  timing: StreakTiming | null,
  deadline: string,
  from: number,
  to: number,
): Promise<string> {
  const days = timing === null ? to - from : daysBetweenDates(timing.needed[from], timing.needed[to]);
  return latestMidnightAfter(ctx, coupleId, deadline, days);
}

/** When a streak whose last day qualified at `observedAt`, on `date`, breaks: the end of its first needed day. */
export async function deadlineAfterDay(
  ctx: ReaderCtx,
  coupleId: string,
  date: string,
  observedAt: string,
): Promise<string> {
  const days = await readTogetherDays(ctx, coupleId, addDaysToDate(date, 1));
  const [first] = neededDaysAfter(days, date, 1);
  return await latestMidnightAfter(ctx, coupleId, observedAt, daysBetweenDates(date, first) + 1);
}

/**
 * When a streak that broke at `breakDeadline`, the end of needed day `breakDay`, can come back. It
 * is free until the end of the next needed day (`saveDeadline`), when both partners show up on it,
 * and by purchase until the end of the two needed days after that (`restoreDeadline`). Each end is
 * local midnight in every partner's zone, and the latest one wins, like every other streak deadline.
 */
export async function brokenStreakDeadlines(
  ctx: ReaderCtx,
  coupleId: string,
  breakDeadline: string,
  timing: StreakTiming | null,
  breakDay: number,
): Promise<{ saveDeadline: string; restoreDeadline: string }> {
  const saveDeadline = await neededDayEnd(ctx, coupleId, timing, breakDeadline, breakDay, breakDay + 1);
  return {
    saveDeadline,
    restoreDeadline: await neededDayEnd(ctx, coupleId, timing, saveDeadline, breakDay + 1, breakDay + 3),
  };
}

/** Port of `internal.resolve_next_activity_deadline_at`. */
export function resolveNextActivityDeadlineAt(
  ctx: ReaderCtx,
  coupleId: string,
  observedAt: string,
): Promise<string> {
  return resolveStreakDeadlineAt(ctx, coupleId, observedAt, 2);
}

/**
 * Port of `internal.get_couple_day_streak_qualified_at`: when every active
 * partner first had an event in the couple day, or null until both contributed.
 */
export async function getCoupleDayStreakQualifiedAt(
  ctx: ReaderCtx,
  coupleId: string,
  coupleDayId: string | null | undefined,
): Promise<string | null> {
  const couple = await ctx.db
    .query("couples")
    .withIndex("by_uuid", (q) => q.eq("id", coupleId))
    .unique();
  if (!couple || couple.status !== "active" || !coupleDayId) {
    return null;
  }
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
  const events = await ctx.db
    .query("couple_activity_events")
    .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", coupleDayId))
    .collect();
  const firstByUser = new Map<string, string>();
  for (const event of events) {
    if (event.couple_id !== coupleId) continue;
    const current = firstByUser.get(event.user_id);
    if (current === undefined || event.occurred_at < current) {
      firstByUser.set(event.user_id, event.occurred_at);
    }
  }
  if (members.length < 2) {
    return null;
  }
  let latest: string | null = null;
  for (const member of members) {
    const first = firstByUser.get(member.user_id);
    if (first === undefined) {
      return null;
    }
    if (latest === null || first > latest) {
      latest = first;
    }
  }
  return latest;
}
