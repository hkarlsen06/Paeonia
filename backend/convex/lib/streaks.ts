import type { Doc } from "../_generated/dataModel";
import { getCurrentEntitledCoupleId } from "./access";
import { findCoupleDayAt, getOrCreateCoupleDayAt } from "./coupleDays";
import { runClientOperation, type ClientOperationInput } from "./clientOperations";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { checkViolation, fail } from "./errors";
import { newUuid } from "./ids";
import { jsonbByteLength } from "./json";
import {
  freezeCoversGap,
  freezeReadyAt,
  freezeReadyBy,
  frozenDeadlineAt,
  getCoupleDayStreakQualifiedAt,
  MIN_PROTECTED_STREAK,
  resolveNextActivityDeadlineAt,
} from "./streakDeadlines";
import { addDaysToDate, addHours, nowIso, zonedLocalToUtcMs } from "./time";

export {
  FREEZE_COOLDOWN_DAYS,
  getCoupleDayStreakQualifiedAt,
  MIN_PROTECTED_STREAK,
  resolveNextActivityDeadlineAt,
  resolveStreakDeadlineAt,
} from "./streakDeadlines";

export const ACTIVITY_KINDS = [
  "daily_challenge_completed",
  "widget_drawing_saved",
  "memory_created",
  "memory_updated",
  "thread_message_sent",
] as const;
export type ActivityKind = (typeof ACTIVITY_KINDS)[number];

async function getStreakState(ctx: ReaderCtx, coupleId: string): Promise<Doc<"streak_states"> | null> {
  return await ctx.db
    .query("streak_states")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

/**
 * Port of `internal.apply_couple_activity`. Records an auditable activity event
 * and advances the shared streak once both partners have contributed to the
 * couple day. Returns the event id (the existing id when the dedupe key repeats).
 */
export async function applyCoupleActivity(
  ctx: WriterCtx,
  args: {
    couple_id: string;
    user_id: string;
    couple_day_id: string;
    activity_kind: string;
    occurred_at?: string | null;
    dedupe_key: string | null | undefined;
    metadata?: Record<string, unknown> | null;
  },
): Promise<string> {
  const coupleId = args.couple_id;
  if (!(ACTIVITY_KINDS as readonly string[]).includes(args.activity_kind)) {
    fail("23514", "couple activity kind is not supported");
  }
  const occurredAt = args.occurred_at ?? nowIso();
  const dedupeKey = args.dedupe_key?.trim() ?? "";
  if (dedupeKey.length < 1 || dedupeKey.length > 240) {
    fail("23514", "couple activity dedupe key is required");
  }
  const metadata = args.metadata ?? {};

  const coupleDay = await getByUuid(ctx, "couple_days", args.couple_day_id);
  if (!coupleDay || coupleDay.couple_id !== coupleId) {
    fail("23514", "couple activity day is invalid");
  }

  const couple = await getByUuid(ctx, "couples", coupleId);
  const member = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", args.user_id))
    .unique();
  if (!couple || couple.status !== "active" || member?.status !== "active") {
    fail("23514", "couple activity user must be an active couple member");
  }

  const duplicate = await ctx.db
    .query("couple_activity_events")
    .withIndex("by_dedupe_key", (q) => q.eq("dedupe_key", dedupeKey))
    .unique();
  if (duplicate) {
    return duplicate.id;
  }
  if (jsonbByteLength(metadata) > 2048) {
    checkViolation("couple_activity_events", "couple_activity_events_metadata_check");
  }
  const eventId = newUuid();
  await ctx.db.insert("couple_activity_events", {
    id: eventId,
    couple_id: coupleId,
    user_id: args.user_id,
    couple_day_id: args.couple_day_id,
    activity_kind: args.activity_kind as ActivityKind,
    occurred_at: occurredAt,
    dedupe_key: dedupeKey,
    metadata,
    created_at: nowIso(),
  });

  const qualifiedAt = await getCoupleDayStreakQualifiedAt(ctx, coupleId, args.couple_day_id);
  // One person can contribute more than once, but no streak state changes until
  // the other active member has also shown up during this couple day.
  if (qualifiedAt === null) {
    return eventId;
  }

  const existing = await getStreakState(ctx, coupleId);
  const resolvedDeadline = await resolveNextActivityDeadlineAt(ctx, coupleId, qualifiedAt);

  if (!existing) {
    await ctx.db.insert("streak_states", {
      couple_id: coupleId,
      current_count: 1,
      longest_count: 1,
      last_qualified_date: coupleDay.local_date,
      last_qualified_couple_day_id: coupleDay.id,
      restore_available: false,
      next_activity_deadline_at: resolvedDeadline,
      updated_at: nowIso(),
      restorable_count: 0,
    });
    return eventId;
  }

  let previousObservedAt = await getCoupleDayStreakQualifiedAt(
    ctx,
    coupleId,
    existing.last_qualified_couple_day_id,
  );
  if (previousObservedAt === null && existing.last_qualified_couple_day_id) {
    // A legacy streak may point at a day that only one partner completed. Its
    // latest event still gives a stable ordering and deadline anchor.
    const dayEvents = await ctx.db
      .query("couple_activity_events")
      .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", existing.last_qualified_couple_day_id!))
      .collect();
    for (const event of dayEvents) {
      if (event.couple_id === coupleId && (previousObservedAt === null || event.occurred_at > previousObservedAt)) {
        previousObservedAt = event.occurred_at;
      }
    }
  }
  const previousDeadline =
    previousObservedAt !== null
      ? await resolveNextActivityDeadlineAt(ctx, coupleId, previousObservedAt)
      : (existing.next_activity_deadline_at ?? null);

  if (coupleDay.id === existing.last_qualified_couple_day_id) {
    await ctx.db.patch(existing._id, withUpdatedAt({ next_activity_deadline_at: resolvedDeadline }));
    return eventId;
  }

  // A late-arriving historical day stays in the audit trail but cannot reorder the streak.
  if (previousObservedAt !== null && qualifiedAt <= previousObservedAt) {
    return eventId;
  }

  // A freeze the cron already spent on this gap, or one that is ready now, covers one missed day.
  const freezeOnGap = previousObservedAt !== null && freezeCoversGap(existing, previousObservedAt);
  let freezeUsedAt = existing.freeze_used_at;
  let continues = previousDeadline !== null && qualifiedAt < previousDeadline;
  if (continues && freezeOnGap) {
    // The day made it in time after all, for example from a phone that was offline. Give the freeze back.
    freezeUsedAt = undefined;
  } else if (
    !continues &&
    previousDeadline !== null &&
    existing.current_count >= MIN_PROTECTED_STREAK &&
    (freezeOnGap || freezeReadyBy(existing, previousDeadline))
  ) {
    continues = qualifiedAt < (await frozenDeadlineAt(ctx, coupleId, previousDeadline));
    if (continues) {
      freezeUsedAt = previousDeadline;
    }
  }

  let nextCurrentCount: number;
  let nextRestorableCount = 0;
  let nextRestorableThroughDate: string | undefined;
  let nextRestoreDeadline: string | undefined;
  if (continues) {
    nextCurrentCount = existing.current_count + 1;
  } else {
    nextCurrentCount = 1;
    const lostCount = Math.max(existing.restorable_count, existing.current_count);
    if (lostCount >= MIN_PROTECTED_STREAK) {
      nextRestorableCount = lostCount;
      nextRestorableThroughDate = existing.restorable_through_date ?? existing.last_qualified_date;
      nextRestoreDeadline =
        existing.restore_deadline ?? (previousDeadline !== null ? addHours(previousDeadline, 24) : undefined);
    }
  }

  await ctx.db.patch(
    existing._id,
    withUpdatedAt({
      current_count: nextCurrentCount,
      longest_count: Math.max(existing.longest_count, nextCurrentCount),
      last_qualified_date: coupleDay.local_date,
      last_qualified_couple_day_id: coupleDay.id,
      restore_available:
        nextRestorableCount > 0 && nextRestoreDeadline !== undefined && nextRestoreDeadline > nowIso(),
      next_activity_deadline_at: resolvedDeadline,
      restorable_count: nextRestorableCount,
      restorable_through_date: nextRestorableThroughDate,
      restore_deadline: nextRestoreDeadline,
      freeze_used_at: freezeUsedAt,
    }),
  );
  return eventId;
}

/**
 * Port of `internal.record_couple_activity`: the app-callable wrapper with a
 * client operation. Returns the activity event id.
 */
export async function recordCoupleActivity(
  ctx: WriterCtx,
  userId: string,
  args: {
    activity_kind: string;
    couple_day_id?: string | null;
    occurred_at?: string | null;
    dedupe_key: string;
    client: Omit<ClientOperationInput, "operation_kind" | "idempotency_scope" | "request">;
  },
): Promise<string> {
  const occurredAt = args.occurred_at ?? nowIso();
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const coupleDayId = args.couple_day_id ?? (await getOrCreateCoupleDayAt(ctx, coupleId, occurredAt));

  const stored = await runClientOperation(
    ctx,
    userId,
    {
      ...args.client,
      operation_kind: "record_couple_activity",
      idempotency_scope: "activity",
      request: [
        "record_couple_activity",
        coupleId,
        userId,
        coupleDayId,
        args.activity_kind,
        occurredAt,
        args.dedupe_key,
      ],
    },
    async () => {
      const eventId = await applyCoupleActivity(ctx, {
        couple_id: coupleId,
        user_id: userId,
        couple_day_id: coupleDayId,
        activity_kind: args.activity_kind,
        occurred_at: occurredAt,
        dedupe_key: args.dedupe_key,
        metadata: {},
      });
      return { activity_event_id: eventId };
    },
  );
  return stored.activity_event_id;
}

/**
 * The deadline `refreshStreakDeadline` would store: the live deadline from the
 * last qualified day and the current partner zones, one day later when a freeze
 * covers the missed day, or the stored one when it cannot be recomputed. Reads only.
 * `frozen` is true when a freeze moved the deadline.
 */
async function liveStreakDeadline(
  ctx: ReaderCtx,
  coupleId: string,
  state: Doc<"streak_states"> | null,
): Promise<{ deadline: string | null; frozen: boolean }> {
  if (!state || state.current_count <= 0 || state.restorable_count > 0) {
    return { deadline: state?.next_activity_deadline_at ?? null, frozen: false };
  }
  let qualifiedAt = await getCoupleDayStreakQualifiedAt(ctx, coupleId, state.last_qualified_couple_day_id);
  if (qualifiedAt === null && state.last_qualified_couple_day_id) {
    // Rows from before mutual participation may have counted a one-person day.
    // Anchor them to their latest event.
    const dayEvents = await ctx.db
      .query("couple_activity_events")
      .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", state.last_qualified_couple_day_id!))
      .collect();
    for (const event of dayEvents) {
      if (event.couple_id === coupleId && (qualifiedAt === null || event.occurred_at > qualifiedAt)) {
        qualifiedAt = event.occurred_at;
      }
    }
  }
  if (qualifiedAt === null) {
    return { deadline: state.next_activity_deadline_at ?? null, frozen: false };
  }
  const deadline = await resolveNextActivityDeadlineAt(ctx, coupleId, qualifiedAt);
  if (freezeCoversGap(state, qualifiedAt)) {
    return { deadline: await frozenDeadlineAt(ctx, coupleId, deadline), frozen: true };
  }
  return { deadline, frozen: false };
}

/**
 * Port of `internal.refresh_streak_deadline`. Recomputes the live deadline from
 * the last qualified day and current partner zones. Returns the deadline or null.
 */
export async function refreshStreakDeadline(ctx: WriterCtx, coupleId: string): Promise<string | null> {
  const state = await getStreakState(ctx, coupleId);
  const { deadline } = await liveStreakDeadline(ctx, coupleId, state);
  if (state && deadline !== null && state.next_activity_deadline_at !== deadline) {
    await ctx.db.patch(state._id, withUpdatedAt({ next_activity_deadline_at: deadline }));
  }
  return deadline;
}

/** Hours a restore offer stays open after the deadline passes. */
const RESTORE_WINDOW_HOURS = 24;

type StreakBreakChange = Partial<
  Pick<
    Doc<"streak_states">,
    | "current_count"
    | "freeze_used_at"
    | "next_activity_deadline_at"
    | "restorable_count"
    | "restorable_through_date"
    | "restore_deadline"
    | "restore_available"
  >
>;

/**
 * What a passed deadline does to the streak, or null when nothing changes yet.
 * In order: a ready freeze covers one missed day, a streak shorter than
 * MIN_PROTECTED_STREAK restarts at zero, and a longer one opens a 24 hour restore offer.
 */
async function streakBreakChange(
  ctx: ReaderCtx,
  coupleId: string,
  state: Doc<"streak_states"> | null,
  deadline: string | null,
  now: string,
): Promise<StreakBreakChange | null> {
  if (!state || state.current_count <= 0 || state.restorable_count !== 0 || deadline === null || now < deadline) {
    return null;
  }
  if (state.current_count < MIN_PROTECTED_STREAK) {
    return { current_count: 0 };
  }
  if (freezeReadyBy(state, deadline)) {
    // A freeze covers one day only. When the day after is also gone, the streak breaks.
    const frozenDeadline = await frozenDeadlineAt(ctx, coupleId, deadline);
    if (now < frozenDeadline) {
      return { freeze_used_at: deadline, next_activity_deadline_at: frozenDeadline };
    }
  }
  const restoreDeadline = addHours(deadline, RESTORE_WINDOW_HOURS);
  return {
    restorable_count: state.current_count,
    restorable_through_date: state.last_qualified_date,
    restore_deadline: restoreDeadline,
    restore_available: restoreDeadline > now,
  };
}

/**
 * Port of `internal.detect_streak_break`. Stores what a passed deadline does:
 * uses a free freeze, restarts a short streak, or opens a 24 hour restore offer.
 */
export async function detectStreakBreak(ctx: WriterCtx, coupleId: string): Promise<void> {
  const resolvedDeadline = await refreshStreakDeadline(ctx, coupleId);
  const state = await getStreakState(ctx, coupleId);
  const change = await streakBreakChange(ctx, coupleId, state, resolvedDeadline, nowIso());
  if (state && change) {
    await ctx.db.patch(state._id, withUpdatedAt(change));
  }
}

export type CoupleStreak = {
  current_count: number;
  longest_count: number;
  last_qualified_date: string | null;
  restore_available: boolean;
  restorable_count: number;
  restore_deadline: string | null;
  /** A free freeze would cover a missed day of this streak. */
  freeze_available: boolean;
  /** When the next free freeze is ready, or null when one is ready now. */
  freeze_ready_at: string | null;
  /** The couple missed a day and a freeze is keeping the streak alive until the next deadline. */
  freeze_saved_streak: boolean;
};

/**
 * Port of `internal.get_couple_streak_for_couple`, without the writes. Reports
 * the state `detectStreakBreak` would store right now: a zone-moved deadline, a
 * freeze that covers a missed day, and a streak that just broke as count 0 with
 * its restore offer open. Safe in a query. The streak cron persists the same state, so a subscribed query flips
 * when the stored row changes. Between the deadline and the next cron run the
 * clock alone changes the answer, which a cached query does not see.
 */
export async function readCoupleStreak(
  ctx: ReaderCtx,
  coupleId: string | null | undefined,
): Promise<CoupleStreak> {
  if (!coupleId) {
    return fail("42501", "active entitled couple access is required");
  }
  const stored = await getStreakState(ctx, coupleId);
  const now = nowIso();
  const live = await liveStreakDeadline(ctx, coupleId, stored);
  const change = await streakBreakChange(ctx, coupleId, stored, live.deadline, now);
  const state = stored && change ? { ...stored, ...change } : stored;
  const deadline = change?.next_activity_deadline_at ?? live.deadline;
  const broken = deadline !== null && now >= deadline;
  const currentCount = broken ? 0 : (state?.current_count ?? 0);
  const restorableCount = state?.restorable_count ?? 0;
  const restoreDeadline = state?.restore_deadline;
  const readyAt = state ? freezeReadyAt(state) : null;
  return {
    current_count: currentCount,
    longest_count: state?.longest_count ?? 0,
    last_qualified_date: state?.last_qualified_date ?? null,
    restore_available: restorableCount > 0 && restoreDeadline !== undefined && restoreDeadline > now,
    restorable_count: restorableCount,
    restore_deadline: restoreDeadline ?? null,
    freeze_available: currentCount >= MIN_PROTECTED_STREAK && (readyAt === null || readyAt <= now),
    freeze_ready_at: readyAt !== null && readyAt > now ? readyAt : null,
    freeze_saved_streak: currentCount > 0 && (live.frozen || change?.freeze_used_at !== undefined),
  };
}

/** Port of `internal.get_couple_streak_for_couple`. Persists the restore offer first, then reads. */
export async function getCoupleStreakForCouple(
  ctx: WriterCtx,
  coupleId: string | null | undefined,
): Promise<CoupleStreak> {
  if (!coupleId) {
    return fail("42501", "active entitled couple access is required");
  }
  await detectStreakBreak(ctx, coupleId);
  return await readCoupleStreak(ctx, coupleId);
}

export type StreakParticipation = { current_user_contributed_today: boolean; partner_contributed_today: boolean };

/** Who has contributed on one couple day. Reads only data of that day, so it does not depend on the clock. */
export async function getCoupleStreakParticipationForDay(
  ctx: ReaderCtx,
  coupleId: string,
  currentUserId: string,
  coupleDayId: string,
): Promise<StreakParticipation> {
  const events = (
    await ctx.db
      .query("couple_activity_events")
      .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", coupleDayId))
      .collect()
  ).filter((event) => event.couple_id === coupleId);
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
    .collect();
  const activeIds = new Set(members.map((member) => member.user_id));
  return {
    current_user_contributed_today: events.some((event) => event.user_id === currentUserId),
    partner_contributed_today: events.some(
      (event) => event.user_id !== currentUserId && activeIds.has(event.user_id),
    ),
  };
}

/** Port of `internal.get_couple_streak_participation_for_user`. */
export async function getCoupleStreakParticipationForUser(
  ctx: ReaderCtx,
  coupleId: string,
  currentUserId: string,
  observedAt: string = nowIso(),
): Promise<StreakParticipation> {
  const day = await findCoupleDayAt(ctx, coupleId, observedAt);
  if (!day) {
    return { current_user_contributed_today: false, partner_contributed_today: false };
  }
  return await getCoupleStreakParticipationForDay(ctx, coupleId, currentUserId, day.id);
}

async function activeCoupleIdsForUser(ctx: ReaderCtx, userId: string): Promise<string[]> {
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId).eq("status", "active"))
    .collect();
  const ids: string[] = [];
  for (const membership of memberships) {
    const couple = await getByUuid(ctx, "couples", membership.couple_id);
    if (couple?.status === "active") {
      ids.push(couple.id);
    }
  }
  return ids;
}

type DeviceSnapshot = {
  time_zone_id?: string | null;
  last_seen_at: string;
  disabled_at?: string | null;
};

/**
 * Port of the `refresh_streak_after_device_time_zone_change` trigger. Call after
 * inserting or updating a user_devices row. Pass the row as it was before the
 * update (omit on insert) so unchanged updates are skipped.
 */
export async function refreshStreakAfterDeviceTimeZoneChange(
  ctx: WriterCtx,
  userId: string,
  after: DeviceSnapshot,
  before?: DeviceSnapshot | null,
): Promise<void> {
  if (
    before &&
    (before.time_zone_id ?? null) === (after.time_zone_id ?? null) &&
    before.last_seen_at === after.last_seen_at &&
    (before.disabled_at ?? null) === (after.disabled_at ?? null)
  ) {
    return;
  }
  for (const coupleId of await activeCoupleIdsForUser(ctx, userId)) {
    await detectStreakBreak(ctx, coupleId);
  }
}

/**
 * Port of the `refresh_streak_after_profile_time_zone_change` trigger. Call
 * after updating `profiles.time_zone_id` on an existing row.
 */
export async function refreshStreakAfterProfileTimeZoneChange(
  ctx: WriterCtx,
  userId: string,
  beforeTimeZoneId: string | null | undefined,
  afterTimeZoneId: string | null | undefined,
): Promise<void> {
  if ((beforeTimeZoneId ?? null) === (afterTimeZoneId ?? null)) {
    return;
  }
  for (const coupleId of await activeCoupleIdsForUser(ctx, userId)) {
    await detectStreakBreak(ctx, coupleId);
  }
}

export type StreakRestoreResult =
  | { ok: true; restoredCount: number; replayed: boolean }
  | { ok: false; error: string; status: number };

/** Port of `internal.apply_streak_restore`. Result keys match the SQL jsonb. */
export async function applyStreakRestore(
  ctx: WriterCtx,
  args: {
    couple_id: string;
    purchaser_user_id: string;
    product_id: string;
    environment: "xcode" | "sandbox" | "production";
    transaction_id: string;
    original_transaction_id?: string | null;
    purchased_at?: string | null;
    raw_payload_id?: string | null;
  },
): Promise<StreakRestoreResult> {
  const replay = await ctx.db
    .query("streak_restorations")
    .withIndex("by_environment_transaction_id", (q) =>
      q.eq("environment", args.environment).eq("transaction_id", args.transaction_id),
    )
    .unique();
  if (replay) {
    return { ok: true, restoredCount: replay.restored_count, replayed: true };
  }

  // The offer may not be stored yet if the deadline passed since the last cron run.
  await detectStreakBreak(ctx, args.couple_id);
  const state = await getStreakState(ctx, args.couple_id);
  const now = nowIso();
  if (
    !state ||
    state.restorable_count <= 0 ||
    state.restore_deadline === undefined ||
    state.restore_deadline <= now
  ) {
    return { ok: false, error: "No streak is available to restore", status: 409 };
  }

  const todayId = await getOrCreateCoupleDayAt(ctx, args.couple_id, now);
  const today = (await getByUuid(ctx, "couple_days", todayId))!;
  const todayQualifiedAt = await getCoupleDayStreakQualifiedAt(ctx, args.couple_id, todayId);

  let resolvedCount: number;
  let resolvedLastDate: string;
  let resolvedLastDayId: string;
  let resolvedDeadline: string;
  // A restore adds today only when both partners contributed. One partner's
  // contribution stays in the audit trail and can qualify the day later.
  if (todayQualifiedAt !== null) {
    resolvedCount = state.restorable_count + 1;
    resolvedLastDate = today.local_date;
    resolvedLastDayId = todayId;
    resolvedDeadline = await resolveNextActivityDeadlineAt(ctx, args.couple_id, todayQualifiedAt);
  } else {
    resolvedCount = state.restorable_count;
    // Yesterday by the calendar, in the zone that anchors today. Noon stays inside the day even
    // across a daylight saving change, where now minus 24 hours can land on today or two days back.
    const yesterdayNoon = zonedLocalToUtcMs(addDaysToDate(today.local_date, -1), today.anchor_time_zone_id, 12);
    const yesterdayId = await getOrCreateCoupleDayAt(ctx, args.couple_id, new Date(yesterdayNoon).toISOString());
    const yesterday = (await getByUuid(ctx, "couple_days", yesterdayId))!;
    resolvedLastDate = yesterday.local_date;
    resolvedLastDayId = yesterdayId;
    resolvedDeadline = await resolveNextActivityDeadlineAt(ctx, args.couple_id, yesterday.starts_at);
  }

  await ctx.db.patch(
    state._id,
    withUpdatedAt({
      current_count: resolvedCount,
      longest_count: Math.max(state.longest_count, resolvedCount),
      last_qualified_date: resolvedLastDate,
      last_qualified_couple_day_id: resolvedLastDayId,
      next_activity_deadline_at: resolvedDeadline,
      restore_available: false,
      restorable_count: 0,
      restorable_through_date: undefined,
      restore_deadline: undefined,
      restored_at: now,
      last_restore_transaction_id: args.transaction_id,
    }),
  );
  await ctx.db.insert("streak_restorations", {
    id: newUuid(),
    couple_id: args.couple_id,
    purchaser_user_id: args.purchaser_user_id,
    product_id: args.product_id,
    environment: args.environment,
    transaction_id: args.transaction_id,
    original_transaction_id: args.original_transaction_id ?? undefined,
    restored_count: resolvedCount,
    restorable_through_date: state.restorable_through_date,
    purchased_at: args.purchased_at ?? undefined,
    restored_at: now,
    raw_payload_id: args.raw_payload_id ?? undefined,
    status: "applied",
    created_at: now,
  });
  return { ok: true, restoredCount: resolvedCount, replayed: false };
}
