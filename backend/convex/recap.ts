import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { action, internalMutation, query, type QueryCtx } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { fail } from "./lib/errors";
import { dateArg } from "./lib/ids";
import { loadLookBackRef, type LookBackItem } from "./lib/lookBack";
import { countRecapStep, findRecap, startRecap } from "./lib/recap";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { localDateOf, nowIso } from "./lib/time";

/** Recaps per `get_recaps` page, so a page reads under 20 documents with the access checks. */
const RECAPS_PAGE = 6;
/** Counting calls one `ensure_anniversary_recap` makes. A busy year needs about 20. */
const MAX_ENSURE_STEPS = 60;

async function requireCoupleAccess(ctx: QueryCtx, userId: string): Promise<string> {
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
    return fail("42501", "active entitled couple access is required");
  }
  return coupleId;
}

type RecapRow = ReturnType<typeof recapRow>;

function recapRow(row: Doc<"anniversary_recaps">) {
  return {
    anniversary_date: row.anniversary_date,
    years: row.years,
    period_start: row.period_start,
    period_end: row.period_end,
    since_joined: row.since_joined,
    counted_on: row.counted_on,
    counts: { ...row.counts, hearts_all_time: row.hearts_sent.reduce((total, sent) => total + sent.count, 0) },
  };
}

/**
 * One page of the couple's finished anniversary recaps, newest first: the numbers only. Pass the
 * returned `next_before` as `p_before` for the next page; it is null on the last.
 * `get_recap_moments` resolves the moments of one recap when it opens.
 */
export const get_recaps = query({
  args: { p_before: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await requireCoupleAccess(ctx, userId);
    const before = args.p_before ? dateArg(args.p_before) : null;
    const rows = await ctx.db
      .query("anniversary_recaps")
      .withIndex("by_couple_id_anniversary_date", (q) =>
        before ? q.eq("couple_id", coupleId).lt("anniversary_date", before) : q.eq("couple_id", coupleId))
      .order("desc")
      .take(RECAPS_PAGE);
    return {
      recaps: rows.filter((row) => !row.counting).map(recapRow),
      next_before: rows.length === RECAPS_PAGE ? rows[rows.length - 1].anniversary_date : null,
    };
  },
});

/**
 * The moments of the recap of `p_anniversary_date`, as Look Back items, checked against the rules
 * the app uses today. A moment that was deleted, hidden, or that the caller may no longer read is
 * left out. Returns an empty list when the couple has no such recap.
 */
export const get_recap_moments = query({
  args: { p_anniversary_date: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await requireCoupleAccess(ctx, userId);
    const recap = await findRecap(ctx, coupleId, dateArg(args.p_anniversary_date));
    if (!recap || recap.counting) return [];
    const timeZone = await resolveMemberStreakTimeZone(ctx, userId);
    const moments: LookBackItem[] = [];
    for (const ref of recap.highlights) {
      const item = await loadLookBackRef(ctx, userId, coupleId, ref, recap.anniversary_date, timeZone);
      if (item) moments.push(item);
    }
    return moments;
  },
});

/**
 * Makes the recap of the couple's newest anniversary if it is due and missing, and returns it, or
 * null when the caller's day is not within the days the recap shows. The app calls this when the
 * Us tab appears in those days and it has no recap for that anniversary. The counting takes one
 * call per page; a recap the anniversary reminder started is picked up where it stopped.
 */
export const ensure_anniversary_recap = action({
  args: {},
  handler: async (ctx): Promise<RecapRow | null> => {
    for (let call = 0; call < MAX_ENSURE_STEPS; call += 1) {
      const step = await ctx.runMutation(internal.recap.ensure_step, {});
      if (step.done) return step.recap;
    }
    return fail("55000", "the recap is still being counted");
  },
});

/** One counting call for the signed-in caller's due recap. */
export const ensure_step = internalMutation({
  args: {},
  handler: async (ctx): Promise<{ done: boolean; recap: RecapRow | null }> => {
    const userId = await requireUserId(ctx);
    const coupleId = await requireCoupleAccess(ctx, userId);
    const timeZone = await resolveMemberStreakTimeZone(ctx, userId);
    const started = await startRecap(ctx, coupleId, localDateOf(nowIso(), timeZone), timeZone);
    const recap = started?.counting ? await countRecapStep(ctx, started._id) : started;
    if (recap?.counting) return { done: false, recap: null };
    return { done: true, recap: recap ? recapRow(recap) : null };
  },
});

/**
 * Starts the recap of the anniversary a date reminder is about, apart from the reminder's own
 * mutation so a failure here never undoes a reminder.
 */
export const start_recap = internalMutation({
  args: { couple_id: v.string(), today: v.string(), time_zone: v.string() },
  handler: async (ctx, args) => {
    const recap = await startRecap(ctx, args.couple_id, args.today, args.time_zone);
    if (recap?.counting) {
      await ctx.scheduler.runAfter(0, internal.recap.count_recap, {
        recap_id: recap._id,
        source: recap.counting.source,
        cursor: recap.counting.cursor,
      });
    }
  },
});

/**
 * Counts the next page of a recap and schedules the page after it. Stops when the row is gone,
 * finished, or another caller has counted past `source` and `cursor`.
 */
export const count_recap = internalMutation({
  args: { recap_id: v.id("anniversary_recaps"), source: v.number(), cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, args) => {
    const before = await ctx.db.get(args.recap_id);
    if (before?.counting?.source !== args.source || before.counting.cursor !== args.cursor) return;
    const recap = await countRecapStep(ctx, args.recap_id);
    if (recap?.counting) {
      await ctx.scheduler.runAfter(0, internal.recap.count_recap, {
        recap_id: recap._id,
        source: recap.counting.source,
        cursor: recap.counting.cursor,
      });
    }
  },
});
