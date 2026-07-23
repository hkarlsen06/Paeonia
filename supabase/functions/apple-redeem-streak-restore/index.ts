/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// Verifies a streak-restore consumable purchase with Apple and, if valid,
// restores the couple's shared streak. Mirrors apple-verify-purchase, but the
// product is a Consumable and the outcome is a streak restore (not an
// entitlement). @supabase/server authenticates the user inside the function.

import { type SupabaseContext, withSupabase } from "npm:@supabase/server@1.4.1";
import {
  APPLE_APP_BUNDLE_ID,
  type AppleTransactionInfo,
  assertAppleEnvironmentConfigured,
  clientSafeErrorMessage,
  decodeAppleJWS,
  jsonResponse,
  millisToIsoOrNull,
  normalizeClientEnvironment,
  readJsonBody,
  requireString,
  stringOrNull,
  toDatabaseEnvironment,
  verifyTransactionWithApple,
} from "../_shared/appleStoreKit.ts";

const STREAK_RESTORE_PRODUCT_ID = "no.paeonia.streak.restore";

interface RedeemStreakRestoreRequest {
  jws?: unknown;
  transactionId?: unknown;
  originalTransactionId?: unknown;
  productId?: unknown;
  environment?: unknown;
}

interface RecordStreakRestoreResponse {
  ok?: boolean;
  error?: string;
  status?: number;
  restoredCount?: number;
}

// Generated database types are not part of the Edge Function bundle yet.
// deno-lint-ignore no-explicit-any
type EdgeDatabase = any;
type AdminClient = SupabaseContext<EdgeDatabase>["supabaseAdmin"];

Deno.serve(withSupabase<EdgeDatabase>({ auth: "user" }, handleRequest));

async function handleRequest(
  request: Request,
  context: SupabaseContext<EdgeDatabase>,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Method not allowed" });
  }

  try {
    assertAppleEnvironmentConfigured();

    const { data: userData, error: userError } = await context.supabase.auth
      .getUser();
    if (userError || !userData.user?.id) {
      return jsonResponse(401, { ok: false, error: "Invalid session" });
    }

    const body = await readJsonBody(request) as RedeemStreakRestoreRequest;
    const uploadedJws = requireString(body.jws, "jws");
    const uploadedTransactionInfo = decodeAppleJWS(
      uploadedJws,
    ) as Partial<AppleTransactionInfo>;
    const transactionId = stringOrNull(body.transactionId) ??
      uploadedTransactionInfo.transactionId;
    const requestedEnvironment = normalizeClientEnvironment(body.environment);

    if (!transactionId) {
      return jsonResponse(400, { ok: false, error: "Missing transactionId" });
    }

    if (requestedEnvironment === "xcode") {
      return jsonResponse(400, {
        ok: false,
        error: "Local StoreKit transactions cannot be verified by Apple",
      });
    }

    const verified = await verifyTransactionWithApple(
      transactionId,
      requestedEnvironment === "sandbox" ? "Sandbox" : "Production",
    );
    const transactionInfo = verified.transactionInfo;

    const validation = validateStreakRestore(transactionInfo, body);
    if (!validation.ok) {
      return jsonResponse(validation.status ?? 400, {
        ok: false,
        error: validation.error,
      });
    }

    const result = await applyRestore(
      userData.user.id,
      context.supabaseAdmin,
      verified.signedTransactionInfo,
      {
        transactionInfo,
        uploadedTransactionInfo,
      },
    );
    if (!result.ok) {
      return jsonResponse(result.status ?? 500, {
        ok: false,
        error: result.error,
      });
    }

    return jsonResponse(200, {
      ok: true,
      entitled: false,
      restoredCount: result.restoredCount ?? null,
    });
  } catch (error) {
    console.error("[apple-redeem-streak-restore]", error);
    return jsonResponse(500, {
      ok: false,
      error: clientSafeErrorMessage(error),
    });
  }
}

function validateStreakRestore(
  transactionInfo: AppleTransactionInfo,
  requestBody: RedeemStreakRestoreRequest,
): { ok: true } | { ok: false; error: string; status?: number } {
  const requestedProductId = stringOrNull(requestBody.productId);
  if (requestedProductId && requestedProductId !== transactionInfo.productId) {
    return {
      ok: false,
      error: "Product does not match Apple verification",
      status: 400,
    };
  }

  if (transactionInfo.bundleId !== APPLE_APP_BUNDLE_ID) {
    return {
      ok: false,
      error: "Apple transaction bundle does not match Paeonia",
      status: 403,
    };
  }

  if (transactionInfo.productId !== STREAK_RESTORE_PRODUCT_ID) {
    return {
      ok: false,
      error: "Apple product is not supported",
      status: 400,
    };
  }

  if (transactionInfo.type !== "Consumable") {
    return {
      ok: false,
      error: "Apple transaction is not a streak restore",
      status: 400,
    };
  }

  if (!transactionInfo.appAccountToken) {
    return {
      ok: false,
      error: "Apple transaction is missing appAccountToken",
      status: 403,
    };
  }

  return { ok: true };
}

async function applyRestore(
  userId: string,
  supabaseAdmin: AdminClient,
  signedTransactionInfo: string,
  payload: {
    transactionInfo: AppleTransactionInfo;
    uploadedTransactionInfo: Partial<AppleTransactionInfo>;
  },
): Promise<
  | { ok: true; restoredCount?: number }
  | { ok: false; error: string; status?: number }
> {
  const transactionInfo = payload.transactionInfo;
  const { data, error } = await supabaseAdmin
    .rpc("record_verified_streak_restore", {
      p_user_id: userId,
      p_app_account_token: transactionInfo.appAccountToken ?? null,
      p_apple_product_id: transactionInfo.productId,
      p_environment: toDatabaseEnvironment(transactionInfo.environment),
      p_original_transaction_id: transactionInfo.originalTransactionId,
      p_transaction_id: transactionInfo.transactionId,
      p_purchased_at: millisToIsoOrNull(transactionInfo.purchaseDate),
      p_signed_payload: signedTransactionInfo,
      p_payload_json: {
        transactionInfo,
        uploadedTransactionInfo: payload.uploadedTransactionInfo,
        verifiedAt: new Date().toISOString(),
      },
    });

  if (error) {
    console.error("[apple-redeem-streak-restore] restore record failed", error);
    return { ok: false, error: "Could not restore your streak" };
  }

  const result = data as RecordStreakRestoreResponse | null;
  if (result?.ok !== true) {
    return {
      ok: false,
      error: result?.error ?? "Could not restore your streak",
      status: result?.status,
    };
  }

  return { ok: true, restoredCount: result.restoredCount };
}
