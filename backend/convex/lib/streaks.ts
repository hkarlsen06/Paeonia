import type { Doc } from "../_generated/dataModel";
import { getCurrentEntitledCoupleId } from "./access";
import { getOrCreateCoupleDayAt } from "./coupleDays";
import { runClientOperation, type ClientOperationInput } from "./clientOperations";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { checkViolation, fail } from "./errors";
import { newUuid } from "./ids";
import { jsonbByteLength } from "./json";
import {
  getCoupleDayStreakQualifiedAt,
  resolveNextActivityDeadlineAt,
} from "./streakDeadlines";
import { addHours, nowIso } from "./time";

export {
  getCoupleDayStreakQualifiedAt,
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

  let nextCurrentCount: number;
  let nextRestorableCount: number;
  let nextRestorableThroughDate: string | undefined;
  let nextRestoreDeadline: string | undefined;
  if (previousDeadline !== null && qualifiedAt < previousDeadline) {
    nextCurrentCount = existing.current_count + 1;
    nextRestorableCount = 0;
  } else {
    nextCurrentCount = 1;
    nextRestorableCount = Math.max(existing.restorable_count, existing.current_count);
    nextRestorableThroughDate = existing.restorable_through_date ?? existing.last_qualified_date;
    nextRestoreDeadline =
      existing.restore_deadline ?? (previousDeadline !== null ? addHours(previousDeadline, 24) : undefined);
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
 * Port of `internal.refresh_streak_deadline`. Recomputes the live deadline from
 * the last qualified day and current partner zones. Returns the deadline or null.
 */
export async function refreshStreakDeadline(ctx: WriterCtx, coupleId: string): Promise<string | null> {
  const state = await getStreakState(ctx, coupleId);
  if (!state || state.current_count <= 0 || state.restorable_count > 0) {
    return state?.next_activity_deadline_at ?? null;
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
    return state.next_activity_deadline_at ?? null;
  }
  const resolvedDeadline = await resolveNextActivityDeadlineAt(ctx, coupleId, qualifiedAt);
  if (state.next_activity_deadline_at !== resolvedDeadline) {
    await ctx.db.patch(state._id, withUpdatedAt({ next_activity_deadline_at: resolvedDeadline }));
  }
  return resolvedDeadline;
}

/**
 * Port of `internal.detect_streak_break`. When the live deadline has passed and
 * no restore offer exists yet, opens a 24 hour restore offer.
 */
export async function detectStreakBreak(ctx: WriterCtx, coupleId: string): Promise<void> {
  const resolvedDeadline = await refreshStreakDeadline(ctx, coupleId);
  const state = await getStreakState(ctx, coupleId);
  const now = nowIso();
  if (
    !state ||
    state.current_count <= 0 ||
    state.restorable_count !== 0 ||
    resolvedDeadline === null ||
    now < resolvedDeadline
  ) {
    return;
  }
  const restoreDeadline = addHours(resolvedDeadline, 24);
  await ctx.db.patch(
    state._id,
    withUpdatedAt({
      restorable_count: state.current_count,
      restorable_through_date: state.last_qualified_date,
      restore_deadline: restoreDeadline,
      restore_available: restoreDeadline > now,
    }),
  );
}

export type CoupleStreak = {
  current_count: number;
  longest_count: number;
  last_qualified_date: string | null;
  restore_available: boolean;
  restorable_count: number;
  restore_deadline: string | null;
};

/** Port of `internal.get_couple_streak_for_couple`. Writes a restore offer when the streak just broke, so call it from a mutation. */
export async function getCoupleStreakForCouple(
  ctx: WriterCtx,
  coupleId: string | null | undefined,
): Promise<CoupleStreak> {
  if (!coupleId) {
    return fail("42501", "active entitled couple access is required");
  }
  await detectStreakBreak(ctx, coupleId);
  const streak = await getStreakState(ctx, coupleId);
  const now = nowIso();
  return {
    current_count:
      streak?.next_activity_deadline_at !== undefined && now >= streak.next_activity_deadline_at
        ? 0
        : (streak?.current_count ?? 0),
    longest_count: streak?.longest_count ?? 0,
    last_qualified_date: streak?.last_qualified_date ?? null,
    restore_available:
      (streak?.restorable_count ?? 0) > 0 &&
      streak?.restore_deadline !== undefined &&
      streak.restore_deadline > now,
    restorable_count: streak?.restorable_count ?? 0,
    restore_deadline: streak?.restore_deadline ?? null,
  };
}

/** Port of `internal.get_couple_streak_participation_for_user`. */
export async function getCoupleStreakParticipationForUser(
  ctx: ReaderCtx,
  coupleId: string,
  currentUserId: string,
  observedAt: string = nowIso(),
): Promise<{ current_user_contributed_today: boolean; partner_contributed_today: boolean }> {
  const earliestStart = new Date(Date.parse(observedAt) - 2 * 86_400_000).toISOString();
  let currentDayId: string | null = null;
  const days = ctx.db
    .query("couple_days")
    .withIndex("by_couple_id_starts_at", (q) =>
      q.eq("couple_id", coupleId).gte("starts_at", earliestStart).lte("starts_at", observedAt),
    )
    .order("desc");
  for await (const day of days) {
    if (observedAt >= day.starts_at && observedAt < day.ends_at) {
      currentDayId = day.id;
      break;
    }
  }
  if (currentDayId === null) {
    return { current_user_contributed_today: false, partner_contributed_today: false };
  }
  const dayId = currentDayId;
  const events = (
    await ctx.db
      .query("couple_activity_events")
      .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", dayId))
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
    const yesterdayId = await getOrCreateCoupleDayAt(
      ctx,
      args.couple_id,
      new Date(Date.parse(now) - 86_400_000).toISOString(),
    );
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
