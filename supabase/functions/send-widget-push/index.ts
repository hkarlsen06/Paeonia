/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// Drains pending notification outbox rows and delivers APNs pushes: silent
// ('content-available') refreshes that wake the app to sync, and visible widget
// alerts. Safe to call repeatedly because rows are claimed atomically in
// Postgres.
//
// APNs environment handling mirrors Tidex: a device token is valid on exactly
// one host, so the device's stored environment is tried first and the other is
// tried on BadDeviceToken, then the confirmed environment is written back so
// later sends skip the fallback. A single token-based .p8 key works for both
// hosts; separate sandbox credentials are optional and fall back to production.

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
const DRAIN_SECRET = Deno.env.get("DRAIN_SECRET") ?? "";

// Production credentials (App Store builds).
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
// Sandbox credentials (debug/TestFlight builds). Optional: a token-based key
// works on both hosts, so these fall back to the production credentials.
const APNS_SANDBOX_KEY_ID = Deno.env.get("APNS_SANDBOX_KEY_ID") ?? "";
const APNS_SANDBOX_PRIVATE_KEY = Deno.env.get("APNS_SANDBOX_PRIVATE_KEY") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "no.paeonia.app";

const PROVIDER_TOKEN_MAX_AGE_SECONDS = 2400; // refresh well under APNs' 60 min cap

type ApnsEnvironment = "sandbox" | "production";

interface ClaimedNotification {
  outbox_id: string;
  target_device_id: string;
  push_token: string;
  apns_environment: ApnsEnvironment;
  apns_push_type: "alert" | "background";
  apns_collapse_id: string | null;
  title: string | null;
  body: string | null;
  payload: Record<string, unknown>;
}

interface ApnsSendResult {
  ok: boolean;
  providerMessageId?: string;
  environment?: ApnsEnvironment;
  invalidToken?: boolean;
  error?: string;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function pemToDer(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const buffer = new ArrayBuffer(binary.length);
  const der = new Uint8Array(buffer);
  for (let index = 0; index < binary.length; index++) {
    der[index] = binary.charCodeAt(index);
  }
  return buffer;
}

// One cached provider JWT per environment; the same key may back both.
const cachedTokens: Record<ApnsEnvironment, { jwt: string; issuedAt: number } | null> = {
  sandbox: null,
  production: null,
};

async function apnsProviderToken(environment: ApnsEnvironment): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const cached = cachedTokens[environment];
  if (cached && now - cached.issuedAt < PROVIDER_TOKEN_MAX_AGE_SECONDS) {
    return cached.jwt;
  }

  const sandbox = environment === "sandbox";
  const keyId = sandbox ? (APNS_SANDBOX_KEY_ID || APNS_KEY_ID) : APNS_KEY_ID;
  const privateKey = sandbox
    ? (APNS_SANDBOX_PRIVATE_KEY || APNS_PRIVATE_KEY)
    : APNS_PRIVATE_KEY;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = base64url(new TextEncoder().encode(
    JSON.stringify({ alg: "ES256", kid: keyId }),
  ));
  const claims = base64url(new TextEncoder().encode(
    JSON.stringify({ iss: APNS_TEAM_ID, iat: now }),
  ));
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${base64url(new Uint8Array(signature))}`;
  cachedTokens[environment] = { jwt, issuedAt: now };
  return jwt;
}

// Preferred environment first, the other as fallback (mixed App Store +
// TestFlight/debug installs).
function environmentOrder(preferred: ApnsEnvironment): ApnsEnvironment[] {
  return preferred === "sandbox"
    ? ["sandbox", "production"]
    : ["production", "sandbox"];
}

// Background rows wake the app to sync (no user-visible alert); alert rows show
// the localized lock-screen banner. Title/body are pre-localized in Postgres.
function buildApsPayload(
  notification: ClaimedNotification,
): Record<string, unknown> {
  if (notification.apns_push_type === "background") {
    return { aps: { "content-available": 1 } };
  }

  const alert: Record<string, string> = { body: notification.body ?? "" };
  if (notification.title) {
    alert.title = notification.title;
  }
  // `mutable-content` lets the Notification Service Extension upgrade this into a
  // communication notification (partner avatar + name). `content-available` also
  // wakes the app to sync the widget on delivery, so the alert landing refreshes
  // the widget even if the separate silent push was throttled. The outbox payload
  // (type, route, canvas_id, sender_user_id) and the sender name are spread
  // top-level so they reach `userInfo` for both the extension and tap routing.
  return {
    aps: { alert, sound: "default", "mutable-content": 1, "content-available": 1 },
    ...notification.payload,
    sender_name: notification.title ?? undefined,
  };
}

async function sendToApns(
  notification: ClaimedNotification,
): Promise<ApnsSendResult> {
  const body = JSON.stringify(buildApsPayload(notification));
  const order = environmentOrder(notification.apns_environment);
  let lastError = "no delivery attempt";

  for (let index = 0; index < order.length; index++) {
    const environment = order[index];
    const isLastAttempt = index === order.length - 1;
    const host = environment === "production"
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";

    let jwt: string;
    try {
      jwt = await apnsProviderToken(environment);
    } catch (error) {
      lastError = `provider token: ${errorMessage(error)}`;
      continue;
    }

    const headers: Record<string, string> = {
      authorization: `bearer ${jwt}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": notification.apns_push_type,
      "apns-priority": notification.apns_push_type === "background" ? "5" : "10",
      "content-type": "application/json",
    };
    if (notification.apns_collapse_id) {
      headers["apns-collapse-id"] = notification.apns_collapse_id;
    }

    const response = await fetch(
      `https://${host}/3/device/${notification.push_token}`,
      { method: "POST", headers, body },
    );

    if (response.status === 200) {
      return {
        ok: true,
        providerMessageId: response.headers.get("apns-id") ?? undefined,
        environment,
      };
    }

    let reason = `status ${response.status}`;
    try {
      const json = await response.json();
      if (json?.reason) reason = String(json.reason);
    } catch {
      // Keep status-based reason.
    }
    lastError = reason;

    // The token is valid on exactly one host. BadDeviceToken means the stored
    // environment was wrong, so try the other before giving up.
    if (response.status === 400 && reason === "BadDeviceToken" && !isLastAttempt) {
      continue;
    }

    // 410 Unregistered, or BadDeviceToken on the final host, means the token is
    // dead on every environment.
    if (
      response.status === 410 ||
      (response.status === 400 && reason === "BadDeviceToken")
    ) {
      return { ok: false, error: reason, invalidToken: true, environment };
    }

    // Any other failure (rate limit, transient server error, payload issue) is
    // not an environment mismatch; let the claim lease retry it later.
    return { ok: false, error: reason, environment };
  }

  return { ok: false, error: lastError };
}

// Writes the confirmed environment back so later sends skip the fallback.
async function persistDeviceEnvironment(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  deviceId: string,
  environment: ApnsEnvironment,
): Promise<void> {
  const { error } = await supabase
    .from("user_devices")
    .update({ apns_environment: environment })
    .eq("id", deviceId);
  if (error) {
    console.error("Unable to persist confirmed APNs environment", {
      deviceId,
      error: error.message,
    });
  }
}

// Retires a device whose token APNs rejected on every environment, so future
// notifications skip it (enqueue filters disabled devices).
async function disableDevice(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  deviceId: string,
): Promise<void> {
  const { error } = await supabase
    .from("user_devices")
    .update({ disabled_at: new Date().toISOString() })
    .eq("id", deviceId)
    .is("disabled_at", null);
  if (error) {
    console.error("Unable to disable device with invalid token", {
      deviceId,
      error: error.message,
    });
  }
}

Deno.serve(async (request) => {
  if (!DRAIN_SECRET || request.headers.get("x-drain-secret") !== DRAIN_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  if (
    !SUPABASE_URL || !SERVICE_KEY || !APNS_KEY_ID || !APNS_TEAM_ID ||
    !APNS_PRIVATE_KEY
  ) {
    return new Response("push delivery is not configured", { status: 500 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data, error } = await supabase.rpc("claim_notification_batch", {
    p_limit: 100,
  });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
    });
  }

  const batch = (data ?? []) as ClaimedNotification[];
  let sent = 0;
  let failed = 0;

  for (const notification of batch) {
    let result: ApnsSendResult;
    try {
      result = await sendToApns(notification);
    } catch (error) {
      result = { ok: false, error: errorMessage(error) };
    }

    if (
      result.ok && result.environment &&
      result.environment !== notification.apns_environment
    ) {
      await persistDeviceEnvironment(
        supabase,
        notification.target_device_id,
        result.environment,
      );
    }

    if (result.invalidToken) {
      await disableDevice(supabase, notification.target_device_id);
    }

    const { error: markError } = await supabase.rpc(
      "mark_notification_result",
      {
        p_outbox_id: notification.outbox_id,
        p_success: result.ok,
        p_provider_message_id: result.providerMessageId ?? null,
        p_error: result.error ?? null,
        p_invalid_token: result.invalidToken ?? false,
      },
    );

    if (markError) {
      console.error("Unable to record notification result", {
        outbox_id: notification.outbox_id,
        error: markError.message,
      });
      failed++;
      continue;
    }

    if (result.ok) sent++;
    else failed++;
  }

  return new Response(
    JSON.stringify({ claimed: batch.length, sent, failed }),
    { headers: { "content-type": "application/json" } },
  );
});
