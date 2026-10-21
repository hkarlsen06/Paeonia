import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import { internalMutation, type MutationCtx } from "./_generated/server";
import { getEntitledCoupleIdForUser, listActiveMembers } from "./lib/access";
import { getByUuid } from "./lib/db";
import {
  DATE_REMINDER_MINUTES,
  DATE_REMINDER_WINDOW_MINUTES,
  planDateReminders,
  type DateReminder,
} from "./lib/dateReminders";
import { optionalTimestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { endOfLocalDay, localTimeWindow, nowIso } from "./lib/time";

const USER_PAGE_SIZE = 50;

/**
 * Queues the reminders for the dates the couple keeps (`lib/dateReminders.ts` decides which)
 * for each user whose local clock is in the morning window, 09:00 to 09:30 in the zone the
 * streak reminders use. It skips users who turned the reminders off, have no entitled couple,
 * or have no push device. A reminder is queued once per device and occurrence. Returns how many
 * notifications this page queued.
 *
 * The zone check comes first and is cheap, so only the few users whose morning it is cost the
 * reads of the couple. One mutation handles a page of users and schedules the next page.
 */
export const enqueue_date_reminders = internalMutation({
  args: {
    p_now: v.optional(v.union(v.null(), v.string())),
    cursor: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const page = await ctx.db
      .query("notification_preferences")
      .withIndex("by_date_reminders_enabled", (q) => q.eq("date_reminders_enabled", true))
      .paginate({ numItems: USER_PAGE_SIZE, cursor: args.cursor ?? null });
    let queued = 0;
    for (const preference of page.page) queued += await remindUser(ctx, preference, now);
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.dateReminders.enqueue_date_reminders, {
        p_now: now,
        cursor: page.continueCursor,
      });
    }
    return queued;
  },
});

async function remindUser(ctx: MutationCtx, preference: Doc<"notification_preferences">, now: string): Promise<number> {
  const userId = preference.user_id;
  const timeZone = await resolveMemberStreakTimeZone(ctx, userId);
  const morning = localTimeWindow(Date.parse(now), timeZone, DATE_REMINDER_MINUTES, DATE_REMINDER_WINDOW_MINUTES);
  if (morning === null) return 0;
  const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
  if (coupleId === null) return 0;

  const couple = await getByUuid(ctx, "couples", coupleId);
  const members = await listActiveMembers(ctx, coupleId);
  const countdowns = await ctx.db
    .query("countdowns")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .collect();
  const reminders = planDateReminders({
    user_id: userId,
    today: morning.localDate,
    started_on: couple?.started_on,
    birthdays: new Map(
      members.flatMap((member) => (member.birthday === undefined ? [] : [[member.user_id, member.birthday] as const])),
    ),
    countdowns,
  });
  // A reminder stops being true when the recipient's day ends.
  const expiresAt = endOfLocalDay(morning.localDate, timeZone);
  let queued = 0;
  for (const reminder of reminders) {
    queued += await enqueueReminder(ctx, userId, coupleId, reminder, expiresAt, now);
  }
  return queued;
}

async function enqueueReminder(
  ctx: MutationCtx,
  userId: string,
  coupleId: string,
  reminder: DateReminder,
  expiresAt: string,
  now: string,
): Promise<number> {
  const subject = reminder.subject_user_id ?? "couple";
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: userId,
    kind: "date_reminder",
    payload: {
      type: "date_reminder",
      couple_id: coupleId,
      reminder: reminder.reminder,
      // The title names this partner (`notificationActorDisplayName`).
      ...(reminder.subject_user_id === undefined ? {} : { actor_user_id: reminder.subject_user_id }),
      ...reminder.extra,
      expires_at: expiresAt,
      route: "dates",
      deeplink: "paeonia://dates",
    },
    dedupe_key: `date_reminder:${reminder.reminder}:${subject}:${reminder.occurrence}:${userId}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `date-reminder:${reminder.reminder}:${reminder.occurrence}`,
    scheduled_for: now,
  });
}
