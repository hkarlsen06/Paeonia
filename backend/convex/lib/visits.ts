import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";
import { addDaysToDate } from "./time";

// When the partners meet in person. A visit runs from `start_date` to `end_date`, both calendar
// days with no time zone, so each partner reads it on their own local day. This file is the one
// place that compares a visit with a day.

/**
 * Visits that may not be over on some phone's day, the ones that end on or after
 * `earliestLocalDate`. A visit that ended stops counting a day or two later, so a couple can
 * always plan the next.
 */
export const MAX_OPEN_VISITS_PER_COUPLE = 20;
/** How many of the visits that ended last `get_visits` sends beside the open ones. */
export const RECENT_ENDED_VISITS = 10;
/** Items on the couple's list, ticked or not. `get_visits` returns every one. */
export const MAX_TOGETHER_ITEMS_PER_COUPLE = 100;
/** The app trims and counts a list item title the same way. */
export const MAX_TOGETHER_ITEM_TITLE_CODE_POINTS = 80;
/** The dates a visit can have, and its longest span in days, the first and last day included. */
export const FIRST_VISIT_DATE = "2000-01-01";
export const LAST_VISIT_DATE = "2100-12-31";
export const MAX_VISIT_DAYS = 366;

type VisitDates = { start_date: string; end_date: string };

export type VisitPhase = "upcoming" | "ongoing" | "ended";

/** Where `localDate` (`YYYY-MM-DD`) falls against the visit. Both the first and the last day count as ongoing. */
export function visitPhase(visit: VisitDates, localDate: string): VisitPhase {
  if (localDate < visit.start_date) return "upcoming";
  return localDate <= visit.end_date ? "ongoing" : "ended";
}

/**
 * The earliest day any phone can be on at `now`. The furthest time zone behind UTC is UTC-12,
 * so no phone's date is before yesterday's date in UTC.
 */
export function earliestLocalDate(now: string): string {
  return addDaysToDate(now.slice(0, 10), -1);
}

/**
 * The couple's visits that end on or after `localDate`, the latest last day first, at most
 * `MAX_OPEN_VISITS_PER_COUPLE`. A save keeps at most that many ending on or after
 * `earliestLocalDate`, so for any phone's day this holds every visit that is not over.
 */
export async function openVisits(ctx: ReaderCtx, coupleId: string, localDate: string): Promise<Doc<"visits">[]> {
  return await ctx.db
    .query("visits")
    .withIndex("by_couple_id_deleted_at_end_date", (q) =>
      q.eq("couple_id", coupleId).eq("deleted_at", undefined).gte("end_date", localDate),
    )
    .order("desc")
    .take(MAX_OPEN_VISITS_PER_COUPLE);
}

/**
 * The couple's visits with the latest last days, without reading the clock. A save keeps at most
 * `MAX_OPEN_VISITS_PER_COUPLE` ending on or after `earliestLocalDate`, so this holds every visit
 * that is not over on some phone's day, and after them the ones that ended last.
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
