import type { ReaderCtx, WriterCtx } from "./db";
import { findCurrentCouple, listActiveMembers } from "./access";
import { accessEndsAt, resolveUserEntitlement } from "./entitlements";
import { enqueueNotificationForUser } from "./notifications";
import { addMs, localDateOf, nowIso } from "./time";
import { resolveMemberStreakTimeZone } from "./streakDeadlines";
import { getByUuid } from "./db";
import type { Doc } from "../_generated/dataModel";
import { pushStatus } from "./pushStatus";

/** Test purchases stay quiet unless an operator explicitly enables subscription push testing. */
export function subscriptionNotificationsEnabled(environment: Doc<"storekit_transactions">["environment"]): boolean {
  return environment === "production" || process.env.PAEONIA_TEST_SUBSCRIPTION_NOTIFICATIONS === "true";
}

export async function subscriptionPushAllowed(ctx: ReaderCtx, subscriptionId: unknown): Promise<boolean> {
  const tx = typeof subscriptionId === "string" ? await getByUuid(ctx, "storekit_transactions", subscriptionId) : null;
  return tx !== null && subscriptionNotificationsEnabled(tx.environment);
}

// The pushes that warn before access ends. Access itself ends where it always did, when the
// last entitlement's `expires_at` passes. The expiry cron then stores the lapsed status
// (storekit.ts `expire_stale_entitlements`).

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
  if (!(await subscriptionPushAllowed(ctx, subscriptionId))) return 0;
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
  if (!(await endingSubscriptionPushAllowed(ctx, userIds, endsAt))) return 0;
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
        route: ownSubscription ? "subscription" : "us",
        deeplink: ownSubscription ? "paeonia://settings/subscription" : "paeonia://us",
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
    if (pushStatus(row) === "pending") await ctx.db.delete(row._id);
  }
}

/** An ending push goes out only while access still ends when it said. Turning renewal back on drops it. */
export async function accessEndingPushStillWanted(
  ctx: ReaderCtx,
  recipientUserId: string,
  payload: Record<string, unknown>,
): Promise<boolean> {
  const { userIds, endsAt } = await sharedAccess(ctx, recipientUserId);
  return endsAt !== null && endsAt === payload.ends_at && await endingSubscriptionPushAllowed(ctx, userIds, endsAt);
}

async function endingSubscriptionPushAllowed(ctx: ReaderCtx, userIds: string[], endsAt: string): Promise<boolean> {
  for (const userId of userIds) {
    const transactions = await ctx.db.query("storekit_transactions")
      .withIndex("by_user_id_status_expires_at", (q) =>
        q.eq("user_id", userId).eq("status", "active").eq("expires_at", endsAt),
      ).collect();
    if (transactions.some((tx) => tx.auto_renew_off === true && subscriptionNotificationsEnabled(tx.environment))) return true;
  }
  return false;
}

// ---- The six-month notice ----
//
// digitalytelsesloven § 33(4): at least every six months, the person who pays is told that the
// subscription runs and how to cancel it.

/**
 * The length of one half-year, counted from the subscription's first purchase. Six calendar months
 * are never shorter than 181 days, so a push the daily run sends up to a day late still comes
 * within six months of the one before. The app counts the same way (`AccessNotice`).
 */
export const RUNNING_NOTICE_PERIOD_DAYS = 180;

/**
 * How long after a half-year passes the push still goes out and the app shows its notice. Shorter
 * than the 30 days an outbox row lives (`retention.ts`), so the dedupe key outlasts it.
 */
export const RUNNING_NOTICE_WINDOW_DAYS = 14;

/**
 * Which half-year notice is due at `now` for a subscription first bought at `subscribedSince`:
 * 1 from day 180, 2 from day 360, and so on. Null in the first half-year and once the window after
 * a half-year has passed.
 */
export function runningNoticeHalfYear(subscribedSince: string, now: string): number | null {
  const elapsedMs = Date.parse(now) - Date.parse(subscribedSince);
  const periodMs = RUNNING_NOTICE_PERIOD_DAYS * DAY_MS;
  const halfYear = Math.floor(elapsedMs / periodMs);
  if (!(halfYear >= 1)) return null;
  return elapsedMs - halfYear * periodMs < RUNNING_NOTICE_WINDOW_DAYS * DAY_MS ? halfYear : null;
}

/** A subscription that is paid up and renews by itself. One that ends or has a failed payment gets its own notice. */
function isRunning(tx: Doc<"storekit_transactions">, now: string): boolean {
  return tx.status === "active" && tx.auto_renew_off !== true && tx.expires_at !== undefined && tx.expires_at > now;
}

/**
 * Apple renews up to a day early, so the period that is about to end and the next one are both
 * active for a while. Only the newest says when the subscription renews next and whether it will.
 */
async function isNewestPeriod(ctx: ReaderCtx, tx: Doc<"storekit_transactions">, expiresAt: string): Promise<boolean> {
  const periods = await ctx.db
    .query("storekit_transactions")
    .withIndex("by_environment_original_transaction_id", (q) =>
      q.eq("environment", tx.environment).eq("original_transaction_id", tx.original_transaction_id),
    )
    .collect();
  return periods.every((period) => period.expires_at === undefined || period.expires_at <= expiresAt);
}

/**
 * One push to the payer when their subscription has run another half-year, saying when it renews
 * and where to cancel. Deduped per subscription and half-year, so the daily runs inside the window
 * queue it once. The partner gets nothing. Returns the number of outbox rows queued.
 */
export async function queueSubscriptionRunningPush(
  ctx: WriterCtx,
  tx: Doc<"storekit_transactions">,
  now: string,
): Promise<number> {
  if (!subscriptionNotificationsEnabled(tx.environment) || !isRunning(tx, now)) return 0;
  if (tx.original_purchased_at === undefined || tx.expires_at === undefined) return 0;
  const halfYear = runningNoticeHalfYear(tx.original_purchased_at, now);
  if (halfYear === null || !(await isNewestPeriod(ctx, tx, tx.expires_at))) return 0;
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: tx.user_id,
    kind: "subscription_running",
    payload: {
      type: "subscription_running",
      route: "subscription",
      deeplink: "paeonia://settings/subscription",
      subscription_id: tx.id,
      // The renewal day on the payer's own calendar, so the push names the date their phone shows.
      renews_on: localDateOf(tx.expires_at, await resolveMemberStreakTimeZone(ctx, tx.user_id)),
    },
    dedupe_key: `subscription_running:${tx.environment}:${tx.original_transaction_id}:${halfYear}`,
    apns_collapse_id: "subscription-running",
  });
}

/** The six-month push goes out only while the subscription it names still runs. */
export async function subscriptionRunningPushStillWanted(ctx: ReaderCtx, subscriptionId: unknown): Promise<boolean> {
  const tx = typeof subscriptionId === "string" ? await getByUuid(ctx, "storekit_transactions", subscriptionId) : null;
  return tx !== null && subscriptionNotificationsEnabled(tx.environment) && isRunning(tx, nowIso());
}
