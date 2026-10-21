import { vOnCompleteArgs } from "@convex-dev/workpool";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import { isQuietNight, notificationStaleAt, type PreparedNotification, type PreparedWidgetPush } from "./lib/apns";
import type { WriterCtx } from "./lib/db";
import { isActiveCoupleMember } from "./lib/access";
import { badgeCountForUser } from "./lib/badges";
import { getByUuid, withTouch } from "./lib/db";
import { isDailyPartnerPushKind, resolveDailyPartnerPush } from "./lib/dailyPartnerPush";
import { gamePushStillWanted } from "./lib/gameRegistry";
import type { GamePushKind } from "./lib/games";
import { uuidArg } from "./lib/ids";
import { hasStartedToday } from "./lib/questionTimeStatus";
import { refreshStreakAfterDeviceTimeZoneChange } from "./lib/streaks";
import { isValidTimeZone, nowIso } from "./lib/time";
import { hasTopicWaiting, topicPushTooSoon } from "./lib/topics";

// The database side of one APNs send. Each outbox row is one pushWorkpool work item
// (`enqueuePush` in lib/notifications.ts). `push:send_push` asks `prepare_*` whether the row
// should still go out, sends it, and records the result here.

const TARGET_INELIGIBLE = "notification target is no longer eligible";
const OUT_OF_DATE = "notification is out of date";

const deviceKind = v.union(v.literal("app"), v.literal("widget"));
type DeviceKind = "app" | "widget";
const OUTBOX = { app: "notification_outbox", widget: "widget_push_outbox" } as const;

/** `substring(btrim(text) for max)` that turns an empty result into undefined. */
function cleanText(value: string | null | undefined, max: number): string | undefined {
  const text = (value ?? "").trim();
  return text === "" ? undefined : Array.from(text).slice(0, max).join("");
}

/** The row when it is neither sent nor failed. */
async function pendingRow<T extends "notification_outbox" | "widget_push_outbox">(
  ctx: WriterCtx,
  table: T,
  outboxId: string,
): Promise<Doc<T> | null> {
  const row = await getByUuid(ctx, table, uuidArg(outboxId));
  return row && row.sent_at === undefined && row.failed_at === undefined ? row : null;
}

async function drop(
  ctx: WriterCtx,
  row: Doc<"notification_outbox"> | Doc<"widget_push_outbox">,
  error: string,
): Promise<null> {
  await ctx.db.patch(row._id, { failed_at: nowIso(), last_error: error });
  return null;
}

/**
 * Port of the preference `case` in `claim_notification_batch`. A missing
 * preference row blocks the kinds that have a preference and allows the rest.
 */
function kindAllowed(row: Doc<"notification_outbox">, preference: Doc<"notification_preferences"> | null): boolean {
  switch (row.kind) {
    case "streak_reminder":
      return preference?.streak_reminders_enabled ?? false;
    case "question_time_reminder":
      return preference?.question_time_enabled ?? false;
    case "date_reminder":
      return preference?.date_reminders_enabled ?? false;
    case "daily_challenge_completed":
      return preference?.daily_challenge_enabled ?? false;
    case "partner_answered":
    case "topics_waiting":
      return preference?.partner_answered_enabled ?? false;
    case "widget_updated":
      return row.apns_push_type !== "alert" || (preference?.widget_updates_enabled ?? false);
    case "location_updated":
      return preference?.location_updates_enabled ?? false;
    case "memory_created":
    case "story_posted":
      return preference?.memories_enabled ?? false;
    case "thread_message_sent":
      return preference?.messages_enabled ?? false;
    case "game_turn_ready":
    case "game_result":
    case "game_invite":
    case "game_turn_reminder":
      return preference?.games_enabled ?? false;
    default:
      return true;
  }
}

const GAME_PUSH_KINDS: readonly string[] = ["game_turn_ready", "game_result", "game_invite", "game_turn_reminder"];

/**
 * Whether the recipient still belongs where the row points. A row whose payload names a couple
 * needs the recipient to be an active member of it, so a push queued before a relationship ended
 * never goes out after. Game pushes also need game access and a turn that still waits for them.
 */
async function rowStillWanted(
  ctx: WriterCtx,
  row: Doc<"notification_outbox">,
  recipientUserId: string,
): Promise<{ wanted: true } | { wanted: false; reason: "ineligible" | "out_of_date" }> {
  const payload = (row.payload ?? {}) as Record<string, unknown>;
  if (GAME_PUSH_KINDS.includes(row.kind)) {
    return await gamePushStillWanted(ctx, row.kind as GamePushKind, payload, recipientUserId);
  }
  if (typeof payload.couple_id === "string" && !(await isActiveCoupleMember(ctx, recipientUserId, payload.couple_id))) {
    return { wanted: false, reason: "ineligible" };
  }
  // The topic push can wait up to 3 hours, so it goes out only if something still waits by then,
  // and never sooner than 3 hours after the previous topic push really went out.
  if (
    row.kind === "topics_waiting" &&
    typeof payload.couple_id === "string" &&
    (!(await hasTopicWaiting(ctx, payload.couple_id, recipientUserId)) ||
      (await topicPushTooSoon(ctx, recipientUserId, row.scheduled_for, nowIso())))
  ) {
    return { wanted: false, reason: "out_of_date" };
  }
  if (
    row.kind === "question_time_reminder" &&
    typeof payload.couple_id === "string" &&
    (await hasStartedToday(ctx, payload.couple_id, recipientUserId, nowIso()))
  ) {
    return { wanted: false, reason: "out_of_date" };
  }
  return { wanted: true };
}

/**
 * The app icon number an alert carries, read at send time. A badge-only push always carries it,
 * zero too. Any other alert carries it only when something waits, so it never clears the icon on
 * its own. Background pushes leave the icon alone.
 */
async function sendBadge(ctx: WriterCtx, row: Doc<"notification_outbox">, userId: string): Promise<number | null> {
  if (row.apns_push_type !== "alert") return null;
  const count = await badgeCountForUser(ctx, userId);
  return row.kind === "badge_update" || count > 0 ? count : null;
}

/** The user picked the time of these alerts, so they keep their sound at night. */
const LOUD_AT_NIGHT_KINDS: readonly string[] = ["question_time_reminder"];

/**
 * Whether an alert should land quietly because it is night where the phone is. Uses the device's
 * zone, else the profile zone. With neither, the alert keeps its sound rather than guess.
 */
async function deliverQuietly(
  ctx: WriterCtx,
  row: Doc<"notification_outbox">,
  device: Doc<"user_devices">,
): Promise<boolean> {
  if (row.apns_push_type !== "alert" || LOUD_AT_NIGHT_KINDS.includes(row.kind)) return false;
  let timeZone = device.time_zone_id;
  if (!isValidTimeZone(timeZone)) {
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", device.user_id))
      .unique();
    timeZone = profile?.time_zone_id;
  }
  return isValidTimeZone(timeZone) && isQuietNight(Date.now(), timeZone);
}

/**
 * Runs right before each send, so a row queued for later is checked when it is due. Fails the row
 * when its device is gone or disabled, the user turned its kind off, its couple or game turn no
 * longer needs it, or its reminder passed. A partner's daily answer push decides here what it says.
 * Returns what the send needs, or null. An alert sent at night goes out at once but quietly
 * (`deliverQuietly`).
 */
export const prepare_notification = internalMutation({
  args: { outbox_id: v.string() },
  handler: async (ctx, args): Promise<PreparedNotification | null> => {
    const row = await pendingRow(ctx, "notification_outbox", args.outbox_id);
    if (!row) return null;
    const device = await getByUuid(ctx, "user_devices", row.target_device_id);
    // A deleted device cascaded its outbox rows in Postgres, so a missing one is ineligible too.
    if (!device || device.disabled_at !== undefined) return await drop(ctx, row, TARGET_INELIGIBLE);
    const preference = await ctx.db
      .query("notification_preferences")
      .withIndex("by_user_id", (q) => q.eq("user_id", device.user_id))
      .unique();
    let sendable = row;
    // A partner's daily answer push waits in a lane and picks its kind and copy now
    // (lib/dailyPartnerPush.ts). The row keeps what went out.
    if (isDailyPartnerPushKind(row.kind)) {
      const resolved = await resolveDailyPartnerPush(ctx, row, device.user_id, device.locale, (kind) =>
        kindAllowed({ ...row, kind }, preference),
      );
      if (!resolved.push) return await drop(ctx, row, resolved.reason === "ineligible" ? TARGET_INELIGIBLE : OUT_OF_DATE);
      await ctx.db.patch(row._id, resolved.push);
      sendable = { ...row, ...resolved.push };
    }
    if (!kindAllowed(sendable, preference)) return await drop(ctx, row, TARGET_INELIGIBLE);
    const still = await rowStillWanted(ctx, sendable, device.user_id);
    if (!still.wanted) return await drop(ctx, row, still.reason === "ineligible" ? TARGET_INELIGIBLE : OUT_OF_DATE);
    const staleAt = notificationStaleAt(sendable.payload);
    if (staleAt !== null && Date.parse(staleAt) <= Date.now()) return await drop(ctx, row, OUT_OF_DATE);
    return {
      outbox_id: row.id,
      target_device_id: row.target_device_id,
      push_token: device.push_token,
      apns_environment: row.apns_environment,
      apns_push_type: row.apns_push_type,
      apns_collapse_id: row.apns_collapse_id ?? null,
      title: sendable.title ?? null,
      body: sendable.body ?? null,
      payload: sendable.payload,
      deliver_quietly: await deliverQuietly(ctx, sendable, device),
      badge: await sendBadge(ctx, sendable, device.user_id),
    };
  },
});

/** Like `prepare_notification` for a WidgetKit push. Only the widget device is checked. */
export const prepare_widget_push = internalMutation({
  args: { outbox_id: v.string() },
  handler: async (ctx, args): Promise<PreparedWidgetPush | null> => {
    const row = await pendingRow(ctx, "widget_push_outbox", args.outbox_id);
    if (!row) return null;
    const device = await getByUuid(ctx, "widget_push_devices", row.target_widget_device_id);
    if (!device || device.disabled_at !== undefined) return await drop(ctx, row, TARGET_INELIGIBLE);
    return {
      outbox_id: row.id,
      target_widget_device_id: device.id,
      widget_push_token: device.widget_push_token,
      apns_environment: row.apns_environment,
      apns_collapse_id: row.apns_collapse_id ?? null,
      payload: row.payload,
    };
  },
});

async function recordResult(
  ctx: WriterCtx,
  kind: DeviceKind,
  outboxId: string,
  result: { provider_message_id?: string; error?: string },
): Promise<void> {
  const row = await pendingRow(ctx, OUTBOX[kind], outboxId);
  if (!row) return;
  const now = nowIso();
  await ctx.db.patch(
    row._id,
    result.error === undefined
      ? { sent_at: now, provider_message_id: cleanText(result.provider_message_id, Infinity), last_error: undefined }
      : { failed_at: now, last_error: cleanText(result.error, 2000) ?? "delivery failed" },
  );
}

/** Port of `internal.mark_notification_result`. Without `error` the row is sent, with it the row failed for good. */
export const mark_push_result = internalMutation({
  args: {
    kind: deviceKind,
    outbox_id: v.string(),
    provider_message_id: v.optional(v.string()),
    error: v.optional(v.string()),
  },
  handler: async (ctx, { kind, outbox_id, ...result }) => {
    await recordResult(ctx, kind, outbox_id, result);
    return null;
  },
});

/** What `push:send_push` returns once APNs answered for good. `push_finished` records it. */
export type PushOutcome = {
  device_id: string;
  provider_message_id?: string;
  error?: string;
  invalid_token: boolean;
  /** The host APNs accepted, when it differs from the one the row was queued for. */
  confirmed_environment?: "sandbox" | "production";
};

/**
 * pushWorkpool `onComplete` for every send. A send that APNs answered records its outcome here,
 * in one mutation, so a failed write cannot leave the row pending after the push went out. A send
 * that used up its retries, or was canceled, fails the row. A `null` result means nothing was sent.
 */
export const push_finished = internalMutation({
  args: vOnCompleteArgs(v.object({ kind: deviceKind, outbox_id: v.string() })),
  handler: async (ctx, { context, result }) => {
    if (result.kind !== "success") {
      await recordResult(ctx, context.kind, context.outbox_id, {
        error: result.kind === "failed" ? result.error : "delivery was canceled",
      });
      return null;
    }
    const outcome = result.returnValue as PushOutcome | null;
    if (!outcome) return null;
    if (outcome.confirmed_environment) {
      await persistDeviceEnvironment(ctx, context.kind, outcome.device_id, outcome.confirmed_environment);
    }
    if (outcome.invalid_token) await disableDevice(ctx, context.kind, outcome.device_id);
    await recordResult(ctx, context.kind, context.outbox_id, outcome);
    return null;
  },
});

async function persistDeviceEnvironment(
  ctx: WriterCtx,
  kind: DeviceKind,
  deviceId: string,
  environment: "sandbox" | "production",
): Promise<void> {
  const id = uuidArg(deviceId);
  if (kind === "app") {
    const device = await getByUuid(ctx, "user_devices", id);
    if (device) await ctx.db.patch(device._id, withTouch(device, { apns_environment: environment }));
  } else {
    const device = await getByUuid(ctx, "widget_push_devices", id);
    if (device) await ctx.db.patch(device._id, withTouch(device, { apns_environment: environment }));
  }
}

async function disableDevice(ctx: WriterCtx, kind: DeviceKind, deviceId: string): Promise<void> {
  const id = uuidArg(deviceId);
  const now = nowIso();
  if (kind === "app") {
    const device = await getByUuid(ctx, "user_devices", id);
    if (!device || device.disabled_at !== undefined) return;
    await ctx.db.patch(device._id, withTouch(device, { disabled_at: now }));
    await refreshStreakAfterDeviceTimeZoneChange(
      ctx,
      device.user_id,
      { time_zone_id: device.time_zone_id, last_seen_at: device.last_seen_at, disabled_at: now },
      { time_zone_id: device.time_zone_id, last_seen_at: device.last_seen_at, disabled_at: null },
    );
  } else {
    const device = await getByUuid(ctx, "widget_push_devices", id);
    if (device && device.disabled_at === undefined) {
      await ctx.db.patch(device._id, withTouch(device, { disabled_at: now }));
    }
  }
}

/** Sets the APNs host a device's pushes go to. */
export const persist_device_environment = internalMutation({
  args: { kind: deviceKind, device_id: v.string(), apns_environment: v.union(v.literal("sandbox"), v.literal("production")) },
  handler: async (ctx, args) => {
    await persistDeviceEnvironment(ctx, args.kind, args.device_id, args.apns_environment);
    return null;
  },
});

/** Retires a device whose token APNs rejected. */
export const disable_device = internalMutation({
  args: { kind: deviceKind, device_id: v.string() },
  handler: async (ctx, args) => {
    await disableDevice(ctx, args.kind, args.device_id);
    return null;
  },
});
