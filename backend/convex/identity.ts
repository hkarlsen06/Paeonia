import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { action, mutation, query, type MutationCtx } from "./_generated/server";
import { requestAccountDeletion, runDeleteAccount } from "./accountDeletion";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { authProviderFromIdentity, ensureCurrentUser, requireUserId, requireUserIdIncludingDeleted } from "./lib/auth";
import { orNull, type ReaderCtx, withTouch } from "./lib/db";
import { checkViolation, fail, uniqueViolation } from "./lib/errors";
import { newUuid, optionalUuidArg, uuidArg } from "./lib/ids";
import { sha256Hex } from "./lib/crypto";
import { isValidQuestionTimeMinutes } from "./lib/questionTime";
import { findProfile, profileRow, profileSummaryRow, updateProfile } from "./lib/profiles";
import { refreshStreakAfterDeviceTimeZoneChange } from "./lib/streaks";
import { nowIso } from "./lib/time";

/** Postgres `btrim`: trims spaces only. */
const btrim = (value: string) => value.replace(/^ +| +$/g, "");
const charLength = (value: string) => Array.from(value).length;
const optionalText = v.optional(v.union(v.null(), v.string()));

async function requireActiveProfile(ctx: MutationCtx, userId: string) {
  const profile = await findProfile(ctx, userId);
  if (!profile || profile.deleted_at !== undefined) {
    return fail("P0002", "active profile was not found");
  }
  return profile;
}

// ---- profile ----

export const ensure_current_user = mutation({
  args: {},
  handler: async (ctx) => {
    // ensureCurrentUser refuses accounts with a pending or finished deletion.
    const userId = await ensureCurrentUser(ctx);
    const profile = await findProfile(ctx, userId);
    return profile ? profileRow(profile) : null;
  },
});

export const complete_profile_onboarding = mutation({
  args: { p_time_zone_id: v.string(), p_profile_photo_asset_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const photoId = optionalUuidArg(args.p_profile_photo_asset_id);
    const zoneLength = charLength(btrim(args.p_time_zone_id));
    if (zoneLength < 1 || zoneLength > 128) {
      checkViolation("profiles", "profiles_time_zone_id_check");
    }
    const profile = await requireActiveProfile(ctx, userId);
    const now = nowIso();
    const updated = await updateProfile(ctx, profile, {
      time_zone_id: args.p_time_zone_id,
      time_zone_updated_at: now,
      onboarding_completed_at: now,
      ...(photoId ? { profile_photo_asset_id: photoId } : {}),
    });
    return profileRow(updated);
  },
});

export const update_own_profile = mutation({
  args: { p_display_name: v.string(), p_profile_photo_asset_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const displayName = btrim(args.p_display_name);
    if (charLength(displayName) < 1 || charLength(displayName) > 80 || /\s/u.test(displayName)) {
      fail("23514", "display name must be one name between 1 and 80 characters");
    }
    const photoId = optionalUuidArg(args.p_profile_photo_asset_id);
    const profile = await requireActiveProfile(ctx, userId);
    const updated = await updateProfile(ctx, profile, {
      display_name: displayName,
      profile_photo_asset_id: photoId,
    });
    return [profileSummaryRow(updated)];
  },
});

export const set_own_provider_profile_photo = mutation({
  args: { p_profile_photo_asset_id: v.union(v.null(), v.string()), p_source: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_profile_photo_asset_id === null || args.p_source !== "google") {
      fail("23514", "provider profile photo input is invalid");
    }
    const photoId = uuidArg(args.p_profile_photo_asset_id);
    const profile = await requireActiveProfile(ctx, userId);
    const updated = await updateProfile(ctx, profile, {
      provider_profile_photo_asset_id: photoId,
      provider_profile_photo_source: "google",
    });
    return [profileSummaryRow(updated)];
  },
});

// ---- devices ----

const DEVICE_CHECKS = {
  locale: { min: 2, max: 64, constraint: "user_devices_locale_check" },
  time_zone_id: { min: 1, max: 128, constraint: "user_devices_time_zone_id_check" },
  app_version: { min: 1, max: 64, constraint: "user_devices_app_version_check" },
} as const;

function deviceText(column: keyof typeof DEVICE_CHECKS, value: string | null | undefined): string | undefined {
  const trimmed = btrim(value ?? "");
  if (trimmed === "") return undefined;
  const { min, max, constraint } = DEVICE_CHECKS[column];
  if (charLength(trimmed) < min || charLength(trimmed) > max) {
    checkViolation("user_devices", constraint);
  }
  return trimmed;
}

export const register_user_device = mutation({
  args: {
    p_platform: v.union(v.null(), v.string()),
    p_push_token: v.union(v.null(), v.string()),
    p_apns_environment: v.union(v.null(), v.string()),
    p_locale: optionalText,
    p_time_zone_id: optionalText,
    p_app_version: optionalText,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const platform = args.p_platform;
    if (platform !== "ios" && platform !== "ipados") {
      return fail("23514", "unsupported device platform");
    }
    const token = args.p_push_token;
    if (token === null || charLength(token) < 20 || charLength(token) > 4096) {
      return fail("23514", "invalid push token");
    }
    const environment = args.p_apns_environment;
    if (environment !== "sandbox" && environment !== "production") {
      return fail("23514", "unsupported APNs environment");
    }

    const locale = deviceText("locale", args.p_locale);
    const timeZoneId = deviceText("time_zone_id", args.p_time_zone_id);
    const appVersion = deviceText("app_version", args.p_app_version);
    const tokenHash = await sha256Hex(token);
    const now = nowIso();

    await assertNoPendingAccountDeletion(ctx, userId);
    const active = await ctx.db
      .query("user_devices")
      .withIndex("by_push_token_hash_apns_environment_disabled_at", (q) =>
        q.eq("push_token_hash", tokenHash).eq("apns_environment", environment).eq("disabled_at", undefined),
      )
      .collect();

    // A token belongs to one account. Disable it for anyone else.
    for (const other of active) {
      if (other.user_id === userId) continue;
      await assertNoPendingAccountDeletion(ctx, other.user_id);
      await ctx.db.patch(other._id, withTouch(other, { disabled_at: now }));
      await refreshStreakAfterDeviceTimeZoneChange(ctx, other.user_id, { ...other, disabled_at: now }, other);
    }

    const own = active
      .filter((device) => device.user_id === userId)
      .sort((a, b) => (a.updated_at === b.updated_at ? (a.id < b.id ? -1 : 1) : a.updated_at < b.updated_at ? 1 : -1))[0];
    if (!own) {
      const id = newUuid();
      await ctx.db.insert("user_devices", {
        id,
        user_id: userId,
        platform,
        push_token: token,
        push_token_hash: tokenHash,
        apns_environment: environment,
        locale,
        time_zone_id: timeZoneId,
        app_version: appVersion,
        last_seen_at: now,
        revision: 1,
        created_at: now,
        updated_at: now,
      });
      await refreshStreakAfterDeviceTimeZoneChange(ctx, userId, {
        time_zone_id: timeZoneId,
        last_seen_at: now,
        disabled_at: null,
      });
      return id;
    }

    await ctx.db.patch(
      own._id,
      withTouch(own, {
        platform,
        push_token: token,
        push_token_hash: tokenHash,
        apns_environment: environment,
        locale,
        time_zone_id: timeZoneId,
        app_version: appVersion,
        last_seen_at: now,
        disabled_at: undefined,
      }),
    );
    await refreshStreakAfterDeviceTimeZoneChange(
      ctx,
      userId,
      { time_zone_id: timeZoneId, last_seen_at: now, disabled_at: null },
      own,
    );
    return own.id;
  },
});

export const disable_user_device = mutation({
  args: { p_device_id: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const deviceId = optionalUuidArg(args.p_device_id);
    const device = deviceId
      ? await ctx.db
          .query("user_devices")
          .withIndex("by_uuid", (q) => q.eq("id", deviceId))
          .unique()
      : null;
    if (!device || device.user_id !== userId) {
      return false;
    }
    await assertNoPendingAccountDeletion(ctx, userId);
    const disabledAt = device.disabled_at ?? nowIso();
    await ctx.db.patch(device._id, withTouch(device, { disabled_at: disabledAt }));
    await refreshStreakAfterDeviceTimeZoneChange(ctx, userId, { ...device, disabled_at: disabledAt }, device);
    return true;
  },
});

// ---- notification preferences ----

const NOTIFICATION_COLUMNS = [
  "streak_reminders_enabled",
  "daily_challenge_enabled",
  "partner_answered_enabled",
  "messages_enabled",
  "widget_updates_enabled",
  "memories_enabled",
  "games_enabled",
] as const;

async function findNotificationPreferences(ctx: ReaderCtx, userId: string) {
  return await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
}

function notificationPreferencesRow(row: NonNullable<Awaited<ReturnType<typeof findNotificationPreferences>>>) {
  return {
    user_id: row.user_id,
    streak_reminders_enabled: row.streak_reminders_enabled,
    daily_challenge_enabled: row.daily_challenge_enabled,
    partner_answered_enabled: row.partner_answered_enabled,
    widget_updates_enabled: row.widget_updates_enabled,
    location_updates_enabled: row.location_updates_enabled,
    lock_screen_detail_level: row.lock_screen_detail_level,
    revision: row.revision,
    created_at: row.created_at,
    updated_at: row.updated_at,
    memories_enabled: row.memories_enabled,
    messages_enabled: row.messages_enabled,
    games_enabled: row.games_enabled,
    question_time_enabled: row.question_time_enabled,
    question_time_minutes: row.question_time_minutes,
  };
}

export const get_notification_preferences = query({
  args: {},
  handler: async (ctx) => {
    const row = await findNotificationPreferences(ctx, await requireUserId(ctx));
    if (!row) return fail("P0002", "notification preferences were not found");
    return notificationPreferencesRow(row);
  },
});

export const set_notification_preference = mutation({
  args: { p_column: v.string(), p_enabled: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const column = NOTIFICATION_COLUMNS.find((name) => name === args.p_column);
    if (!column) {
      return fail("23514", "unsupported notification preference");
    }
    await assertNoPendingAccountDeletion(ctx, userId);
    const row = await findNotificationPreferences(ctx, userId);
    if (!row) return fail("P0002", "notification preferences were not found");
    await ctx.db.patch(row._id, withTouch(row, { [column]: args.p_enabled }));
    return notificationPreferencesRow((await findNotificationPreferences(ctx, userId))!);
  },
});

/** Turns the "question time" reminder on or off and sets its time, in minutes after local midnight. */
export const set_question_time_reminder = mutation({
  args: { p_enabled: v.boolean(), p_minutes: v.number() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (!isValidQuestionTimeMinutes(args.p_minutes)) {
      return fail("23514", "question time must be a whole minute of the day");
    }
    await assertNoPendingAccountDeletion(ctx, userId);
    const row = await findNotificationPreferences(ctx, userId);
    if (!row) return fail("P0002", "notification preferences were not found");
    await ctx.db.patch(
      row._id,
      withTouch(row, { question_time_enabled: args.p_enabled, question_time_minutes: args.p_minutes }),
    );
    return notificationPreferencesRow((await findNotificationPreferences(ctx, userId))!);
  },
});

// ---- privacy requests ----

function privacyRequestRow(row: Doc<"privacy_requests">) {
  return {
    id: row.id,
    user_id: row.user_id,
    request_kind: row.request_kind,
    status: row.status,
    requested_at: row.requested_at,
    verified_at: orNull(row.verified_at),
    completed_at: orNull(row.completed_at),
    cancelled_at: orNull(row.cancelled_at),
    contact_email: orNull(row.contact_email),
    requester_note: orNull(row.requester_note),
    visible_status_message: orNull(row.visible_status_message),
    revision: row.revision,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

export const get_privacy_requests = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const rows = await ctx.db
      .query("privacy_requests")
      .withIndex("by_user_id_requested_at", (q) => q.eq("user_id", userId))
      .order("desc")
      .take(100);
    return rows.map(privacyRequestRow);
  },
});

const REQUEST_KINDS = ["access", "export", "deletion", "correction"] as const;

export const create_privacy_request = mutation({
  args: { p_id: v.string(), p_kind: v.string(), p_requester_note: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const id = uuidArg(args.p_id);
    const kind = REQUEST_KINDS.find((name) => name === args.p_kind);
    if (!kind) {
      return checkViolation("privacy_requests", "privacy_requests_request_kind_check");
    }
    const note = args.p_requester_note ?? undefined;
    if (note !== undefined && charLength(note) > 4000) {
      checkViolation("privacy_requests", "privacy_requests_requester_note_check");
    }
    await assertNoPendingAccountDeletion(ctx, userId);

    const duplicate = await ctx.db
      .query("privacy_requests")
      .withIndex("by_uuid", (q) => q.eq("id", id))
      .unique();
    if (duplicate) uniqueViolation("privacy_requests_pkey");
    // Two devices can file the same request at once. The app already shows an open request of
    // the same kind instead of filing another, so return it. Deletion keeps the SQL unique index error.
    for (const status of ["submitted", "verifying", "processing"] as const) {
      const open = await ctx.db
        .query("privacy_requests")
        .withIndex("by_user_id_request_kind_status", (q) =>
          q.eq("user_id", userId).eq("request_kind", kind).eq("status", status),
        )
        .first();
      if (!open) continue;
      if (kind === "deletion") uniqueViolation("privacy_requests_active_deletion_user_idx");
      return privacyRequestRow(open);
    }

    const now = nowIso();
    await ctx.db.insert("privacy_requests", {
      id,
      user_id: userId,
      request_kind: kind,
      status: "submitted",
      requested_at: now,
      requester_note: note,
      revision: 1,
      created_at: now,
      updated_at: now,
    });
    const row = await ctx.db
      .query("privacy_requests")
      .withIndex("by_uuid", (q) => q.eq("id", id))
      .unique();
    return privacyRequestRow(row!);
  },
});

// ---- account deletion ----

export const request_account_deletion = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserIdIncludingDeleted(ctx);
    const identity = (await ctx.auth.getUserIdentity())!;
    return await requestAccountDeletion(ctx, userId, authProviderFromIdentity(identity));
  },
});

/**
 * Deletes the caller's account: tombstones the data, revokes Sign in with Apple when the account
 * uses it, and deletes the Clerk user. `appleAuthorizationCode` is a fresh code from Sign in with
 * Apple, needed to revoke the token.
 *
 * Returns `{ requestId, authDeleteStatus, appleRevocation, requiresManualAppleRevocation,
 * revocationErrorCode? }`. `authDeleteStatus` is `completed` or `queued` (a background job
 * finishes the Clerk deletion). Fails with `not_signed_in` or `account_deletion_failed`.
 */
export const delete_account = action({
  args: { appleAuthorizationCode: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => await runDeleteAccount(ctx, args.appleAuthorizationCode),
});
