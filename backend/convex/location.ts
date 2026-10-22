import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { canAccessCoupleContent, getCurrentEntitledCoupleId } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { runClientOperation } from "./lib/clientOperations";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { optionalTimestampArg, timestampArg, uuidArg } from "./lib/ids";
import { isSharingNow, MAX_LOCATION_PAUSE_MS } from "./lib/locationPause";
import {
  enqueueLockScreenRefreshForPartner,
  enqueueLockScreenRefreshForUser,
  enqueueNotificationForUser,
  enqueuePartnerNotification,
  LOCK_SCREEN_LOCATION_DELAY_SECONDS,
  LOCK_SCREEN_REFRESH_DELAY_SECONDS,
} from "./lib/notifications";
import { addMs, nowIso } from "./lib/time";
import { locationPermission } from "./lib/validators";
import type { WriterCtx } from "./lib/db";

const nullable = <T extends ReturnType<typeof v.string> | ReturnType<typeof v.number> | ReturnType<typeof v.boolean>>(
  validator: T,
) => v.optional(v.union(v.null(), validator));

const LOCATION_SOURCES = ["foreground_open", "manual_refresh", "settings_toggle", "background"] as const;
type LocationSource = (typeof LOCATION_SOURCES)[number];

/** `lower(btrim(coalesce(p_source, default)))`, validated against the check constraint list. */
function resolveSource(source: string | null | undefined, fallback: LocationSource): LocationSource {
  const resolved = (source ?? fallback).trim().toLowerCase();
  if (!(LOCATION_SOURCES as readonly string[]).includes(resolved)) {
    fail("23514", "location source is not supported");
  }
  return resolved as LocationSource;
}

/** Rounds to a numeric(p, scale) column the way Postgres does (half away from zero). */
function roundTo(value: number, scale: number): number {
  const factor = 10 ** scale;
  return (Math.sign(value) * Math.round(Math.abs(value) * factor)) / factor;
}

function locationRow(row: Doc<"latest_partner_locations">) {
  return {
    couple_id: row.couple_id,
    user_id: row.user_id,
    latitude: row.latitude,
    longitude: row.longitude,
    accuracy_m: orNull(row.accuracy_m),
    captured_at: row.captured_at,
    received_at: row.received_at,
    updated_at: row.updated_at,
  };
}

/** Port of the `delete_latest_locations_on_preference_disable` trigger body. */
async function deleteLatestLocationForUser(ctx: WriterCtx, coupleId: string, userId: string): Promise<void> {
  const rows = await ctx.db
    .query("latest_partner_locations")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .collect();
  for (const row of rows) {
    await ctx.db.delete(row._id);
  }
}

/**
 * Ends a pause: clears `paused_until` and refreshes the person's own Lock Screen, because the
 * distance comes back there. The partner's Lock Screen kept the last distance all along. The cron
 * and the first location update after the pause's time both call it.
 */
async function endLocationPause(ctx: WriterCtx, preference: Doc<"location_sharing_preferences">): Promise<void> {
  await ctx.db.patch(preference._id, withUpdatedAt({ paused_until: undefined }));
  await enqueueLockScreenRefreshForUser(ctx, {
    couple_id: preference.couple_id,
    user_id: preference.user_id,
    delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
  });
}

/**
 * Port of both `update_latest_partner_location` overloads. The overload without
 * `p_accuracy_m` is the same function with the argument omitted.
 */
export const update_latest_partner_location = mutation({
  args: {
    p_couple_id: v.string(),
    p_latitude: nullable(v.number()),
    p_longitude: nullable(v.number()),
    p_accuracy_m: nullable(v.number()),
    p_captured_at: nullable(v.string()),
    p_source: nullable(v.string()),
    p_client_operation_id: v.string(),
    p_client_id: v.string(),
    p_client_sequence: v.number(),
    p_local_created_at: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      fail("42501", "active entitled couple access is required");
    }
    const source = resolveSource(args.p_source, "foreground_open");

    const latitude = args.p_latitude ?? null;
    const longitude = args.p_longitude ?? null;
    const accuracy = args.p_accuracy_m ?? null;
    const capturedAtInput = optionalTimestampArg(args.p_captured_at);
    if (
      latitude === null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude === null ||
      longitude < -180 ||
      longitude > 180 ||
      (accuracy !== null && (accuracy < 0 || accuracy > 100000)) ||
      capturedAtInput === undefined ||
      capturedAtInput > addMs(nowIso(), 5 * 60_000)
    ) {
      fail("23514", "location payload is out of range");
    }
    const capturedAt = capturedAtInput;

    const preference = await ctx.db
      .query("location_sharing_preferences")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
      .unique();
    if (!preference?.is_enabled) {
      fail("42501", "location sharing must be enabled before updating location");
    }
    if (preference.paused_until !== undefined) {
      // A phone sends nothing during a pause. This refuses a late or stray update. Once the time has
      // passed, the first update ends the pause itself, so it never waits for the cron.
      if (preference.paused_until > nowIso()) {
        fail("42501", "location sharing is paused");
      }
      await endLocationPause(ctx, preference);
    }

    const operationId = uuidArg(args.p_client_operation_id);
    const clientId = uuidArg(args.p_client_id);
    const localCreatedAt = optionalTimestampArg(args.p_local_created_at)!;

    const stored = await runClientOperation(
      ctx,
      userId,
      {
        client_operation_id: operationId,
        client_id: clientId,
        client_sequence: args.p_client_sequence,
        local_created_at: localCreatedAt,
        operation_kind: "update_latest_partner_location",
        idempotency_scope: "location",
        request: {
          kind: "update_latest_partner_location",
          couple_id: coupleId,
          user_id: userId,
          latitude,
          longitude,
          accuracy_m: accuracy,
          captured_at: capturedAt,
          source,
        },
      },
      async () => {
        await assertNoPendingAccountDeletion(ctx, userId);
        const existing = await ctx.db
          .query("latest_partner_locations")
          .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
          .unique();

        // A newer stored location wins. The stale write is a successful no-op that returns the stored row.
        if (existing && existing.captured_at > capturedAt) {
          return locationRow(existing);
        }

        const now = nowIso();
        const values = {
          latitude: roundTo(latitude, 6),
          longitude: roundTo(longitude, 6),
          accuracy_m: accuracy === null ? undefined : roundTo(accuracy, 2),
          captured_at: capturedAt,
          received_at: now,
          source,
          client_operation_id: operationId,
          client_id: clientId,
          client_sequence: args.p_client_sequence,
        };
        let row: Doc<"latest_partner_locations">;
        if (existing) {
          await ctx.db.patch(existing._id, withUpdatedAt(values));
          row = (await ctx.db.get(existing._id))!;
        } else {
          const id = await ctx.db.insert("latest_partner_locations", {
            couple_id: coupleId,
            user_id: userId,
            ...values,
            updated_at: now,
          });
          row = (await ctx.db.get(id))!;
        }

        // Tell the partner only when they share their own location too.
        const members = await ctx.db
          .query("couple_members")
          .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
          .collect();
        let partnerShares = false;
        for (const member of members) {
          if (member.user_id === userId) continue;
          const partnerPreference = await ctx.db
            .query("location_sharing_preferences")
            .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", member.user_id))
            .unique();
          if (isSharingNow(partnerPreference)) partnerShares = true;
        }
        if (partnerShares) {
          // The distance on the partner's Lock Screen changes with every fix. Updates come often, so this lane sends at most one push per half hour.
          await enqueueLockScreenRefreshForPartner(ctx, {
            couple_id: coupleId,
            actor_user_id: userId,
            delay_seconds: LOCK_SCREEN_LOCATION_DELAY_SECONDS,
            lane: "location",
          });
          await enqueuePartnerNotification(ctx, {
            couple_id: coupleId,
            actor_user_id: userId,
            kind: "location_updated",
            payload: {
              type: "location_updated",
              couple_id: coupleId,
              actor_user_id: userId,
              captured_at: row.captured_at,
              route: "location",
            },
            dedupe_key: `location_updated:${coupleId}:${userId}:${row.captured_at}`,
            redaction_level: "private",
            apns_push_type: "background",
            apns_collapse_id: `location:${coupleId}`,
            scheduled_for: now,
          });
        }
        return locationRow(row);
      },
    );
    return [stored];
  },
});

/**
 * Port of both `update_location_sharing_preference` overloads. The overload
 * without `p_consent_version` is the same function with the argument omitted.
 */
export const update_location_sharing_preference = mutation({
  args: {
    p_couple_id: v.string(),
    p_is_enabled: nullable(v.boolean()),
    p_consent_version: nullable(v.string()),
    p_source: nullable(v.string()),
    // Pauses sharing until this time. Only valid with `p_is_enabled: true`. Omitted or null ends a pause.
    p_paused_until: nullable(v.string()),
    p_client_operation_id: v.string(),
    p_client_id: v.string(),
    p_client_sequence: v.number(),
    p_local_created_at: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_is_enabled === null || args.p_is_enabled === undefined) {
      fail("23514", "location sharing state is required");
    }
    const isEnabled = args.p_is_enabled;
    const source = resolveSource(args.p_source, "settings_toggle");
    const consentVersion = (args.p_consent_version ?? "").trim() || undefined;
    if (isEnabled && (consentVersion === undefined || Array.from(consentVersion).length > 80)) {
      fail("23514", "location sharing consent version is required");
    }
    const pausedUntilInput = optionalTimestampArg(args.p_paused_until);
    if (pausedUntilInput !== undefined && !isEnabled) {
      fail("23514", "location sharing can only be paused while it is on");
    }
    if (pausedUntilInput !== undefined && pausedUntilInput > addMs(nowIso(), MAX_LOCATION_PAUSE_MS)) {
      fail("23514", "location sharing pause is too long");
    }
    const coupleId = uuidArg(args.p_couple_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      fail("42501", "active entitled couple access is required");
    }

    const stored = await runClientOperation(
      ctx,
      userId,
      {
        client_operation_id: uuidArg(args.p_client_operation_id),
        client_id: uuidArg(args.p_client_id),
        client_sequence: args.p_client_sequence,
        local_created_at: optionalTimestampArg(args.p_local_created_at)!,
        operation_kind: "update_location_sharing_preference",
        idempotency_scope: "location",
        request: {
          kind: "update_location_sharing_preference",
          couple_id: coupleId,
          user_id: userId,
          is_enabled: isEnabled,
          consent_version: consentVersion ?? "",
          paused_until: pausedUntilInput ?? null,
          source,
        },
      },
      async () => {
        await assertNoPendingAccountDeletion(ctx, userId);
        const now = nowIso();
        // A pause that is already over when it arrives, such as one queued offline, changes nothing.
        const pausedUntil = pausedUntilInput !== undefined && pausedUntilInput > now ? pausedUntilInput : undefined;
        const existing = await ctx.db
          .query("location_sharing_preferences")
          .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
          .unique();
        let row: Doc<"location_sharing_preferences">;
        if (existing) {
          await ctx.db.patch(
            existing._id,
            withUpdatedAt({
              is_enabled: isEnabled,
              // A pause or an end of a pause does not restart "enabled".
              enabled_at: isEnabled ? (existing.is_enabled ? (existing.enabled_at ?? now) : now) : existing.enabled_at,
              disabled_at: isEnabled ? undefined : now,
              paused_until: pausedUntil,
              consent_version: isEnabled ? consentVersion : existing.consent_version,
              source,
              // Turning sharing back on later does not bring it back by itself.
              updates_while_closed: isEnabled ? existing.updates_while_closed : false,
            }),
          );
          row = (await ctx.db.get(existing._id))!;
        } else {
          const id = await ctx.db.insert("location_sharing_preferences", {
            couple_id: coupleId,
            user_id: userId,
            is_enabled: isEnabled,
            enabled_at: isEnabled ? now : undefined,
            disabled_at: isEnabled ? undefined : now,
            consent_version: isEnabled ? consentVersion : undefined,
            source,
            updates_while_closed: false,
            paused_until: pausedUntil,
            created_at: now,
            updated_at: now,
          });
          row = (await ctx.db.get(id))!;
        }
        // Turning sharing off removes the position. A pause keeps it, so the partner goes on seeing
        // where the person last was and when, and nothing tells them about the pause.
        if (!isEnabled) {
          await deleteLatestLocationForUser(ctx, coupleId, userId);
        }
        // Turning sharing on or off shows or hides the distance on the partner's Lock Screen. A pause
        // only hides it on the person's own Lock Screen.
        if ((existing?.is_enabled ?? false) !== row.is_enabled) {
          await enqueueLockScreenRefreshForPartner(ctx, {
            couple_id: coupleId,
            actor_user_id: userId,
            delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
          });
        }
        if (isSharingNow(existing) !== isSharingNow(row)) {
          await enqueueLockScreenRefreshForUser(ctx, {
            couple_id: coupleId,
            user_id: userId,
            delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
          });
        }
        return {
          couple_id: row.couple_id,
          user_id: row.user_id,
          is_enabled: row.is_enabled,
          enabled_at: orNull(row.enabled_at),
          disabled_at: orNull(row.disabled_at),
          paused_until: orNull(row.paused_until),
          updated_at: row.updated_at,
        };
      },
    );
    return [stored];
  },
});

/**
 * Cron: ends every pause whose time has passed and, for a phone that sends moves while Paeonia is
 * closed, wakes it with a silent push so it sends where it is now. Without the push, the partner
 * would see no position until the person next moved a long way. A pause is also ended by the first
 * location update after its time, so a phone that is awake never waits for this run.
 */
export const resume_paused_location_sharing = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = nowIso();
    const due = await ctx.db
      .query("location_sharing_preferences")
      .withIndex("by_paused_until", (q) => q.gt("paused_until", "").lte("paused_until", now))
      .take(200);
    for (const preference of due) {
      const pausedUntil = preference.paused_until!;
      await endLocationPause(ctx, preference);
      if (preference.updates_while_closed && preference.is_enabled) {
        await enqueueNotificationForUser(ctx, {
          recipient_user_id: preference.user_id,
          kind: "location_pause_ended",
          payload: { type: "location_pause_ended", couple_id: preference.couple_id },
          dedupe_key: `location_pause_ended:${preference.couple_id}:${preference.user_id}:${pausedUntil}`,
          apns_push_type: "background",
          apns_collapse_id: `location-resume:${preference.couple_id}`,
        });
      }
    }
    return due.length;
  },
});

/**
 * The phone reports whether it sends moves while Paeonia is closed and which
 * iOS location access it has. It reports when either changes and when the app
 * opens. `p_updates_while_closed: null` asks for the stored choice without
 * changing it, which a phone does after a new sign-in to restore the choice.
 * The choice is only kept while sharing is on. A report older than the stored
 * one changes nothing. Returns the stored choice.
 */
export const report_location_device_state = mutation({
  args: {
    p_couple_id: v.string(),
    p_updates_while_closed: v.union(v.null(), v.boolean()),
    p_permission: locationPermission,
    p_reported_at: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const reportedAt = timestampArg(args.p_reported_at);
    if (reportedAt > addMs(nowIso(), 5 * 60_000)) {
      fail("23514", "location device report time is out of range");
    }
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      fail("42501", "active entitled couple access is required");
    }
    await assertNoPendingAccountDeletion(ctx, userId);

    const existing = await ctx.db
      .query("location_sharing_preferences")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
      .unique();
    // Without a row, sharing was never turned on, so there is nothing to keep.
    if (!existing) {
      return { updates_while_closed: false };
    }
    if (existing.device_state_reported_at !== undefined && existing.device_state_reported_at >= reportedAt) {
      return { updates_while_closed: existing.updates_while_closed };
    }
    const updatesWhileClosed =
      args.p_updates_while_closed === null
        ? existing.updates_while_closed
        : args.p_updates_while_closed && existing.is_enabled;
    // `updated_at` stays, because it times sharing changes the partner can see.
    await ctx.db.patch(existing._id, {
      updates_while_closed: updatesWhileClosed,
      location_permission: args.p_permission,
      device_state_reported_at: reportedAt,
    });
    return { updates_while_closed: updatesWhileClosed };
  },
});

const VIEWER_STATUSES = ["active", "left", "ended_notice_pending", "ended_notice_seen"];

/** Port of `get_partner_location_visibility`. */
export const get_partner_location_visibility = query({
  args: { p_couple_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId =
      args.p_couple_id === null || args.p_couple_id === undefined
        ? await getCurrentEntitledCoupleId(ctx, userId)
        : uuidArg(args.p_couple_id);

    const couple = await getByUuid(ctx, "couples", coupleId);
    const viewer = couple
      ? await ctx.db
          .query("couple_members")
          .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
          .unique()
      : null;
    if (!couple || !viewer || !VIEWER_STATUSES.includes(viewer.status)) {
      fail("42501", "relationship was not found");
    }

    const activeMembers = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
      .collect();
    const partner = activeMembers
      .filter((member) => member.user_id !== userId)
      .sort((a, b) =>
        a.joined_at !== b.joined_at ? (a.joined_at < b.joined_at ? 1 : -1) : a.user_id < b.user_id ? -1 : 1,
      )[0];

    const now = nowIso();
    const result = (
      state: string,
      viewerEnabled: boolean,
      partnerEnabled: boolean,
      updatedAt: string,
      location?: Doc<"latest_partner_locations">,
      viewerPausedUntil?: string,
    ) => [
      {
        couple_id: coupleId,
        viewer_user_id: userId,
        partner_user_id: partner?.user_id ?? null,
        visibility_state: state,
        viewer_sharing_enabled: viewerEnabled,
        partner_sharing_enabled: partnerEnabled,
        // Only the viewer's own pause. Nothing in this result tells the viewer the partner paused.
        viewer_paused_until: viewerPausedUntil ?? null,
        partner_location_latitude: location?.latitude ?? null,
        partner_location_longitude: location?.longitude ?? null,
        partner_location_accuracy_m: orNull(location?.accuracy_m),
        partner_location_captured_at: location?.captured_at ?? null,
        // Query results are cached, so clients should recompute staleness from partner_location_captured_at.
        partner_location_is_stale: location ? location.captured_at < addMs(now, -24 * 3_600_000) : false,
        updated_at: location?.updated_at ?? updatedAt,
      },
    ];

    if (couple.status !== "active" || viewer.status !== "active" || !partner) {
      return result("relationship_ended", false, false, couple.updated_at);
    }
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      fail("42501", "active entitled couple access is required");
    }

    const preferenceFor = (memberId: string) =>
      ctx.db
        .query("location_sharing_preferences")
        .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", memberId))
        .unique();
    const viewerPreference = await preferenceFor(userId);
    const partnerPreference = await preferenceFor(partner.user_id);
    const viewerEnabled = viewerPreference?.is_enabled ?? false;
    const partnerEnabled = partnerPreference?.is_enabled ?? false;
    // Without a location, updated_at is the newest sharing preference change, so the value is stable between writes.
    const preferencesUpdatedAt = [couple.updated_at, viewerPreference?.updated_at, partnerPreference?.updated_at].reduce<string>(
      (best, value) => (value !== undefined && value > best ? value : best),
      "",
    );
    if (!viewerEnabled) return result("disabled", false, partnerEnabled, preferencesUpdatedAt);
    // Sharing is mutual, so a person on pause does not see the partner's position either.
    if (viewerPreference?.paused_until !== undefined) {
      const pausedUntil = viewerPreference.paused_until;
      return result("viewer_paused", true, partnerEnabled, preferencesUpdatedAt, undefined, pausedUntil);
    }
    if (!partnerEnabled) return result("not_sharing", true, false, preferencesUpdatedAt);
    // A partner on pause looks like one whose phone has not sent a new position: the viewer sees the
    // last one and how old it is.
    const location = await ctx.db
      .query("latest_partner_locations")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", partner.user_id))
      .unique();
    if (!location) return result("not_sharing", true, true, preferencesUpdatedAt);
    return result("visible", true, true, preferencesUpdatedAt, location);
  },
});
