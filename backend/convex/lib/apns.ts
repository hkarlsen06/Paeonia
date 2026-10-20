// Pure APNs helpers: request builders, provider JWT, and the sandbox/production
// fallback. The HTTP/2 transport lives in push.ts ("use node").

import { localWallClockMs } from "./time";
import type { NotificationKind } from "./notifications";

export type ApnsEnvironment = "sandbox" | "production";

export type PreparedNotification = {
  outbox_id: string;
  target_device_id: string;
  push_token: string;
  apns_environment: ApnsEnvironment;
  apns_push_type: "alert" | "background";
  apns_collapse_id: string | null;
  title: string | null;
  body: string | null;
  payload: Record<string, unknown>;
  /** Night where the phone is, so the alert lands in Notification Center without sound or a lit screen. */
  deliver_quietly: boolean;
  /** The app icon number at send time (lib/badges.ts), or null to leave the icon as it is. */
  badge: number | null;
};

/** A badge-only push (`queueBadgeUpdate` in lib/badges.ts): it changes the app icon number and shows nothing. */
export function isBadgeUpdate(notification: PreparedNotification): boolean {
  return notification.payload.type === "badge_update";
}

export type PreparedWidgetPush = {
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

/** Local hour, inclusive, when night starts for alerts. */
export const QUIET_NIGHT_START_HOUR = 22;
/** Local hour, exclusive, when night ends for alerts. */
export const QUIET_NIGHT_END_HOUR = 7;

/** True when `instant` falls between 22:00 and 07:00 on the local clock in `timeZone`. */
export function isQuietNight(instant: string | number, timeZone: string): boolean {
  const ms = typeof instant === "number" ? instant : Date.parse(instant);
  const hour = new Date(localWallClockMs(ms, timeZone)).getUTCHours();
  return hour >= QUIET_NIGHT_START_HOUR || hour < QUIET_NIGHT_END_HOUR;
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Background rows wake the app to sync. Alert rows show a localized lock-screen
 * banner whose title and body were written when the row was queued.
 * The payload privacy rules were applied at queue time, so this adds only `aps`.
 */
export function buildAppApsPayload(notification: PreparedNotification): Record<string, unknown> {
  if (notification.apns_push_type === "background") {
    return { aps: { "content-available": 1 }, ...notification.payload };
  }
  if (isBadgeUpdate(notification)) return { aps: { badge: notification.badge ?? 0 } };
  // A row without a body shows its title alone, never an empty line.
  const alert: Record<string, string> = {};
  if (notification.title) alert.title = notification.title;
  if (notification.body) alert.body = notification.body;
  // At night a passive alert with no sound waits in Notification Center instead of waking the phone.
  const interruption = notification.deliver_quietly ? { "interruption-level": "passive" } : { sound: "default" };
  // `mutable-content` lets the Notification Service Extension upgrade into a
  // communication notification. `content-available` also wakes the app so the
  // alert path refreshes widget data even if the separate silent push is
  // throttled.
  return {
    aps: {
      alert,
      ...interruption,
      "mutable-content": 1,
      "content-available": 1,
      ...notificationGrouping(notification.payload),
      ...(notification.badge === null ? {} : { badge: notification.badge }),
    },
    ...notification.payload,
    sender_name: notification.title ?? undefined,
  };
}

/**
 * The category of each alert kind. The app registers one `UNNotificationCategory` per value
 * (`PaeoniaNotificationCategory`), which gives the lock screen a short line such as "New message"
 * when Show Previews is off. Keep the two lists the same.
 */
const NOTIFICATION_CATEGORY: Record<Exclude<NotificationKind, "location_updated" | "badge_update">, string> = {
  thread_message_sent: "message",
  widget_updated: "drawing",
  partner_answered: "answer",
  daily_challenge_completed: "answer",
  topics_waiting: "answer",
  game_turn_ready: "game",
  game_turn_reminder: "game",
  game_invite: "game",
  game_result: "game",
  memory_created: "partner",
  story_posted: "partner",
  partner_joined: "partner",
  question_time_reminder: "reminder",
  streak_reminder: "reminder",
  subscription_trial_reminder: "reminder",
};

/**
 * The stack an alert joins in Notification Center. A chat stacks by its thread and a game by its
 * kind. The notification service extension keeps this id, and the app reads the `widget` id to
 * spot a drawing alert. Null for a kind without a stack.
 */
export function notificationThreadId(payload: Record<string, unknown>): string | null {
  switch (payload.type) {
    case "thread_message_sent":
      return typeof payload.thread_id === "string" ? `chat:${payload.thread_id}` : "chat";
    case "game_turn_ready":
    case "game_turn_reminder":
    case "game_invite":
    case "game_result":
      return typeof payload.game_kind === "string" ? `game:${payload.game_kind}` : "game";
    case "widget_updated":
      return "widget";
    case "partner_answered":
    case "daily_challenge_completed":
    case "question_time_reminder":
      return "daily";
    case "topics_waiting":
      return "topics";
    case "memory_created":
      return "memories";
    case "story_posted":
      return "stories";
    case "partner_joined":
      return "pairing";
    case "streak_reminder":
      return "streak";
    case "subscription_trial_reminder":
      return "subscription";
    default:
      return null;
  }
}

/** The `thread-id` and `category` keys of an alert's `aps`, leaving out any it has no value for. */
function notificationGrouping(payload: Record<string, unknown>): Record<string, string> {
  const grouping: Record<string, string> = {};
  const threadId = notificationThreadId(payload);
  if (threadId) grouping["thread-id"] = threadId;
  const kind = payload.type;
  if (typeof kind === "string" && Object.hasOwn(NOTIFICATION_CATEGORY, kind)) {
    grouping.category = NOTIFICATION_CATEGORY[kind as keyof typeof NOTIFICATION_CATEGORY];
  }
  return grouping;
}

/**
 * When a reminder stops being true: a streak reminder at its deadline, a trial
 * reminder when the trial ends, a question time reminder at the end of the user's local day.
 * `prepare_notification` drops a row past this time, and APNs drops it on a phone that stays
 * offline past it. Null for everything else.
 */
export function notificationStaleAt(payload: Record<string, unknown>): string | null {
  const value =
    payload.type === "streak_reminder"
      ? payload.next_activity_deadline_at
      : payload.type === "subscription_trial_reminder"
        ? payload.trial_ends_at
        : payload.type === "question_time_reminder"
          ? payload.expires_at
          : null;
  return typeof value === "string" && !Number.isNaN(Date.parse(value)) ? value : null;
}

export function buildAppRequest(notification: PreparedNotification, bundleId: string): ApnsSendRequest {
  const staleAt = notificationStaleAt(notification.payload);
  return {
    token: notification.push_token,
    preferredEnvironment: notification.apns_environment,
    topic: bundleId,
    pushType: notification.apns_push_type,
    // A badge-only push shows nothing, so it never needs to wake the phone at once.
    priority: notification.apns_push_type === "background" || isBadgeUpdate(notification) ? "5" : "10",
    expiration: staleAt === null ? undefined : String(Math.floor(Date.parse(staleAt) / 1000)),
    collapseId: notification.apns_collapse_id,
    body: JSON.stringify(buildAppApsPayload(notification)),
  };
}

export function buildWidgetApsPayload(notification: PreparedWidgetPush): Record<string, unknown> {
  return { aps: { "content-changed": true }, ...notification.payload };
}

export function buildWidgetRequest(notification: PreparedWidgetPush, bundleId: string): ApnsSendRequest {
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
 * is not an environment mismatch, so pushWorkpool retries it later.
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

/** A provider token cache that lives as long as the returned object, one send. */
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
