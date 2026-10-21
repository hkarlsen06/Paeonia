import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import { optionalTimestampArg } from "./lib/ids";
import { cleanupCoupleContent, isPurgeable, purgeCoupleContent, ROWS_PER_CHUNK } from "./lib/relationshipCleanup";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { nowIso } from "./lib/time";

// The relationship jobs that need lib/relationshipEnd.ts (which reaches every game through the badge
// code) and lib/relationshipCleanup.ts. They live in their own module so relationship.ts, whose
// get_relationship_sync_events query every open app subscribes to, does not load that code on each
// call. Convex evaluates a function's whole import graph on every call, and there is no lazy import.

/**
 * Ends the pair's active relationship. `relationship.leave_relationship` calls it after it has
 * checked the caller. Returns false when the pair has no active couple.
 */
export const end_relationship_for_pair = internalMutation({
  args: { pair_id: v.string(), initiated_by_user_id: v.string(), reason: v.string() },
  handler: async (ctx, args): Promise<boolean> =>
    await endRelationshipForPair(ctx, args.pair_id, args.initiated_by_user_id, args.reason),
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
      await ctx.scheduler.runAfter(0, internal.relationshipJobs.cleanup_expired_relationship_content, { p_now: now });
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
        await ctx.scheduler.runAfter(0, internal.relationshipJobs.purge_deleted_relationship_content, { p_now: now });
      }
      return [{ couple_id: couple.id, ...result }];
    }
    return [];
  },
});
