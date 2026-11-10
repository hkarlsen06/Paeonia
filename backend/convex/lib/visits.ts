import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";

// When the partners meet in person. A visit runs from `start_date` to `end_date`, both calendar
// days with no time zone, so each partner reads it on their own local day. This file is the one
// place that compares a visit with a day.

/** Visits that are not over. A visit that ended never counts, so a couple can always plan the next. */
export const MAX_OPEN_VISITS_PER_COUPLE = 20;
/** How many of the visits that ended last `get_visits` sends beside the open ones. */
export const RECENT_ENDED_VISITS = 10;
/** Items on the couple's list, ticked or not. `get_visits` returns every one. */
export const MAX_TOGETHER_ITEMS_PER_COUPLE = 100;
/** The app trims and counts a list item title the same way. */
export const MAX_TOGETHER_ITEM_TITLE_CODE_POINTS = 80;

type VisitDates = { start_date: string; end_date: string };

export type VisitPhase = "upcoming" | "ongoing" | "ended";

/** Where `localDate` (`YYYY-MM-DD`) falls against the visit. Both the first and the last day count as ongoing. */
export function visitPhase(visit: VisitDates, localDate: string): VisitPhase {
  if (localDate < visit.start_date) return "upcoming";
  return localDate <= visit.end_date ? "ongoing" : "ended";
}

/** The couple's visits that are not over on `localDate`, read from the index with `visitPhase`'s rule. */
export async function openVisits(ctx: ReaderCtx, coupleId: string, localDate: string): Promise<Doc<"visits">[]> {
  return await ctx.db
    .query("visits")
    .withIndex("by_couple_id_deleted_at_end_date", (q) =>
      q.eq("couple_id", coupleId).eq("deleted_at", undefined).gte("end_date", localDate),
    )
    .collect();
}

/**
 * The couple's visits with the latest last days, without reading the clock. A save keeps at most
 * `MAX_OPEN_VISITS_PER_COUPLE` open on the saver's day, and a partner's day is at most two days
 * behind, so this holds every open visit and the ones that ended last.
 */
export async function recentVisits(ctx: ReaderCtx, coupleId: string): Promise<Doc<"visits">[]> {
  return await ctx.db
    .query("visits")
    .withIndex("by_couple_id_deleted_at_end_date", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .order("desc")
    .take(MAX_OPEN_VISITS_PER_COUPLE + RECENT_ENDED_VISITS);
}

/** The couple's list items that are not deleted. A couple has at most `MAX_TOGETHER_ITEMS_PER_COUPLE`. */
export async function liveTogetherItems(ctx: ReaderCtx, coupleId: string): Promise<Doc<"together_list_items">[]> {
  return await ctx.db
    .query("together_list_items")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .collect();
}
