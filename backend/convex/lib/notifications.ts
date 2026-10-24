import { Workpool } from "@convex-dev/workpool";
import { components, internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import { listActiveMembers } from "./access";
import type { WriterCtx } from "./db";
import { checkViolation, fail } from "./errors";
import { memoryDeepLink, storyDeepLink } from "./deepLinks";
import { isJsonObject, jsonbByteLength } from "./json";
import { newUuid } from "./ids";
import { nameForViewer } from "./partnerNames";
import { notificationAlertBody, notificationAlertTitle, notificationLocaleLanguage } from "./notificationCopy";
import { addMs, nowIso } from "./time";

export * from "./notificationCopy";

const GAME_PUSH_FIELDS = [
  "type", "couple_id", "actor_user_id", "route", "deeplink", "game_kind", "game_id", "round_id", "step",
] as const;
const DAILY_PARTNER_PUSH_FIELDS = [
  "type", "couple_id", "actor_user_id", "route", "deeplink", "couple_day_id", "instance_ids",
] as const;

/**
 * Every notification kind and the only payload fields it may carry. APNs delivers the payload
 * whole, so a field missing here is refused instead of sent: answer or note text, media URLs,
 * invite codes, locations and report details never reach a phone by accident. Values must be ids,
 * dates, counts, flags or fixed tokens, never something a person wrote.
 */
const NOTIFICATION_PAYLOAD_FIELDS = {
  streak_reminder: [
    "type", "couple_id", "actor_user_id", "route", "deeplink", "partner_checked_in", "current_count",
    "last_qualified_date", "next_activity_deadline_at", "contribution_needed",
  ],
  daily_challenge_completed: DAILY_PARTNER_PUSH_FIELDS,
  partner_answered: [...DAILY_PARTNER_PUSH_FIELDS, "question_count"],
  widget_updated: [
    "type", "couple_id", "actor_user_id", "sender_user_id", "route", "deeplink", "canvas_id", "revision_id",
  ],
  location_updated: ["type", "couple_id", "actor_user_id", "route", "captured_at"],
  location_pause_ended: ["type", "couple_id"],
  subscription_trial_reminder: ["type", "route", "deeplink", "subscription_id", "trial_ends_at", "days_left"],
  subscription_payment_failed: ["type", "route", "deeplink", "subscription_id"],
  subscription_ending: ["type", "couple_id", "route", "deeplink", "ends_at", "days_left", "own_subscription"],
  memory_created: ["type", "couple_id", "actor_user_id", "route", "deeplink", "memory_id"],
  story_posted: ["type", "couple_id", "actor_user_id", "route", "deeplink", "story_id"],
  thread_message_sent: [
    "type", "couple_id", "actor_user_id", "route", "deeplink", "thread_id", "message_id", "question_id",
    "memory_id", "story_id",
  ],
  thread_message_deleted: ["type", "couple_id", "actor_user_id", "thread_id", "message_id"],
  game_turn_ready: GAME_PUSH_FIELDS,
  game_result: GAME_PUSH_FIELDS,
  game_invite: GAME_PUSH_FIELDS,
  game_turn_reminder: GAME_PUSH_FIELDS,
  question_time_reminder: ["type", "couple_id", "route", "deeplink", "expires_at"],
  date_reminder: [
    "type", "couple_id", "actor_user_id", "route", "deeplink", "reminder", "expires_at", "years", "days",
    "milestone", "count",
  ],
  partner_joined: ["type", "couple_id", "actor_user_id", "route", "deeplink"],
  pairing_invite_reminder: ["type", "route", "deeplink", "invite_id"],
  topics_waiting: ["type", "couple_id", "actor_user_id", "route", "deeplink"],
  reaction_added: [
    "type", "couple_id", "actor_user_id", "route", "deeplink", "target_kind", "target_id", "emoji", "game_kind",
  ],
  badge_update: ["type"],
  data_export_ready: ["type", "route", "deeplink", "export_id"],
} as const satisfies Record<string, readonly string[]>;
export type NotificationKind = keyof typeof NOTIFICATION_PAYLOAD_FIELDS;
export const NOTIFICATION_KINDS = Object.keys(NOTIFICATION_PAYLOAD_FIELDS) as NotificationKind[];

export function isNotificationKind(kind: string): kind is NotificationKind {
  return Object.hasOwn(NOTIFICATION_PAYLOAD_FIELDS, kind);
}

const isPayloadValue = (value: unknown) =>
  value === null ||
  ["string", "number", "boolean"].includes(typeof value) ||
  (Array.isArray(value) && value.every((item) => typeof item === "string"));

/**
 * True when `payload` is an object of at most 4 KB whose every field is one that `kind` may carry
 * (`NOTIFICATION_PAYLOAD_FIELDS`), with a plain value or a list of ids.
 */
export function notificationPayloadIsSafe(kind: string, payload: unknown): boolean {
  if (!isNotificationKind(kind) || !isJsonObject(payload) || jsonbByteLength(payload) > 4096) return false;
  const allowed: readonly string[] = NOTIFICATION_PAYLOAD_FIELDS[kind];
  return Object.entries(payload).every(([key, value]) => allowed.includes(key) && isPayloadValue(value));
}

export const UNSAFE_PAYLOAD_ERROR = "notification payload contains sensitive or unsupported fields";

export function assertNotificationPayloadSafe(kind: string, payload: unknown): void {
  if (!notificationPayloadIsSafe(kind, payload)) {
    fail("23514", UNSAFE_PAYLOAD_ERROR);
  }
}

/**
 * Runs `push:send_push`, one work item per outbox row. At most ten sends run at once, which is
 * far more than this app needs and caps a burst. A failed send retries after about 10, 20, 40,
 * and 80 seconds, then `push_finished` fails the row.
 */
const pushWorkpool = new Workpool(components.pushWorkpool, {
  maxParallelism: 10,
  retryActionsByDefault: true,
  defaultRetryBehavior: { maxAttempts: 5, initialBackoffMs: 10_000, base: 2 },
});

/**
 * Queues the send of one outbox row at its `scheduled_for`. Replaces the
 * `invoke_push_notification_drain` triggers and the 30 second drain cron.
 */
async function enqueuePush(ctx: WriterCtx, kind: "app" | "widget", outboxId: string, scheduledFor: string): Promise<void> {
  const context = { kind, outbox_id: outboxId };
  await pushWorkpool.enqueueAction(ctx, internal.push.send_push, context, {
    runAt: Date.parse(scheduledFor),
    onComplete: internal.pushQueue.push_finished,
    context,
  });
}

function trimmedLength(value: string): number {
  return value.trim().length;
}

export type NotificationOutboxInsert = {
  recipient_user_id: string;
  target_device_id: string;
  push_token_hash: string;
  apns_environment: "sandbox" | "production";
  kind: NotificationKind;
  redaction_level?: "private" | "generic" | "content_allowed";
  payload: Record<string, unknown>;
  dedupe_key?: string | null;
  apns_push_type?: "alert" | "background";
  apns_collapse_id?: string | null;
  title?: string | null;
  body?: string | null;
  scheduled_for?: string | null;
};

/**
 * Inserts one notification_outbox row. Applies the table check constraints and
 * the `assert_notification_outbox_payload_safe` trigger. Returns false (and
 * inserts nothing) when the dedupe key already exists, like `on conflict do nothing`.
 * Queues the send for `scheduled_for`, or now.
 */
export async function insertNotificationOutbox(
  ctx: WriterCtx,
  row: NotificationOutboxInsert,
): Promise<boolean> {
  assertNotificationPayloadSafe(row.kind, row.payload);
  const table = "notification_outbox";
  if (row.dedupe_key != null) {
    const length = trimmedLength(row.dedupe_key);
    if (length < 1 || length > 320) checkViolation(table, "notification_outbox_dedupe_key_check");
  }
  if (row.apns_collapse_id != null) {
    const length = trimmedLength(row.apns_collapse_id);
    if (length < 1 || length > 64) checkViolation(table, "notification_outbox_apns_collapse_id_check");
  }
  if (row.title != null) {
    const length = trimmedLength(row.title);
    if (length < 1 || length > 200) checkViolation(table, "notification_outbox_title_check");
  }
  if (row.body != null) {
    const length = trimmedLength(row.body);
    if (length < 1 || length > 1000) checkViolation(table, "notification_outbox_body_check");
  }
  if (row.dedupe_key != null) {
    const existing = await ctx.db
      .query("notification_outbox")
      .withIndex("by_dedupe_key", (q) => q.eq("dedupe_key", row.dedupe_key!))
      .first();
    if (existing) {
      return false;
    }
  }
  const now = nowIso();
  const id = newUuid();
  const scheduledFor = row.scheduled_for ?? now;
  await ctx.db.insert("notification_outbox", {
    id,
    recipient_user_id: row.recipient_user_id,
    target_device_id: row.target_device_id,
    push_token_hash: row.push_token_hash,
    apns_environment: row.apns_environment,
    kind: row.kind,
    payload_version: 1,
    redaction_level: row.redaction_level ?? "private",
    payload: row.payload,
    dedupe_key: row.dedupe_key ?? undefined,
    apns_push_type: row.apns_push_type ?? "alert",
    apns_collapse_id: row.apns_collapse_id ?? undefined,
    scheduled_for: scheduledFor,
    created_at: now,
    title: row.title ?? undefined,
    body: row.body ?? undefined,
  });
  await enqueuePush(ctx, "app", id, scheduledFor);
  return true;
}

export function preferenceAllows(
  kind: NotificationKind,
  pushType: string,
  preference: Doc<"notification_preferences">,
  payload?: Record<string, unknown>,
): boolean {
  switch (kind) {
    case "streak_reminder":
      return preference.streak_reminders_enabled;
    case "question_time_reminder":
      return preference.question_time_enabled;
    case "date_reminder":
      return preference.date_reminders_enabled;
    case "daily_challenge_completed":
      return preference.daily_challenge_enabled;
    case "partner_answered":
    case "topics_waiting":
      return preference.partner_answered_enabled;
    case "widget_updated":
      return pushType !== "alert" || preference.widget_updates_enabled;
    case "location_updated":
      return preference.location_updates_enabled;
    case "memory_created":
    case "story_posted":
      return preference.memories_enabled;
    case "thread_message_sent":
    case "thread_message_deleted":
      return preference.messages_enabled;
    case "game_turn_ready":
    case "game_result":
    case "game_invite":
    case "game_turn_reminder":
      return preference.games_enabled;
    case "reaction_added":
      return reactionPreferenceAllows(payload?.target_kind, preference);
    default:
      return true;
  }
}

/**
 * A reaction follows the setting of the feature it was on: Memories for stories and memories,
 * Drawings for widget drawings, Games for game creations. Anything else stays off.
 */
export function reactionPreferenceAllows(targetKind: unknown, preference: Doc<"notification_preferences">): boolean {
  switch (targetKind) {
    case "story":
    case "memory":
      return preference.memories_enabled;
    case "widget_drawing":
      return preference.widget_updates_enabled;
    case "draw_and_guess_round":
    case "exquisite_corpse_figure":
    case "story_chain_story":
      return preference.games_enabled;
    default:
      return false;
  }
}

/** Active (not disabled) push devices of a user. */
export async function listActiveUserDevices(
  ctx: WriterCtx,
  userId: string,
): Promise<Doc<"user_devices">[]> {
  return await ctx.db
    .query("user_devices")
    .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", userId).eq("disabled_at", undefined))
    .collect();
}

/**
 * Port of `internal.enqueue_notification_for_user`. Queues one alert per active
 * device when the user's preferences allow the kind.
 * Returns the number of rows queued.
 */
export async function enqueueNotificationForUser(
  ctx: WriterCtx,
  args: {
    recipient_user_id: string | null | undefined;
    kind: string;
    payload: Record<string, unknown>;
    dedupe_key?: string | null;
    redaction_level?: string;
    apns_push_type?: "alert" | "background";
    apns_collapse_id?: string | null;
    scheduled_for?: string | null;
  },
): Promise<number> {
  if (!args.recipient_user_id) {
    return fail("23514", "notification recipient is required");
  }
  if (!isNotificationKind(args.kind)) {
    return fail("23514", "notification kind is not supported");
  }
  const kind = args.kind;
  const redactionLevel = args.redaction_level ?? "private";
  if (redactionLevel !== "private") {
    return fail("23514", "only private notification payloads are supported for MVP");
  }
  assertNotificationPayloadSafe(kind, args.payload);
  const pushType = args.apns_push_type ?? "alert";

  const preference = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", args.recipient_user_id!))
    .unique();
  if (!preference) {
    return 0;
  }
  const dedupeBase = (args.dedupe_key ?? "").trim();
  const collapseId = (args.apns_collapse_id ?? "").trim();

  let queued = 0;
  for (const device of await listActiveUserDevices(ctx, args.recipient_user_id)) {
    if (!preferenceAllows(kind, pushType, preference, args.payload)) {
      continue;
    }
    const inserted = await insertNotificationOutbox(ctx, {
      recipient_user_id: device.user_id,
      target_device_id: device.id,
      push_token_hash: device.push_token_hash,
      apns_environment: device.apns_environment,
      kind,
      redaction_level: "private",
      payload: args.payload,
      dedupe_key: dedupeBase === "" ? null : `${dedupeBase}:${device.id}`,
      apns_push_type: pushType,
      apns_collapse_id: collapseId === "" ? null : collapseId,
      title: pushType === "alert" ? await notificationAlertTitle(ctx, device.user_id, kind, args.payload, device.locale) : null,
      body: pushType === "alert" ? notificationAlertBody(kind, args.payload, device.locale) : null,
      scheduled_for: args.scheduled_for ?? null,
    });
    if (inserted) queued += 1;
  }
  return queued;
}

/** Port of `internal.enqueue_partner_notification`: queues the notification for every other active member. */
export async function enqueuePartnerNotification(
  ctx: WriterCtx,
  args: {
    couple_id: string;
    actor_user_id: string;
    kind: string;
    payload: Record<string, unknown>;
    dedupe_key?: string | null;
    redaction_level?: string;
    apns_push_type?: "alert" | "background";
    apns_collapse_id?: string | null;
    scheduled_for?: string | null;
  },
): Promise<number> {
  let queued = 0;
  for (const member of await listActiveMembers(ctx, args.couple_id)) {
    if (member.user_id === args.actor_user_id) continue;
    queued += await enqueueNotificationForUser(ctx, {
      recipient_user_id: member.user_id,
      kind: args.kind,
      payload: args.payload,
      dedupe_key: args.dedupe_key,
      redaction_level: args.redaction_level,
      apns_push_type: args.apns_push_type,
      apns_collapse_id: args.apns_collapse_id,
      scheduled_for: args.scheduled_for,
    });
  }
  return queued;
}

/**
 * Insert one widget_push_outbox row. Applies the table checks and the pending
 * dedupe unique index. Returns false when a pending row with the same device
 * and dedupe key exists. Queues the send for `scheduled_for`, or now.
 */
export async function insertWidgetPushOutbox(
  ctx: WriterCtx,
  row: {
    recipient_user_id: string;
    target_widget_device_id: string;
    widget_push_token_hash: string;
    apns_environment: "sandbox" | "production";
    payload: Record<string, unknown>;
    dedupe_key?: string | null;
    apns_collapse_id?: string | null;
    scheduled_for?: string | null;
  },
): Promise<boolean> {
  const table = "widget_push_outbox";
  if (!notificationPayloadIsSafe("widget_updated", row.payload) || jsonbByteLength(row.payload) > 2048) {
    checkViolation(table, "widget_push_outbox_payload_check");
  }
  if (row.dedupe_key != null) {
    const length = trimmedLength(row.dedupe_key);
    if (length < 1 || length > 256) checkViolation(table, "widget_push_outbox_dedupe_key_check");
    // A key that repeats (the lock screen refresh) piles up sent rows, so look at the newest row only.
    // Rows of one key are sent in the order they were queued, so an older row is never the pending one.
    const newest = await ctx.db
      .query("widget_push_outbox")
      .withIndex("by_target_widget_device_id_dedupe_key", (q) =>
        q.eq("target_widget_device_id", row.target_widget_device_id).eq("dedupe_key", row.dedupe_key!),
      )
      .order("desc")
      .first();
    if (newest && newest.sent_at === undefined && newest.failed_at === undefined) {
      return false;
    }
  }
  if (row.apns_collapse_id != null) {
    const length = trimmedLength(row.apns_collapse_id);
    if (length < 1 || length > 64) checkViolation(table, "widget_push_outbox_collapse_id_check");
  }
  const now = nowIso();
  const id = newUuid();
  const scheduledFor = row.scheduled_for ?? now;
  await ctx.db.insert("widget_push_outbox", {
    id,
    recipient_user_id: row.recipient_user_id,
    target_widget_device_id: row.target_widget_device_id,
    widget_push_token_hash: row.widget_push_token_hash,
    apns_environment: row.apns_environment,
    kind: "widget_updated",
    payload: row.payload,
    dedupe_key: row.dedupe_key ?? undefined,
    apns_collapse_id: row.apns_collapse_id ?? undefined,
    scheduled_for: scheduledFor,
    created_at: now,
  });
  await enqueuePush(ctx, "widget", id, scheduledFor);
  return true;
}

/** Port of `internal.enqueue_widget_push_for_user`. Queues a silent widget refresh for each active PaeoniaWidget device. */
export async function enqueueWidgetPushForUser(
  ctx: WriterCtx,
  args: {
    recipient_user_id: string | null | undefined;
    kind: string;
    payload?: Record<string, unknown> | null;
    dedupe_key?: string | null;
    apns_collapse_id?: string | null;
    scheduled_for?: string | null;
  },
): Promise<number> {
  if (!args.recipient_user_id) {
    return fail("23514", "widget push recipient required");
  }
  if (args.kind !== "widget_updated") {
    return fail("23514", "unsupported widget push kind");
  }
  const payload = args.payload ?? {};
  if (!isJsonObject(payload)) {
    return fail("23514", "widget push payload must be an object");
  }
  const devices = await ctx.db
    .query("widget_push_devices")
    .withIndex("by_user_id_disabled_at", (q) =>
      q.eq("user_id", args.recipient_user_id!).eq("disabled_at", undefined),
    )
    .collect();
  let queued = 0;
  for (const device of devices) {
    if (device.widget_kind !== "PaeoniaWidget") continue;
    const inserted = await insertWidgetPushOutbox(ctx, {
      recipient_user_id: device.user_id,
      target_widget_device_id: device.id,
      widget_push_token_hash: device.widget_push_token_hash,
      apns_environment: device.apns_environment,
      payload,
      dedupe_key: args.dedupe_key,
      apns_collapse_id: args.apns_collapse_id,
      scheduled_for: args.scheduled_for,
    });
    if (inserted) queued += 1;
  }
  return queued;
}

/** How long a change waits before its Lock Screen push goes out, so a burst of changes becomes one push. */
export const LOCK_SCREEN_REFRESH_DELAY_SECONDS = 20;
/** Location updates are frequent, so they cost at most about one Lock Screen push per half hour. */
export const LOCK_SCREEN_LOCATION_DELAY_SECONDS = 30 * 60;
/**
 * A live game trades turns every few seconds while both phones are open, so turns cost at most one
 * push per two minutes. WidgetKit gives each phone a small daily push budget.
 */
export const LOCK_SCREEN_GAME_DELAY_SECONDS = 2 * 60;

/**
 * Queues a silent WidgetKit refresh of the partner's Lock Screen widgets, `delay_seconds` from now.
 * The actor is skipped, because their own app reloads its widgets. While a push for the same
 * partner and `lane` is still waiting, a new call queues nothing, so a burst of changes inside the
 * delay becomes one push. A slow lane (location, games) uses its own `lane` so it never holds back a fast one.
 * Never throws: a failed push must not fail the write that caused it.
 */
export async function enqueueLockScreenRefreshForPartner(
  ctx: WriterCtx,
  args: { couple_id: string; actor_user_id: string; delay_seconds: number; lane?: "location" | "games" },
): Promise<void> {
  try {
    for (const member of await listActiveMembers(ctx, args.couple_id)) {
      if (member.user_id === args.actor_user_id) continue;
      await enqueueLockScreenRefreshForUser(ctx, { ...args, user_id: member.user_id });
    }
  } catch {
    // WidgetKit push delivery must never make the user's write fail.
  }
}

/**
 * Like `enqueueLockScreenRefreshForPartner` for one user, whatever their membership status. Ending a
 * relationship uses it, because the partner is no longer an active member by then. Never throws.
 */
export async function enqueueLockScreenRefreshForUser(
  ctx: WriterCtx,
  args: { couple_id: string; user_id: string; delay_seconds: number; lane?: "location" | "games" },
): Promise<void> {
  try {
    await enqueueWidgetPushForUser(ctx, {
      recipient_user_id: args.user_id,
      kind: "widget_updated",
      payload: { type: "lock_screen_updated", couple_id: args.couple_id },
      dedupe_key: `lockscreen:${args.user_id}${args.lane ? `:${args.lane}` : ""}`,
      apns_collapse_id: `lockscreen:${args.couple_id}`,
      scheduled_for: addMs(nowIso(), args.delay_seconds * 1000),
    });
  } catch {
    // WidgetKit push delivery must never make the user's write fail.
  }
}

/** Port of the `enqueue_memory_created_notification` trigger. Call after inserting a memories row. */
export async function enqueueMemoryCreatedNotification(
  ctx: WriterCtx,
  memory: Doc<"memories">,
): Promise<void> {
  if (memory.deleted_at !== undefined || memory.moderation_status !== "visible") {
    return;
  }
  await enqueuePartnerNotification(ctx, {
    couple_id: memory.couple_id,
    actor_user_id: memory.created_by_user_id,
    kind: "memory_created",
    payload: {
      type: "memory_created",
      couple_id: memory.couple_id,
      memory_id: memory.id,
      actor_user_id: memory.created_by_user_id,
      route: "memories",
      deeplink: memoryDeepLink(memory.id),
    },
    dedupe_key: `memory_created:${memory.id}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `memory:${memory.id}`,
    scheduled_for: nowIso(),
  });
}

/** Queues the "shared a story" alert for the partner. Call after inserting a stories row. The payload never holds the caption. */
export async function enqueueStoryPostedNotification(ctx: WriterCtx, story: Doc<"stories">): Promise<void> {
  await enqueuePartnerNotification(ctx, {
    couple_id: story.couple_id,
    actor_user_id: story.author_user_id,
    kind: "story_posted",
    payload: {
      type: "story_posted",
      couple_id: story.couple_id,
      story_id: story.id,
      actor_user_id: story.author_user_id,
      route: "home",
      deeplink: storyDeepLink(story.id),
    },
    dedupe_key: `story_posted:${story.id}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `story:${story.couple_id}`,
    scheduled_for: nowIso(),
  });
}

/**
 * Port of `internal.enqueue_widget_update_alert`. Queues a visible "new drawing"
 * alert for the partner (the title is the author's name). Returns rows queued.
 */
export async function enqueueWidgetUpdateAlert(
  ctx: WriterCtx,
  args: { couple_id: string; author_user_id: string; canvas_id: string; revision_id: string },
): Promise<number> {
  const recipient = (await listActiveMembers(ctx, args.couple_id)).find(
    (member) => member.user_id !== args.author_user_id,
  );
  if (!recipient) return 0;

  const authorName = await nameForViewer(ctx, recipient.user_id, args.author_user_id);

  const preference = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", recipient.user_id))
    .unique();
  if (!preference?.widget_updates_enabled) return 0;

  let queued = 0;
  for (const device of await listActiveUserDevices(ctx, recipient.user_id)) {
    const inserted = await insertNotificationOutbox(ctx, {
      recipient_user_id: device.user_id,
      target_device_id: device.id,
      push_token_hash: device.push_token_hash,
      apns_environment: device.apns_environment,
      kind: "widget_updated",
      redaction_level: "private",
      payload: {
        type: "widget_updated",
        couple_id: args.couple_id,
        canvas_id: args.canvas_id,
        revision_id: args.revision_id,
        actor_user_id: args.author_user_id,
        sender_user_id: args.author_user_id,
        route: "widget",
        deeplink: "paeonia://widget/drawing",
      },
      dedupe_key: `widget_updated_alert:${args.revision_id}:${device.id}`,
      apns_push_type: "alert",
      apns_collapse_id: `widget-alert:${args.couple_id}`,
      title: authorName ?? (notificationLocaleLanguage(device.locale) === "nb" ? "Partneren din" : "Your partner"),
      body: notificationAlertBody("widget_updated", {}, device.locale),
      scheduled_for: nowIso(),
    });
    if (inserted) queued += 1;
  }
  return queued;
}
