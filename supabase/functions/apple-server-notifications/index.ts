/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library";
import { type SupabaseContext, withSupabase } from "npm:@supabase/server@1.4.1";

const APPLE_ROOT_CA_G2_URL =
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer";
const APPLE_ROOT_CA_G3_URL =
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";
const APPLE_ROOT_CA_URLS = [APPLE_ROOT_CA_G2_URL, APPLE_ROOT_CA_G3_URL];
const EXTERNAL_FETCH_TIMEOUT_MS = 15_000;
const APPLE_APP_BUNDLE_ID = Deno.env.get("APPLE_APP_BUNDLE_ID") ??
  "no.paeonia.app";
const STREAK_RESTORE_PRODUCT_ID = "no.paeonia.streak.restore";
const APPLE_APP_APPLE_ID_RAW = Deno.env.get("APPLE_APP_APPLE_ID") ??
  Deno.env.get("APPLE_APP_ID") ??
  "";
const APPLE_APP_APPLE_ID = Number(APPLE_APP_APPLE_ID_RAW);
type AppleEnvironment = "Production" | "Sandbox";
type StoreKitEnvironment = "production" | "sandbox";
type StoreKitStatus =
  | "active"
  | "grace"
  | "billing_retry"
  | "expired"
  | "revoked"
  | "refunded";

interface AppleNotificationPayload {
  notificationType: string;
  subtype?: string | null;
  notificationUUID: string;
  data?: {
    appAppleId?: number;
    bundleId?: string;
    bundleVersion?: string;
    environment?: AppleEnvironment;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
  version?: string;
  signedDate?: number;
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
  offerType?: number;
  offerDiscountType?: string;
  type?: string;
}

interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: number;
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

interface AppleVerificationResult {
  notification: AppleNotificationPayload;
  verifier: SignedDataVerifier;
}

interface RecordStoreKitNotificationResponse {
  ok?: boolean;
  duplicate?: boolean;
  processed?: boolean;
  status?: number;
  error?: string;
}

let appleRootCertificatesPromise: Promise<Buffer[]> | null = null;
// Generated database types are not part of the Edge Function bundle yet.
// deno-lint-ignore no-explicit-any
type EdgeDatabase = any;
type AdminClient = SupabaseContext<EdgeDatabase>["supabaseAdmin"];

Deno.serve(withSupabase<EdgeDatabase>({ auth: "none" }, handleRequest));

async function handleRequest(
  request: Request,
  context: SupabaseContext<EdgeDatabase>,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Method not allowed" });
  }

  try {
    const body = await readJsonBody(request);
    const signedPayload = stringOrNull(body.signedPayload);
    if (!signedPayload) {
      return jsonResponse(400, {
        ok: false,
        error: "Missing signedPayload",
      });
    }
    const verification = await verifyAppleNotification(signedPayload);
    if (!verification) {
      return jsonResponse(400, {
        ok: false,
        error: "Invalid Apple notification",
      });
    }

    const { notification, verifier } = verification;
    const transactionInfo = await decodeSignedTransactionInfo(
      verifier,
      notification.data?.signedTransactionInfo,
    );
    const renewalInfo = await decodeSignedRenewalInfo(
      verifier,
      notification.data?.signedRenewalInfo,
    );

    // The streak-restore consumable lives outside the subscription tables, so
    // route its notifications to the restore ledger instead of the entitlement
    // path. Refunds are logged; the restored streak is intentionally kept.
    if (transactionInfo?.productId === STREAK_RESTORE_PRODUCT_ID) {
      const restoreResult = await persistStreakRestoreNotification(
        context.supabaseAdmin,
        notification,
        transactionInfo,
      );

      if (restoreResult.ok !== true && (restoreResult.status ?? 500) >= 500) {
        return jsonResponse(restoreResult.status ?? 500, {
          received: false,
          processed: false,
          error: restoreResult.error ??
            "Could not process Apple notification",
        });
      }

      return jsonResponse(200, {
        received: true,
        duplicate: false,
        processed: restoreResult.processed === true,
      });
    }

    const result = await persistNotification(
      context.supabaseAdmin,
      notification,
      transactionInfo,
      renewalInfo,
      signedPayload,
    );

    if (result.ok !== true && (result.status ?? 500) >= 500) {
      return jsonResponse(result.status ?? 500, {
        received: false,
        processed: false,
        error: result.error ?? "Could not process Apple notification",
      });
    }

    return jsonResponse(200, {
      received: true,
      duplicate: result.duplicate === true,
      processed: result.processed === true,
    });
  } catch (error) {
    console.error("[apple-server-notifications]", error);
    return jsonResponse(500, {
      received: false,
      processed: false,
      error: "Unexpected error",
    });
  }
}

async function verifyAppleNotification(
  signedPayload: string,
): Promise<AppleVerificationResult | null> {
  try {
    const rootCertificates = await appleRootCertificates();

    for (const verifier of appleVerifiers(rootCertificates, signedPayload)) {
      try {
        const notification = await verifier.verifyAndDecodeNotification(
          signedPayload,
        ) as AppleNotificationPayload;
        return { notification, verifier };
      } catch (error) {
        console.warn(
          "[apple-server-notifications] verification attempt failed",
          error instanceof Error ? error.message : error,
        );
      }
    }

    console.error(
      "[apple-server-notifications] signed payload verification failed",
    );
    return null;
  } catch (error) {
    console.error(
      "[apple-server-notifications] verification failed",
      error instanceof Error ? error.message : error,
    );
    return null;
  }
}

async function appleRootCertificates(): Promise<Buffer[]> {
  appleRootCertificatesPromise ??= Promise.all(
    APPLE_ROOT_CA_URLS.map(async (url) => {
      const response = await fetchWithTimeout(url);
      if (!response.ok) {
        throw new Error(`Failed to fetch Apple root certificate: ${url}`);
      }

      return Buffer.from(await response.arrayBuffer());
    }),
  ).catch((error) => {
    appleRootCertificatesPromise = null;
    throw error;
  });

  return appleRootCertificatesPromise;
}

function appleVerifiers(
  rootCertificates: Buffer[],
  signedPayload: string,
): SignedDataVerifier[] {
  const environment = appleNotificationEnvironmentHint(signedPayload);
  if (environment === "Sandbox") {
    return [
      new SignedDataVerifier(
        rootCertificates,
        false,
        Environment.SANDBOX,
        APPLE_APP_BUNDLE_ID,
      ),
    ];
  }

  if (environment === "Production") {
    return [
      new SignedDataVerifier(
        rootCertificates,
        false,
        Environment.PRODUCTION,
        APPLE_APP_BUNDLE_ID,
        productionAppleAppId(),
      ),
    ];
  }

  const verifiers = [
    new SignedDataVerifier(
      rootCertificates,
      false,
      Environment.SANDBOX,
      APPLE_APP_BUNDLE_ID,
    ),
  ];

  if (APPLE_APP_APPLE_ID_RAW) {
    verifiers.unshift(
      new SignedDataVerifier(
        rootCertificates,
        false,
        Environment.PRODUCTION,
        APPLE_APP_BUNDLE_ID,
        productionAppleAppId(),
      ),
    );
  }

  return verifiers;
}

function productionAppleAppId(): number {
  if (!Number.isFinite(APPLE_APP_APPLE_ID) || APPLE_APP_APPLE_ID <= 0) {
    throw new Error(
      "APPLE_APP_APPLE_ID or APPLE_APP_ID must be set for Production Apple notifications",
    );
  }

  return APPLE_APP_APPLE_ID;
}

function appleNotificationEnvironmentHint(
  signedPayload: string,
): AppleEnvironment | null {
  const payload = decodeAppleJWS(signedPayload);
  const environment = payload?.data?.environment ??
    payload?.summary?.environment ??
    payload?.appData?.environment;

  return environment === "Production" || environment === "Sandbox"
    ? environment
    : null;
}

async function decodeSignedTransactionInfo(
  verifier: SignedDataVerifier,
  signedTransactionInfo: string | undefined,
): Promise<AppleTransactionInfo | null> {
  if (!signedTransactionInfo) {
    return null;
  }

  try {
    return await verifier.verifyAndDecodeTransaction(
      signedTransactionInfo,
    ) as AppleTransactionInfo;
  } catch (error) {
    console.error(
      "[apple-server-notifications] transaction decode failed",
      error instanceof Error ? error.message : error,
    );
    return null;
  }
}

async function decodeSignedRenewalInfo(
  verifier: SignedDataVerifier,
  signedRenewalInfo: string | undefined,
): Promise<AppleRenewalInfo | null> {
  if (!signedRenewalInfo) {
    return null;
  }

  try {
    return await verifier.verifyAndDecodeRenewalInfo(
      signedRenewalInfo,
    ) as AppleRenewalInfo;
  } catch (error) {
    console.error(
      "[apple-server-notifications] renewal decode failed",
      error instanceof Error ? error.message : error,
    );
    return null;
  }
}

async function persistStreakRestoreNotification(
  supabaseAdmin: AdminClient,
  notification: AppleNotificationPayload,
  transactionInfo: AppleTransactionInfo,
): Promise<RecordStoreKitNotificationResponse> {
  const notificationType = requireString(
    notification.notificationType,
    "notificationType",
  );

  // Only refund/revoke matters for a consumable; everything else is a no-op ack.
  if (notificationType !== "REFUND" && notificationType !== "REVOKE") {
    return { ok: true, processed: false };
  }

  const { error } = await supabaseAdmin
    .rpc("mark_streak_restore_refunded", {
      p_environment: toDatabaseEnvironment(transactionInfo.environment),
      p_transaction_id: transactionInfo.transactionId,
    });

  if (error) {
    console.error(
      "[apple-server-notifications] streak restore refund failed",
      error,
    );
    return {
      ok: false,
      status: 500,
      error: "Could not record streak restore refund",
    };
  }

  return { ok: true, processed: true };
}

async function persistNotification(
  supabaseAdmin: AdminClient,
  notification: AppleNotificationPayload,
  transactionInfo: AppleTransactionInfo | null,
  renewalInfo: AppleRenewalInfo | null,
  signedPayload: string,
): Promise<RecordStoreKitNotificationResponse> {
  const notificationType = requireString(
    notification.notificationType,
    "notificationType",
  );
  const environment = toDatabaseEnvironment(
    transactionInfo?.environment ?? notification.data?.environment,
  );
  const status = transactionInfo
    ? determineSubscriptionStatus(
      notificationType,
      transactionInfo,
      renewalInfo,
    )
    : null;
  const revocation = transactionInfo
    ? revocationState(notificationType, transactionInfo)
    : { revokedAt: null, reason: null };

  const { data, error } = await supabaseAdmin
    .rpc("record_storekit_server_notification", {
      p_notification_uuid: requireString(
        notification.notificationUUID,
        "notificationUUID",
      ),
      p_notification_type: notificationType,
      p_subtype: stringOrNull(notification.subtype),
      p_environment: environment,
      p_original_transaction_id: transactionInfo?.originalTransactionId ?? null,
      p_transaction_id: transactionInfo?.transactionId ?? null,
      p_app_account_token: uuidOrNull(transactionInfo?.appAccountToken),
      p_apple_product_id: transactionInfo?.productId ?? null,
      p_web_order_line_item_id: transactionInfo?.webOrderLineItemId ?? null,
      p_status: status,
      p_purchased_at: millisToIsoOrNull(transactionInfo?.purchaseDate),
      p_expires_at: millisToIsoOrNull(transactionInfo?.expiresDate),
      p_revoked_at: revocation.revokedAt,
      p_revocation_reason: revocation.reason,
      p_signed_notification_payload: signedPayload,
      p_signed_transaction_info: notification.data?.signedTransactionInfo ??
        null,
      p_payload_json: {
        notification,
        transactionInfo,
        renewalInfo,
        signedRenewalInfo: notification.data?.signedRenewalInfo ?? null,
        processedAt: new Date().toISOString(),
      },
    });

  if (error) {
    console.error("[apple-server-notifications] RPC failed", error);
    return {
      ok: false,
      status: 500,
      error: "Could not record Apple notification",
    };
  }

  return (data ??
    { ok: false, status: 500 }) as RecordStoreKitNotificationResponse;
}

function determineSubscriptionStatus(
  notificationType: string,
  transactionInfo: AppleTransactionInfo,
  renewalInfo?: AppleRenewalInfo | null,
): StoreKitStatus {
  const now = Date.now();

  if (notificationType === "REFUND") {
    return "refunded";
  }

  if (notificationType === "REVOKE") {
    return "revoked";
  }

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

function revocationState(
  notificationType: string,
  transactionInfo: AppleTransactionInfo,
): { revokedAt: string | null; reason: string | null } {
  if (transactionInfo.revocationDate) {
    return {
      revokedAt: millisToIsoOrNull(transactionInfo.revocationDate),
      reason: revocationReason(transactionInfo),
    };
  }

  if (notificationType === "REFUND") {
    return {
      revokedAt: new Date().toISOString(),
      reason: "customer_refund",
    };
  }

  if (notificationType === "REVOKE") {
    return {
      revokedAt: new Date().toISOString(),
      reason: "developer_revoked",
    };
  }

  return { revokedAt: null, reason: null };
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

function toDatabaseEnvironment(
  environment: AppleEnvironment | undefined,
): StoreKitEnvironment {
  return environment === "Production" ? "production" : "sandbox";
}

function decodeAppleJWS(jws: string): Record<string, any> | null {
  try {
    const parts = jws.split(".");
    if (parts.length !== 3) {
      return null;
    }

    const normalized = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(
      normalized.length + (4 - (normalized.length % 4)) % 4,
      "=",
    );
    return JSON.parse(atob(padded));
  } catch {
    return null;
  }
}

async function fetchWithTimeout(
  input: string | URL | Request,
  init: RequestInit = {},
  timeoutMs = EXTERNAL_FETCH_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  const upstreamSignal = init.signal;
  const abortFromUpstream = () => controller.abort();

  if (upstreamSignal?.aborted) {
    controller.abort();
  } else {
    upstreamSignal?.addEventListener("abort", abortFromUpstream, {
      once: true,
    });
  }

  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
    upstreamSignal?.removeEventListener("abort", abortFromUpstream);
  }
}

async function readJsonBody(
  request: Request,
): Promise<Record<string, unknown>> {
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

function uuidOrNull(value: unknown): string | null {
  const stringValue = stringOrNull(value);
  if (
    stringValue &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(stringValue)
  ) {
    return stringValue;
  }

  return null;
}

function millisToIsoOrNull(value: number | undefined): string | null {
  return typeof value === "number" ? new Date(value).toISOString() : null;
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}
