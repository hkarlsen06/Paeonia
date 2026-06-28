/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

import { corsHeaders } from "../_shared/cors.ts";
import {
  adminClient,
  APPLE_APP_BUNDLE_ID,
  type AppleRenewalInfo,
  type AppleTransactionInfo,
  assertAppleEnvironmentConfigured,
  clientSafeErrorMessage,
  decodeAppleJWS,
  getAuthenticatedUser,
  jsonResponse,
  millisToIsoOrNull,
  normalizeClientEnvironment,
  readJsonBody,
  requireString,
  stringOrNull,
  toDatabaseEnvironment,
  type VerifiedAppleTransaction,
  verifyTransactionWithApple,
} from "../_shared/appleStoreKit.ts";

type StoreKitStatus =
  | "active"
  | "grace"
  | "billing_retry"
  | "expired"
  | "revoked"
  | "refunded";

const ALLOWED_PRODUCTS = new Set([
  "no.paeonia.couple",
  "no.paeonia.couple.year",
]);

interface VerifyPurchaseRequest {
  jws?: unknown;
  transactionId?: unknown;
  originalTransactionId?: unknown;
  productId?: unknown;
  environment?: unknown;
  priceDisplay?: unknown;
}

interface RecordStoreKitTransactionResponse {
  ok?: boolean;
  error?: string;
  status?: number;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Method not allowed" });
  }

  try {
    assertAppleEnvironmentConfigured();

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(401, { ok: false, error: "Missing authorization" });
    }

    const user = await getAuthenticatedUser(authHeader);
    if (!user?.id) {
      return jsonResponse(401, { ok: false, error: "Invalid session" });
    }

    const body = await readJsonBody(request) as VerifyPurchaseRequest;
    const uploadedJws = requireString(body.jws, "jws");
    const uploadedTransactionInfo = decodeAppleJWS(
      uploadedJws,
    ) as Partial<AppleTransactionInfo>;
    const transactionId = stringOrNull(body.transactionId) ??
      uploadedTransactionInfo.transactionId;
    const requestedEnvironment = normalizeClientEnvironment(body.environment);

    if (!transactionId) {
      return jsonResponse(400, {
        ok: false,
        error: "Missing transactionId",
      });
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

    const validation = validateTransaction(
      verified.transactionInfo,
      verified.renewalInfo,
      uploadedTransactionInfo,
      body,
    );
    if (!validation.ok) {
      return jsonResponse(validation.status ?? 400, {
        ok: false,
        error: validation.error,
      });
    }

    const writeResult = await persistSubscription(
      user.id,
      verified,
      uploadedTransactionInfo,
      stringOrNull(body.priceDisplay),
    );
    if (!writeResult.ok) {
      return jsonResponse(writeResult.status ?? 500, {
        ok: false,
        error: writeResult.error,
      });
    }

    const status = determineSubscriptionStatus(
      verified.transactionInfo,
      verified.renewalInfo,
    );

    return jsonResponse(200, {
      ok: true,
      entitled: status === "active" || status === "grace",
      subscription: {
        status,
        productId: verified.transactionInfo.productId,
        expiresAt: millisToIsoOrNull(verified.transactionInfo.expiresDate),
        environment: toDatabaseEnvironment(
          verified.transactionInfo.environment,
        ),
        originalTransactionId: verified.transactionInfo.originalTransactionId,
        transactionId: verified.transactionInfo.transactionId,
      },
    });
  } catch (error) {
    console.error("[apple-verify-purchase]", error);
    return jsonResponse(500, {
      ok: false,
      error: clientSafeErrorMessage(error),
    });
  }
});

async function persistSubscription(
  userId: string,
  verified: VerifiedAppleTransaction,
  uploadedTransactionInfo: Partial<AppleTransactionInfo>,
  priceDisplay: string | null,
): Promise<{ ok: true } | { ok: false; error: string; status?: number }> {
  const transactionInfo = verified.transactionInfo;
  const environment = toDatabaseEnvironment(transactionInfo.environment);
  const status = determineSubscriptionStatus(
    transactionInfo,
    verified.renewalInfo,
  );
  const supabaseAdmin = adminClient();

  const { data, error } = await supabaseAdmin
    .rpc("record_verified_storekit_transaction", {
      p_user_id: userId,
      p_app_account_token: transactionInfo.appAccountToken ?? null,
      p_apple_product_id: transactionInfo.productId,
      p_environment: environment,
      p_original_transaction_id: transactionInfo.originalTransactionId,
      p_transaction_id: transactionInfo.transactionId,
      p_web_order_line_item_id: transactionInfo.webOrderLineItemId ?? null,
      p_status: status,
      p_purchased_at: millisToIsoOrNull(transactionInfo.purchaseDate),
      p_expires_at: millisToIsoOrNull(transactionInfo.expiresDate),
      p_revoked_at: millisToIsoOrNull(transactionInfo.revocationDate),
      p_revocation_reason: revocationReason(transactionInfo),
      p_signed_payload: verified.signedTransactionInfo,
      p_payload_json: {
        transactionInfo,
        renewalInfo: verified.renewalInfo ?? null,
        uploadedTransactionInfo,
        signedRenewalInfo: verified.signedRenewalInfo ?? null,
        priceDisplay,
        verifiedAt: new Date().toISOString(),
      },
    });

  if (error) {
    console.error("[apple-verify-purchase] transaction record failed", error);
    return { ok: false, error: "Could not save subscription" };
  }

  const result = data as RecordStoreKitTransactionResponse | null;
  if (result?.ok !== true) {
    return {
      ok: false,
      error: result?.error ?? "Could not save subscription",
      status: result?.status,
    };
  }

  return { ok: true };
}

function validateTransaction(
  transactionInfo: AppleTransactionInfo,
  renewalInfo: AppleRenewalInfo | undefined,
  uploadedTransactionInfo: Partial<AppleTransactionInfo>,
  requestBody: VerifyPurchaseRequest,
): { ok: true } | { ok: false; error: string; status?: number } {
  const comparedFields: Array<keyof AppleTransactionInfo> = [
    "transactionId",
    "originalTransactionId",
    "bundleId",
    "productId",
    "environment",
  ];

  for (const field of comparedFields) {
    const uploadedValue = uploadedTransactionInfo[field];
    if (
      uploadedValue !== undefined && uploadedValue !== transactionInfo[field]
    ) {
      return {
        ok: false,
        error: "Uploaded transaction does not match Apple verification",
        status: 400,
      };
    }
  }

  const requestedOriginalTransactionId = stringOrNull(
    requestBody.originalTransactionId,
  );
  if (
    requestedOriginalTransactionId &&
    requestedOriginalTransactionId !== transactionInfo.originalTransactionId
  ) {
    return {
      ok: false,
      error: "Original transaction does not match Apple verification",
      status: 400,
    };
  }

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

  if (!ALLOWED_PRODUCTS.has(transactionInfo.productId)) {
    return {
      ok: false,
      error: "Apple product is not supported",
      status: 400,
    };
  }

  if (transactionInfo.type !== "Auto-Renewable Subscription") {
    return {
      ok: false,
      error: "Apple transaction is not a subscription",
      status: 400,
    };
  }

  const status = determineSubscriptionStatus(
    transactionInfo,
    renewalInfo,
  );
  if (
    (status === "active" || status === "grace") && !transactionInfo.expiresDate
  ) {
    return {
      ok: false,
      error: "Apple subscription is missing an expiry date",
      status: 400,
    };
  }

  return { ok: true };
}

function determineSubscriptionStatus(
  transactionInfo: AppleTransactionInfo,
  renewalInfo?: AppleRenewalInfo,
): StoreKitStatus {
  const now = Date.now();

  if (transactionInfo.revocationDate) {
    return transactionInfo.revocationReason === 1 ? "refunded" : "revoked";
  }

  if (
    renewalInfo?.gracePeriodExpiresDate &&
    renewalInfo.gracePeriodExpiresDate > now
  ) {
    return "grace";
  }

  if (transactionInfo.expiresDate && transactionInfo.expiresDate > now) {
    return "active";
  }

  if (renewalInfo?.isInBillingRetryPeriod) {
    return "billing_retry";
  }

  return "expired";
}

function revocationReason(
  transactionInfo: AppleTransactionInfo,
): string | null {
  if (!transactionInfo.revocationDate) {
    return null;
  }

  if (transactionInfo.revocationReason === 1) {
    return "customer_refund";
  }

  if (transactionInfo.revocationReason === 0) {
    return "developer_revoked";
  }

  return transactionInfo.revocationReason === undefined
    ? "revoked"
    : `apple_revocation_${transactionInfo.revocationReason}`;
}
