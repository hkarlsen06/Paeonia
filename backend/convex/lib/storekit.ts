import type { Doc } from "../_generated/dataModel";
import { sha256Hex } from "./crypto";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { checkViolation } from "./errors";
import { getEntitledCoupleIdForUser } from "./access";
import { newUuid, optionalTimestampArg, uuidArg } from "./ids";
import { isJsonObject } from "./json";
import { applyStreakRestore } from "./streaks";
import { invalidateAccessEndingPushes, queuePaymentFailedPush } from "./subscriptionNotices";
import { nowIso } from "./time";

export const STOREKIT_STATUSES = ["active", "grace", "billing_retry", "expired", "revoked", "refunded"] as const;
export type StorekitStatus = (typeof STOREKIT_STATUSES)[number];
export const STOREKIT_ENVIRONMENTS = ["xcode", "sandbox", "production"] as const;
export type StorekitEnvironment = (typeof STOREKIT_ENVIRONMENTS)[number];

/** Result of the record_* functions. Failures are values, not exceptions, like the SQL jsonb results. */
export type StorekitRecordResult =
  | ({ ok: true } & Record<string, unknown>)
  | { ok: false; error: string; status: number };

function recordFailure(error: string, status: number): StorekitRecordResult {
  return { ok: false, error, status };
}

function assertEnvironment(value: string): StorekitEnvironment {
  if (!(STOREKIT_ENVIRONMENTS as readonly string[]).includes(value)) {
    checkViolation("storekit_transactions", "storekit_transactions_environment_check");
  }
  return value as StorekitEnvironment;
}

// ---- app account tokens ----

/** Port of `internal.get_user_id_by_app_account_token`. */
export async function findAppAccountTokenOwner(ctx: ReaderCtx, token: string): Promise<string | null> {
  const row = await ctx.db
    .query("app_account_tokens")
    .withIndex("by_token", (q) => q.eq("token", token))
    .unique();
  return row?.user_id ?? null;
}

// ---- storekit_payloads ----

export type StorekitPayloadInsert = {
  payload_kind: Doc<"storekit_payloads">["payload_kind"];
  environment: StorekitEnvironment;
  original_transaction_id?: string | null;
  transaction_id?: string | null;
  notification_uuid?: string | null;
  signed_payload?: string | null;
  payload_json?: unknown;
  sha256?: string | null;
};

/**
 * Inserts a payload archive row. A row with the same non-null (environment,
 * sha256) already stored is returned instead, like `on conflict ... do update
 * set received_at = received_at`.
 */
export async function insertStorekitPayload(ctx: WriterCtx, row: StorekitPayloadInsert): Promise<string> {
  if (row.sha256) {
    const sha256 = row.sha256;
    const existing = await ctx.db
      .query("storekit_payloads")
      .withIndex("by_environment_sha256", (q) => q.eq("environment", row.environment).eq("sha256", sha256))
      .first();
    if (existing) {
      return existing.id;
    }
  }
  const now = nowIso();
  const id = newUuid();
  await ctx.db.insert("storekit_payloads", {
    id,
    payload_kind: row.payload_kind,
    environment: row.environment,
    original_transaction_id: row.original_transaction_id ?? undefined,
    transaction_id: row.transaction_id ?? undefined,
    notification_uuid: row.notification_uuid ?? undefined,
    signed_payload: row.signed_payload ?? undefined,
    payload_json: row.payload_json ?? undefined,
    sha256: row.sha256 ?? undefined,
    received_at: now,
    created_at: now,
  });
  return id;
}

// ---- storekit_transactions ----

export async function findStorekitTransaction(
  ctx: ReaderCtx,
  environment: StorekitEnvironment,
  transactionId: string,
): Promise<Doc<"storekit_transactions"> | null> {
  return await ctx.db
    .query("storekit_transactions")
    .withIndex("by_environment_transaction_id", (q) =>
      q.eq("environment", environment).eq("transaction_id", transactionId),
    )
    .unique();
}

/**
 * Port of the `invalidate_subscription_trial_reminder` trigger body: deletes
 * the unsent, unfailed trial reminders queued for one subscription. The queue
 * builds dedupe keys as `subscription_trial_reminder:<subscription id>:<device id>`.
 */
export async function invalidateSubscriptionTrialReminder(ctx: WriterCtx, subscriptionId: string): Promise<void> {
  const prefix = `subscription_trial_reminder:${subscriptionId}:`;
  const rows = await ctx.db
    .query("notification_outbox")
    .withIndex("by_dedupe_key", (q) => q.gte("dedupe_key", prefix).lt("dedupe_key", `${prefix}￿`))
    .collect();
  for (const row of rows) {
    if (
      row.kind === "subscription_trial_reminder" &&
      row.sent_at === undefined &&
      row.failed_at === undefined &&
      isJsonObject(row.payload) &&
      row.payload.subscription_id === subscriptionId
    ) {
      await ctx.db.delete(row._id);
    }
  }
}

export type StorekitTransactionFields = Omit<
  Doc<"storekit_transactions">,
  "_id" | "_creationTime" | "id" | "created_at" | "updated_at"
>;

/**
 * Write helper for every `storekit_transactions` patch. Replaces the
 * `set_updated_at` trigger and the update half of
 * `invalidate_trial_reminder_after_storekit_update`.
 */
export async function patchStorekitTransaction(
  ctx: WriterCtx,
  tx: Doc<"storekit_transactions">,
  patch: Partial<StorekitTransactionFields>,
): Promise<void> {
  const statusChanged = "status" in patch && patch.status !== tx.status;
  const expiryChanged = "expires_at" in patch && patch.expires_at !== tx.expires_at;
  const renewalChanged = "auto_renew_off" in patch && patch.auto_renew_off !== tx.auto_renew_off;
  await ctx.db.patch(tx._id, withUpdatedAt(patch));
  if (statusChanged || expiryChanged) {
    await invalidateSubscriptionTrialReminder(ctx, tx.id);
  }
  if (renewalChanged || statusChanged || expiryChanged) {
    await invalidateAccessEndingPushes(ctx, tx.user_id);
  }
}

/** Write helper for `storekit_transactions` deletes. Replaces `invalidate_trial_reminder_after_storekit_delete`. */
export async function deleteStorekitTransaction(ctx: WriterCtx, tx: Doc<"storekit_transactions">): Promise<void> {
  await ctx.db.delete(tx._id);
  await invalidateSubscriptionTrialReminder(ctx, tx.id);
}

/**
 * Inserts a transaction, or overwrites every column of the row with the same
 * (environment, transaction_id), like `on conflict ... do update`. Returns the row id.
 */
export async function upsertStorekitTransaction(
  ctx: WriterCtx,
  fields: StorekitTransactionFields,
): Promise<string> {
  const existing = await findStorekitTransaction(ctx, fields.environment, fields.transaction_id);
  if (existing) {
    await patchStorekitTransaction(ctx, existing, fields);
    return existing.id;
  }
  const now = nowIso();
  const id = newUuid();
  await ctx.db.insert("storekit_transactions", { ...fields, id, created_at: now, updated_at: now });
  return id;
}

// ---- record_verified_storekit_transaction ----

/** True when the payload's transaction info says the purchase started with a free trial offer. */
export function isFreeTrialPayload(payloadJson: unknown): boolean {
  const info = isJsonObject(payloadJson) ? payloadJson.transactionInfo : undefined;
  return (
    isJsonObject(info) &&
    String(info.offerType) === "1" &&
    String(info.offerDiscountType ?? "").toUpperCase() === "FREE_TRIAL"
  );
}

export type VerifiedTransactionInput = {
  p_user_id?: string | null;
  p_app_account_token?: string | null;
  p_apple_product_id?: string | null;
  p_environment: string;
  p_original_transaction_id: string;
  p_transaction_id: string;
  p_web_order_line_item_id?: string | null;
  p_status?: string | null;
  p_purchased_at?: string | null;
  p_expires_at?: string | null;
  p_revoked_at?: string | null;
  p_revocation_reason?: string | null;
  /** True when Apple's renewal info says the payer turned off auto-renew. Null keeps what is stored. */
  p_auto_renew_off?: boolean | null;
  p_signed_payload?: string | null;
  p_payload_json?: unknown;
};

/**
 * Ownership checks shared by both record_verified_* functions. A token no
 * account holds comes back as `orphaned`. Account deletion removes the token,
 * so this is a purchase whose account is gone.
 */
async function checkAppAccountToken(
  ctx: ReaderCtx,
  userId: string | null | undefined,
  appAccountToken: string | null | undefined,
): Promise<{ failure: StorekitRecordResult } | { userId: string; token: string; orphaned: boolean }> {
  if (!userId) {
    return { failure: recordFailure("Invalid user", 401) };
  }
  if (!appAccountToken) {
    return { failure: recordFailure("Apple transaction is missing appAccountToken", 403) };
  }
  const token = uuidArg(appAccountToken);
  const owner = await findAppAccountTokenOwner(ctx, token);
  if (owner && owner !== userId) {
    return { failure: recordFailure("Apple transaction belongs to a different user", 403) };
  }
  return { userId, token, orphaned: !owner };
}

/** A user whose account deletion finished, or whose row no longer exists. */
async function isGoneUser(ctx: ReaderCtx, userId: string): Promise<boolean> {
  if (!(await getByUuid(ctx, "users", userId))) {
    return true;
  }
  const completedDeletion = await ctx.db
    .query("account_deletion_jobs")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .filter((q) => q.eq(q.field("status"), "completed"))
    .first();
  return completedDeletion !== null;
}

/**
 * Someone who deletes their account and signs up again keeps paying Apple for
 * the old subscription, and StoreKit hands it to the new account with the old
 * token. When every earlier owner of the subscription is gone, it moves to
 * `userId`. A subscription a live account still holds stays with that account.
 */
async function adoptOrphanedSubscription(
  ctx: WriterCtx,
  userId: string,
  environment: StorekitEnvironment,
  originalTransactionId: string,
): Promise<StorekitRecordResult | null> {
  const rows = await ctx.db
    .query("storekit_transactions")
    .withIndex("by_environment_original_transaction_id", (q) =>
      q.eq("environment", environment).eq("original_transaction_id", originalTransactionId),
    )
    .collect();
  const earlierOwners = [...new Set(rows.map((row) => row.user_id))].filter((owner) => owner !== userId);
  for (const owner of earlierOwners) {
    if (!(await isGoneUser(ctx, owner))) {
      return recordFailure("Apple transaction belongs to a different user", 403);
    }
  }
  for (const row of rows) {
    if (row.user_id !== userId) {
      await patchStorekitTransaction(ctx, row, { user_id: userId });
    }
  }
  return null;
}

async function findActiveProduct(
  ctx: ReaderCtx,
  appleProductId: string | null | undefined,
  kind?: Doc<"subscription_products">["kind"],
): Promise<Doc<"subscription_products"> | null> {
  if (!appleProductId) {
    return null;
  }
  const product = await ctx.db
    .query("subscription_products")
    .withIndex("by_apple_product_id", (q) => q.eq("apple_product_id", appleProductId))
    .unique();
  if (!product || !product.is_active || (kind !== undefined && product.kind !== kind)) {
    return null;
  }
  return product;
}

/** Port of `internal.record_verified_storekit_transaction`. */
export async function recordVerifiedStorekitTransaction(
  ctx: WriterCtx,
  input: VerifiedTransactionInput,
): Promise<StorekitRecordResult> {
  const userId = input.p_user_id ? uuidArg(input.p_user_id) : null;
  const checked = await checkAppAccountToken(ctx, userId, input.p_app_account_token);
  if ("failure" in checked) {
    return checked.failure;
  }

  const product = await findActiveProduct(ctx, input.p_apple_product_id);
  if (!product) {
    return recordFailure("Apple product is not active in Paeonia", 400);
  }

  const environment = assertEnvironment(input.p_environment);
  if (checked.orphaned) {
    const refused = await adoptOrphanedSubscription(ctx, checked.userId, environment, input.p_original_transaction_id);
    if (refused) {
      return refused;
    }
  }
  const existing = await findStorekitTransaction(ctx, environment, input.p_transaction_id);
  if (existing && existing.user_id !== checked.userId) {
    return recordFailure("Apple transaction belongs to a different user", 403);
  }

  const status = input.p_status;
  if (!status || !(STOREKIT_STATUSES as readonly string[]).includes(status)) {
    checkViolation("storekit_transactions", "storekit_transactions_status_check");
  }

  const payloadId = await insertStorekitPayload(ctx, {
    payload_kind: "transaction",
    environment,
    original_transaction_id: input.p_original_transaction_id,
    transaction_id: input.p_transaction_id,
    signed_payload: input.p_signed_payload,
    payload_json: input.p_payload_json,
  });

  const transactionId = await upsertStorekitTransaction(ctx, {
    user_id: checked.userId,
    product_id: product.id,
    environment,
    app_account_token: checked.token,
    original_transaction_id: input.p_original_transaction_id,
    transaction_id: input.p_transaction_id,
    web_order_line_item_id: input.p_web_order_line_item_id ?? undefined,
    status: status as StorekitStatus,
    purchased_at: optionalTimestampArg(input.p_purchased_at),
    expires_at: optionalTimestampArg(input.p_expires_at),
    revoked_at: optionalTimestampArg(input.p_revoked_at),
    revocation_reason: input.p_revocation_reason ?? undefined,
    is_free_trial: isFreeTrialPayload(input.p_payload_json) ? true : undefined,
    auto_renew_off: (input.p_auto_renew_off ?? existing?.auto_renew_off) === true ? true : undefined,
    raw_payload_id: payloadId,
  });

  return { ok: true, productId: product.id, payloadId, transactionId };
}

// ---- record_verified_streak_restore ----

export type VerifiedStreakRestoreInput = {
  p_user_id?: string | null;
  p_app_account_token?: string | null;
  p_apple_product_id?: string | null;
  p_environment: string;
  p_original_transaction_id: string;
  p_transaction_id: string;
  p_purchased_at?: string | null;
  p_signed_payload?: string | null;
  p_payload_json?: unknown;
};

/** Port of `internal.record_verified_streak_restore`. */
export async function recordVerifiedStreakRestore(
  ctx: WriterCtx,
  input: VerifiedStreakRestoreInput,
): Promise<StorekitRecordResult> {
  const userId = input.p_user_id ? uuidArg(input.p_user_id) : null;
  const checked = await checkAppAccountToken(ctx, userId, input.p_app_account_token);
  if ("failure" in checked) {
    return checked.failure;
  }
  // A streak restore is bought on the spot, so it always carries the buyer's token.
  if (checked.orphaned) {
    return recordFailure("Apple appAccountToken is not registered", 403);
  }

  const product = await findActiveProduct(ctx, input.p_apple_product_id, "streak_restore");
  if (!product) {
    return recordFailure("Apple product is not active in Paeonia", 400);
  }

  const coupleId = await getEntitledCoupleIdForUser(ctx, checked.userId);
  if (!coupleId) {
    return recordFailure("No entitled couple for this user", 403);
  }

  const environment = assertEnvironment(input.p_environment);
  const payloadId = await insertStorekitPayload(ctx, {
    payload_kind: "transaction",
    environment,
    original_transaction_id: input.p_original_transaction_id,
    transaction_id: input.p_transaction_id,
    signed_payload: input.p_signed_payload,
    payload_json: input.p_payload_json,
  });

  return (await applyStreakRestore(ctx, {
    couple_id: coupleId,
    purchaser_user_id: checked.userId,
    product_id: product.id,
    environment,
    transaction_id: input.p_transaction_id,
    original_transaction_id: input.p_original_transaction_id,
    purchased_at: optionalTimestampArg(input.p_purchased_at) ?? null,
    raw_payload_id: payloadId,
  })) as StorekitRecordResult;
}

// ---- record_storekit_server_notification ----

export type ServerNotificationInput = {
  p_notification_uuid?: string | null;
  p_notification_type?: string | null;
  p_subtype?: string | null;
  p_environment: string;
  p_original_transaction_id?: string | null;
  p_transaction_id?: string | null;
  p_app_account_token?: string | null;
  p_apple_product_id?: string | null;
  p_web_order_line_item_id?: string | null;
  p_status?: string | null;
  p_purchased_at?: string | null;
  p_expires_at?: string | null;
  p_revoked_at?: string | null;
  p_revocation_reason?: string | null;
  p_auto_renew_off?: boolean | null;
  p_signed_notification_payload?: string | null;
  p_signed_transaction_info?: string | null;
  p_payload_json?: unknown;
};

async function resolveExistingTransactionOwner(
  ctx: ReaderCtx,
  environment: StorekitEnvironment,
  transactionId: string,
  originalTransactionId: string,
): Promise<string | null> {
  const exact = await findStorekitTransaction(ctx, environment, transactionId);
  if (exact) {
    return exact.user_id;
  }
  const related = await ctx.db
    .query("storekit_transactions")
    .withIndex("by_environment_original_transaction_id", (q) =>
      q.eq("environment", environment).eq("original_transaction_id", originalTransactionId),
    )
    .collect();
  related.sort((a, b) => (a.updated_at < b.updated_at ? 1 : a.updated_at > b.updated_at ? -1 : 0));
  return related[0]?.user_id ?? null;
}

/** Port of `internal.record_storekit_server_notification`. */
export async function recordStorekitServerNotification(
  ctx: WriterCtx,
  input: ServerNotificationInput,
): Promise<Record<string, unknown>> {
  if (!input.p_notification_uuid) {
    return recordFailure("Invalid notification UUID", 400);
  }
  const notificationUuid = uuidArg(input.p_notification_uuid);
  const notificationType = input.p_notification_type;
  if (!notificationType || notificationType.trim().length < 1 || notificationType.trim().length > 120) {
    return recordFailure("Invalid notification type", 400);
  }
  if (input.p_environment !== "sandbox" && input.p_environment !== "production") {
    return recordFailure("Invalid StoreKit environment", 400);
  }
  const environment = input.p_environment;
  if (!isJsonObject(input.p_payload_json)) {
    return recordFailure("Invalid notification payload", 400);
  }

  const signedPayload = input.p_signed_notification_payload ?? null;
  const payloadId = await insertStorekitPayload(ctx, {
    payload_kind: "server_notification",
    environment,
    original_transaction_id: input.p_original_transaction_id,
    transaction_id: input.p_transaction_id,
    notification_uuid: notificationUuid,
    signed_payload: signedPayload,
    payload_json: input.p_payload_json,
    sha256: signedPayload === null ? null : await sha256Hex(signedPayload),
  });

  const duplicate = await ctx.db
    .query("storekit_notification_events")
    .withIndex("by_notification_uuid", (q) => q.eq("notification_uuid", notificationUuid))
    .first();
  if (duplicate) {
    return { ok: true, duplicate: true, processed: false };
  }
  const now = nowIso();
  const eventId = newUuid();
  const eventDocId = await ctx.db.insert("storekit_notification_events", {
    id: eventId,
    notification_uuid: notificationUuid,
    notification_type: notificationType,
    subtype: input.p_subtype?.trim() ? input.p_subtype.trim() : undefined,
    environment,
    original_transaction_id: input.p_original_transaction_id ?? undefined,
    raw_payload_id: payloadId,
    signed_payload: signedPayload ?? undefined,
    received_at: now,
    created_at: now,
  });
  const setEvent = async (patch: { processed_at?: string; processing_error?: string }) => {
    await ctx.db.patch(eventDocId, patch);
  };

  if (notificationType === "TEST") {
    await setEvent({ processed_at: nowIso(), processing_error: undefined });
    return { ok: true, duplicate: false, processed: true, test: true };
  }

  if (!input.p_transaction_id || !input.p_original_transaction_id) {
    await setEvent({ processing_error: "Apple notification did not include transaction info" });
    return { ok: true, duplicate: false, processed: false, status: 202 };
  }

  const appAccountToken = input.p_app_account_token ? uuidArg(input.p_app_account_token) : null;
  const tokenUserId = appAccountToken ? await findAppAccountTokenOwner(ctx, appAccountToken) : null;
  const existingUserId = await resolveExistingTransactionOwner(
    ctx,
    environment,
    input.p_transaction_id,
    input.p_original_transaction_id,
  );

  if (tokenUserId && existingUserId && tokenUserId !== existingUserId) {
    const error = "Apple notification purchase owner does not match existing transaction owner";
    await setEvent({ processing_error: error });
    return recordFailure(error, 409);
  }

  const resolvedUserId = tokenUserId ?? existingUserId;
  if (!resolvedUserId) {
    await setEvent({ processing_error: "Could not resolve Apple notification purchase owner" });
    return { ok: true, duplicate: false, processed: false, status: 202 };
  }

  const result = await recordVerifiedStorekitTransaction(ctx, {
    p_user_id: resolvedUserId,
    p_app_account_token: appAccountToken,
    p_apple_product_id: input.p_apple_product_id,
    p_environment: environment,
    p_original_transaction_id: input.p_original_transaction_id,
    p_transaction_id: input.p_transaction_id,
    p_web_order_line_item_id: input.p_web_order_line_item_id,
    p_status: input.p_status,
    p_purchased_at: input.p_purchased_at,
    p_expires_at: input.p_expires_at,
    p_revoked_at: input.p_revoked_at,
    p_revocation_reason: input.p_revocation_reason,
    p_auto_renew_off: input.p_auto_renew_off,
    p_signed_payload: input.p_signed_transaction_info,
    p_payload_json: {
      ...input.p_payload_json,
      notificationPayloadId: payloadId,
      notificationEventId: eventId,
    },
  });

  if (result.ok) {
    // Apple could not take the renewal payment. It keeps trying, during the grace period with
    // access, and the payer is told once. Recovery or a renewal records a new active transaction.
    if (notificationType === "DID_FAIL_TO_RENEW") {
      await queuePaymentFailedPush(ctx, resolvedUserId, result.transactionId as string);
    }
    await setEvent({ processed_at: nowIso(), processing_error: undefined });
    return { ok: true, duplicate: false, processed: true, transaction: result };
  }

  const error = result.error || "Could not record StoreKit transaction";
  await setEvent({ processing_error: error.slice(0, 4000) });
  return recordFailure(error, result.status ?? 500);
}
