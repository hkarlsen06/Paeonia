import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";

// When the partners meet in person. A visit runs from `start_date` to `end_date`, both calendar
// days with no time zone, so each partner reads it on their own local day. `visitPhase` is the one
// place that compares a visit with a day.

export const MAX_VISITS_PER_COUPLE = 20;
/** Items on the couple's list, ticked or not. `get_visits` returns every one. */
export const MAX_TOGETHER_ITEMS_PER_COUPLE = 100;

type VisitDates = { start_date: string; end_date: string };

export type VisitPhase = "upcoming" | "ongoing" | "ended";

/** Where `localDate` (`YYYY-MM-DD`) falls against the visit. Both the first and the last day count as ongoing. */
export function visitPhase(visit: VisitDates, localDate: string): VisitPhase {
  if (localDate < visit.start_date) return "upcoming";
  return localDate <= visit.end_date ? "ongoing" : "ended";
}

/** The visit that is ongoing on `localDate`, or else the soonest upcoming one. Null when every visit is over. */
export function currentOrNextVisit<T extends VisitDates>(visits: readonly T[], localDate: string): T | null {
  let best: T | null = null;
  for (const visit of visits) {
    if (visitPhase(visit, localDate) === "ended") continue;
    if (best === null || visit.start_date < best.start_date) best = visit;
  }
  return best;
}

/** The couple's visits that are not deleted. A couple has at most `MAX_VISITS_PER_COUPLE`. */
export async function liveVisits(ctx: ReaderCtx, coupleId: string): Promise<Doc<"visits">[]> {
  return await ctx.db
    .query("visits")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .collect();
}

/** The couple's list items that are not deleted. A couple has at most `MAX_TOGETHER_ITEMS_PER_COUPLE`. */
export async function liveTogetherItems(ctx: ReaderCtx, coupleId: string): Promise<Doc<"together_list_items">[]> {
  return await ctx.db
    .query("together_list_items")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .collect();
}
