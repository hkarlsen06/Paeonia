import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { fail } from "./errors";
import { newUuid } from "./ids";
import {
  endOfLocalDay,
  isValidTimeZone,
  localDateOf,
  localWallClockMs,
  nowIso,
  startOfLocalDay,
  validTimeZoneOrUtc,
} from "./time";

export type CoupleDayAnchor = {
  local_date: string;
  anchor_time_zone_id: string;
  starts_at: string;
  ends_at: string;
};

/**
 * Port of `internal.resolve_couple_day_anchor_at`.
 *
 * The couple day follows the active member whose local wall clock is earliest
 * (the westmost zone), ties broken by zone name. Members without a valid
 * profile zone count as UTC.
 */
export async function resolveCoupleDayAnchorAt(
  ctx: ReaderCtx,
  coupleId: string,
  observedAt: string | null | undefined,
): Promise<CoupleDayAnchor> {
  if (!observedAt) {
    return fail("23514", "daily operation timestamp is required");
  }
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
  if (members.length === 0) {
    return fail("23514", "active couple members are required");
  }
  const observedMs = Date.parse(observedAt);
  const candidates: { timeZone: string; wallMs: number }[] = [];
  for (const member of members) {
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", member.user_id))
      .unique();
    const timeZone = validTimeZoneOrUtc(profile?.time_zone_id);
    candidates.push({ timeZone, wallMs: localWallClockMs(observedMs, timeZone) });
  }
  candidates.sort((a, b) =>
    a.wallMs !== b.wallMs ? a.wallMs - b.wallMs : a.timeZone < b.timeZone ? -1 : a.timeZone > b.timeZone ? 1 : 0,
  );
  const anchor = candidates[0];
  const localDate = localDateOf(observedMs, anchor.timeZone);
  return {
    local_date: localDate,
    anchor_time_zone_id: anchor.timeZone,
    starts_at: startOfLocalDay(localDate, anchor.timeZone),
    ends_at: endOfLocalDay(localDate, anchor.timeZone),
  };
}

/** Port of `internal.resolve_couple_day_anchor`. */
export function resolveCoupleDayAnchor(ctx: ReaderCtx, coupleId: string): Promise<CoupleDayAnchor> {
  return resolveCoupleDayAnchorAt(ctx, coupleId, nowIso());
}

/** The couple day whose window contains `observedAt`, latest start first, or null. */
export async function findCoupleDayAt(
  ctx: ReaderCtx,
  coupleId: string,
  observedAt: string,
): Promise<Doc<"couple_days"> | null> {
  // A couple day is one local day, so at most about 25 hours long. Rows that start
  // more than 2 days before the instant cannot contain it.
  const earliestStart = new Date(Date.parse(observedAt) - 2 * 86_400_000).toISOString();
  const rows = ctx.db
    .query("couple_days")
    .withIndex("by_couple_id_starts_at", (q) =>
      q.eq("couple_id", coupleId).gte("starts_at", earliestStart).lte("starts_at", observedAt),
    )
    .order("desc");
  for await (const day of rows) {
    if (observedAt >= day.starts_at && observedAt < day.ends_at) {
      return day;
    }
  }
  return null;
}

/** Port of `internal.get_or_create_couple_day_at`. Returns the couple day id. */
export async function getOrCreateCoupleDayAt(
  ctx: WriterCtx,
  coupleId: string,
  observedAt: string | null | undefined,
): Promise<string> {
  if (!observedAt) {
    return fail("23514", "daily operation timestamp is required");
  }
  const existing = await findCoupleDayAt(ctx, coupleId, observedAt);
  if (existing) {
    return existing.id;
  }
  const anchor = await resolveCoupleDayAnchorAt(ctx, coupleId, observedAt);
  // (couple_id, local_date) is unique. A day that exists but does not contain the instant wins.
  const sameDate = await ctx.db
    .query("couple_days")
    .withIndex("by_couple_id_local_date", (q) =>
      q.eq("couple_id", coupleId).eq("local_date", anchor.local_date),
    )
    .unique();
  if (sameDate) {
    return sameDate.id;
  }
  const id = newUuid();
  await ctx.db.insert("couple_days", {
    id,
    couple_id: coupleId,
    local_date: anchor.local_date,
    anchor_time_zone_id: anchor.anchor_time_zone_id,
    starts_at: anchor.starts_at,
    ends_at: anchor.ends_at,
    created_at: nowIso(),
  });
  return id;
}

/** Port of `internal.get_or_create_today_couple_day`. */
export function getOrCreateTodayCoupleDay(ctx: WriterCtx, coupleId: string): Promise<string> {
  return getOrCreateCoupleDayAt(ctx, coupleId, nowIso());
}

/** Port of `internal.user_local_date`: the user's local calendar date, or the UTC date without a valid profile zone. */
export async function userLocalDate(
  ctx: ReaderCtx,
  userId: string,
  observedAt: string,
): Promise<string> {
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
  const timeZone = isValidTimeZone(profile?.time_zone_id) ? profile.time_zone_id : "UTC";
  return localDateOf(observedAt, timeZone);
}
