import { v } from "convex/values";
import { internal } from "./_generated/api";
import { action, internalQuery, mutation, type ActionCtx } from "./_generated/server";
import { resolveCurrentCoupleEntitlement, resolveUserEntitlement } from "./lib/access";
import {
  type AppleRenewalInfo,
  type AppleTransactionInfo,
  appleBundleId,
  assertAppleEnvironmentConfigured,
  clientSafeErrorMessage,
  decodeAppleJWS,
  determineSubscriptionStatus,
  millisToIsoOrNull,
  normalizeClientEnvironment,
  requireString,
  revocationReason,
  stringOrNull,
  toDatabaseEnvironment,
  unwrapAppleResponse,
  verifyTransactionWithApple,
  type AppleResponse,
} from "./lib/appleStoreKit";
import { activeUserIdForSubject, getCurrentUserId, requireUserId } from "./lib/auth";
import { fail } from "./lib/errors";
import { newUuid, uuidArg } from "./lib/ids";
import { getCurrentRelationshipState } from "./lib/relationshipState";
import { nowIso } from "./lib/time";

// ---- App-callable reads and token handling ----

/** Port of `get_access_snapshot`. One row with the three JSON objects the app routes on. */
export const get_access_snapshot = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return [
      {
        user_entitlement: await resolveUserEntitlement(ctx, userId),
        couple_entitlement: await resolveCurrentCoupleEntitlement(ctx, userId),
        relationship_state: await getCurrentRelationshipState(ctx, userId),
      },
    ];
  },
});

/** Port of `get_my_entitlement`. */
export const get_my_entitlement = mutation({
  args: {},
  handler: async (ctx) => [await resolveUserEntitlement(ctx, await requireUserId(ctx))],
});

/** Port of `get_my_couple_entitlement`. Empty when the caller has no active couple. */
export const get_my_couple_entitlement = mutation({
  args: {},
  handler: async (ctx) => {
    const entitlement = await resolveCurrentCoupleEntitlement(ctx, await requireUserId(ctx));
    return entitlement ? [entitlement] : [];
  },
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

/** Port of `complete_review_access_session`. True when the caller owns the session. */
export const complete_review_access_session = mutation({
  args: { p_review_session_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const session = await ctx.db
      .query("review_access_sessions")
      .withIndex("by_uuid", (q) => q.eq("id", uuidArg(args.p_review_session_id)))
      .unique();
    if (!session || session.user_id !== userId) {
      return false;
    }
    if (session.completed_at === undefined) {
      await ctx.db.patch(session._id, { completed_at: nowIso() });
    }
    return true;
  },
});

/** Maps a Clerk subject to the Paeonia user id for the actions below. */
export const user_id_for_subject = internalQuery({
  args: { subject: v.string() },
  handler: async (ctx, args) => await activeUserIdForSubject(ctx, args.subject),
});

// ---- Purchase actions (ports of the apple-verify-purchase and apple-redeem-streak-restore Edge Functions) ----

const STREAK_RESTORE_PRODUCT_ID = "no.paeonia.streak.restore";
const ALLOWED_SUBSCRIPTION_PRODUCTS = new Set(["no.paeonia.couple", "no.paeonia.couple.year"]);

const purchaseBodyArgs = {
  jws: v.optional(v.any()),
  transactionId: v.optional(v.any()),
  originalTransactionId: v.optional(v.any()),
  productId: v.optional(v.any()),
  environment: v.optional(v.any()),
  priceDisplay: v.optional(v.any()),
};

type PurchaseBody = {
  jws?: unknown;
  transactionId?: unknown;
  originalTransactionId?: unknown;
  productId?: unknown;
  environment?: unknown;
  priceDisplay?: unknown;
};

type Validation = { ok: true } | { ok: false; error: string; status: number };

function failure(status: number, error: string): AppleResponse {
  return { status, body: { ok: false, error } };
}

/** The Convex values accepted by mutations have no `undefined` fields, so round-trip through JSON. */
function plain<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

async function signedInUserId(ctx: ActionCtx): Promise<string | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return null;
  }
  return await ctx.runQuery(internal.access.user_id_for_subject, { subject: identity.subject });
}

/** Everything the two purchase flows share up to the point where Apple has confirmed the transaction. */
async function verifyUploadedTransaction(
  ctx: ActionCtx,
  body: PurchaseBody,
): Promise<
  | { response: AppleResponse }
  | { userId: string; uploaded: Partial<AppleTransactionInfo>; verified: Awaited<ReturnType<typeof verifyTransactionWithApple>> }
> {
  assertAppleEnvironmentConfigured();
  const userId = await signedInUserId(ctx);
  if (!userId) {
    return { response: failure(401, "Invalid session") };
  }
  const uploadedJws = requireString(body.jws, "jws");
  const uploaded = decodeAppleJWS(uploadedJws) as Partial<AppleTransactionInfo>;
  const transactionId = stringOrNull(body.transactionId) ?? uploaded.transactionId;
  const requestedEnvironment = normalizeClientEnvironment(body.environment);

  if (!transactionId) {
    return { response: failure(400, "Missing transactionId") };
  }
  if (requestedEnvironment === "xcode") {
    return { response: failure(400, "Local StoreKit transactions cannot be verified by Apple") };
  }
  const verified = await verifyTransactionWithApple(
    transactionId,
    requestedEnvironment === "sandbox" ? "Sandbox" : "Production",
  );
  return { userId, uploaded, verified };
}

function validateSubscription(
  transactionInfo: AppleTransactionInfo,
  renewalInfo: AppleRenewalInfo | undefined,
  uploaded: Partial<AppleTransactionInfo>,
  body: PurchaseBody,
): Validation {
  const comparedFields = ["transactionId", "originalTransactionId", "bundleId", "productId", "environment"] as const;
  for (const field of comparedFields) {
    const uploadedValue = uploaded[field];
    if (uploadedValue !== undefined && uploadedValue !== transactionInfo[field]) {
      return { ok: false, error: "Uploaded transaction does not match Apple verification", status: 400 };
    }
  }
  const requestedOriginal = stringOrNull(body.originalTransactionId);
  if (requestedOriginal && requestedOriginal !== transactionInfo.originalTransactionId) {
    return { ok: false, error: "Original transaction does not match Apple verification", status: 400 };
  }
  const requestedProduct = stringOrNull(body.productId);
  if (requestedProduct && requestedProduct !== transactionInfo.productId) {
    return { ok: false, error: "Product does not match Apple verification", status: 400 };
  }
  if (transactionInfo.bundleId !== appleBundleId()) {
    return { ok: false, error: "Apple transaction bundle does not match Paeonia", status: 403 };
  }
  if (!ALLOWED_SUBSCRIPTION_PRODUCTS.has(transactionInfo.productId)) {
    return { ok: false, error: "Apple product is not supported", status: 400 };
  }
  if (transactionInfo.type !== "Auto-Renewable Subscription") {
    return { ok: false, error: "Apple transaction is not a subscription", status: 400 };
  }
  const status = determineSubscriptionStatus(transactionInfo, renewalInfo);
  if ((status === "active" || status === "grace") && !transactionInfo.expiresDate) {
    return { ok: false, error: "Apple subscription is missing an expiry date", status: 400 };
  }
  return { ok: true };
}

function validateStreakRestore(transactionInfo: AppleTransactionInfo, body: PurchaseBody): Validation {
  const requestedProduct = stringOrNull(body.productId);
  if (requestedProduct && requestedProduct !== transactionInfo.productId) {
    return { ok: false, error: "Product does not match Apple verification", status: 400 };
  }
  if (transactionInfo.bundleId !== appleBundleId()) {
    return { ok: false, error: "Apple transaction bundle does not match Paeonia", status: 403 };
  }
  if (transactionInfo.productId !== STREAK_RESTORE_PRODUCT_ID) {
    return { ok: false, error: "Apple product is not supported", status: 400 };
  }
  if (transactionInfo.type !== "Consumable") {
    return { ok: false, error: "Apple transaction is not a streak restore", status: 400 };
  }
  if (!transactionInfo.appAccountToken) {
    return { ok: false, error: "Apple transaction is missing appAccountToken", status: 403 };
  }
  return { ok: true };
}

async function runVerifyPurchase(ctx: ActionCtx, body: PurchaseBody): Promise<AppleResponse> {
  try {
    const step = await verifyUploadedTransaction(ctx, body);
    if ("response" in step) {
      return step.response;
    }
    const { userId, uploaded, verified } = step;
    const { transactionInfo, renewalInfo } = verified;

    const validation = validateSubscription(transactionInfo, renewalInfo, uploaded, body);
    if (!validation.ok) {
      return failure(validation.status, validation.error);
    }

    const status = determineSubscriptionStatus(transactionInfo, renewalInfo);
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
        p_expires_at: millisToIsoOrNull(transactionInfo.expiresDate),
        p_revoked_at: millisToIsoOrNull(transactionInfo.revocationDate),
        p_revocation_reason: revocationReason(transactionInfo),
        p_signed_payload: verified.signedTransactionInfo,
        p_payload_json: plain({
          transactionInfo,
          renewalInfo: renewalInfo ?? null,
          uploadedTransactionInfo: uploaded,
          signedRenewalInfo: verified.signedRenewalInfo ?? null,
          priceDisplay: stringOrNull(body.priceDisplay),
          verifiedAt: nowIso(),
        }),
      });
    } catch (error) {
      console.error("[apple-verify-purchase] transaction record failed", error);
      return failure(500, "Could not save subscription");
    }
    if (result.ok !== true) {
      return failure(
        typeof result.status === "number" ? result.status : 500,
        typeof result.error === "string" ? result.error : "Could not save subscription",
      );
    }

    return {
      status: 200,
      body: {
        ok: true,
        entitled: status === "active" || status === "grace",
        subscription: {
          status,
          productId: transactionInfo.productId,
          expiresAt: millisToIsoOrNull(transactionInfo.expiresDate),
          environment: toDatabaseEnvironment(transactionInfo.environment),
          originalTransactionId: transactionInfo.originalTransactionId,
          transactionId: transactionInfo.transactionId,
        },
      },
    };
  } catch (error) {
    console.error("[apple-verify-purchase]", error);
    return failure(500, clientSafeErrorMessage(error));
  }
}

async function runRedeemStreakRestore(ctx: ActionCtx, body: PurchaseBody): Promise<AppleResponse> {
  try {
    const step = await verifyUploadedTransaction(ctx, body);
    if ("response" in step) {
      return step.response;
    }
    const { userId, uploaded, verified } = step;
    const { transactionInfo } = verified;

    const validation = validateStreakRestore(transactionInfo, body);
    if (!validation.ok) {
      return failure(validation.status, validation.error);
    }

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
      console.error("[apple-redeem-streak-restore] restore record failed", error);
      return failure(500, "Could not restore your streak");
    }
    if (result.ok !== true) {
      return failure(
        typeof result.status === "number" ? result.status : 500,
        typeof result.error === "string" ? result.error : "Could not restore your streak",
      );
    }
    return {
      status: 200,
      body: { ok: true, entitled: false, restoredCount: typeof result.restoredCount === "number" ? result.restoredCount : null },
    };
  } catch (error) {
    console.error("[apple-redeem-streak-restore]", error);
    return failure(500, clientSafeErrorMessage(error));
  }
}

/**
 * Port of the apple-verify-purchase Edge Function. Arguments are its JSON body.
 * A failure becomes `http_<status>` with the body's error text.
 */
export const verify_purchase = action({
  args: purchaseBodyArgs,
  handler: async (ctx, args) => unwrapAppleResponse(await runVerifyPurchase(ctx, args)),
});

/** Port of the apple-redeem-streak-restore Edge Function. Same contract as `verify_purchase`. */
export const redeem_streak_restore = action({
  args: purchaseBodyArgs,
  handler: async (ctx, args) => unwrapAppleResponse(await runRedeemStreakRestore(ctx, args)),
});
