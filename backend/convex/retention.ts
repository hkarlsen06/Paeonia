import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import { addDaysToDate, addDaysToInstant, nowIso } from "./lib/time";
import { TOGETHER_DAYS_KEPT } from "./lib/together";

// Rows that only matter for a short while after they are written. Without this job they grow with
// every write and push for as long as the account exists.
//
// client_operations: replay protection for the phone's offline queue. A queued write older than
// this window runs again instead of returning the stored response.
// notification_outbox, widget_push_outbox, live_activity_push_outbox: a row is sent or failed
// within hours, so an old row protects nothing. The Lock Screen push key repeats, and only its
// newest row is ever checked.
// together_days: dates the partners were together, from location or a visit that changed after
// them, kept TOGETHER_DAYS_KEPT days by date. A row that starts earlier keeps its later dates.
const RETENTION_DAYS = 30;
const BATCH = 1000;

/** Deletes up to BATCH expired rows per table, and runs again right away when a table had more. */
export const prune_expired_rows = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = nowIso();
    const cutoff = addDaysToInstant(now, -RETENTION_DAYS);
    const oldestTogetherDay = addDaysToDate(now.slice(0, 10), -TOGETHER_DAYS_KEPT);
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
      await ctx.db
        .query("live_activity_push_outbox")
        .withIndex("by_created_at", (q) => q.lt("created_at", cutoff))
        .take(BATCH),
    ];
    for (const row of batches.flat()) await ctx.db.delete(row._id);
    const togetherDays = await ctx.db
      .query("together_days")
      .withIndex("by_start_date", (q) => q.lt("start_date", oldestTogetherDay))
      .take(BATCH);
    for (const row of togetherDays) {
      if (row.end_date < oldestTogetherDay) await ctx.db.delete(row._id);
      else await ctx.db.patch(row._id, { start_date: oldestTogetherDay });
    }
    if ([...batches, togetherDays].some((rows) => rows.length === BATCH)) {
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
