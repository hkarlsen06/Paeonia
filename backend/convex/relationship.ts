import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation, mutation, query } from "./_generated/server";
import { findCurrentCouple, getCurrentEntitledCoupleId } from "./lib/access";
import { isSupersededClientOperation, runClientOperation } from "./lib/clientOperations";
import { userLocalDate } from "./lib/coupleDays";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { dateArg, optionalTimestampArg, optionalUuidArg } from "./lib/ids";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { enqueueLockScreenRefreshForPartner, LOCK_SCREEN_REFRESH_DELAY_SECONDS } from "./lib/notifications";
import { cleanupCoupleContent, isPurgeable, purgeCoupleContent, ROWS_PER_CHUNK } from "./lib/relationshipCleanup";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { requireUserId } from "./lib/auth";
import { createRelationshipSyncEvent } from "./lib/syncEvents";
import { nowIso } from "./lib/time";

export const get_relationship_sync_events = query({
  args: {
    p_after_created_at: v.optional(v.union(v.null(), v.string())),
    p_after_id: v.optional(v.union(v.null(), v.string())),
    p_limit: v.number(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (!(args.p_limit >= 1)) {
      fail("23514", "sync event limit is out of range");
    }
    const limit = Math.min(Math.floor(args.p_limit), 1000);
    const afterCreatedAt = optionalTimestampArg(args.p_after_created_at);
    const afterId = optionalUuidArg(args.p_after_id);

    const events = ctx.db
      .query("relationship_sync_events")
      .withIndex("by_user_id_created_at_id", (q) =>
        afterCreatedAt ? q.eq("user_id", userId).gte("created_at", afterCreatedAt) : q.eq("user_id", userId),
      );
    const rows = [];
    for await (const event of events) {
      if (afterCreatedAt && event.created_at === afterCreatedAt && (!afterId || event.id <= afterId)) continue;
      rows.push({
        id: event.id,
        user_id: event.user_id,
        couple_id: event.couple_id,
        initiated_by_user_id: orNull(event.initiated_by_user_id),
        event_kind: event.event_kind,
        reason: orNull(event.reason),
        occurred_at: event.occurred_at,
        relationship_status: event.relationship_status,
        member_status: event.member_status,
        ended_at: orNull(event.ended_at),
        delete_after: orNull(event.delete_after),
        local_purge_scope: event.local_purge_scope,
        created_at: event.created_at,
        updated_at: event.updated_at,
      });
      if (rows.length >= limit) break;
    }
    return rows;
  },
});

export const leave_relationship = mutation({
  args: clientOperationArgs,
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const outcome = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, { kind: "leave_relationship", scope: "relationship_lifecycle", request: { kind: "leave_relationship" } }),
      async () => {
        const couple = await findCurrentCouple(ctx, userId);
        const left = couple ? await endRelationshipForPair(ctx, couple.pair_id, userId, "user_left") : false;
        return { left };
      },
    );
    return outcome.left;
  },
});

export const mark_relationship_ended_notice_seen = mutation({
  args: { p_couple_id: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = optionalUuidArg(args.p_couple_id);
    if (!coupleId) return false;
    const member = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
      .unique();
    if (!member || member.status !== "ended_notice_pending") {
      return false;
    }
    await ctx.db.patch(
      member._id,
      withUpdatedAt({ status: "ended_notice_seen" as const, ended_notice_seen_at: nowIso() }),
    );
    return true;
  },
});

export const set_couple_started_on = mutation({
  args: { p_started_on: v.union(v.null(), v.string()), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_started_on === null) {
      return fail("23514", "relationship start date must be today or earlier");
    }
    const startedOn = dateArg(args.p_started_on);
    if (startedOn > (await userLocalDate(ctx, userId, nowIso()))) {
      fail("23514", "relationship start date must be today or earlier");
    }

    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const scope = `couple:${coupleId}:started_on`;
    const input = toClientOperation(args, {
      kind: "set_couple_started_on",
      scope,
      request: { kind: "set_couple_started_on", couple_id: coupleId, started_on: startedOn },
    });
    const outcome = await runClientOperation(ctx, userId, input, async () => {
      if (await isSupersededClientOperation(ctx, userId, input)) {
        const couple = await getByUuid(ctx, "couples", coupleId);
        return { couple_id: coupleId, started_on: orNull(couple?.started_on), superseded: true };
      }

      const couple = await getByUuid(ctx, "couples", coupleId);
      if (!couple || couple.status !== "active") {
        return fail("P0002", "active relationship not found");
      }
      await ctx.db.patch(couple._id, withUpdatedAt({ started_on: startedOn }));
      const members = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
        .collect();
      for (const member of members) {
        await createRelationshipSyncEvent(ctx, {
          user_id: member.user_id,
          couple_id: coupleId,
          initiated_by_user_id: userId,
          event_kind: "relationship_updated",
          reason: "relationship_start_date_changed",
          relationship_status: "active",
          member_status: member.status,
          local_purge_scope: { relationship: "refresh" },
        });
      }
      await enqueueLockScreenRefreshForPartner(ctx, {
        couple_id: coupleId,
        actor_user_id: userId,
        delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
      });
      return { couple_id: coupleId, started_on: startedOn };
    });
    return outcome.started_on ?? null;
  },
});

// ---- cleanup (operator and cron) ----

/**
 * Couples the purge run checks for ready files before it gives up. A check is one index read, so
 * this many fit one mutation. Couples whose files never get deleted stay in range and are checked
 * again each run, and only more than this many of them could hide a purgeable couple behind them.
 */
const PURGE_CANDIDATES_PER_RUN = 500;

/**
 * Hides one ended couple's content. Each run changes at most `ROWS_PER_CHUNK` rows and runs
 * again while a couple is still due, so one big couple never holds up the others or hits the
 * limits of a single transaction. A couple leaves the range when its cleanup finishes.
 */
export const cleanup_expired_relationship_content = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const due = () =>
      ctx.db
        .query("couples")
        .withIndex("by_status_purged_at_delete_after", (q) =>
          q.eq("status", "ended").eq("purged_at", undefined).gt("delete_after", "").lte("delete_after", now),
        );
    const couple = await due().first();
    if (!couple) return [];
    const { done: _done, ...result } = await cleanupCoupleContent(ctx, couple, now, { left: ROWS_PER_CHUNK });
    if ((await due().first()) !== null) {
      await ctx.scheduler.runAfter(0, internal.relationship.cleanup_expired_relationship_content, { p_now: now });
    }
    return [{ couple_id: couple.id, ...result }];
  },
});

/**
 * Hard deletes one deleted couple's content once its stored files are gone, in chunks like
 * the cleanup. A purged couple has `purged_at` and leaves the range.
 */
export const purge_deleted_relationship_content = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const due = () =>
      ctx.db
        .query("couples")
        .withIndex("by_status_purged_at_delete_after", (q) =>
          q.eq("status", "deleted").eq("purged_at", undefined).gt("delete_after", "").lte("delete_after", now),
        );
    let checked = 0;
    for await (const couple of due()) {
      if (++checked > PURGE_CANDIDATES_PER_RUN) break;
      if (!(await isPurgeable(ctx, couple))) continue;
      const { done: _done, ...result } = await purgeCoupleContent(ctx, couple, { left: ROWS_PER_CHUNK });
      if ((await due().first()) !== null) {
        await ctx.scheduler.runAfter(0, internal.relationship.purge_deleted_relationship_content, { p_now: now });
      }
      return [{ couple_id: couple.id, ...result }];
    }
    return [];
  },
});
