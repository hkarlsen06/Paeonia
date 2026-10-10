import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { canAccessCoupleContent, getCurrentEntitledCoupleId } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { runClientOperation } from "./lib/clientOperations";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { optionalTimestampArg, uuidArg } from "./lib/ids";
import { enqueuePartnerNotification } from "./lib/notifications";
import { addMs, nowIso } from "./lib/time";
import type { WriterCtx } from "./lib/db";

const nullable = <T extends ReturnType<typeof v.string> | ReturnType<typeof v.number> | ReturnType<typeof v.boolean>>(
  validator: T,
) => v.optional(v.union(v.null(), validator));

const LOCATION_SOURCES = ["foreground_open", "manual_refresh", "settings_toggle"] as const;
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
          if (partnerPreference?.is_enabled) partnerShares = true;
        }
        if (partnerShares) {
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
          source,
        },
      },
      async () => {
        await assertNoPendingAccountDeletion(ctx, userId);
        const now = nowIso();
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
              enabled_at: isEnabled ? now : existing.enabled_at,
              disabled_at: isEnabled ? undefined : now,
              consent_version: isEnabled ? consentVersion : existing.consent_version,
              source,
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
            created_at: now,
            updated_at: now,
          });
          row = (await ctx.db.get(id))!;
        }
        if (!isEnabled) {
          await deleteLatestLocationForUser(ctx, coupleId, userId);
        }
        return {
          couple_id: row.couple_id,
          user_id: row.user_id,
          is_enabled: row.is_enabled,
          enabled_at: orNull(row.enabled_at),
          disabled_at: orNull(row.disabled_at),
          updated_at: row.updated_at,
        };
      },
    );
    return [stored];
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
    ) => [
      {
        couple_id: coupleId,
        viewer_user_id: userId,
        partner_user_id: partner?.user_id ?? null,
        visibility_state: state,
        viewer_sharing_enabled: viewerEnabled,
        partner_sharing_enabled: partnerEnabled,
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
    if (!partnerEnabled) return result("not_sharing", true, false, preferencesUpdatedAt);

    const location = await ctx.db
      .query("latest_partner_locations")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", partner.user_id))
      .unique();
    if (!location) return result("not_sharing", true, true, preferencesUpdatedAt);
    return result("visible", true, true, preferencesUpdatedAt, location);
  },
});
