import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import { addDaysToInstant, nowIso } from "./lib/time";

// Rows that only matter for a short while after they are written. Without this job they grow with
// every write and push for as long as the account exists.
//
// client_operations: replay protection for the phone's offline queue. A queued write older than
// this window runs again instead of returning the stored response.
// notification_outbox, widget_push_outbox: a row is sent or failed within hours, so an old row
// protects nothing. The Lock Screen push key repeats, and only its newest row is ever checked.
const RETENTION_DAYS = 30;
const BATCH = 1000;

/** Deletes up to BATCH expired rows per table, and runs again right away when a table had more. */
export const prune_expired_rows = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = addDaysToInstant(nowIso(), -RETENTION_DAYS);
    const batches = [
      await ctx.db
        .query("client_operations")
        .withIndex("by_status_created_at", (q) => q.eq("status", "succeeded").lt("created_at", cutoff))
        .take(BATCH),
      await ctx.db
        .query("notification_outbox")
        .withIndex("by_created_at", (q) => q.lt("created_at", cutoff))
        .take(BATCH),
      await ctx.db
        .query("widget_push_outbox")
        .withIndex("by_created_at", (q) => q.lt("created_at", cutoff))
        .take(BATCH),
    ];
    for (const row of batches.flat()) await ctx.db.delete(row._id);
    if (batches.some((rows) => rows.length === BATCH)) {
      await ctx.scheduler.runAfter(0, internal.retention.prune_expired_rows, {});
    }
  },
});

/** Account deletion: removes the user's client operations in batches, so a heavy user fits the write limit. */
export const delete_user_client_operations = internalMutation({
  args: { p_user_id: v.string() },
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("client_operations")
      .withIndex("by_user_id_created_at", (q) => q.eq("user_id", args.p_user_id))
      .take(BATCH);
    for (const row of rows) await ctx.db.delete(row._id);
    if (rows.length === BATCH) {
      await ctx.scheduler.runAfter(0, internal.retention.delete_user_client_operations, args);
    }
  },
});
