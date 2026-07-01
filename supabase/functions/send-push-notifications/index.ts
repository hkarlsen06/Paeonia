/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// Drains pending push outbox rows and delivers APNs requests:
// * normal app pushes: alert/background tokens for notifications and fallback sync
// * WidgetKit pushes: widget push tokens, `widgets` push type, content-changed payload
//
// Safe to call repeatedly because rows are claimed atomically in Postgres.

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = readSupabaseKeyDictionary(
  "SUPABASE_SECRET_KEYS",
  Deno.env.get("SUPABASE_SECRET_KEY_NAME") ?? "default",
) ?? Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DRAIN_SECRET = Deno.env.get("DRAIN_SECRET") ?? "";

// Production credentials (App Store builds).
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
// Sandbox credentials (debug/TestFlight builds). Optional: token-based keys
// work on both hosts, so fall back to production credentials.
const APNS_SANDBOX_KEY_ID = Deno.env.get("APNS_SANDBOX_KEY_ID") ?? "";
const APNS_SANDBOX_PRIVATE_KEY = Deno.env.get("APNS_SANDBOX_PRIVATE_KEY") ??
  "";
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

interface ClaimedWidgetPush {
  outbox_id: string;
  target_widget_device_id: string;
  widget_push_token: string;
  apns_environment: ApnsEnvironment;
  apns_collapse_id: string | null;
  payload: Record<string, unknown>;
}

interface ApnsSendRequest {
  token: string;
  preferredEnvironment: ApnsEnvironment;
  topic: string;
  pushType: string;
  priority?: "5" | "10";
  expiration?: string;
  collapseId?: string | null;
  body: string;
}

interface ApnsSendResult {
  ok: boolean;
  providerMessageId?: string;
  environment?: ApnsEnvironment;
  invalidToken?: boolean;
  error?: string;
}

interface DrainStats {
  claimed: number;
  sent: number;
  failed: number;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
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

// Compares SHA-256 digests so the check is constant-time regardless of where
// the provided value diverges from the configured secret.
async function drainSecretMatches(
  provided: string | null,
  expected: string,
): Promise<boolean> {
  if (!provided || !expected) return false;
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(a);
  const right = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
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
const cachedTokens: Record<
  ApnsEnvironment,
  { jwt: string; issuedAt: number } | null
> = {
  sandbox: null,
  production: null,
};

async function apnsProviderToken(
  environment: ApnsEnvironment,
): Promise<string> {
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

  const header = base64url(
    new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: keyId })),
  );
  const claims = base64url(
    new TextEncoder().encode(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })),
  );
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

// Preferred environment first, then the other host for mixed App Store and
// TestFlight/debug installs.
function environmentOrder(preferred: ApnsEnvironment): ApnsEnvironment[] {
  return preferred === "sandbox"
    ? ["sandbox", "production"]
    : ["production", "sandbox"];
}

async function sendApnsRequest(
  request: ApnsSendRequest,
): Promise<ApnsSendResult> {
  const order = environmentOrder(request.preferredEnvironment);
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
      "apns-topic": request.topic,
      "apns-push-type": request.pushType,
      "content-type": "application/json",
    };
    if (request.priority) headers["apns-priority"] = request.priority;
    if (request.expiration) headers["apns-expiration"] = request.expiration;
    if (request.collapseId) headers["apns-collapse-id"] = request.collapseId;

    const response = await fetch(`https://${host}/3/device/${request.token}`, {
      method: "POST",
      headers,
      body: request.body,
    });

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

    // A token is valid on exactly one host. BadDeviceToken means the stored
    // environment was wrong, so try the other host before giving up.
    if (
      response.status === 400 && reason === "BadDeviceToken" && !isLastAttempt
    ) {
      continue;
    }

    // 410 Unregistered, or BadDeviceToken on the final host, means the token
    // is dead on every environment.
    if (
      response.status === 410 ||
      (response.status === 400 && reason === "BadDeviceToken")
    ) {
      return { ok: false, error: reason, invalidToken: true, environment };
    }

    // Any other failure is not an environment mismatch; let the claim lease
    // retry it later.
    return { ok: false, error: reason, environment };
  }

  return { ok: false, error: lastError };
}

// Background rows wake the app to sync; alert rows show a localized lock-screen
// banner. Title/body are pre-localized in Postgres.
function buildAppApsPayload(
  notification: ClaimedNotification,
): Record<string, unknown> {
  if (notification.apns_push_type === "background") {
    return {
      aps: { "content-available": 1 },
      ...notification.payload,
    };
  }

  const alert: Record<string, string> = { body: notification.body ?? "" };
  if (notification.title) alert.title = notification.title;

  // `mutable-content` lets the Notification Service Extension upgrade into a
  // communication notification. `content-available` also wakes the app so the
  // alert path refreshes widget data even if the separate silent push is
  // throttled.
  return {
    aps: {
      alert,
      sound: "default",
      "mutable-content": 1,
      "content-available": 1,
    },
    ...notification.payload,
    sender_name: notification.title ?? undefined,
  };
}

async function sendAppNotification(
  notification: ClaimedNotification,
): Promise<ApnsSendResult> {
  return sendApnsRequest({
    token: notification.push_token,
    preferredEnvironment: notification.apns_environment,
    topic: APNS_BUNDLE_ID,
    pushType: notification.apns_push_type,
    priority: notification.apns_push_type === "background" ? "5" : "10",
    collapseId: notification.apns_collapse_id,
    body: JSON.stringify(buildAppApsPayload(notification)),
  });
}

function buildWidgetApsPayload(
  notification: ClaimedWidgetPush,
): Record<string, unknown> {
  return {
    aps: { "content-changed": true },
    ...notification.payload,
  };
}

async function sendWidgetPush(
  notification: ClaimedWidgetPush,
): Promise<ApnsSendResult> {
  return sendApnsRequest({
    token: notification.widget_push_token,
    preferredEnvironment: notification.apns_environment,
    topic: `${APNS_BUNDLE_ID}.push-type.widgets`,
    pushType: "widgets",
    priority: "10",
    expiration: "0",
    collapseId: notification.apns_collapse_id,
    body: JSON.stringify(buildWidgetApsPayload(notification)),
  });
}

// Writes confirmed app-device environment back so later sends skip fallback.
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

async function persistWidgetDeviceEnvironment(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  deviceId: string,
  environment: ApnsEnvironment,
): Promise<void> {
  const { error } = await supabase
    .from("widget_push_devices")
    .update({ apns_environment: environment })
    .eq("id", deviceId);
  if (error) {
    console.error("Unable to persist confirmed WidgetKit APNs environment", {
      deviceId,
      error: error.message,
    });
  }
}

// Retires app-device token APNs rejected on every environment.
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

async function disableWidgetDevice(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  deviceId: string,
): Promise<void> {
  const { error } = await supabase
    .from("widget_push_devices")
    .update({ disabled_at: new Date().toISOString() })
    .eq("id", deviceId)
    .is("disabled_at", null);
  if (error) {
    console.error("Unable to disable widget device with invalid token", {
      deviceId,
      error: error.message,
    });
  }
}

async function drainAppNotifications(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<DrainStats> {
  const { data, error } = await supabase.rpc("claim_notification_batch", {
    p_limit: 100,
  });
  if (error) throw new Error(error.message);

  const batch = (data ?? []) as ClaimedNotification[];
  let sent = 0;
  let failed = 0;

  for (const notification of batch) {
    let result: ApnsSendResult;
    try {
      result = await sendAppNotification(notification);
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

  return { claimed: batch.length, sent, failed };
}

async function drainWidgetPushes(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<DrainStats> {
  const { data, error } = await supabase.rpc("claim_widget_push_batch", {
    p_limit: 100,
  });
  if (error) throw new Error(error.message);

  const batch = (data ?? []) as ClaimedWidgetPush[];
  let sent = 0;
  let failed = 0;

  for (const notification of batch) {
    let result: ApnsSendResult;
    try {
      result = await sendWidgetPush(notification);
    } catch (error) {
      result = { ok: false, error: errorMessage(error) };
    }

    if (
      result.ok && result.environment &&
      result.environment !== notification.apns_environment
    ) {
      await persistWidgetDeviceEnvironment(
        supabase,
        notification.target_widget_device_id,
        result.environment,
      );
    }

    if (result.invalidToken) {
      await disableWidgetDevice(supabase, notification.target_widget_device_id);
    }

    const { error: markError } = await supabase.rpc(
      "mark_widget_push_result",
      {
        p_outbox_id: notification.outbox_id,
        p_success: result.ok,
        p_provider_message_id: result.providerMessageId ?? null,
        p_error: result.error ?? null,
        p_invalid_token: result.invalidToken ?? false,
      },
    );

    if (markError) {
      console.error("Unable to record WidgetKit push result", {
        outbox_id: notification.outbox_id,
        error: markError.message,
      });
      failed++;
      continue;
    }

    if (result.ok) sent++;
    else failed++;
  }

  return { claimed: batch.length, sent, failed };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(JSON.stringify({ ok: true }), {
      headers: { "content-type": "application/json" },
    });
  }

  if (request.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  if (!DRAIN_SECRET) {
    console.error("push delivery is not configured", {
      missing: ["DRAIN_SECRET"],
    });
    return new Response("push delivery is not configured", { status: 500 });
  }

  const secretMatches = await drainSecretMatches(
    request.headers.get("x-drain-secret"),
    DRAIN_SECRET,
  );
  if (!secretMatches) {
    return new Response("unauthorized", { status: 401 });
  }

  if (
    !SUPABASE_URL || !SERVICE_KEY || !APNS_KEY_ID || !APNS_TEAM_ID ||
    !APNS_PRIVATE_KEY
  ) {
    const missing = [
      !SUPABASE_URL ? "SUPABASE_URL" : null,
      !SERVICE_KEY ? "SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY" : null,
      !APNS_KEY_ID ? "APNS_KEY_ID" : null,
      !APNS_TEAM_ID ? "APNS_TEAM_ID" : null,
      !APNS_PRIVATE_KEY ? "APNS_PRIVATE_KEY" : null,
    ].filter((value): value is string => value !== null);
    console.error("push delivery is not configured", {
      missing,
    });
    return new Response("push delivery is not configured", { status: 500 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  let app: DrainStats;
  let widget: DrainStats;
  try {
    app = await drainAppNotifications(supabase);
    widget = await drainWidgetPushes(supabase);
  } catch (error) {
    return new Response(JSON.stringify({ error: errorMessage(error) }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({
      claimed: app.claimed + widget.claimed,
      sent: app.sent + widget.sent,
      failed: app.failed + widget.failed,
      app,
      widget,
    }),
    { headers: { "content-type": "application/json" } },
  );
});
