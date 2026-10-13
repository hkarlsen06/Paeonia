import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import { listActiveMembers } from "./access";
import type { WriterCtx } from "./db";
import { getByUuid } from "./db";
import { checkViolation, fail } from "./errors";
import { isJsonObject, jsonbByteLength } from "./json";
import { newUuid } from "./ids";
import {
  notificationAlertBody,
  notificationAlertTitle,
  notificationPayloadIsSafe,
} from "./notificationCopy";
import { nowIso } from "./time";

export * from "./notificationCopy";

const NOTIFICATION_KINDS = [
  "streak_reminder",
  "daily_challenge_completed",
  "partner_answered",
  "widget_updated",
  "location_updated",
  "subscription_trial_reminder",
  "memory_created",
  "thread_message_sent",
  "game_turn_ready",
  "game_result",
  "game_invite",
  "game_turn_reminder",
] as const;
export type NotificationKind = (typeof NOTIFICATION_KINDS)[number];

/** Port of `internal.assert_notification_payload_safe`. */
export function assertNotificationPayloadSafe(payload: unknown): void {
  if (!notificationPayloadIsSafe(payload)) {
    fail("23514", "notification payload contains sensitive or unsupported fields");
  }
}

/** Schedules the APNs drain. Replaces the `invoke_push_notification_drain` statement trigger. */
export async function scheduleNotificationDrain(ctx: WriterCtx): Promise<void> {
  await ctx.scheduler.runAfter(0, internal.push.drain_notifications, {});
}

/** Schedules the widget push drain. Replaces the `invoke_push_notification_drain` trigger on widget_push_outbox. */
export async function scheduleWidgetPushDrain(ctx: WriterCtx): Promise<void> {
  await ctx.scheduler.runAfter(0, internal.push.drain_widget_pushes, {});
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
 * Does not schedule the drain. Callers call `scheduleNotificationDrain` once after their inserts.
 */
export async function insertNotificationOutbox(
  ctx: WriterCtx,
  row: NotificationOutboxInsert,
): Promise<boolean> {
  assertNotificationPayloadSafe(row.payload);
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
  await ctx.db.insert("notification_outbox", {
    id: newUuid(),
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
    attempt_count: 0,
    scheduled_for: row.scheduled_for ?? now,
    created_at: now,
    title: row.title ?? undefined,
    body: row.body ?? undefined,
  });
  return true;
}

function preferenceAllows(
  kind: NotificationKind,
  pushType: string,
  preference: Doc<"notification_preferences">,
): boolean {
  switch (kind) {
    case "streak_reminder":
      return preference.streak_reminders_enabled;
    case "daily_challenge_completed":
      return preference.daily_challenge_enabled;
    case "partner_answered":
      return preference.partner_answered_enabled;
    case "widget_updated":
      return pushType !== "alert" || preference.widget_updates_enabled;
    case "location_updated":
      return preference.location_updates_enabled;
    case "memory_created":
      return preference.memories_enabled;
    case "thread_message_sent":
      return preference.messages_enabled;
    case "game_turn_ready":
    case "game_result":
    case "game_invite":
    case "game_turn_reminder":
      return preference.games_enabled;
    default:
      return true;
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
 * device when the user's preferences allow the kind, then schedules the drain.
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
  if (!(NOTIFICATION_KINDS as readonly string[]).includes(args.kind)) {
    return fail("23514", "notification kind is not supported");
  }
  const kind = args.kind as NotificationKind;
  const redactionLevel = args.redaction_level ?? "private";
  if (redactionLevel !== "private") {
    return fail("23514", "only private notification payloads are supported for MVP");
  }
  if (!notificationPayloadIsSafe(args.payload)) {
    return fail("23514", "notification payload contains sensitive or unsupported fields");
  }
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
    if (!preferenceAllows(kind, pushType, preference)) {
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
      title: pushType === "alert" ? await notificationAlertTitle(ctx, kind, args.payload, device.locale) : null,
      body: pushType === "alert" ? notificationAlertBody(kind, args.payload, device.locale) : null,
      scheduled_for: args.scheduled_for ?? null,
    });
    if (inserted) queued += 1;
  }
  if (queued > 0) {
    await scheduleNotificationDrain(ctx);
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
 * and dedupe key exists.
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
  if (!isJsonObject(row.payload) || jsonbByteLength(row.payload) > 2048) {
    checkViolation(table, "widget_push_outbox_payload_check");
  }
  if (row.dedupe_key != null) {
    const length = trimmedLength(row.dedupe_key);
    if (length < 1 || length > 256) checkViolation(table, "widget_push_outbox_dedupe_key_check");
    const pending = await ctx.db
      .query("widget_push_outbox")
      .withIndex("by_target_widget_device_id_dedupe_key", (q) =>
        q.eq("target_widget_device_id", row.target_widget_device_id).eq("dedupe_key", row.dedupe_key!),
      )
      .collect();
    if (pending.some((item) => item.sent_at === undefined && item.failed_at === undefined)) {
      return false;
    }
  }
  if (row.apns_collapse_id != null) {
    const length = trimmedLength(row.apns_collapse_id);
    if (length < 1 || length > 64) checkViolation(table, "widget_push_outbox_collapse_id_check");
  }
  const now = nowIso();
  await ctx.db.insert("widget_push_outbox", {
    id: newUuid(),
    recipient_user_id: row.recipient_user_id,
    target_widget_device_id: row.target_widget_device_id,
    widget_push_token_hash: row.widget_push_token_hash,
    apns_environment: row.apns_environment,
    kind: "widget_updated",
    payload: row.payload,
    dedupe_key: row.dedupe_key ?? undefined,
    apns_collapse_id: row.apns_collapse_id ?? undefined,
    attempt_count: 0,
    scheduled_for: row.scheduled_for ?? now,
    created_at: now,
  });
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
  if (queued > 0) {
    await scheduleWidgetPushDrain(ctx);
  }
  return queued;
}

/**
 * Port of the `enqueue_partner_answered_notification` trigger. Call after
 * inserting a daily_question_answers row. Notifies the first partner when the
 * second visible answer arrives.
 */
export async function enqueuePartnerAnsweredNotification(
  ctx: WriterCtx,
  answer: Doc<"daily_question_answers">,
): Promise<void> {
  if (answer.deleted_at !== undefined || answer.moderation_status !== "visible") {
    return;
  }
  const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
  if (!instance) return;
  const coupleDay = await getByUuid(ctx, "couple_days", instance.couple_day_id);
  if (!coupleDay) return;

  const answers = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", answer.instance_id))
    .collect();
  const visible = answers.filter((item) => item.deleted_at === undefined && item.moderation_status === "visible");
  if (visible.length !== 2) return;
  const recipient = visible.find((item) => item.user_id !== answer.user_id);
  if (!recipient) return;

  await enqueueNotificationForUser(ctx, {
    recipient_user_id: recipient.user_id,
    kind: "partner_answered",
    payload: {
      type: "partner_answered",
      couple_id: coupleDay.couple_id,
      couple_day_id: instance.couple_day_id,
      instance_id: answer.instance_id,
      actor_user_id: answer.user_id,
      route: "daily",
      deeplink: `paeonia://daily/reveal?instanceId=${answer.instance_id}&coupleDayId=${instance.couple_day_id}`,
    },
    dedupe_key: `partner_answered:${answer.instance_id}:${answer.user_id}:${recipient.user_id}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `daily:${coupleDay.couple_id}`,
    scheduled_for: nowIso(),
  });
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
      deeplink: "paeonia://memories",
    },
    dedupe_key: `memory_created:${memory.id}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `memory:${memory.id}`,
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

  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", args.author_user_id))
    .unique();
  const authorName = profile?.display_name?.trim() || null;

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
      title: authorName ?? "Paeonia",
      body: notificationAlertBody("widget_updated", {}, device.locale),
      scheduled_for: nowIso(),
    });
    if (inserted) queued += 1;
  }
  if (queued > 0) {
    await scheduleNotificationDrain(ctx);
  }
  return queued;
}
