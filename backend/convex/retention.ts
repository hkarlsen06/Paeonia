import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, type MutationCtx } from "./_generated/server";
import { optionalTimestampArg } from "./lib/ids";
import { addDaysToDate, addDaysToInstant, localDateOf, nowIso, startOfLocalDay } from "./lib/time";
import { TOGETHER_DAYS_KEPT } from "./lib/together";

// Rows that only matter for a short while after they are written. Without this job they grow with
// every write and push for as long as the account exists.
//
// client_operations: replay protection for the phone's offline queue. A queued write older than
// this window runs again instead of returning the stored response.
// notification_outbox, widget_push_outbox, live_activity_push_outbox: a row is sent or failed
// within hours, so an old row protects nothing. The Lock Screen push key repeats, and only its
// newest row is ever checked.
// call_reports: what a phone measured about a call's connection, read to find problems soon after.
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
      await ctx.db
        .query("call_reports")
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

// ---- Records with a set time ----
//
// The privacy policy names how long these stay. A report, what was done about it, the safety
// warning it left on the pair and a privacy request stay three years after the case closed.
// A purchase record stays five years after the end of the year of the purchase, which is what
// bokføringsloven § 13 asks for. A block has no time limit: it stays until the person who made it
// deletes their account (`accountDeletion.ts`).

const CASE_RETENTION_YEARS = 3;
const PURCHASE_RETENTION_YEARS = 5;
const RECORD_PAGE_SIZE = 100;
/** The wait between pages, so a long backlog stays under the server's write limit. */
const RECORD_PAGE_WAIT_MS = 1000;

/** Cases closed before this instant are past their three years. */
export function closedCaseCutoff(now: string): string {
  const cutoff = new Date(now);
  cutoff.setUTCFullYear(cutoff.getUTCFullYear() - CASE_RETENTION_YEARS);
  return cutoff.toISOString();
}

/**
 * Purchases made before this instant are past their five years: the start of the Norwegian
 * calendar year five years before the current one. A purchase from 2026 goes on 1 January 2032.
 */
export function purchaseRecordCutoff(now: string): string {
  const year = Number(localDateOf(now, "Europe/Oslo").slice(0, 4));
  return startOfLocalDay(`${year - PURCHASE_RETENTION_YEARS}-01-01`, "Europe/Oslo");
}

type Page = { isDone: boolean; continueCursor: string };
type PageArgs = { numItems: number; cursor: string | null };

/** Deletes a closed report with everything that hangs on it. A block it led to stays, without the link. */
async function deleteReport(ctx: MutationCtx, report: Doc<"content_reports">): Promise<void> {
  const byReport = [
    ...(await ctx.db.query("content_report_targets").withIndex("by_report_id", (q) => q.eq("report_id", report.id)).collect()),
    ...(await ctx.db.query("report_snapshots").withIndex("by_report_id", (q) => q.eq("report_id", report.id)).collect()),
    ...(await ctx.db
      .query("moderation_actions")
      .withIndex("by_report_id_created_at", (q) => q.eq("report_id", report.id))
      .collect()),
    ...(await ctx.db
      .query("pair_safety_warning_flags")
      .withIndex("by_source_report_id", (q) => q.eq("source_report_id", report.id))
      .collect()),
  ];
  for (const row of byReport) await ctx.db.delete(row._id);
  const blocks = await ctx.db
    .query("relationship_blocks")
    .withIndex("by_source_report_id", (q) => q.eq("source_report_id", report.id))
    .collect();
  for (const block of blocks) await ctx.db.patch(block._id, { source_report_id: undefined });
  await ctx.db.delete(report._id);
}

/**
 * A closed report whose snapshot files are still stored waits for `cleanup-report-snapshots`,
 * which removes them 180 days after the first action. Content hidden or removed for the report
 * keeps its `moderation_report_id`, which then names a report that is gone.
 */
async function pruneClosedReports(ctx: MutationCtx, now: string, page: PageArgs): Promise<Page> {
  const cutoff = closedCaseCutoff(now);
  const result = await ctx.db
    .query("content_reports")
    .withIndex("by_resolved_at", (q) => q.gt("resolved_at", "").lt("resolved_at", cutoff))
    .paginate(page);
  for (const report of result.page) {
    const storedFile = await ctx.db
      .query("report_snapshot_assets")
      .withIndex("by_report_id_source_media_asset_id", (q) => q.eq("report_id", report.id))
      .first();
    if (!storedFile) await deleteReport(ctx, report);
  }
  return result;
}

/**
 * A finished deletion request stays with its `account_deletion_jobs` row, which is what keeps a
 * deleted account from being set up again.
 */
function pruneClosedPrivacyRequests(status: "completed" | "rejected" | "cancelled") {
  return async (ctx: MutationCtx, now: string, page: PageArgs): Promise<Page> => {
    const cutoff = closedCaseCutoff(now);
    const result = await ctx.db
      .query("privacy_requests")
      .withIndex("by_status_updated_at", (q) => q.eq("status", status).lt("updated_at", cutoff))
      .paginate(page);
    for (const request of result.page) {
      const job = await ctx.db
        .query("account_deletion_jobs")
        .withIndex("by_request_id", (q) => q.eq("request_id", request.id))
        .first();
      if (job) continue;
      const events = await ctx.db
        .query("privacy_request_events")
        .withIndex("by_request_id_created_at", (q) => q.eq("request_id", request.id))
        .collect();
      for (const event of events) await ctx.db.delete(event._id);
      await ctx.db.delete(request._id);
    }
    return result;
  };
}

function pruneOldPurchases(table: "storekit_transactions" | "streak_restorations") {
  return async (ctx: MutationCtx, now: string, page: PageArgs): Promise<Page> => {
    const cutoff = purchaseRecordCutoff(now);
    const result = await ctx.db
      .query(table)
      .withIndex("by_purchased_at", (q) => q.gt("purchased_at", "").lt("purchased_at", cutoff))
      .paginate(page);
    for (const row of result.page) await ctx.db.delete(row._id);
    return result;
  };
}

async function pruneOldStoreNotices(ctx: MutationCtx, now: string, page: PageArgs): Promise<Page> {
  const result = await ctx.db
    .query("storekit_notification_events")
    .withIndex("by_created_at", (q) => q.lt("created_at", purchaseRecordCutoff(now)))
    .paginate(page);
  for (const row of result.page) await ctx.db.delete(row._id);
  return result;
}

/** Apple's signed data goes once it is old enough and no purchase or notice still points to it. */
async function pruneOldStorePayloads(ctx: MutationCtx, now: string, page: PageArgs): Promise<Page> {
  const result = await ctx.db
    .query("storekit_payloads")
    .withIndex("by_created_at", (q) => q.lt("created_at", purchaseRecordCutoff(now)))
    .paginate(page);
  for (const payload of result.page) {
    const stillUsed =
      (await ctx.db.query("storekit_transactions").withIndex("by_raw_payload_id", (q) => q.eq("raw_payload_id", payload.id)).first()) ??
      (await ctx.db.query("streak_restorations").withIndex("by_raw_payload_id", (q) => q.eq("raw_payload_id", payload.id)).first()) ??
      (await ctx.db
        .query("storekit_notification_events")
        .withIndex("by_raw_payload_id", (q) => q.eq("raw_payload_id", payload.id))
        .first());
    if (!stillUsed) await ctx.db.delete(payload._id);
  }
  return result;
}

/** In order: a purchase and a notice go before the signed data they point to. */
const RECORD_STEPS = [
  pruneClosedReports,
  pruneClosedPrivacyRequests("completed"),
  pruneClosedPrivacyRequests("rejected"),
  pruneClosedPrivacyRequests("cancelled"),
  pruneOldPurchases("storekit_transactions"),
  pruneOldPurchases("streak_restorations"),
  pruneOldStoreNotices,
  pruneOldStorePayloads,
];

/**
 * Daily (`prune-kept-records`). Deletes the records above that are past their time, one page of
 * one step per mutation. Each mutation schedules the next page, or the next step, a second later.
 */
export const prune_kept_records = internalMutation({
  args: {
    p_now: v.optional(v.union(v.null(), v.string())),
    step: v.optional(v.number()),
    cursor: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const step = args.step ?? 0;
    const page = await RECORD_STEPS[step](ctx, now, { numItems: RECORD_PAGE_SIZE, cursor: args.cursor ?? null });
    const next = page.isDone ? { step: step + 1, cursor: null } : { step, cursor: page.continueCursor };
    if (next.step < RECORD_STEPS.length) {
      await ctx.scheduler.runAfter(RECORD_PAGE_WAIT_MS, internal.retention.prune_kept_records, { p_now: now, ...next });
    }
  },
});
