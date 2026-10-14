import { v } from "convex/values";
import { query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { resolveCoupleDayAnchorAt } from "./lib/coupleDays";
import { fail } from "./lib/errors";
import { timestampArg } from "./lib/ids";
import { pickLookBack } from "./lib/lookBack";

/**
 * The Home look-back card. See `lib/lookBack.ts` for how the item is chosen.
 *
 * A query must not read the clock, so the app passes the time it is asking at in `p_now`, rounded
 * down to 15 minutes so the result still caches. The couple-local date comes from that time and the
 * partners' time zones. Every couple day starts and ends on a 15 minute mark, so an app that asks
 * at `ends_at` gets the next day.
 *
 * Returns `{ item, ends_at }`. `item` is the look-back item or null when the couple has nothing old
 * enough. `ends_at` is when the couple day of `p_now` ends, which is when the app should ask again.
 */
export const get_look_back = query({
  args: { p_now: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      return fail("42501", "active entitled couple access is required");
    }
    const day = await resolveCoupleDayAnchorAt(ctx, coupleId, timestampArg(args.p_now));
    return {
      item: await pickLookBack(ctx, userId, coupleId, day.local_date, day.anchor_time_zone_id),
      ends_at: day.ends_at,
    };
  },
});
