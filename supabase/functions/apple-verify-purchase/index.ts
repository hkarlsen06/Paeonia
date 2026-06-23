/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

import { createClient } from "npm:@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";
import { corsHeaders } from "../_shared/cors.ts";

const APPLE_PRODUCTION_URL = "https://api.storekit.itunes.apple.com";
const APPLE_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";
const APPLE_API_TIMEOUT_MS = 15_000;
const APPLE_APP_BUNDLE_ID = Deno.env.get("APPLE_APP_BUNDLE_ID") ??
  "no.paeonia.app";
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID") ?? "";
const APPLE_ISSUER_ID = Deno.env.get("APPLE_ISSUER_ID") ?? "";
const APPLE_PRIVATE_KEY = Deno.env.get("APPLE_PRIVATE_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SECRET_KEY = readSupabaseKeyDictionary(
  "SUPABASE_SECRET_KEYS",
  Deno.env.get("SUPABASE_SECRET_KEY_NAME") ?? "default",
) ?? Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";
const SUPABASE_USER_KEY = readSupabaseKeyDictionary(
  "SUPABASE_PUBLISHABLE_KEYS",
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY_NAME") ?? "default",
) ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ??
  "";

const ALLOWED_PRODUCTS = new Set([
  "no.paeonia.couple",
  "no.paeonia.couple.year",
]);

type StoreKitEnvironment = "xcode" | "sandbox" | "production";
type AppleEnvironment = "Sandbox" | "Production";
type StoreKitStatus =
  | "active"
  | "grace"
  | "billing_retry"
  | "expired"
  | "revoked"
  | "refunded";

interface VerifyPurchaseRequest {
  jws?: unknown;
  transactionId?: unknown;
  originalTransactionId?: unknown;
  productId?: unknown;
  environment?: unknown;
  priceDisplay?: unknown;
}

interface AppleTransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  environment: AppleEnvironment;
  appAccountToken?: string;
  webOrderLineItemId?: string;
  type:
    | "Auto-Renewable Subscription"
    | "Non-Consumable"
    | "Consumable"
    | "Non-Renewing Subscription";
}

interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: number;
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

interface VerifiedAppleTransaction {
  signedTransactionInfo: string;
  signedRenewalInfo?: string;
  transactionInfo: AppleTransactionInfo;
  renewalInfo?: AppleRenewalInfo;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Method not allowed" });
  }

  try {
    assertEnvironmentConfigured();

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(401, { ok: false, error: "Missing authorization" });
    }

    const user = await getAuthenticatedUser(authHeader);
    if (!user?.id) {
      return jsonResponse(401, { ok: false, error: "Invalid session" });
    }

    const body = await readJsonBody(request);
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

    const ownership = await assertTransactionBelongsToUser(
      user.id,
      verified.transactionInfo,
    );
    if (!ownership.ok) {
      return jsonResponse(ownership.status ?? 403, {
        ok: false,
        error: ownership.error,
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
      error: error instanceof Error ? error.message : "Unexpected error",
    });
  }
});

function assertEnvironmentConfigured() {
  const missing: string[] = [];

  if (!SUPABASE_URL) missing.push("SUPABASE_URL");
  if (!SUPABASE_SECRET_KEY) {
    missing.push("SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY");
  }
  if (!SUPABASE_USER_KEY) {
    missing.push("SUPABASE_PUBLISHABLE_KEYS or SUPABASE_ANON_KEY");
  }
  if (!APPLE_KEY_ID) missing.push("APPLE_KEY_ID");
  if (!APPLE_ISSUER_ID) missing.push("APPLE_ISSUER_ID");
  if (!APPLE_PRIVATE_KEY) missing.push("APPLE_PRIVATE_KEY");

  if (missing.length > 0) {
    throw new Error(`Missing required environment: ${missing.join(", ")}`);
  }
}

async function getAuthenticatedUser(authHeader: string) {
  const userClient = createClient(SUPABASE_URL, SUPABASE_USER_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });

  const { data, error } = await userClient.auth.getUser();
  if (error) {
    console.warn("[apple-verify-purchase] auth.getUser failed", error.message);
    return null;
  }

  return data.user;
}

async function verifyTransactionWithApple(
  transactionId: string,
  preferredEnvironment: AppleEnvironment,
): Promise<VerifiedAppleTransaction> {
  const attempts: AppleEnvironment[] = preferredEnvironment === "Sandbox"
    ? ["Sandbox", "Production"]
    : ["Production", "Sandbox"];

  let lastError = "Apple transaction verification failed";

  for (const environment of attempts) {
    const result = await fetchAppleTransaction(transactionId, environment);
    if (result.ok) {
      return result.value;
    }

    lastError = result.error;
    if (result.status !== 404) {
      break;
    }
  }

  throw new Error(lastError);
}

async function fetchAppleTransaction(
  transactionId: string,
  environment: AppleEnvironment,
): Promise<
  | { ok: true; value: VerifiedAppleTransaction }
  | { ok: false; status: number; error: string }
> {
  const jwt = await generateAppleJWT();
  const baseUrl = environment === "Sandbox"
    ? APPLE_SANDBOX_URL
    : APPLE_PRODUCTION_URL;

  const transactionResponse = await fetchWithTimeout(
    `${baseUrl}/inApps/v1/transactions/${transactionId}`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!transactionResponse.ok) {
    return {
      ok: false,
      status: transactionResponse.status,
      error: await appleErrorMessage(transactionResponse),
    };
  }

  const transactionBody = await transactionResponse.json();
  const signedTransactionInfo = transactionBody.signedTransactionInfo;
  if (typeof signedTransactionInfo !== "string") {
    return {
      ok: false,
      status: 502,
      error: "Apple response did not include signed transaction info",
    };
  }

  const transactionInfo = decodeAppleJWS(
    signedTransactionInfo,
  ) as unknown as AppleTransactionInfo;
  let signedRenewalInfo: string | undefined;
  let renewalInfo: AppleRenewalInfo | undefined;

  if (transactionInfo.type === "Auto-Renewable Subscription") {
    const renewalResponse = await fetchWithTimeout(
      `${baseUrl}/inApps/v1/subscriptions/${transactionInfo.originalTransactionId}`,
      { headers: { Authorization: `Bearer ${jwt}` } },
    );

    if (renewalResponse.ok) {
      const renewalBody = await renewalResponse.json();
      const lastTransaction = renewalBody.data?.[0]?.lastTransactions?.[0];
      if (typeof lastTransaction?.signedRenewalInfo === "string") {
        const currentSignedRenewalInfo = lastTransaction.signedRenewalInfo;
        signedRenewalInfo = currentSignedRenewalInfo;
        renewalInfo = decodeAppleJWS(
          currentSignedRenewalInfo,
        ) as unknown as AppleRenewalInfo;
      }
    } else {
      console.warn(
        "[apple-verify-purchase] renewal lookup failed",
        renewalResponse.status,
        await safeResponseText(renewalResponse),
      );
    }
  }

  return {
    ok: true,
    value: {
      signedTransactionInfo,
      signedRenewalInfo,
      transactionInfo,
      renewalInfo,
    },
  };
}

async function generateAppleJWT(): Promise<string> {
  const keyPem = APPLE_PRIVATE_KEY.replace(/\\n/g, "\n");
  const privateKey = await jose.importPKCS8(keyPem, "ES256");

  return await new jose.SignJWT({
    bid: APPLE_APP_BUNDLE_ID,
    nonce: crypto.randomUUID(),
  })
    .setProtectedHeader({
      alg: "ES256",
      kid: APPLE_KEY_ID,
      typ: "JWT",
    })
    .setIssuer(APPLE_ISSUER_ID)
    .setAudience("appstoreconnect-v1")
    .setIssuedAt()
    .setExpirationTime("20m")
    .sign(privateKey);
}

async function assertTransactionBelongsToUser(
  userId: string,
  transactionInfo: AppleTransactionInfo,
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  const appAccountToken = transactionInfo.appAccountToken;
  if (!appAccountToken) {
    return {
      ok: false,
      error: "Apple transaction is missing appAccountToken",
      status: 403,
    };
  }

  const supabaseAdmin = adminClient();
  const { data, error } = await supabaseAdmin
    .schema("internal")
    .from("app_account_tokens")
    .select("user_id")
    .eq("token", appAccountToken)
    .maybeSingle();

  if (error) {
    console.error("[apple-verify-purchase] token lookup failed", error);
    return {
      ok: false,
      error: "Could not verify purchase owner",
      status: 500,
    };
  }

  if (!data?.user_id) {
    return {
      ok: false,
      error: "Apple appAccountToken is not registered",
      status: 403,
    };
  }

  if (data.user_id !== userId) {
    return {
      ok: false,
      error: "Apple transaction belongs to a different user",
      status: 403,
    };
  }

  return { ok: true };
}

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

  const { data: product, error: productError } = await supabaseAdmin
    .from("subscription_products")
    .select("id")
    .eq("apple_product_id", transactionInfo.productId)
    .eq("is_active", true)
    .maybeSingle();

  if (productError) {
    console.error(
      "[apple-verify-purchase] product lookup failed",
      productError,
    );
    return { ok: false, error: "Could not verify product" };
  }

  if (!product?.id) {
    return {
      ok: false,
      error: "Apple product is not active in Paeonia",
      status: 400,
    };
  }

  const { data: existing, error: existingError } = await supabaseAdmin
    .schema("internal")
    .from("storekit_transactions")
    .select("id, user_id")
    .eq("environment", environment)
    .eq("transaction_id", transactionInfo.transactionId)
    .maybeSingle();

  if (existingError) {
    console.error(
      "[apple-verify-purchase] existing transaction lookup failed",
      existingError,
    );
    return { ok: false, error: "Could not verify existing purchase" };
  }

  if (existing?.user_id && existing.user_id !== userId) {
    return {
      ok: false,
      error: "Apple transaction belongs to a different user",
      status: 403,
    };
  }

  const { data: payload, error: payloadError } = await supabaseAdmin
    .schema("internal")
    .from("storekit_payloads")
    .insert({
      payload_kind: "transaction",
      environment,
      original_transaction_id: transactionInfo.originalTransactionId,
      transaction_id: transactionInfo.transactionId,
      signed_payload: verified.signedTransactionInfo,
      payload_json: {
        transactionInfo,
        renewalInfo: verified.renewalInfo ?? null,
        uploadedTransactionInfo,
        signedRenewalInfo: verified.signedRenewalInfo ?? null,
        priceDisplay,
        verifiedAt: new Date().toISOString(),
      },
    })
    .select("id")
    .single();

  if (payloadError || !payload?.id) {
    console.error(
      "[apple-verify-purchase] payload insert failed",
      payloadError,
    );
    return { ok: false, error: "Could not save Apple verification" };
  }

  const { error: transactionError } = await supabaseAdmin
    .schema("internal")
    .from("storekit_transactions")
    .upsert({
      user_id: userId,
      product_id: product.id,
      environment,
      app_account_token: transactionInfo.appAccountToken ?? null,
      original_transaction_id: transactionInfo.originalTransactionId,
      transaction_id: transactionInfo.transactionId,
      web_order_line_item_id: transactionInfo.webOrderLineItemId ?? null,
      status,
      purchased_at: millisToIsoOrNull(transactionInfo.purchaseDate),
      expires_at: millisToIsoOrNull(transactionInfo.expiresDate),
      revoked_at: millisToIsoOrNull(transactionInfo.revocationDate),
      revocation_reason: revocationReason(transactionInfo),
      raw_payload_id: payload.id,
      last_reconciled_at: new Date().toISOString(),
    }, {
      onConflict: "environment,transaction_id",
    });

  if (transactionError) {
    console.error(
      "[apple-verify-purchase] transaction upsert failed",
      transactionError,
    );
    return { ok: false, error: "Could not save subscription" };
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

function normalizeClientEnvironment(value: unknown): StoreKitEnvironment {
  if (value === "production") return "production";
  if (value === "xcode") return "xcode";
  return "sandbox";
}

function toDatabaseEnvironment(
  environment: AppleEnvironment,
): StoreKitEnvironment {
  return environment === "Production" ? "production" : "sandbox";
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

function decodeAppleJWS(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid Apple JWS format");
  }

  const normalized = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(
    normalized.length + (4 - (normalized.length % 4)) % 4,
    "=",
  );
  return JSON.parse(atob(padded));
}

async function fetchWithTimeout(
  input: string | URL | Request,
  init: RequestInit = {},
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), APPLE_API_TIMEOUT_MS);

  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function appleErrorMessage(response: Response): Promise<string> {
  const body = await safeResponseText(response);
  return body
    ? `Apple verification failed (${response.status}): ${body}`
    : `Apple verification failed (${response.status})`;
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "";
  }
}

async function readJsonBody(request: Request): Promise<VerifyPurchaseRequest> {
  try {
    return await request.json();
  } catch {
    throw new Error("Request body must be JSON");
  }
}

function requireString(value: unknown, name: string): string {
  const stringValue = stringOrNull(value);
  if (!stringValue) {
    throw new Error(`Missing ${name}`);
  }

  return stringValue;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function millisToIsoOrNull(value: number | undefined): string | null {
  return typeof value === "number" ? new Date(value).toISOString() : null;
}

function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
    auth: { persistSession: false },
  });
}

function readSupabaseKeyDictionary(
  envName: string,
  keyName: string,
): string | null {
  const rawValue = Deno.env.get(envName);
  if (!rawValue) {
    return null;
  }

  try {
    const parsed = JSON.parse(rawValue) as Record<string, unknown>;
    const namedValue = parsed[keyName] ?? parsed.default ??
      Object.values(parsed)[0];
    return typeof namedValue === "string" && namedValue.length > 0
      ? namedValue
      : null;
  } catch {
    return null;
  }
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
