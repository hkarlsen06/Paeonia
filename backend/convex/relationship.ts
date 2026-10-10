import { v } from "convex/values";
import { internalMutation, mutation } from "./_generated/server";
import { findCurrentCouple, getCurrentEntitledCoupleId } from "./lib/access";
import { runClientOperation } from "./lib/clientOperations";
import { userLocalDate } from "./lib/coupleDays";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { dateArg, optionalTimestampArg, optionalUuidArg } from "./lib/ids";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { blockRelationship } from "./lib/relationshipBlock";
import { cleanupCoupleContent, isPurgeable, purgeCoupleContent } from "./lib/relationshipCleanup";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { getCurrentRelationshipState } from "./lib/relationshipState";
import { requireUserId } from "./lib/auth";
import { createRelationshipSyncEvent } from "./lib/syncEvents";
import { nowIso } from "./lib/time";

export const get_current_relationship_state = mutation({
  args: {},
  handler: async (ctx) => {
    const state = await getCurrentRelationshipState(ctx, await requireUserId(ctx));
    return state ? [state] : [];
  },
});

export const get_relationship_sync_events = mutation({
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

export const block_relationship = mutation({
  args: { p_blocked_user_id: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    return await blockRelationship(ctx, userId, optionalUuidArg(args.p_blocked_user_id));
  },
});

export const unblock_pair = mutation({
  args: { p_pair_id: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const pairId = optionalUuidArg(args.p_pair_id);
    if (!pairId) return false;
    const blocks = await ctx.db
      .query("relationship_blocks")
      .withIndex("by_pair_id_revoked_at", (q) => q.eq("pair_id", pairId).eq("revoked_at", undefined))
      .collect();
    const own = blocks.filter((block) => block.blocked_by_user_id === userId);
    const revokedAt = nowIso();
    for (const block of own) {
      await ctx.db.patch(block._id, {
        revoked_at: revokedAt,
        revoked_by_user_id: userId,
        revoke_reason: "user_unblocked",
      });
    }
    return own.length > 0;
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
      // A delayed retry must not overwrite a newer edit the same client already completed.
      const operations = await ctx.db
        .query("client_operations")
        .withIndex("by_user_id_idempotency_scope_created_at", (q) =>
          q.eq("user_id", userId).eq("idempotency_scope", scope),
        )
        .collect();
      const superseded = operations.some(
        (operation) =>
          operation.client_id === input.client_id &&
          operation.client_sequence > input.client_sequence &&
          operation.operation_kind === "set_couple_started_on" &&
          operation.status === "succeeded",
      );
      if (superseded) {
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
      return { couple_id: coupleId, started_on: startedOn };
    });
    return outcome.started_on ?? null;
  },
});

// ---- cleanup (operator and cron) ----

function limitArg(value: number | undefined, fallback: number, max: number, message: string): number {
  const limit = value ?? fallback;
  if (!Number.isInteger(limit) || limit < 1 || limit > max) {
    return fail("23514", message);
  }
  return limit;
}

export const cleanup_expired_relationship_content = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())), p_limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = limitArg(args.p_limit, 25, 100, "relationship cleanup limit is out of range");
    const due = await ctx.db
      .query("couples")
      .withIndex("by_status_delete_after", (q) => q.eq("status", "ended").gt("delete_after", "").lte("delete_after", now))
      .take(limit * 2);
    const results = [];
    for (const couple of due.filter((row) => row.delete_after !== undefined).slice(0, limit)) {
      results.push({ couple_id: couple.id, ...(await cleanupCoupleContent(ctx, couple, now)) });
    }
    return results;
  },
});

export const purge_deleted_relationship_content = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())), p_limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = limitArg(args.p_limit, 25, 100, "relationship purge limit is out of range");
    const due = await ctx.db
      .query("couples")
      .withIndex("by_status_delete_after", (q) => q.eq("status", "deleted").gt("delete_after", "").lte("delete_after", now))
      .collect();
    const results = [];
    for (const couple of due) {
      if (results.length >= limit) break;
      if (couple.delete_after === undefined || !(await isPurgeable(ctx, couple))) continue;
      results.push({ couple_id: couple.id, ...(await purgeCoupleContent(ctx, couple)) });
    }
    return results;
  },
});
