import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery } from "./_generated/server";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, withTouch } from "./lib/db";
import { fail } from "./lib/errors";
import { optionalTimestampArg, uuidArg } from "./lib/ids";
import { refreshStreakAfterDeviceTimeZoneChange } from "./lib/streaks";
import { addMs, nowIso } from "./lib/time";

/** The outbox tables and the Edge Function share this attempt budget. */
const MAX_ATTEMPTS = 5;
/** A claimed notification is invisible to other drains for this long. A failed send retries after it. */
const NOTIFICATION_LEASE_MS = 30_000;
/** Read cap per call. The 30 second cron picks up whatever is left. */
const SCAN_CAP = 1000;
const TARGET_INELIGIBLE = "notification target is no longer eligible";

const clampLimit = (limit: number | undefined) => Math.max(1, Math.min(limit ?? 50, 200));

/** `substring(btrim(text) for max)` that turns an empty result into undefined. */
function cleanText(value: string | null | undefined, max: number): string | undefined {
  const text = (value ?? "").trim();
  return text === "" ? undefined : Array.from(text).slice(0, max).join("");
}

/** Due, unsent, not failed. Ordered by `scheduled_for`. */
function pendingDueNotifications(ctx: ReaderCtx, now: string) {
  return ctx.db
    .query("notification_outbox")
    .withIndex("by_sent_at_failed_at_scheduled_for", (q) =>
      q.eq("sent_at", undefined).eq("failed_at", undefined).lte("scheduled_for", now),
    );
}

function pendingDueWidgetPushes(ctx: ReaderCtx, now: string) {
  return ctx.db
    .query("widget_push_outbox")
    .withIndex("by_sent_at_failed_at_scheduled_for", (q) =>
      q.eq("sent_at", undefined).eq("failed_at", undefined).lte("scheduled_for", now),
    );
}

/**
 * Port of the preference `case` in `claim_notification_batch` and
 * `claim_due_notifications`. A missing preference row blocks the kinds that
 * have a preference and allows the rest. `strictWidget` is the older
 * `claim_due_notifications` rule, which also gates silent widget pushes.
 */
function kindAllowed(
  row: Doc<"notification_outbox">,
  preference: Doc<"notification_preferences"> | null,
  strictWidget: boolean,
): boolean {
  switch (row.kind) {
    case "streak_reminder":
      return preference?.streak_reminders_enabled ?? false;
    case "daily_challenge_completed":
      return preference?.daily_challenge_enabled ?? false;
    case "partner_answered":
      return preference?.partner_answered_enabled ?? false;
    case "widget_updated":
      return (!strictWidget && row.apns_push_type !== "alert") || (preference?.widget_updates_enabled ?? false);
    case "location_updated":
      return preference?.location_updates_enabled ?? false;
    case "memory_created":
      return preference?.memories_enabled ?? false;
    case "thread_message_sent":
      return preference?.messages_enabled ?? false;
    default:
      return true;
  }
}

/**
 * The shared body of both notification claims. Fails every due row whose device
 * is gone or disabled or whose kind the user turned off, then returns up to
 * `limit` of the remaining due rows (oldest first) with their device.
 */
async function sweepAndPickNotifications(
  ctx: WriterCtx,
  now: string,
  limit: number,
  options: { strictWidget: boolean; respectAttemptBudget: boolean },
): Promise<{ row: Doc<"notification_outbox">; device: Doc<"user_devices"> }[]> {
  const devices = new Map<string, Doc<"user_devices"> | null>();
  const preferences = new Map<string, Doc<"notification_preferences"> | null>();
  const picked: { row: Doc<"notification_outbox">; device: Doc<"user_devices"> }[] = [];

  const rows = await pendingDueNotifications(ctx, now).take(SCAN_CAP);
  for (const row of rows) {
    if (!devices.has(row.target_device_id)) {
      devices.set(row.target_device_id, await getByUuid(ctx, "user_devices", row.target_device_id));
    }
    const device = devices.get(row.target_device_id)!;
    // A deleted device cascaded its outbox rows in Postgres, so a missing one is ineligible too.
    let eligible = device !== null && device.disabled_at === undefined;
    if (eligible) {
      if (!preferences.has(device!.user_id)) {
        preferences.set(
          device!.user_id,
          await ctx.db
            .query("notification_preferences")
            .withIndex("by_user_id", (q) => q.eq("user_id", device!.user_id))
            .unique(),
        );
      }
      eligible = kindAllowed(row, preferences.get(device!.user_id)!, options.strictWidget);
    }
    if (!eligible) {
      await ctx.db.patch(row._id, { failed_at: now, last_attempt_at: now, last_error: TARGET_INELIGIBLE });
      continue;
    }
    if (picked.length < limit && (!options.respectAttemptBudget || row.attempt_count < MAX_ATTEMPTS)) {
      picked.push({ row, device: device! });
    }
  }
  return picked;
}

/** Port of `internal.fail_exhausted_notification_claims`. Only rows whose lease has ended. */
async function failExhaustedNotifications(ctx: WriterCtx, now: string): Promise<number> {
  let failed = 0;
  for (const row of await pendingDueNotifications(ctx, now).take(SCAN_CAP)) {
    if (row.attempt_count >= MAX_ATTEMPTS) {
      await ctx.db.patch(row._id, {
        failed_at: now,
        last_error: row.last_error || "delivery attempt budget exhausted before a result was recorded",
      });
      failed += 1;
    }
  }
  return failed;
}

async function failExhaustedWidgetPushes(ctx: WriterCtx, now: string): Promise<number> {
  let failed = 0;
  for (const row of await pendingDueWidgetPushes(ctx, now).take(SCAN_CAP)) {
    if (row.attempt_count >= MAX_ATTEMPTS) {
      await ctx.db.patch(row._id, { failed_at: now, last_error: row.last_error ?? "attempts exhausted" });
      failed += 1;
    }
  }
  return failed;
}

export const fail_exhausted_notification_claims = internalMutation({
  args: { p_now: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await failExhaustedNotifications(ctx, optionalTimestampArg(args.p_now) ?? nowIso());
    return null;
  },
});

export const fail_exhausted_widget_push_claims = internalMutation({
  args: { p_now: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await failExhaustedWidgetPushes(ctx, optionalTimestampArg(args.p_now) ?? nowIso());
    return null;
  },
});

/**
 * Port of `internal.claim_notification_batch`, the claim the APNs drain uses.
 * Each claimed row gets a 30 second lease so a second drain skips it.
 */
export const claim_notification_batch = internalMutation({
  args: { p_limit: v.optional(v.number()), p_now: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    await failExhaustedNotifications(ctx, now);
    const picked = await sweepAndPickNotifications(ctx, now, clampLimit(args.p_limit), {
      strictWidget: false,
      respectAttemptBudget: true,
    });
    const lease = addMs(now, NOTIFICATION_LEASE_MS);
    const claimed = [];
    for (const { row, device } of picked) {
      await ctx.db.patch(row._id, {
        attempt_count: row.attempt_count + 1,
        last_attempt_at: now,
        last_error: undefined,
        scheduled_for: lease,
      });
      claimed.push({
        outbox_id: row.id,
        target_device_id: row.target_device_id,
        push_token: device.push_token,
        apns_environment: row.apns_environment,
        apns_push_type: row.apns_push_type,
        apns_collapse_id: row.apns_collapse_id ?? null,
        title: row.title ?? null,
        body: row.body ?? null,
        payload: row.payload,
      });
    }
    return claimed;
  },
});

/** Port of `internal.claim_due_notifications`. No lease and no attempt budget. */
export const claim_due_notifications = internalMutation({
  args: { p_limit: v.optional(v.number()), p_now: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const limit = args.p_limit ?? 100;
    if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
      fail("23514", "notification claim limit is out of range");
    }
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const picked = await sweepAndPickNotifications(ctx, now, limit, { strictWidget: true, respectAttemptBudget: false });
    const claimed = [];
    for (const { row, device } of picked) {
      await ctx.db.patch(row._id, { attempt_count: row.attempt_count + 1, last_attempt_at: now, last_error: undefined });
      claimed.push({
        outbox_id: row.id,
        recipient_user_id: row.recipient_user_id,
        target_device_id: row.target_device_id,
        push_token: device.push_token,
        push_token_hash: row.push_token_hash,
        apns_environment: row.apns_environment,
        kind: row.kind,
        payload_version: row.payload_version,
        redaction_level: row.redaction_level,
        payload: row.payload,
        apns_push_type: row.apns_push_type,
        apns_collapse_id: row.apns_collapse_id ?? null,
        attempt_count: row.attempt_count + 1,
      });
    }
    return claimed;
  },
});

/** Port of `internal.mark_notification_result`. */
export const mark_notification_result = internalMutation({
  args: {
    p_outbox_id: v.string(),
    p_success: v.boolean(),
    p_provider_message_id: v.optional(v.union(v.null(), v.string())),
    p_error: v.optional(v.union(v.null(), v.string())),
    p_invalid_token: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "notification_outbox", uuidArg(args.p_outbox_id));
    if (!row || row.sent_at !== undefined || row.failed_at !== undefined) return null;
    const now = nowIso();
    if (args.p_success) {
      await ctx.db.patch(row._id, {
        sent_at: now,
        provider_message_id: cleanText(args.p_provider_message_id, Infinity),
        last_error: undefined,
      });
    } else {
      await ctx.db.patch(row._id, {
        last_error: cleanText(args.p_error, 2000) ?? "delivery failed",
        failed_at: args.p_invalid_token || row.attempt_count >= MAX_ATTEMPTS ? now : undefined,
      });
    }
    return null;
  },
});

/** Port of `internal.mark_notification_sent`. */
export const mark_notification_sent = internalMutation({
  args: { p_outbox_id: v.string(), p_provider_message_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "notification_outbox", uuidArg(args.p_outbox_id));
    if (!row || row.sent_at !== undefined) return false;
    await ctx.db.patch(row._id, {
      provider_message_id: cleanText(args.p_provider_message_id, Infinity),
      sent_at: nowIso(),
      failed_at: undefined,
      last_error: undefined,
    });
    return true;
  },
});

/** Port of `internal.mark_notification_failed`. */
export const mark_notification_failed = internalMutation({
  args: { p_outbox_id: v.string(), p_error: v.optional(v.union(v.null(), v.string())), p_terminal: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "notification_outbox", uuidArg(args.p_outbox_id));
    if (!row || row.sent_at !== undefined) return false;
    await ctx.db.patch(row._id, {
      last_error: cleanText(args.p_error, 2000),
      failed_at: args.p_terminal ? nowIso() : undefined,
    });
    return true;
  },
});

/** Port of `internal.claim_widget_push_batch`. There is no lease: a failed push retries on the next drain. */
export const claim_widget_push_batch = internalMutation({
  args: { p_limit: v.optional(v.number()), p_now: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    await failExhaustedWidgetPushes(ctx, now);
    const limit = clampLimit(args.p_limit);
    const claimed = [];
    for (const row of await pendingDueWidgetPushes(ctx, now).take(SCAN_CAP)) {
      if (claimed.length >= limit) break;
      if (row.attempt_count >= MAX_ATTEMPTS) continue;
      const device = await getByUuid(ctx, "widget_push_devices", row.target_widget_device_id);
      if (!device || device.disabled_at !== undefined) continue;
      await ctx.db.patch(row._id, { attempt_count: row.attempt_count + 1, last_attempt_at: now });
      claimed.push({
        outbox_id: row.id,
        target_widget_device_id: device.id,
        widget_push_token: device.widget_push_token,
        apns_environment: row.apns_environment,
        apns_collapse_id: row.apns_collapse_id ?? null,
        payload: row.payload,
      });
    }
    return claimed;
  },
});

/** Port of `internal.mark_widget_push_result`. */
export const mark_widget_push_result = internalMutation({
  args: {
    p_outbox_id: v.string(),
    p_success: v.boolean(),
    p_provider_message_id: v.optional(v.union(v.null(), v.string())),
    p_error: v.optional(v.union(v.null(), v.string())),
    p_invalid_token: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "widget_push_outbox", uuidArg(args.p_outbox_id));
    if (!row) return null;
    if (args.p_success) {
      await ctx.db.patch(row._id, {
        sent_at: nowIso(),
        provider_message_id: args.p_provider_message_id ?? undefined,
        last_error: undefined,
      });
    } else {
      await ctx.db.patch(row._id, {
        failed_at: args.p_invalid_token || row.attempt_count >= MAX_ATTEMPTS ? nowIso() : row.failed_at,
        last_error: args.p_error ?? undefined,
      });
    }
    return null;
  },
});

/** Port of `internal.has_due_push_notification_work`. */
export const has_due_push_notification_work = internalQuery({
  args: { p_now: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    for await (const row of pendingDueNotifications(ctx, now)) {
      if (row.attempt_count < MAX_ATTEMPTS) return true;
    }
    for await (const row of pendingDueWidgetPushes(ctx, now)) {
      if (row.attempt_count >= MAX_ATTEMPTS) continue;
      const device = await getByUuid(ctx, "widget_push_devices", row.target_widget_device_id);
      if (device && device.disabled_at === undefined) return true;
    }
    return false;
  },
});

const deviceKind = v.union(v.literal("app"), v.literal("widget"));

/** The drain writes back an environment APNs confirmed, so later sends skip the fallback host. */
export const persist_device_environment = internalMutation({
  args: { kind: deviceKind, device_id: v.string(), apns_environment: v.union(v.literal("sandbox"), v.literal("production")) },
  handler: async (ctx, args) => {
    const id = uuidArg(args.device_id);
    if (args.kind === "app") {
      const device = await getByUuid(ctx, "user_devices", id);
      if (device) await ctx.db.patch(device._id, withTouch(device, { apns_environment: args.apns_environment }));
    } else {
      const device = await getByUuid(ctx, "widget_push_devices", id);
      if (device) await ctx.db.patch(device._id, withTouch(device, { apns_environment: args.apns_environment }));
    }
    return null;
  },
});

/** Retires a device token APNs rejected on every environment. */
export const disable_device = internalMutation({
  args: { kind: deviceKind, device_id: v.string() },
  handler: async (ctx, args) => {
    const id = uuidArg(args.device_id);
    const now = nowIso();
    if (args.kind === "app") {
      const device = await getByUuid(ctx, "user_devices", id);
      if (!device || device.disabled_at !== undefined) return null;
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
    return null;
  },
});
