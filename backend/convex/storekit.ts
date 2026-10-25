import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { httpAction, internalMutation } from "./_generated/server";
import { listActiveMembers, userHasDirectEntitlement } from "./lib/access";
import {
  type AppleRenewalInfo,
  type AppleTransactionInfo,
  millisToIsoOrNull,
  requireString,
  revocationReason,
  stringOrNull,
  determineSubscription,
  toDatabaseEnvironment,
  autoRenewOff,
} from "./lib/appleStoreKit";
import { getByUuid, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { timestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import { ENDING_NOTICE_DAYS, queueAccessEndingPushes } from "./lib/subscriptionNotices";
import { createRelationshipSyncEvent } from "./lib/syncEvents";
import {
  patchStorekitTransaction,
  recordStorekitServerNotification,
  recordVerifiedStorekitTransaction,
  recordVerifiedStreakRestore,
} from "./lib/storekit";
import { addMs, nowIso } from "./lib/time";

const STREAK_RESTORE_PRODUCT_ID = "no.paeonia.streak.restore";

const nullableString = v.optional(v.union(v.null(), v.string()));
const nullableBoolean = v.optional(v.union(v.null(), v.boolean()));

// ---- StoreKit recording (the actions in access.ts and the webhook below call these) ----

export const record_verified_storekit_transaction = internalMutation({
  args: {
    p_user_id: nullableString,
    p_app_account_token: nullableString,
    p_apple_product_id: nullableString,
    p_environment: v.string(),
    p_original_transaction_id: v.string(),
    p_transaction_id: v.string(),
    p_web_order_line_item_id: nullableString,
    p_status: nullableString,
    p_purchased_at: nullableString,
    p_expires_at: nullableString,
    p_revoked_at: nullableString,
    p_revocation_reason: nullableString,
    p_auto_renew_off: nullableBoolean,
    p_signed_payload: nullableString,
    p_payload_json: v.optional(v.any()),
  },
  handler: async (ctx, args) => await recordVerifiedStorekitTransaction(ctx, args),
});

export const record_verified_streak_restore = internalMutation({
  args: {
    p_user_id: nullableString,
    p_app_account_token: nullableString,
    p_apple_product_id: nullableString,
    p_environment: v.string(),
    p_original_transaction_id: v.string(),
    p_transaction_id: v.string(),
    p_purchased_at: nullableString,
    p_signed_payload: nullableString,
    p_payload_json: v.optional(v.any()),
  },
  handler: async (ctx, args) => await recordVerifiedStreakRestore(ctx, args),
});

export const record_storekit_server_notification = internalMutation({
  args: {
    p_notification_uuid: nullableString,
    p_notification_type: nullableString,
    p_subtype: nullableString,
    p_environment: v.string(),
    p_original_transaction_id: nullableString,
    p_transaction_id: nullableString,
    p_app_account_token: nullableString,
    p_apple_product_id: nullableString,
    p_web_order_line_item_id: nullableString,
    p_status: nullableString,
    p_purchased_at: nullableString,
    p_expires_at: nullableString,
    p_revoked_at: nullableString,
    p_revocation_reason: nullableString,
    p_auto_renew_off: nullableBoolean,
    p_signed_notification_payload: nullableString,
    p_signed_transaction_info: nullableString,
    p_payload_json: v.optional(v.any()),
  },
  handler: async (ctx, args) => await recordStorekitServerNotification(ctx, args),
});

/** Port of `internal.mark_streak_restore_refunded`. Keeps the restored streak and flags the purchase. */
export const mark_streak_restore_refunded = internalMutation({
  args: { p_environment: v.string(), p_transaction_id: v.string() },
  handler: async (ctx, args) => {
    const restoration = await ctx.db
      .query("streak_restorations")
      .withIndex("by_environment_transaction_id", (q) =>
        q.eq("environment", args.p_environment as Doc<"streak_restorations">["environment"]).eq("transaction_id", args.p_transaction_id),
      )
      .unique();
    if (!restoration || restoration.status === "refunded") {
      return false;
    }
    await ctx.db.patch(restoration._id, { status: "refunded", refunded_at: nowIso() });
    return true;
  },
});

// ---- Expiry ----

/**
 * Apple retries a failed renewal for up to 60 days after the period ends, then sends EXPIRED
 * (or DID_RENEW when a payment goes through). A `billing_retry` row stays until that notification,
 * and the cron expires it this long after its `expires_at` in case the notification never came.
 */
const BILLING_RETRY_DAYS = 60;

/**
 * What the cron does to a transaction whose `expires_at` is at least `afterMs` in the past.
 * An active subscription ends. A grace period ends while Apple still retries the payment, so it
 * becomes `billing_retry`. Both end access at that moment, so their members may need an
 * `entitlement_lost` event. A `billing_retry` row granted nothing already.
 */
const LAPSES = [
  { status: "active", next: "expired", afterMs: 0, endsAccess: true },
  { status: "grace", next: "billing_retry", afterMs: 0, endsAccess: true },
  { status: "billing_retry", next: "expired", afterMs: BILLING_RETRY_DAYS * 86_400_000, endsAccess: false },
] as const;

function compareNullsFirst(a: string | undefined, b: string | undefined): number {
  if (a === b) return 0;
  if (a === undefined) return -1;
  if (b === undefined) return 1;
  return a < b ? -1 : 1;
}

/**
 * Port of `internal.expire_stale_entitlements`. Moves lapsed StoreKit transactions on (`LAPSES`),
 * expires lapsed grants, and tells the members of a couple that lost its last entitlement. The SQL
 * schedule never ran it. In Convex the `expire-stale-entitlements` cron runs it, because queries
 * cannot write and would otherwise report a lapsed row as entitled until the next write.
 * Each run handles at most `p_limit` rows (default 500) and handled rows no longer match,
 * so a backlog drains over several runs.
 */
export const expire_stale_entitlements = internalMutation({
  args: { p_now: nullableString, p_limit: v.optional(v.union(v.null(), v.number())) },
  handler: async (ctx, args) => {
    const now = args.p_now === undefined ? nowIso() : args.p_now === null ? null : timestampArg(args.p_now);
    if (now === null) {
      return fail("23514", "entitlement expiry timestamp is required");
    }
    const limit = args.p_limit === undefined ? 500 : args.p_limit;
    if (limit === null || limit < 1 || limit > 5000) {
      return fail("23514", "entitlement expiry limit is out of range");
    }

    const lapsedTransactions: { tx: Doc<"storekit_transactions">; lapse: (typeof LAPSES)[number] }[] = [];
    for (const lapse of LAPSES) {
      const cutoff = addMs(now, -lapse.afterMs);
      const rows = await ctx.db
        .query("storekit_transactions")
        .withIndex("by_status_expires_at", (q) => q.eq("status", lapse.status).gt("expires_at", "").lte("expires_at", cutoff))
        .take(limit);
      lapsedTransactions.push(...rows.map((tx) => ({ tx, lapse })));
    }
    lapsedTransactions.sort(
      (a, b) => compareNullsFirst(a.tx.expires_at, b.tx.expires_at) || compareNullsFirst(a.tx.id, b.tx.id),
    );
    const affectedUserIds = new Set<string>();
    let transactionsExpired = 0;
    let transactionsInBillingRetry = 0;
    for (const { tx, lapse } of lapsedTransactions.slice(0, limit)) {
      await patchStorekitTransaction(ctx, tx, { status: lapse.next });
      if (lapse.next === "expired") transactionsExpired += 1;
      else transactionsInBillingRetry += 1;
      if (lapse.endsAccess) affectedUserIds.add(tx.user_id);
    }

    const expiredGrants = (
      await ctx.db
        .query("entitlement_grants")
        .withIndex("by_status_expires_at", (q) => q.eq("status", "active").gt("expires_at", "").lte("expires_at", now))
        .take(limit)
    ).sort((a, b) => compareNullsFirst(a.expires_at, b.expires_at) || compareNullsFirst(a.id, b.id));
    for (const grant of expiredGrants) {
      await ctx.db.patch(grant._id, withUpdatedAt({ status: "expired" as const }));
      affectedUserIds.add(grant.user_id);
    }

    const couplesToNotify = new Map<string, Doc<"couples">>();
    for (const userId of affectedUserIds) {
      const memberships = await ctx.db
        .query("couple_members")
        .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId).eq("status", "active"))
        .collect();
      for (const membership of memberships) {
        const couple = await getByUuid(ctx, "couples", membership.couple_id);
        if (couple?.status === "active") {
          couplesToNotify.set(couple.id, couple);
        }
      }
    }
    for (const couple of couplesToNotify.values()) {
      let someoneEntitled = false;
      for (const member of await listActiveMembers(ctx, couple.id)) {
        if (await userHasDirectEntitlement(ctx, member.user_id)) {
          someoneEntitled = true;
          break;
        }
      }
      if (someoneEntitled) continue;
      const members = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
        .collect();
      for (const member of members) {
        await createRelationshipSyncEvent(ctx, {
          user_id: member.user_id,
          couple_id: couple.id,
          event_kind: "entitlement_lost",
          reason: "entitlement_expired",
          relationship_status: couple.status,
          member_status: member.status,
          ended_at: couple.ended_at,
          delete_after: couple.delete_after,
          local_purge_scope: {
            entitlement: "refresh",
            relationship_content: "hide",
            media_cache: "purge",
            widget_cache: "purge",
          },
        });
      }
    }

    return [
      {
        storekit_transactions_expired: transactionsExpired,
        storekit_transactions_in_billing_retry: transactionsInBillingRetry,
        entitlement_grants_expired: expiredGrants.length,
      },
    ];
  },
});

// ---- Trial reminders ----

const TRIAL_REMINDER_DAYS_BEFORE_END = 2;

/**
 * Port of `internal.queue_subscription_trial_reminders` (pg_cron job
 * `queue-subscription-trial-reminders`, `15 * * * *`). Queues one reminder per
 * device for verified initial free trials that end within the next two days and
 * an hour, unless renewal is off. `prepare_notification` writes the body at the send, and it
 * tells a payer in no couple with a pending invite that their partner has not joined yet. Returns
 * the number of outbox rows queued.
 */
export const queue_subscription_trial_reminders = internalMutation({
  args: { p_batch_size: v.optional(v.union(v.null(), v.number())) },
  handler: async (ctx, args) => {
    const batchSize = Math.max(args.p_batch_size ?? 500, 1);
    const now = nowIso();
    const reminderMs = TRIAL_REMINDER_DAYS_BEFORE_END * 86_400_000;
    // tx.expires_at - 2 days <= now + 1 hour
    const horizon = addMs(now, reminderMs + 3_600_000);

    // A grace row's expires_at is the end of the grace period, not of the trial.
    const candidates = await ctx.db
      .query("storekit_transactions")
      .withIndex("by_is_free_trial_status_expires_at", (q) =>
        q.eq("is_free_trial", true).eq("status", "active").gt("expires_at", now).lte("expires_at", horizon),
      )
      .collect();

    let queued = 0;
    let picked = 0;
    for (const tx of candidates) {
      if (picked >= batchSize) break;
      if (tx.transaction_id !== tx.original_transaction_id || !tx.expires_at) continue;
      // With renewal off the trial ends without a charge, and the payer hears of the end from the
      // ending push (`queue_subscription_ending_reminders`) instead.
      if (tx.auto_renew_off === true) continue;
      const product = await getByUuid(ctx, "subscription_products", tx.product_id);
      if (!product || !product.is_active || product.kind !== "couple_subscription") continue;

      const preference = await ctx.db
        .query("notification_preferences")
        .withIndex("by_user_id", (q) => q.eq("user_id", tx.user_id))
        .unique();
      if (!preference) continue;
      const devices = await ctx.db
        .query("user_devices")
        .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", tx.user_id).eq("disabled_at", undefined))
        .collect();
      let hasUnqueuedDevice = false;
      for (const device of devices) {
        const existing = await ctx.db
          .query("notification_outbox")
          .withIndex("by_dedupe_key", (q) => q.eq("dedupe_key", `subscription_trial_reminder:${tx.id}:${device.id}`))
          .first();
        if (!existing) {
          hasUnqueuedDevice = true;
          break;
        }
      }
      if (!hasUnqueuedDevice) continue;

      picked += 1;
      const reminderAt = addMs(tx.expires_at, -reminderMs);
      const deliverAt = reminderAt > now ? reminderAt : now;
      // A trial found late (shorter than two days, or a missed run) says how much time is really left.
      const daysLeft = Math.max(1, Math.ceil((Date.parse(tx.expires_at) - Date.parse(deliverAt)) / 86_400_000));
      queued += await enqueueNotificationForUser(ctx, {
        recipient_user_id: tx.user_id,
        kind: "subscription_trial_reminder",
        payload: {
          type: "subscription_trial_reminder",
          route: "subscription",
          deeplink: "paeonia://settings/subscription",
          subscription_id: tx.id,
          trial_ends_at: tx.expires_at,
          days_left: daysLeft,
        },
        dedupe_key: `subscription_trial_reminder:${tx.id}`,
        redaction_level: "private",
        apns_push_type: "alert",
        apns_collapse_id: "subscription-trial",
        scheduled_for: deliverAt,
      });
    }
    return queued;
  },
});

// ---- Ending reminders ----

/**
 * Hourly (`queue-subscription-ending-reminders`). Finds subscriptions whose payer turned off
 * auto-renew and whose period ends within `ENDING_NOTICE_DAYS` days and an hour, and queues the
 * ending push for the payer and their partner (`queueAccessEndingPushes`). Each one is deduped per
 * couple and end, so later runs queue nothing new. Returns the number of outbox rows queued.
 */
export const queue_subscription_ending_reminders = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = nowIso();
    const horizon = addMs(now, ENDING_NOTICE_DAYS * 86_400_000 + 3_600_000);
    const candidates = await ctx.db
      .query("storekit_transactions")
      .withIndex("by_auto_renew_off_status_expires_at", (q) =>
        q.eq("auto_renew_off", true).eq("status", "active").gt("expires_at", now).lte("expires_at", horizon),
      )
      .collect();
    let queued = 0;
    for (const payerUserId of new Set(candidates.map((tx) => tx.user_id))) {
      queued += await queueAccessEndingPushes(ctx, payerUserId, now);
    }
    return queued;
  },
});

// ---- Apple App Store Server Notifications webhook ----

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function uuidOrNull(value: unknown): string | null {
  const text = stringOrNull(value);
  return text && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}

type NotificationPayload = {
  notificationType: string;
  subtype?: string | null;
  notificationUUID: string;
  data?: { environment?: "Sandbox" | "Production"; signedTransactionInfo?: string; signedRenewalInfo?: string };
};

function revocationState(
  notificationType: string,
  transactionInfo: AppleTransactionInfo,
): { revokedAt: string | null; reason: string | null } {
  if (transactionInfo.revocationDate) {
    return { revokedAt: millisToIsoOrNull(transactionInfo.revocationDate), reason: revocationReason(transactionInfo) };
  }
  if (notificationType === "REFUND") {
    return { revokedAt: nowIso(), reason: "customer_refund" };
  }
  if (notificationType === "REVOKE") {
    return { revokedAt: nowIso(), reason: "developer_revoked" };
  }
  return { revokedAt: null, reason: null };
}

/**
 * `POST /apple/server-notifications`. Port of the apple-server-notifications
 * Edge Function. Apple verifies nothing about the caller, so the signed payload
 * is checked against Apple's root certificates before anything is stored.
 */
export const apple_server_notifications = httpAction(async (ctx, request) => {
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Method not allowed" });
  }

  try {
    let body: Record<string, unknown>;
    try {
      body = await request.json();
    } catch {
      throw new Error("Request body must be JSON");
    }
    const signedPayload = stringOrNull(body.signedPayload);
    if (!signedPayload) {
      return jsonResponse(400, { ok: false, error: "Missing signedPayload" });
    }

    const verification = await ctx.runAction(internal.storekitNode.verify_notification, { signedPayload });
    if (!verification) {
      return jsonResponse(400, { ok: false, error: "Invalid Apple notification" });
    }
    const notification = verification.notification as NotificationPayload;
    const transactionInfo = verification.transactionInfo as AppleTransactionInfo | null;
    const renewalInfo = verification.renewalInfo as AppleRenewalInfo | null;
    const notificationType = requireString(notification.notificationType, "notificationType");

    // The streak-restore consumable lives outside the subscription tables.
    // Refunds are logged; the restored streak is intentionally kept.
    if (transactionInfo?.productId === STREAK_RESTORE_PRODUCT_ID) {
      let processed = false;
      if (notificationType === "REFUND" || notificationType === "REVOKE") {
        try {
          await ctx.runMutation(internal.storekit.mark_streak_restore_refunded, {
            p_environment: toDatabaseEnvironment(transactionInfo.environment),
            p_transaction_id: transactionInfo.transactionId,
          });
          processed = true;
        } catch (error) {
          console.error("[apple-server-notifications] streak restore refund failed", error);
          return jsonResponse(500, {
            received: false,
            processed: false,
            error: "Could not record streak restore refund",
          });
        }
      }
      return jsonResponse(200, { received: true, duplicate: false, processed });
    }

    const environment = toDatabaseEnvironment(transactionInfo?.environment ?? notification.data?.environment);
    const subscription = transactionInfo ? determineSubscription(transactionInfo, renewalInfo, notificationType) : null;
    const revocation = transactionInfo
      ? revocationState(notificationType, transactionInfo)
      : { revokedAt: null, reason: null };

    let result: Record<string, unknown>;
    try {
      result = await ctx.runMutation(internal.storekit.record_storekit_server_notification, {
        p_notification_uuid: requireString(notification.notificationUUID, "notificationUUID"),
        p_notification_type: notificationType,
        p_subtype: stringOrNull(notification.subtype),
        p_environment: environment,
        p_original_transaction_id: transactionInfo?.originalTransactionId ?? null,
        p_transaction_id: transactionInfo?.transactionId ?? null,
        p_app_account_token: uuidOrNull(transactionInfo?.appAccountToken),
        p_apple_product_id: transactionInfo?.productId ?? null,
        p_web_order_line_item_id: transactionInfo?.webOrderLineItemId ?? null,
        p_status: subscription?.status ?? null,
        p_purchased_at: millisToIsoOrNull(transactionInfo?.purchaseDate),
        p_expires_at: millisToIsoOrNull(subscription?.expiresAt),
        p_revoked_at: revocation.revokedAt,
        p_revocation_reason: revocation.reason,
        p_auto_renew_off: autoRenewOff(renewalInfo),
        p_signed_notification_payload: signedPayload,
        p_signed_transaction_info: notification.data?.signedTransactionInfo ?? null,
        p_payload_json: JSON.parse(
          JSON.stringify({
            notification,
            transactionInfo,
            renewalInfo,
            signedRenewalInfo: notification.data?.signedRenewalInfo ?? null,
            processedAt: nowIso(),
          }),
        ),
      });
    } catch (error) {
      console.error("[apple-server-notifications] mutation failed", error);
      return jsonResponse(500, { received: false, processed: false, error: "Could not record Apple notification" });
    }

    const resultStatus = typeof result.status === "number" ? result.status : 500;
    if (result.ok !== true && resultStatus >= 500) {
      return jsonResponse(resultStatus, {
        received: false,
        processed: false,
        error: typeof result.error === "string" ? result.error : "Could not process Apple notification",
      });
    }
    return jsonResponse(200, {
      received: true,
      duplicate: result.duplicate === true,
      processed: result.processed === true,
    });
  } catch (error) {
    console.error("[apple-server-notifications]", error);
    return jsonResponse(500, { received: false, processed: false, error: "Unexpected error" });
  }
});
