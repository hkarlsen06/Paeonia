/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// Shared App Store Server API verification primitives, used by both
// apple-verify-purchase (subscriptions) and apple-redeem-streak-restore
// (the streak-restore consumable). Domain logic — what a verified transaction
// means for entitlements vs. streaks — stays in each function.

import { createClient } from "npm:@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";
import { corsHeaders } from "./cors.ts";

export const APPLE_PRODUCTION_URL = "https://api.storekit.itunes.apple.com";
export const APPLE_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";
export const APPLE_API_TIMEOUT_MS = 15_000;
export const APPLE_APP_BUNDLE_ID = Deno.env.get("APPLE_APP_BUNDLE_ID") ??
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

export { SUPABASE_SECRET_KEY, SUPABASE_URL, SUPABASE_USER_KEY };

export type StoreKitEnvironment = "xcode" | "sandbox" | "production";
export type AppleEnvironment = "Sandbox" | "Production";

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
  type:
    | "Auto-Renewable Subscription"
    | "Non-Consumable"
    | "Consumable"
    | "Non-Renewing Subscription";
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

export function assertAppleEnvironmentConfigured() {
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
    throw new PurchaseVerifierConfigurationError(
      `Missing required environment: ${missing.join(", ")}`,
    );
  }
}

export function clientSafeErrorMessage(error: unknown): string {
  if (error instanceof PurchaseVerifierConfigurationError) {
    return "Purchase verification is not ready yet.";
  }

  return error instanceof Error ? error.message : "Unexpected error";
}

export async function getAuthenticatedUser(authHeader: string) {
  const userClient = createClient(SUPABASE_URL, SUPABASE_USER_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });

  const { data, error } = await userClient.auth.getUser();
  if (error) {
    console.warn("[appleStoreKit] auth.getUser failed", error.message);
    return null;
  }

  return data.user;
}

export async function verifyTransactionWithApple(
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
        "[appleStoreKit] renewal lookup failed",
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

export function decodeAppleJWS(jws: string): Record<string, unknown> {
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

export async function readJsonBody(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    return await request.json();
  } catch {
    throw new Error("Request body must be JSON");
  }
}

export function requireString(value: unknown, name: string): string {
  const stringValue = stringOrNull(value);
  if (!stringValue) {
    throw new Error(`Missing ${name}`);
  }

  return stringValue;
}

export function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

export function millisToIsoOrNull(value: number | undefined): string | null {
  return typeof value === "number" ? new Date(value).toISOString() : null;
}

export function normalizeClientEnvironment(value: unknown): StoreKitEnvironment {
  if (value === "production") return "production";
  if (value === "xcode") return "xcode";
  return "sandbox";
}

export function toDatabaseEnvironment(
  environment: AppleEnvironment,
): StoreKitEnvironment {
  return environment === "Production" ? "production" : "sandbox";
}

export function adminClient() {
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

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
