import type { WriterCtx } from "./db";

/** Most hearts one `hearts:send_hearts` call may carry. The app splits a bigger batch into several calls. */
export const MAX_HEARTS_PER_SEND = 100;

/**
 * The seen total after a mark. The app reports the total it showed, which can be
 * behind the server (a heart arrived mid-animation) and must not pass it (a
 * stale or wrong client). It never goes down.
 */
export function seenTotalAfterMark(current: number, shown: number, sent: number): number {
  return Math.max(current, Math.min(shown, sent));
}

/** Deletes every heart row of a couple. Call when the couple stops being active. */
export async function deleteHeartsForCouple(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = await ctx.db
    .query("couple_hearts")
    .withIndex("by_couple_id_sender_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}
