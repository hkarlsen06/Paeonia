import { v } from "convex/values";
import { query } from "./_generated/server";
import { requireUserId } from "./lib/auth";
import { notificationStaleAt } from "./lib/apns";
import { resolveDailyPartnerPush, isDailyPartnerPushKind } from "./lib/dailyPartnerPush";
import { getByUuid } from "./lib/db";
import { fail } from "./lib/errors";
import { timestampArg, uuidArg } from "./lib/ids";
import { notificationStillWanted } from "./lib/notificationState";
import { preferenceAllows } from "./lib/notifications";

/** Checks only the caller's delivered alerts. The phone advances p_now as time passes. */
export const get_obsolete_notifications = query({
  args: { p_notification_ids: v.array(v.string()), p_now: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_notification_ids.length > 100) fail("22023", "too many notification ids");
    const now = timestampArg(args.p_now);
    const preference = await ctx.db.query("notification_preferences")
      .withIndex("by_user_id", q => q.eq("user_id", userId)).unique();
    const obsolete: string[] = [];
    for (const value of args.p_notification_ids) {
      const id = uuidArg(value);
      const row = await getByUuid(ctx, "notification_outbox", id);
      if (row && row.recipient_user_id !== userId) fail("42501", "notification access denied");
      if (!row) {
        obsolete.push(id);
        continue;
      }
      const allows = (kind: typeof row.kind) => preference !== null &&
        preferenceAllows(kind, row.apns_push_type, preference, row.payload);
      const expires = notificationStaleAt(row.payload);
      const daily = isDailyPartnerPushKind(row.kind)
        ? await resolveDailyPartnerPush(ctx, row, userId, null, allows) : null;
      if (!allows(row.kind) || (expires !== null && expires <= now) ||
          (daily !== null && daily.push === null) ||
          !(await notificationStillWanted(ctx, row, userId, now)).wanted) obsolete.push(id);
    }
    return obsolete;
  },
});
