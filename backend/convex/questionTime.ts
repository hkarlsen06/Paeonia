import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, type MutationCtx } from "./_generated/server";
import { getEntitledCoupleIdForUser } from "./lib/access";
import { optionalTimestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import { questionTimeDue } from "./lib/questionTime";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { hasStartedToday } from "./lib/questionTimeStatus";
import { nowIso } from "./lib/time";

/**
 * Queues the opt-in "question time" reminder for each user whose chosen time came in the last
 * `QUESTION_TIME_WINDOW_MINUTES`, in their own time zone (the one the streak reminders use). It
 * skips users who have no entitled couple, have already answered a question today, or have no
 * push device. One reminder per device per local date. It writes no activity event, so it never
 * touches a streak. Returns how many notifications were queued.
 *
 * ponytail: one mutation reads every opted-in user each run (the index skips the rest). Fan the
 * users out in batches through the background workpool if opt-ins grow past a few thousand.
 */
export const enqueue_question_time_reminders = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    let queued = 0;
    for await (const preference of ctx.db
      .query("notification_preferences")
      .withIndex("by_question_time_enabled", (q) => q.eq("question_time_enabled", true))) {
      queued += await remindUser(ctx, preference, now);
    }
    return queued;
  },
});

async function remindUser(ctx: MutationCtx, preference: Doc<"notification_preferences">, now: string): Promise<number> {
  const userId = preference.user_id;
  const due = questionTimeDue(
    Date.parse(now),
    await resolveMemberStreakTimeZone(ctx, userId),
    preference.question_time_minutes,
  );
  if (due === null) return 0;
  const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
  if (coupleId === null || (await hasStartedToday(ctx, coupleId, userId, now))) return 0;
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: userId,
    kind: "question_time_reminder",
    payload: {
      type: "question_time_reminder",
      couple_id: coupleId,
      expires_at: due.expiresAt,
      route: "daily",
      deeplink: "paeonia://daily/today",
    },
    dedupe_key: `question_time_reminder:${userId}:${due.localDate}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `question-time:${coupleId}`,
    scheduled_for: now,
  });
}
