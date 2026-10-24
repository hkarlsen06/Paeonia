// App Store Server API primitives shared by access.ts (verify_purchase,
// redeem_streak_restore) and storekit.ts (server notifications). Uses only
// fetch and WebCrypto, so it runs in the default Convex runtime. Verifying
// Apple's signed notification payloads needs Node's X.509 support and lives
// in storekitNode.ts.
import { ConvexError } from "convex/values";
import { fail } from "./errors";

export const APPLE_PRODUCTION_URL = "https://api.storekit.itunes.apple.com";
export const APPLE_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";
export const APPLE_API_TIMEOUT_MS = 15_000;

export type AppleEnvironment = "Sandbox" | "Production";
export type StoreKitStatus = "active" | "grace" | "billing_retry" | "expired" | "revoked" | "refunded";

export interface AppleTransactionInfo {
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
  type?: "Auto-Renewable Subscription" | "Non-Consumable" | "Consumable" | "Non-Renewing Subscription";
}

export interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: number;
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

export interface VerifiedAppleTransaction {
  signedTransactionInfo: string;
  signedRenewalInfo?: string;
  transactionInfo: AppleTransactionInfo;
  renewalInfo?: AppleRenewalInfo;
}

export class PurchaseVerifierConfigurationError extends Error {
  override name = "PurchaseVerifierConfigurationError";
}

/** An error whose message is safe to return to the app. `code` is the `ConvexError` code the purchase actions use. */
export class ClientFacingError extends Error {
  override name = "ClientFacingError";
  readonly code: string;
  constructor(message: string, code = "invalid_request") {
    super(message);
    this.code = code;
  }
}

/** Bundle id of the app. */
export function appleBundleId(): string {
  return process.env.APPLE_BUNDLE_ID || "no.paeonia.app";
}

export function assertAppleEnvironmentConfigured(): void {
  const missing: string[] = [];
  if (!process.env.APPLE_IAP_KEY_ID) missing.push("APPLE_IAP_KEY_ID");
  if (!process.env.APPLE_IAP_ISSUER_ID) missing.push("APPLE_IAP_ISSUER_ID");
  if (!process.env.APPLE_IAP_PRIVATE_KEY) missing.push("APPLE_IAP_PRIVATE_KEY");
  if (missing.length > 0) {
    throw new PurchaseVerifierConfigurationError(`Missing required environment: ${missing.join(", ")}`);
  }
}

/**
 * Turns an error from a purchase action into a `ConvexError` whose text is safe to show the app.
 * Errors thrown with `fail` pass through. `name` labels the log line for anything else.
 */
export function failWithClientSafeError(name: string, error: unknown): never {
  if (error instanceof ConvexError) {
    throw error;
  }
  console.error(`[${name}]`, error);
  if (error instanceof PurchaseVerifierConfigurationError) {
    return fail("service_not_ready", "Purchase verification is not ready yet.");
  }
  if (error instanceof ClientFacingError) {
    return fail(error.code, error.message);
  }
  return fail("unexpected", "Unexpected error");
}

export function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

export function requireString(value: unknown, name: string): string {
  const stringValue = stringOrNull(value);
  if (!stringValue) {
    throw new ClientFacingError(`Missing ${name}`);
  }
  return stringValue;
}

export function millisToIsoOrNull(value: number | undefined | null): string | null {
  return typeof value === "number" ? new Date(value).toISOString() : null;
}

export function toDatabaseEnvironment(environment: AppleEnvironment | undefined): "sandbox" | "production" {
  return environment === "Production" ? "production" : "sandbox";
}

/** Reads the payload of a JWS without verifying it. Callers either fetched it from Apple over TLS or verified it first. */
export function decodeAppleJWS(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new ClientFacingError("Invalid Apple JWS format");
  }
  try {
    return JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1]))) as Record<string, unknown>;
  } catch {
    throw new ClientFacingError("Invalid Apple JWS format");
  }
}

function base64UrlDecode(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function base64UrlEncode(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Signs the ES256 JWT the App Store Server API expects. WebCrypto's ECDSA output is the raw r||s form JWS needs. */
export async function generateAppleJWT(): Promise<string> {
  const pem = (process.env.APPLE_IAP_PRIVATE_KEY ?? "").replace(/\\n/g, "\n");
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    base64UrlDecode(body) as BufferSource,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(
    JSON.stringify({ alg: "ES256", kid: process.env.APPLE_IAP_KEY_ID, typ: "JWT" }),
  );
  const payload = base64UrlEncode(
    JSON.stringify({
      bid: appleBundleId(),
      nonce: crypto.randomUUID(),
      iss: process.env.APPLE_IAP_ISSUER_ID,
      aud: "appstoreconnect-v1",
      iat: issuedAt,
      exp: issuedAt + 20 * 60,
    }),
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function fetchWithTimeout(input: string, init: RequestInit = {}): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), APPLE_API_TIMEOUT_MS);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "";
  }
}

async function appleErrorMessage(response: Response): Promise<string> {
  const body = await safeResponseText(response);
  return body
    ? `Apple verification failed (${response.status}): ${body}`
    : `Apple verification failed (${response.status})`;
}

type FetchResult =
  | { ok: true; value: VerifiedAppleTransaction }
  | { ok: false; status: number; error: string };

async function fetchAppleTransaction(transactionId: string, environment: AppleEnvironment): Promise<FetchResult> {
  const jwt = await generateAppleJWT();
  const baseUrl = environment === "Sandbox" ? APPLE_SANDBOX_URL : APPLE_PRODUCTION_URL;
  const headers = { Authorization: `Bearer ${jwt}` };

  const transactionResponse = await fetchWithTimeout(
    `${baseUrl}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
    { headers },
  );
  if (!transactionResponse.ok) {
    return { ok: false, status: transactionResponse.status, error: await appleErrorMessage(transactionResponse) };
  }

  const transactionBody = await transactionResponse.json();
  const signedTransactionInfo = transactionBody.signedTransactionInfo;
  if (typeof signedTransactionInfo !== "string") {
    return { ok: false, status: 502, error: "Apple response did not include signed transaction info" };
  }

  const transactionInfo = decodeAppleJWS(signedTransactionInfo) as unknown as AppleTransactionInfo;
  let signedRenewalInfo: string | undefined;
  let renewalInfo: AppleRenewalInfo | undefined;

  if (transactionInfo.type === "Auto-Renewable Subscription") {
    const renewalResponse = await fetchWithTimeout(
      `${baseUrl}/inApps/v1/subscriptions/${encodeURIComponent(transactionInfo.originalTransactionId)}`,
      { headers },
    );
    if (renewalResponse.ok) {
      const renewalBody = await renewalResponse.json();
      const lastTransaction = renewalBody.data?.[0]?.lastTransactions?.[0];
      if (typeof lastTransaction?.signedRenewalInfo === "string") {
        signedRenewalInfo = lastTransaction.signedRenewalInfo;
        renewalInfo = decodeAppleJWS(lastTransaction.signedRenewalInfo) as unknown as AppleRenewalInfo;
      }
    } else {
      console.warn("[appleStoreKit] renewal lookup failed", renewalResponse.status, await safeResponseText(renewalResponse));
    }
  }

  return { ok: true, value: { signedTransactionInfo, signedRenewalInfo, transactionInfo, renewalInfo } };
}

/** Looks the transaction up with Apple, trying the preferred environment first and the other on a 404. */
export async function verifyTransactionWithApple(
  transactionId: string,
  preferredEnvironment: AppleEnvironment,
): Promise<VerifiedAppleTransaction> {
  const attempts: AppleEnvironment[] =
    preferredEnvironment === "Sandbox" ? ["Sandbox", "Production"] : ["Production", "Sandbox"];
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

  // Apple's error bodies can include request detail clients should not see.
  console.error("[appleStoreKit] transaction verification failed", lastError);
  throw new ClientFacingError("Apple could not verify this purchase", "apple_verification_failed");
}

/**
 * Subscription status from the transaction and renewal info, and when its access ends.
 * `notificationType` REFUND and REVOKE win. During billing grace the transaction's
 * `expiresDate` has already passed, and access runs until the grace period ends.
 */
export function determineSubscription(
  transactionInfo: AppleTransactionInfo,
  renewalInfo?: AppleRenewalInfo | null,
  notificationType?: string,
  now: number = Date.now(),
): { status: StoreKitStatus; expiresAt: number | undefined } {
  const atTransactionExpiry = (status: StoreKitStatus) => ({ status, expiresAt: transactionInfo.expiresDate });
  if (notificationType === "REFUND") return atTransactionExpiry("refunded");
  if (notificationType === "REVOKE") return atTransactionExpiry("revoked");
  if (transactionInfo.revocationDate) {
    return atTransactionExpiry(transactionInfo.revocationReason === 1 ? "refunded" : "revoked");
  }
  if (renewalInfo?.gracePeriodExpiresDate && renewalInfo.gracePeriodExpiresDate > now) {
    return { status: "grace", expiresAt: renewalInfo.gracePeriodExpiresDate };
  }
  if (transactionInfo.expiresDate && transactionInfo.expiresDate > now) {
    return atTransactionExpiry("active");
  }
  if (renewalInfo?.isInBillingRetryPeriod) {
    return atTransactionExpiry("billing_retry");
  }
  return atTransactionExpiry("expired");
}

export function revocationReason(transactionInfo: AppleTransactionInfo): string | null {
  if (!transactionInfo.revocationDate) return null;
  if (transactionInfo.revocationReason === 1) return "customer_refund";
  if (transactionInfo.revocationReason === 0) return "developer_revoked";
  return transactionInfo.revocationReason === undefined
    ? "revoked"
    : `apple_revocation_${transactionInfo.revocationReason}`;
}
