import { type ObjectType, v } from "convex/values";
import { internal } from "./_generated/api";
import { action, internalQuery, mutation, query, type ActionCtx } from "./_generated/server";
import { readAccessSnapshot } from "./lib/accessSnapshot";
import {
  type AppleRenewalInfo,
  type AppleTransactionInfo,
  appleBundleId,
  assertAppleEnvironmentConfigured,
  autoRenewOff,
  decodeAppleJWS,
  determineSubscription,
  failWithClientSafeError,
  millisToIsoOrNull,
  revocationReason,
  stringOrNull,
  toDatabaseEnvironment,
  verifyTransactionWithApple,
} from "./lib/appleStoreKit";
import { activeUserIdForSubject, getCurrentUserId } from "./lib/auth";
import { fail } from "./lib/errors";
import { newUuid, uuidArg } from "./lib/ids";
import { nowIso } from "./lib/time";
import { storekitEnvironment } from "./lib/validators";

// ---- App-callable reads and token handling ----

/**
 * Port of `get_access_snapshot`. One row with the JSON objects the app routes on.
 * A banned account gets `account_status: "banned"` and nothing else, so the app
 * shows the closed-account screen. The app subscribes to this, so a ban reaches
 * an open app at once.
 */
export const get_access_snapshot = query({
  args: {},
  handler: async (ctx) => [await readAccessSnapshot(ctx)],
});

/** Port of `get_or_create_app_account_token`. Returns the uuid the app passes to StoreKit as appAccountToken. */
export const get_or_create_app_account_token = mutation({
  args: { p_user_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await getCurrentUserId(ctx);
    if (!userId || uuidArg(args.p_user_id) !== userId) {
      return fail("42501", "not authorized");
    }
    const existing = await ctx.db
      .query("app_account_tokens")
      .withIndex("by_user_id", (q) => q.eq("user_id", userId))
      .unique();
    if (existing) {
      return existing.token;
    }
    const now = nowIso();
    const token = newUuid();
    await ctx.db.insert("app_account_tokens", { user_id: userId, token, created_at: now, updated_at: now });
    return token;
  },
});

/** Maps a Clerk subject to the Paeonia user id for the actions below. */
export const user_id_for_subject = internalQuery({
  args: { subject: v.string() },
  handler: async (ctx, args) => await activeUserIdForSubject(ctx, args.subject),
});

// ---- Purchase actions ----

const STREAK_RESTORE_PRODUCT_ID = "no.paeonia.streak.restore";
const ALLOWED_SUBSCRIPTION_PRODUCTS = new Set(["no.paeonia.couple", "no.paeonia.couple.year"]);

const purchaseArgs = {
  jws: v.string(),
  transactionId: v.string(),
  originalTransactionId: v.string(),
  productId: v.string(),
  environment: storekitEnvironment,
};

type PurchaseArgs = ObjectType<typeof purchaseArgs> & { priceDisplay?: string };

type SubscriptionResult = {
  entitled: boolean;
  subscription: {
    status: string;
    productId: string;
    expiresAt: string | null;
    environment: "sandbox" | "production";
    originalTransactionId: string;
    transactionId: string;
  };
};

/** Error codes for text the record mutations return. Anything else is `purchase_not_saved`. */
const RECORD_FAILURE_CODES: Record<string, string> = {
  "Invalid user": "not_signed_in",
  "Apple transaction is missing appAccountToken": "app_account_token_missing",
  "Apple appAccountToken is not registered": "purchase_linked_to_another_account",
  "Apple transaction belongs to a different user": "purchase_linked_to_another_account",
  "Apple product is not active in Paeonia": "invalid_transaction",
  "No entitled couple for this user": "no_entitled_couple",
  "No streak is available to restore": "no_streak_to_restore",
};

/** The Convex values accepted by mutations have no `undefined` fields, so round-trip through JSON. */
function plain<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function failRecord(result: Record<string, unknown>, fallback: string): never {
  const message = typeof result.error === "string" ? result.error : fallback;
  return fail(RECORD_FAILURE_CODES[message] ?? "purchase_not_saved", message);
}

async function signedInUserId(ctx: ActionCtx): Promise<string | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return null;
  }
  return await ctx.runQuery(internal.access.user_id_for_subject, { subject: identity.subject });
}

/** Everything the two purchase flows share up to the point where Apple has confirmed the transaction. */
async function verifyUploadedTransaction(ctx: ActionCtx, args: PurchaseArgs) {
  assertAppleEnvironmentConfigured();
  const userId = await signedInUserId(ctx);
  if (!userId) {
    return fail("not_signed_in", "Invalid session");
  }
  const uploaded = decodeAppleJWS(args.jws) as Partial<AppleTransactionInfo>;
  if (!stringOrNull(args.transactionId)) {
    return fail("invalid_request", "Missing transactionId");
  }
  if (args.environment === "xcode") {
    return fail("invalid_request", "Local StoreKit transactions cannot be verified by Apple");
  }
  const verified = await verifyTransactionWithApple(
    args.transactionId,
    args.environment === "sandbox" ? "Sandbox" : "Production",
  );
  return { userId, uploaded, verified };
}

function assertValidSubscription(
  transactionInfo: AppleTransactionInfo,
  renewalInfo: AppleRenewalInfo | undefined,
  uploaded: Partial<AppleTransactionInfo>,
  args: PurchaseArgs,
): void {
  const comparedFields = ["transactionId", "originalTransactionId", "bundleId", "productId", "environment"] as const;
  for (const field of comparedFields) {
    const uploadedValue = uploaded[field];
    if (uploadedValue !== undefined && uploadedValue !== transactionInfo[field]) {
      fail("transaction_mismatch", "Uploaded transaction does not match Apple verification");
    }
  }
  if (args.originalTransactionId && args.originalTransactionId !== transactionInfo.originalTransactionId) {
    fail("transaction_mismatch", "Original transaction does not match Apple verification");
  }
  if (args.productId && args.productId !== transactionInfo.productId) {
    fail("transaction_mismatch", "Product does not match Apple verification");
  }
  if (transactionInfo.bundleId !== appleBundleId()) {
    fail("transaction_mismatch", "Apple transaction bundle does not match Paeonia");
  }
  if (!ALLOWED_SUBSCRIPTION_PRODUCTS.has(transactionInfo.productId)) {
    fail("invalid_transaction", "Apple product is not supported");
  }
  if (transactionInfo.type !== "Auto-Renewable Subscription") {
    fail("invalid_transaction", "Apple transaction is not a subscription");
  }
  const { status } = determineSubscription(transactionInfo, renewalInfo);
  if ((status === "active" || status === "grace") && !transactionInfo.expiresDate) {
    fail("invalid_transaction", "Apple subscription is missing an expiry date");
  }
}

function assertValidStreakRestore(transactionInfo: AppleTransactionInfo, args: PurchaseArgs): void {
  if (args.productId && args.productId !== transactionInfo.productId) {
    fail("transaction_mismatch", "Product does not match Apple verification");
  }
  if (transactionInfo.bundleId !== appleBundleId()) {
    fail("transaction_mismatch", "Apple transaction bundle does not match Paeonia");
  }
  if (transactionInfo.productId !== STREAK_RESTORE_PRODUCT_ID) {
    fail("invalid_transaction", "Apple product is not supported");
  }
  if (transactionInfo.type !== "Consumable") {
    fail("invalid_transaction", "Apple transaction is not a streak restore");
  }
  if (!transactionInfo.appAccountToken) {
    fail("app_account_token_missing", "Apple transaction is missing appAccountToken");
  }
}

async function runVerifyPurchase(ctx: ActionCtx, args: PurchaseArgs): Promise<SubscriptionResult> {
  const { userId, uploaded, verified } = await verifyUploadedTransaction(ctx, args);
  const { transactionInfo, renewalInfo } = verified;
  assertValidSubscription(transactionInfo, renewalInfo, uploaded, args);

  const { status, expiresAt } = determineSubscription(transactionInfo, renewalInfo);
  let result: Record<string, unknown>;
  try {
    result = await ctx.runMutation(internal.storekit.record_verified_storekit_transaction, {
      p_user_id: userId,
      p_app_account_token: transactionInfo.appAccountToken ?? null,
      p_apple_product_id: transactionInfo.productId,
      p_environment: toDatabaseEnvironment(transactionInfo.environment),
      p_original_transaction_id: transactionInfo.originalTransactionId,
      p_transaction_id: transactionInfo.transactionId,
      p_web_order_line_item_id: transactionInfo.webOrderLineItemId ?? null,
      p_status: status,
      p_purchased_at: millisToIsoOrNull(transactionInfo.purchaseDate),
      p_expires_at: millisToIsoOrNull(expiresAt),
      p_revoked_at: millisToIsoOrNull(transactionInfo.revocationDate),
      p_revocation_reason: revocationReason(transactionInfo),
      p_auto_renew_off: autoRenewOff(renewalInfo),
      p_signed_payload: verified.signedTransactionInfo,
      p_payload_json: plain({
        transactionInfo,
        renewalInfo: renewalInfo ?? null,
        uploadedTransactionInfo: uploaded,
        signedRenewalInfo: verified.signedRenewalInfo ?? null,
        priceDisplay: stringOrNull(args.priceDisplay),
        verifiedAt: nowIso(),
      }),
    });
  } catch (error) {
    console.error("[verify_purchase] transaction record failed", error);
    return fail("purchase_not_saved", "Could not save subscription");
  }
  if (result.ok !== true) {
    return failRecord(result, "Could not save subscription");
  }

  return {
    entitled: status === "active" || status === "grace",
    subscription: {
      status,
      productId: transactionInfo.productId,
      expiresAt: millisToIsoOrNull(expiresAt),
      environment: toDatabaseEnvironment(transactionInfo.environment),
      originalTransactionId: transactionInfo.originalTransactionId,
      transactionId: transactionInfo.transactionId,
    },
  };
}

async function runRedeemStreakRestore(ctx: ActionCtx, args: PurchaseArgs): Promise<{ restoredCount: number }> {
  const { userId, uploaded, verified } = await verifyUploadedTransaction(ctx, args);
  const { transactionInfo } = verified;
  assertValidStreakRestore(transactionInfo, args);

  let result: Record<string, unknown>;
  try {
    result = await ctx.runMutation(internal.storekit.record_verified_streak_restore, {
      p_user_id: userId,
      p_app_account_token: transactionInfo.appAccountToken ?? null,
      p_apple_product_id: transactionInfo.productId,
      p_environment: toDatabaseEnvironment(transactionInfo.environment),
      p_original_transaction_id: transactionInfo.originalTransactionId,
      p_transaction_id: transactionInfo.transactionId,
      p_purchased_at: millisToIsoOrNull(transactionInfo.purchaseDate),
      p_signed_payload: verified.signedTransactionInfo,
      p_payload_json: plain({ transactionInfo, uploadedTransactionInfo: uploaded, verifiedAt: nowIso() }),
    });
  } catch (error) {
    console.error("[redeem_streak_restore] restore record failed", error);
    return fail("purchase_not_saved", "Could not restore your streak");
  }
  if (result.ok !== true) {
    return failRecord(result, "Could not restore your streak");
  }
  return { restoredCount: typeof result.restoredCount === "number" ? result.restoredCount : 0 };
}

/**
 * Checks a StoreKit subscription purchase with Apple and records it. The caller
 * is the signed-in user. `jws` is the signed transaction from StoreKit, and the
 * other transaction fields must match what Apple returns for `transactionId`.
 *
 * Returns `{ entitled, subscription }`. Fails with `not_signed_in`,
 * `invalid_request`, `transaction_mismatch`, `invalid_transaction`,
 * `app_account_token_missing`, `purchase_linked_to_another_account`,
 * `apple_verification_failed`, `service_not_ready`, `purchase_not_saved`, or
 * `unexpected`. The message is written for the app to show or log.
 */
export const verify_purchase = action({
  args: { ...purchaseArgs, priceDisplay: v.optional(v.string()) },
  handler: async (ctx, args): Promise<SubscriptionResult> => {
    try {
      return await runVerifyPurchase(ctx, args);
    } catch (error) {
      return failWithClientSafeError("verify_purchase", error);
    }
  },
});

/**
 * Checks a streak restore purchase with Apple and applies it to the caller's
 * couple. Takes the same arguments as `verify_purchase` without `priceDisplay`.
 *
 * Returns `{ restoredCount }`. Fails with the codes of `verify_purchase`, plus
 * `no_entitled_couple` and `no_streak_to_restore`.
 */
export const redeem_streak_restore = action({
  args: purchaseArgs,
  handler: async (ctx, args): Promise<{ restoredCount: number }> => {
    try {
      return await runRedeemStreakRestore(ctx, args);
    } catch (error) {
      return failWithClientSafeError("redeem_streak_restore", error);
    }
  },
});
