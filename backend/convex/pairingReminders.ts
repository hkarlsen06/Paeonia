import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import { internalMutation, type MutationCtx } from "./_generated/server";
import { isQuietNight } from "./lib/apns";
import { withUpdatedAt } from "./lib/db";
import { optionalTimestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import { PAIRING_INVITE_REMINDER_AFTER_MS, pairingInviteStillWaiting } from "./lib/pairingInviteReminder";
import { resolveMemberStreakTimeZone } from "./lib/streakDeadlines";
import { addMs, nowIso } from "./lib/time";

const INVITE_PAGE_SIZE = 50;

/**
 * Sends an inviter one reminder to share their invite again when nobody joined within
 * `PAIRING_INVITE_REMINDER_AFTER_MS`. Each pending invite is handled once: the cron sets
 * `reminded_at` whether it queued the push or found the invite no longer waiting
 * (`pairingInviteStillWaiting`). An invite whose inviter is in their night (22:00 to 07:00 on the
 * clock the streak reminders use) is left for a later run, so the reminder comes in the morning
 * with its sound. The push follows no preference switch, like `partner_joined`, and reaches only
 * phones that allow notifications. Returns how many notifications this page queued.
 */
export const send_pairing_invite_reminders = internalMutation({
  args: {
    p_now: v.optional(v.union(v.null(), v.string())),
    cursor: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const createdBefore = addMs(now, -PAIRING_INVITE_REMINDER_AFTER_MS);
    const page = await ctx.db
      .query("pairing_invites")
      .withIndex("by_status_reminded_at_created_at", (q) =>
        q.eq("status", "pending").eq("reminded_at", undefined).lte("created_at", createdBefore),
      )
      .paginate({ numItems: INVITE_PAGE_SIZE, cursor: args.cursor ?? null });
    let queued = 0;
    for (const invite of page.page) queued += await remindInviter(ctx, invite, now);
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.pairingReminders.send_pairing_invite_reminders, {
        p_now: now,
        cursor: page.continueCursor,
      });
    }
    return queued;
  },
});

async function remindInviter(ctx: MutationCtx, invite: Doc<"pairing_invites">, now: string): Promise<number> {
  const userId = invite.created_by_user_id;
  if (!(await pairingInviteStillWaiting(ctx, invite, now))) {
    await ctx.db.patch(invite._id, withUpdatedAt({ reminded_at: now }));
    return 0;
  }
  if (isQuietNight(now, await resolveMemberStreakTimeZone(ctx, userId))) return 0;
  await ctx.db.patch(invite._id, withUpdatedAt({ reminded_at: now }));
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: userId,
    kind: "pairing_invite_reminder",
    payload: {
      type: "pairing_invite_reminder",
      invite_id: invite.id,
      // An inviter without a couple has the invite screen as the app's root, so Home lands there.
      route: "home",
      deeplink: "paeonia://home",
    },
    dedupe_key: `pairing_invite_reminder:${invite.id}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `pairing-invite:${userId}`,
    scheduled_for: now,
  });
}
