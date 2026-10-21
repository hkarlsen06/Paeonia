import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { enqueueLockScreenRefreshForUser, LOCK_SCREEN_REFRESH_DELAY_SECONDS } from "./lib/notifications";
import { normalizePartnerNickname } from "./lib/partnerNames";

/**
 * Sets what the caller calls their partner, or clears it with null, an empty string or only spaces.
 * The nickname is private: the partner never reads it. The app and every push then show it in place
 * of the partner's own name (see `lib/partnerNames.ts`). Fails with `23514` when it is longer than
 * 30 characters and with `42501` when the caller has no partner. Returns the stored nickname.
 */
export const set_partner_nickname = mutation({
  args: { p_nickname: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const nickname = normalizePartnerNickname(args.p_nickname);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const members = await listActiveMembers(ctx, coupleId);
    const member = members.find((row) => row.user_id === userId);
    if (!member || !members.some((row) => row.user_id !== userId)) {
      return fail("42501", "a partner is required to set a nickname");
    }
    if ((member.partner_nickname ?? null) !== nickname) {
      await ctx.db.patch(member._id, withUpdatedAt({ partner_nickname: nickname ?? undefined }));
      // The caller's own Lock Screen widget shows the partner's name.
      await enqueueLockScreenRefreshForUser(ctx, {
        couple_id: coupleId,
        user_id: userId,
        delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
      });
    }
    return { partner_nickname: nickname };
  },
});
