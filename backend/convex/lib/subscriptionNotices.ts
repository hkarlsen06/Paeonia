import type { ReaderCtx, WriterCtx } from "./db";
import { findCurrentCouple, listActiveMembers } from "./access";
import { accessEndsAt, resolveUserEntitlement } from "./entitlements";
import { enqueueNotificationForUser } from "./notifications";
import { addMs } from "./time";

// The pushes that warn before access ends. Access itself ends where it always did, when the
// expiry cron marks the last entitlement expired (storekit.ts `expire_stale_entitlements`).

const DAY_MS = 86_400_000;

/** How many days before access ends both partners hear of it. The app shows its notice from the same day (`AccessNotice`). */
export const ENDING_NOTICE_DAYS = 5;

/**
 * The people who share access with `userId` (their current couple, or only them without one), each
 * one's own entitlement, and when that shared access ends (`accessEndsAt`).
 */
async function sharedAccess(ctx: ReaderCtx, userId: string) {
  const couple = await findCurrentCouple(ctx, userId);
  const userIds = couple ? (await listActiveMembers(ctx, couple.id)).map((member) => member.user_id) : [userId];
  const entitlements = [];
  for (const id of userIds) entitlements.push(await resolveUserEntitlement(ctx, id));
  return { coupleId: couple?.id ?? null, userIds, entitlements, endsAt: accessEndsAt(entitlements) };
}

/** Statuses of a subscription whose renewal payment failed and that a new payment can still save. */
const PAYMENT_PROBLEM_STATUSES: readonly (string | null)[] = ["grace", "billing_retry", "expired"];

/**
 * Whether the payment push still helps `userId`: their own best entitlement is a failed renewal
 * (not a refund, not working access), and nobody they share access with keeps it going on a
 * subscription or grant that is not in its own grace period.
 */
export async function paymentProblemPushWanted(ctx: ReaderCtx, userId: string): Promise<boolean> {
  const { userIds, entitlements } = await sharedAccess(ctx, userId);
  return userIds.every((id, index) => {
    const entitlement = entitlements[index];
    if (id !== userId) return !entitlement.is_entitled || entitlement.status === "grace";
    return PAYMENT_PROBLEM_STATUSES.includes(entitlement.status);
  });
}

/**
 * One push to the payer when Apple could not take a renewal payment, once per subscription period
 * (`subscriptionId` is the transaction that failed to renew). The partner gets nothing.
 */
export async function queuePaymentFailedPush(ctx: WriterCtx, userId: string, subscriptionId: string): Promise<number> {
  if (!(await paymentProblemPushWanted(ctx, userId))) return 0;
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: userId,
    kind: "subscription_payment_failed",
    payload: {
      type: "subscription_payment_failed",
      route: "subscription",
      deeplink: "paeonia://settings/subscription",
      subscription_id: subscriptionId,
    },
    dedupe_key: `subscription_payment_failed:${subscriptionId}`,
    apns_collapse_id: "subscription-payment",
  });
}

/**
 * Queues the ending push for everyone who shares access with `payerUserId`, when that access ends
 * within `ENDING_NOTICE_DAYS` days and an hour. Each goes out `ENDING_NOTICE_DAYS` days before the
 * end, or now when the end is closer. The person who pays gets the copy that asks them to turn
 * renewal back on, the partner a neutral one. Deduped per couple and end, so it is one push per period.
 */
export async function queueAccessEndingPushes(ctx: WriterCtx, payerUserId: string, now: string): Promise<number> {
  const { coupleId, userIds, entitlements, endsAt } = await sharedAccess(ctx, payerUserId);
  if (endsAt === null || endsAt <= now) return 0;
  const noticeAt = addMs(endsAt, -ENDING_NOTICE_DAYS * DAY_MS);
  // Someone else's access lasts longer. The cron finds their subscription when its time comes.
  if (noticeAt > addMs(now, 3_600_000)) return 0;
  const deliverAt = noticeAt > now ? noticeAt : now;
  const daysLeft = Math.max(1, Math.ceil((Date.parse(endsAt) - Date.parse(deliverAt)) / DAY_MS));

  let queued = 0;
  for (const [index, userId] of userIds.entries()) {
    const ownSubscription = entitlements[index].is_entitled && entitlements[index].source === "storekit";
    queued += await enqueueNotificationForUser(ctx, {
      recipient_user_id: userId,
      kind: "subscription_ending",
      payload: {
        type: "subscription_ending",
        route: ownSubscription ? "subscription" : "home",
        deeplink: ownSubscription ? "paeonia://settings/subscription" : "paeonia://home",
        ...(coupleId ? { couple_id: coupleId } : {}),
        ends_at: endsAt,
        days_left: daysLeft,
        own_subscription: ownSubscription,
      },
      dedupe_key: `subscription_ending:${coupleId ?? payerUserId}:${endsAt}`,
      apns_collapse_id: "subscription-ending",
      scheduled_for: deliverAt,
    });
  }
  return queued;
}

/**
 * Deletes the unsent ending pushes of everyone who shares access with `userId`. Runs when a
 * subscription's renewal, status or end changes, so the next cron run queues what is true then,
 * under the same dedupe key.
 */
export async function invalidateAccessEndingPushes(ctx: WriterCtx, userId: string): Promise<void> {
  const couple = await findCurrentCouple(ctx, userId);
  const prefix = `subscription_ending:${couple?.id ?? userId}:`;
  const rows = await ctx.db
    .query("notification_outbox")
    .withIndex("by_dedupe_key", (q) => q.gte("dedupe_key", prefix).lt("dedupe_key", `${prefix}\uffff`))
    .collect();
  for (const row of rows) {
    if (row.sent_at === undefined && row.failed_at === undefined) await ctx.db.delete(row._id);
  }
}

/** An ending push goes out only while access still ends when it said. Turning renewal back on drops it. */
export async function accessEndingPushStillWanted(
  ctx: ReaderCtx,
  recipientUserId: string,
  payload: Record<string, unknown>,
): Promise<boolean> {
  return (await sharedAccess(ctx, recipientUserId)).endsAt === payload.ends_at;
}
