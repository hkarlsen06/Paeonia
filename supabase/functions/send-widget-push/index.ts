/// <reference types="jsr:@supabase/functions-js/edge-runtime.d.ts" />

// Drains pending notifications from the outbox and delivers them to APNs as
// silent ('content-available') pushes. Invoked by a Database Webhook on
// `internal.notification_outbox` insert (and/or on a schedule). Idempotent and
// safe to call repeatedly — it only sends rows it can atomically claim.

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
const DRAIN_SECRET = Deno.env.get("DRAIN_SECRET") ?? "";

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "no.paeonia.app";

const PROVIDER_TOKEN_MAX_AGE_SECONDS = 2400; // refresh well under APNs' 60 min cap

interface ClaimedNotification {
  outbox_id: string;
  push_token: string;
  apns_environment: "sandbox" | "production";
  apns_push_type: "alert" | "background";
  apns_collapse_id: string | null;
  payload: Record<string, unknown>;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
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
    for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
    return buffer;
}

let cachedToken: { jwt: string; issuedAt: number } | null = null;

async function apnsProviderToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.issuedAt < PROVIDER_TOKEN_MAX_AGE_SECONDS) {
    return cachedToken.jwt;
  }

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(APNS_PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = base64url(new TextEncoder().encode(
    JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }),
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
  cachedToken = { jwt, issuedAt: now };
  return jwt;
}

async function sendToApns(
  notification: ClaimedNotification,
  jwt: string,
): Promise<{ ok: boolean; providerMessageId?: string; error?: string }> {
  const host = notification.apns_environment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

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

  const body = notification.apns_push_type === "background"
    ? JSON.stringify({ aps: { "content-available": 1 } })
    : JSON.stringify({ aps: { "content-available": 1 } });

  const response = await fetch(`https://${host}/3/device/${notification.push_token}`, {
    method: "POST",
    headers,
    body,
  });

  if (response.status === 200) {
    return { ok: true, providerMessageId: response.headers.get("apns-id") ?? undefined };
  }

  let reason = `status ${response.status}`;
  try {
    const json = await response.json();
    if (json?.reason) reason = String(json.reason);
  } catch (_) {
    // keep the status-based reason
  }
  return { ok: false, error: reason };
}

Deno.serve(async (request) => {
  if (!DRAIN_SECRET || request.headers.get("x-drain-secret") !== DRAIN_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY || !SERVICE_KEY) {
    return new Response("push delivery is not configured", { status: 500 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data, error } = await supabase.rpc("claim_notification_batch", { p_limit: 100 });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const batch = (data ?? []) as ClaimedNotification[];
  const jwt = await apnsProviderToken();
  let sent = 0;
  let failed = 0;

  for (const notification of batch) {
    const result = await sendToApns(notification, jwt);
    await supabase.rpc("mark_notification_result", {
      p_outbox_id: notification.outbox_id,
      p_success: result.ok,
      p_provider_message_id: result.providerMessageId ?? null,
      p_error: result.error ?? null,
    });
    if (result.ok) sent++;
    else failed++;
  }

  return new Response(
    JSON.stringify({ claimed: batch.length, sent, failed }),
    { headers: { "content-type": "application/json" } },
  );
});
