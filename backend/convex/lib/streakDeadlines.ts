import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";
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

/** Streaks shorter than this restart when they break: no freeze and no restore offer. */
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

/** The deadline after a freeze adds one day: the next local midnight in each partner's zone. */
export function frozenDeadlineAt(ctx: ReaderCtx, coupleId: string, deadline: string): Promise<string> {
  return resolveStreakDeadlineAt(ctx, coupleId, deadline, 1);
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
