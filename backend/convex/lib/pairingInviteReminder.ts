import type { Doc } from "../_generated/dataModel";
import { findCurrentCouple } from "./access";
import type { ReaderCtx } from "./db";
import { userHasDirectEntitlement } from "./entitlements";

/** How long an invite waits for the partner before its inviter gets the one reminder to share it again. */
export const PAIRING_INVITE_REMINDER_AFTER_MS = 2 * 86_400_000;

/**
 * Whether an invite still waits for the partner, so a reminder to share it again makes sense. It
 * must be pending and unexpired, and no newer pending invite of the same inviter may have replaced
 * it. The inviter must be in no couple, since they may have joined through their partner's code
 * instead, and must still have the subscription their partner would join through. The reminder
 * cron asks this before it queues the push, and `prepare_notification` asks again before the send.
 */
export async function pairingInviteStillWaiting(
  ctx: ReaderCtx,
  invite: Doc<"pairing_invites">,
  now: string,
): Promise<boolean> {
  if (invite.status !== "pending" || invite.expires_at <= now) return false;
  const pending = await ctx.db
    .query("pairing_invites")
    .withIndex("by_created_by_user_id_status_expires_at", (q) =>
      q.eq("created_by_user_id", invite.created_by_user_id).eq("status", "pending").gt("expires_at", now),
    )
    .collect();
  if (pending.some((other) => other.created_at > invite.created_at)) return false;
  if ((await findCurrentCouple(ctx, invite.created_by_user_id)) !== null) return false;
  return await userHasDirectEntitlement(ctx, invite.created_by_user_id);
}
