// Pure APNs helpers: request builders, provider JWT, and the sandbox/production
// fallback. The HTTP/2 transport lives in push.ts ("use node").

export type ApnsEnvironment = "sandbox" | "production";

export type ClaimedNotification = {
  outbox_id: string;
  target_device_id: string;
  push_token: string;
  apns_environment: ApnsEnvironment;
  apns_push_type: "alert" | "background";
  apns_collapse_id: string | null;
  title: string | null;
  body: string | null;
  payload: Record<string, unknown>;
};

export type ClaimedWidgetPush = {
  outbox_id: string;
  target_widget_device_id: string;
  widget_push_token: string;
  apns_environment: ApnsEnvironment;
  apns_collapse_id: string | null;
  payload: Record<string, unknown>;
};

export type ApnsSendRequest = {
  token: string;
  preferredEnvironment: ApnsEnvironment;
  topic: string;
  pushType: string;
  priority?: "5" | "10";
  expiration?: string;
  collapseId?: string | null;
  body: string;
};

export type ApnsSendResult = {
  ok: boolean;
  providerMessageId?: string;
  environment?: ApnsEnvironment;
  invalidToken?: boolean;
  error?: string;
};

export type ApnsHttpResponse = { status: number; apnsId?: string; reason?: string };

/** One APNs HTTP request and the provider token it needs. Tests replace it. */
export type ApnsTransport = {
  providerToken(environment: ApnsEnvironment): Promise<string>;
  post(
    environment: ApnsEnvironment,
    jwt: string,
    request: ApnsSendRequest,
  ): Promise<ApnsHttpResponse>;
};

export const DEFAULT_BUNDLE_ID = "no.paeonia.app";
/** Refresh well under the 60 minute APNs cap. */
export const PROVIDER_TOKEN_MAX_AGE_SECONDS = 2400;

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Background rows wake the app to sync. Alert rows show a localized lock-screen
 * banner whose title and body were written when the row was queued.
 * The payload privacy rules were applied at queue time, so this adds only `aps`.
 */
export function buildAppApsPayload(notification: ClaimedNotification): Record<string, unknown> {
  if (notification.apns_push_type === "background") {
    return { aps: { "content-available": 1 }, ...notification.payload };
  }
  const alert: Record<string, string> = { body: notification.body ?? "" };
  if (notification.title) alert.title = notification.title;
  // `mutable-content` lets the Notification Service Extension upgrade into a
  // communication notification. `content-available` also wakes the app so the
  // alert path refreshes widget data even if the separate silent push is
  // throttled.
  return {
    aps: { alert, sound: "default", "mutable-content": 1, "content-available": 1 },
    ...notification.payload,
    sender_name: notification.title ?? undefined,
  };
}

/**
 * When a reminder stops being true: a streak reminder at its deadline, a trial
 * reminder when the trial ends. The claim drops a row past this time, and APNs
 * drops it on a phone that stays offline past it. Null for everything else.
 */
export function notificationStaleAt(payload: Record<string, unknown>): string | null {
  const value =
    payload.type === "streak_reminder"
      ? payload.next_activity_deadline_at
      : payload.type === "subscription_trial_reminder"
        ? payload.trial_ends_at
        : null;
  return typeof value === "string" && !Number.isNaN(Date.parse(value)) ? value : null;
}

export function buildAppRequest(notification: ClaimedNotification, bundleId: string): ApnsSendRequest {
  const staleAt = notificationStaleAt(notification.payload);
  return {
    token: notification.push_token,
    preferredEnvironment: notification.apns_environment,
    topic: bundleId,
    pushType: notification.apns_push_type,
    priority: notification.apns_push_type === "background" ? "5" : "10",
    expiration: staleAt === null ? undefined : String(Math.floor(Date.parse(staleAt) / 1000)),
    collapseId: notification.apns_collapse_id,
    body: JSON.stringify(buildAppApsPayload(notification)),
  };
}

export function buildWidgetApsPayload(notification: ClaimedWidgetPush): Record<string, unknown> {
  return { aps: { "content-changed": true }, ...notification.payload };
}

export function buildWidgetRequest(notification: ClaimedWidgetPush, bundleId: string): ApnsSendRequest {
  return {
    token: notification.widget_push_token,
    preferredEnvironment: notification.apns_environment,
    topic: `${bundleId}.push-type.widgets`,
    pushType: "widgets",
    priority: "10",
    expiration: "0",
    collapseId: notification.apns_collapse_id,
    body: JSON.stringify(buildWidgetApsPayload(notification)),
  };
}

/** The HTTP/2 request headers, including the pseudo headers. */
export function apnsHeaders(jwt: string, request: ApnsSendRequest): Record<string, string> {
  const headers: Record<string, string> = {
    ":method": "POST",
    ":path": `/3/device/${request.token}`,
    authorization: `bearer ${jwt}`,
    "apns-topic": request.topic,
    "apns-push-type": request.pushType,
    "content-type": "application/json",
  };
  if (request.priority) headers["apns-priority"] = request.priority;
  if (request.expiration) headers["apns-expiration"] = request.expiration;
  if (request.collapseId) headers["apns-collapse-id"] = request.collapseId;
  return headers;
}

export function apnsHost(environment: ApnsEnvironment): string {
  return environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
}

/** Preferred environment first, then the other host for mixed App Store and TestFlight installs. */
export function environmentOrder(preferred: ApnsEnvironment): ApnsEnvironment[] {
  return preferred === "sandbox" ? ["sandbox", "production"] : ["production", "sandbox"];
}

/**
 * Sends through the preferred host and falls back to the other one when APNs
 * says BadDeviceToken. A token is valid on exactly one host. 410 Unregistered,
 * or BadDeviceToken on the last host, marks the token dead. Any other failure
 * is not an environment mismatch, so the claim lease retries it later.
 */
export async function sendWithEnvironmentFallback(
  request: ApnsSendRequest,
  transport: ApnsTransport,
): Promise<ApnsSendResult> {
  const order = environmentOrder(request.preferredEnvironment);
  let lastError = "no delivery attempt";

  for (let index = 0; index < order.length; index += 1) {
    const environment = order[index];
    const isLastAttempt = index === order.length - 1;

    let jwt: string;
    try {
      jwt = await transport.providerToken(environment);
    } catch (error) {
      lastError = `provider token: ${errorMessage(error)}`;
      continue;
    }

    const response = await transport.post(environment, jwt, request);
    if (response.status === 200) {
      return { ok: true, providerMessageId: response.apnsId, environment };
    }

    const reason = response.reason || `status ${response.status}`;
    lastError = reason;

    if (response.status === 400 && reason === "BadDeviceToken" && !isLastAttempt) {
      continue;
    }
    if (response.status === 410 || (response.status === 400 && reason === "BadDeviceToken")) {
      return { ok: false, error: reason, invalidToken: true, environment };
    }
    return { ok: false, error: reason, environment };
  }
  return { ok: false, error: lastError };
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const buffer = new ArrayBuffer(binary.length);
  const der = new Uint8Array(buffer);
  for (let index = 0; index < binary.length; index += 1) der[index] = binary.charCodeAt(index);
  return buffer;
}

export type ApnsCredentials = { keyId: string; teamId: string; privateKey: string };

/** ES256 provider JWT. WebCrypto signs ECDSA as raw r||s, which is the JWS format. */
export async function buildProviderJwt(credentials: ApnsCredentials, nowSeconds: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(credentials.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: credentials.keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: credentials.teamId, iat: nowSeconds })));
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

export type ApnsEnv = Record<string, string | undefined>;

/** Reads the APNs settings. Sandbox falls back to the production key. Returns the missing names too. */
export function readApnsConfig(env: ApnsEnv): {
  production: ApnsCredentials;
  sandbox: ApnsCredentials;
  bundleId: string;
  missing: string[];
} {
  const keyId = env.APNS_KEY_ID ?? "";
  const teamId = env.APNS_TEAM_ID ?? "";
  const privateKey = env.APNS_PRIVATE_KEY ?? "";
  const missing = [
    !keyId ? "APNS_KEY_ID" : null,
    !teamId ? "APNS_TEAM_ID" : null,
    !privateKey ? "APNS_PRIVATE_KEY" : null,
  ].filter((name): name is string => name !== null);
  return {
    production: { keyId, teamId, privateKey },
    sandbox: {
      keyId: env.APNS_SANDBOX_KEY_ID || keyId,
      teamId,
      privateKey: env.APNS_SANDBOX_PRIVATE_KEY || privateKey,
    },
    bundleId: env.APNS_BUNDLE_ID || DEFAULT_BUNDLE_ID,
    missing,
  };
}

/** A provider token cache that lives as long as the returned object, one drain run. */
export function cachedProviderTokens(
  credentialsFor: (environment: ApnsEnvironment) => ApnsCredentials,
  now: () => number = () => Math.floor(Date.now() / 1000),
): (environment: ApnsEnvironment) => Promise<string> {
  const cache = new Map<ApnsEnvironment, { jwt: string; issuedAt: number }>();
  return async (environment) => {
    const seconds = now();
    const cached = cache.get(environment);
    if (cached && seconds - cached.issuedAt < PROVIDER_TOKEN_MAX_AGE_SECONDS) return cached.jwt;
    const jwt = await buildProviderJwt(credentialsFor(environment), seconds);
    cache.set(environment, { jwt, issuedAt: seconds });
    return jwt;
  };
}
