import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import {
  canAccessCoupleContent,
  getCurrentEntitledCoupleId,
  isActiveCoupleMember,
} from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { sha256Hex } from "./lib/crypto";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull, withTouch } from "./lib/db";
import { checkViolation, fail } from "./lib/errors";
import { newUuid, optionalTimestampArg, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import { signLiveTicket } from "./lib/liveTicket";
import { readLockScreenState } from "./lib/lockScreenState";
import { btrim, btrimToNull, charLength } from "./lib/text";
import { nowIso } from "./lib/time";
import {
  MAX_WIDGET_PAYLOAD_BYTES,
  getOrCreateWidgetCanvas,
  insertWidgetDrawingRevision,
  isUsableWidgetPayloadAsset,
  parseWidgetDrawingPayload,
  payloadIsVisible,
  widgetDrawingPayloadArgs,
  widgetDrawingPayloadHashFields,
} from "./lib/widgetDrawings";

const nullableInt = v.optional(v.union(v.null(), v.number()));

type Revision = Doc<"widget_drawing_revisions">;
type Asset = Doc<"media_assets">;

/** Port of `assert_widget_drawing_revision_allowed`. */
async function assertWidgetDrawingRevisionAllowed(
  ctx: ReaderCtx,
  userId: string,
  revision: {
    id: string;
    canvas_id: string;
    author_user_id: string;
    parent_revision_id?: string;
    payload_media_asset_id: string;
    payload_bytes: number;
  },
): Promise<void> {
  const canvas = await getByUuid(ctx, "widget_canvases", revision.canvas_id);
  if (!canvas || canvas.deleted_at !== undefined || !(await canAccessCoupleContent(ctx, userId, canvas.couple_id))) {
    fail("42501", "active entitled widget canvas access is required");
  }
  if (!(await isActiveCoupleMember(ctx, revision.author_user_id, canvas.couple_id))) {
    fail("23514", "widget revision author must be an active couple member");
  }
  if (revision.parent_revision_id !== undefined) {
    const parent = await getByUuid(ctx, "widget_drawing_revisions", revision.parent_revision_id);
    if (parent?.canvas_id !== revision.canvas_id) {
      fail("23514", "parent widget revision must belong to the same canvas");
    }
  }
  const asset = await getByUuid(ctx, "media_assets", revision.payload_media_asset_id);
  const expectedPath = `${canvas.couple_id}/${canvas.id}/revisions/${revision.id}/drawing.pkdrawing`;
  if (
    !asset ||
    asset.owner_user_id !== revision.author_user_id ||
    asset.couple_id !== canvas.couple_id ||
    asset.reserved_parent_kind !== "widget_drawing_revision" ||
    asset.reserved_parent_id !== revision.id ||
    asset.bucket !== "widget-drawings" ||
    asset.storage_path !== expectedPath ||
    asset.media_type !== "drawing_payload" ||
    asset.upload_purpose !== "widget_drawing_payload" ||
    asset.expected_media_type !== "drawing_payload" ||
    asset.expected_bucket !== "widget-drawings" ||
    asset.upload_status !== "finalized" ||
    asset.upload_finalized_at === undefined ||
    asset.byte_size !== revision.payload_bytes ||
    asset.byte_size > MAX_WIDGET_PAYLOAD_BYTES ||
    asset.sha256 === undefined ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", "widget drawing payload asset is not usable");
  }
}

// --- Canvas reads -----------------------------------------------------------

async function resolveCoupleId(ctx: ReaderCtx, userId: string, coupleArg: string | null | undefined): Promise<string> {
  const coupleId = optionalUuidArg(coupleArg);
  if (coupleId === undefined) return await getCurrentEntitledCoupleId(ctx, userId);
  if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
    fail("42501", "active entitled couple access is required");
  }
  return coupleId;
}

export const get_or_create_widget_canvas = mutation({
  args: { p_couple_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await resolveCoupleId(ctx, userId, args.p_couple_id);
    const canvas = await getOrCreateWidgetCanvas(ctx, coupleId);
    if (canvas.deleted_at !== undefined) return [];
    return [
      {
        canvas_id: canvas.id,
        couple_id: canvas.couple_id,
        active_revision_id: orNull(canvas.active_revision_id),
        created_at: canvas.created_at,
        updated_at: canvas.updated_at,
      },
    ];
  },
});

// --- Live drawing relay -----------------------------------------------------

/**
 * Signs a short ticket for the live drawing relay (`lib/liveTicket.ts`) for the
 * couple's widget canvas room. Returns null when the relay is not configured.
 */
export const create_widget_live_ticket = mutation({
  args: { p_couple_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await resolveCoupleId(ctx, userId, args.p_couple_id);
    return await signLiveTicket({ coupleId, userId });
  },
});

/** The payload columns shared by the canvas and revision reads. Null unless the payload is visible. */
function payloadColumns(revision: Revision, asset: Asset | null, visible: boolean) {
  const shown = <T>(value: T | undefined | null): T | null => (visible ? orNull(value) : null);
  return {
    payload_media_asset_id: shown(revision.payload_media_asset_id),
    payload_bucket: shown(asset?.bucket),
    payload_storage_path: shown(asset?.storage_path),
    payload_sha256_hex: shown(asset?.sha256),
    payload_bytes: shown(revision.payload_bytes),
    uncompressed_bytes: shown(revision.uncompressed_bytes),
    compression: shown(revision.compression),
    stroke_count: shown(revision.stroke_count),
    point_count: shown(revision.point_count),
    bounds: shown(revision.bounds),
    format: shown(revision.format),
    format_version: shown(revision.format_version),
    renderer_version: shown(revision.renderer_version),
    client_decode_validated_at: shown(revision.client_decode_validated_at),
    client_renderer_version: shown(revision.client_renderer_version),
    client_validation_version: shown(revision.client_validation_version),
  };
}

function latest(...values: (string | undefined)[]): string {
  return values.reduce<string>((best, value) => (value !== undefined && value > best ? value : best), "");
}

export const get_widget_canvas = query({
  args: { p_couple_id: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await resolveCoupleId(ctx, userId, args.p_couple_id);
    const canvas = await ctx.db
      .query("widget_canvases")
      .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
      .unique();
    if (!canvas || canvas.deleted_at !== undefined) return [];

    const revision = await getByUuid(ctx, "widget_drawing_revisions", canvas.active_revision_id);
    const asset = revision ? await getByUuid(ctx, "media_assets", revision.payload_media_asset_id) : null;
    const visible = payloadIsVisible(revision, asset);
    const columns = revision ? payloadColumns(revision, asset, visible) : null;
    const { payload_media_asset_id, ...rest } = columns ?? payloadColumns({} as Revision, null, false);
    return [
      {
        canvas_id: canvas.id,
        couple_id: canvas.couple_id,
        active_revision_id: orNull(canvas.active_revision_id),
        active_revision_moderation_status: orNull(revision?.moderation_status),
        active_revision_deleted_at: orNull(revision?.deleted_at),
        active_revision_author_user_id: visible ? revision!.author_user_id : null,
        payload_media_asset_id,
        ...rest,
        revision_created_at: visible ? revision!.created_at : null,
        canvas_created_at: canvas.created_at,
        canvas_updated_at: canvas.updated_at,
        sync_updated_at: latest(canvas.updated_at, revision?.updated_at, asset?.updated_at),
      },
    ];
  },
});

/**
 * Everything the Lock Screen widgets show, in one read: the partner's name and zone, the start date,
 * the next countdowns, the distance, the streak, the daily question, and the games waiting for the
 * caller. Returns null without an active entitled couple. It never returns coordinates or text.
 *
 * A query must not read the clock, so the widget passes its time in `p_now`, rounded down to the
 * minute. A new minute is a new argument, so Convex never serves a result cached before midnight.
 */
export const get_lock_screen_state = query({
  args: { p_now: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    return await readLockScreenState(ctx, userId, timestampArg(args.p_now));
  },
});

export const get_widget_drawing_revisions = query({
  args: {
    p_canvas_id: v.string(),
    p_updated_after: v.optional(v.union(v.null(), v.string())),
    p_limit: nullableInt,
    p_updated_after_revision_id: v.optional(v.union(v.null(), v.string())),
    p_created_before: v.optional(v.union(v.null(), v.string())),
    p_created_before_revision_id: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const canvasId = uuidArg(args.p_canvas_id);
    const limit = args.p_limit === undefined ? 100 : args.p_limit;
    if (limit === null || !Number.isInteger(limit) || limit < 1 || limit > 200) {
      fail("23514", "widget drawing revision read limit is out of range");
    }
    const updatedAfter = optionalTimestampArg(args.p_updated_after);
    const updatedAfterId = optionalUuidArg(args.p_updated_after_revision_id);
    const createdBefore = optionalTimestampArg(args.p_created_before);
    const createdBeforeId = optionalUuidArg(args.p_created_before_revision_id);
    if (updatedAfter !== undefined && createdBefore !== undefined) {
      fail("23514", "widget drawing sync and history cursors cannot be combined");
    }
    if ((updatedAfter === undefined) !== (updatedAfterId === undefined)) {
      fail("23514", "widget drawing sync cursor requires timestamp and revision id");
    }
    if ((createdBefore === undefined) !== (createdBeforeId === undefined)) {
      fail("23514", "widget drawing history cursor requires timestamp and revision id");
    }
    const canvas = await getByUuid(ctx, "widget_canvases", canvasId);
    if (!canvas || canvas.deleted_at !== undefined || !(await canAccessCoupleContent(ctx, userId, canvas.couple_id))) {
      fail("42501", "active entitled widget canvas access is required");
    }

    const row = async (revision: Doc<"widget_drawing_revisions">) => {
      const asset = await getByUuid(ctx, "media_assets", revision.payload_media_asset_id);
      if (!asset) return null;
      const visible = payloadIsVisible(revision, asset);
      return {
        canvas_id: revision.canvas_id,
        revision_id: revision.id,
        author_user_id: revision.author_user_id,
        parent_revision_id: orNull(revision.parent_revision_id),
        moderation_status: revision.moderation_status,
        deleted_at: orNull(revision.deleted_at),
        ...payloadColumns(revision, asset, visible),
        created_at: revision.created_at,
        updated_at: revision.updated_at,
        sync_updated_at: latest(revision.updated_at, asset.updated_at),
      };
    };

    if (updatedAfter === undefined) {
      // History, newest first: read only one page from the index.
      const history = ctx.db
        .query("widget_drawing_revisions")
        .withIndex("by_canvas_id_created_at_id", (q) =>
          createdBefore === undefined
            ? q.eq("canvas_id", canvasId)
            : q.eq("canvas_id", canvasId).lte("created_at", createdBefore),
        )
        .order("desc");
      const rows = [];
      for await (const revision of history) {
        if (rows.length >= limit) break;
        if (revision.created_at === createdBefore && revision.id >= createdBeforeId!) continue;
        const next = await row(revision);
        if (next) rows.push(next);
      }
      return rows;
    }

    // ponytail: the sync cursor also moves when the payload asset changes, which no index covers,
    // so this reads every revision of the canvas. Store sync_updated_at on the revision if canvases grow large.
    const revisions = await ctx.db
      .query("widget_drawing_revisions")
      .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvasId))
      .collect();
    const rows = [];
    for (const revision of revisions) {
      const next = await row(revision);
      if (next) rows.push(next);
    }
    return rows
      .filter(
        (row) =>
          row.sync_updated_at > updatedAfter ||
          (row.sync_updated_at === updatedAfter && row.revision_id > updatedAfterId!),
      )
      .sort((a, b) =>
        a.sync_updated_at !== b.sync_updated_at
          ? a.sync_updated_at < b.sync_updated_at
            ? -1
            : 1
          : a.revision_id < b.revision_id
            ? -1
            : 1,
      )
      .slice(0, limit);
  },
});

// --- Submit -----------------------------------------------------------------

export const submit_widget_drawing_revision = mutation({
  args: {
    p_canvas_id: v.string(),
    p_parent_revision_id: v.optional(v.union(v.null(), v.string())),
    ...widgetDrawingPayloadArgs,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const canvasId = uuidArg(args.p_canvas_id);
    const assetId = uuidArg(args.p_payload_media_asset_id);
    const parentId = optionalUuidArg(args.p_parent_revision_id);

    const payload = parseWidgetDrawingPayload(args);

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "submit_widget_drawing_revision",
        scope: "widget",
        request: [
          "submit_widget_drawing_revision",
          canvasId,
          assetId,
          parentId ?? "",
          ...widgetDrawingPayloadHashFields(payload),
        ],
      }),
      async () => {
        const canvas = await getByUuid(ctx, "widget_canvases", canvasId);
        if (!canvas || canvas.deleted_at !== undefined || !(await canAccessCoupleContent(ctx, userId, canvas.couple_id))) {
          return fail("42501", "active entitled widget canvas access is required");
        }
        if (canvas.active_revision_id !== parentId) fail("40001", "widget drawing parent revision conflict");

        const asset = await getByUuid(ctx, "media_assets", assetId);
        if (!asset) return fail("22023", "widget drawing payload asset was not found");
        const revisionId = asset.reserved_parent_id;
        const expectedPath = `${canvas.couple_id}/${canvas.id}/revisions/${revisionId}/drawing.pkdrawing`;
        if (!isUsableWidgetPayloadAsset(asset, { ownerUserId: userId, coupleId: canvas.couple_id, storagePath: expectedPath, payload })) {
          fail("23514", "widget drawing payload asset is not usable");
        }
        const sameRevision = await getByUuid(ctx, "widget_drawing_revisions", revisionId);
        const sameAsset = await ctx.db
          .query("widget_drawing_revisions")
          .withIndex("by_payload_media_asset_id", (q) => q.eq("payload_media_asset_id", asset.id))
          .first();
        if (sameRevision || sameAsset) fail("23505", "widget drawing payload asset was already saved");

        await assertWidgetDrawingRevisionAllowed(ctx, userId, {
          id: revisionId,
          canvas_id: canvas.id,
          author_user_id: userId,
          parent_revision_id: parentId,
          payload_media_asset_id: asset.id,
          payload_bytes: payload.payloadBytes,
        });
        const { revision, updatedAt } = await insertWidgetDrawingRevision(ctx, canvas, {
          id: revisionId,
          authorUserId: userId,
          parentRevisionId: parentId,
          payloadMediaAssetId: asset.id,
          payload,
          alert: true,
        });
        return {
          canvas_id: canvas.id,
          revision_id: revision.id,
          active_revision_id: revision.id,
          payload_media_asset_id: revision.payload_media_asset_id,
          created_at: revision.created_at,
          updated_at: updatedAt,
        };
      },
    );
    return [stored];
  },
});

// --- Push device ------------------------------------------------------------

export const register_widget_push_device = mutation({
  args: {
    p_widget_kind: v.string(),
    p_widget_push_token: v.string(),
    p_apns_environment: v.string(),
    p_locale: v.optional(v.union(v.null(), v.string())),
    p_time_zone_id: v.optional(v.union(v.null(), v.string())),
    p_app_version: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args): Promise<string> => {
    const userId = await requireUserId(ctx);
    const kindLength = charLength(btrim(args.p_widget_kind));
    if (kindLength < 1 || kindLength > 128) fail("23514", "invalid widget kind");
    const tokenLength = charLength(args.p_widget_push_token);
    if (tokenLength < 20 || tokenLength > 4096) fail("23514", "invalid widget push token");
    if (args.p_apns_environment !== "sandbox" && args.p_apns_environment !== "production") {
      fail("23514", "unsupported APNs environment");
    }
    const environment = args.p_apns_environment;
    const tokenHash = await sha256Hex(args.p_widget_push_token);
    const locale = btrimToNull(args.p_locale) ?? undefined;
    const timeZone = btrimToNull(args.p_time_zone_id) ?? undefined;
    const appVersion = btrimToNull(args.p_app_version) ?? undefined;

    const sameToken = await ctx.db
      .query("widget_push_devices")
      .withIndex("by_token_hash_apns_environment_widget_kind_disabled_at", (q) =>
        q.eq("widget_push_token_hash", tokenHash).eq("apns_environment", environment).eq("widget_kind", args.p_widget_kind),
      )
      .collect();

    // A token belongs to one account at a time. Disable it for everyone else.
    for (const device of sameToken) {
      if (device.user_id !== userId && device.disabled_at === undefined) {
        await assertNoPendingAccountDeletion(ctx, device.user_id);
        await ctx.db.patch(device._id, withTouch(device, { disabled_at: nowIso() }));
      }
    }

    await assertNoPendingAccountDeletion(ctx, userId);
    const mine = sameToken
      .filter((device) => device.user_id === userId)
      .sort((a, b) => (a.updated_at !== b.updated_at ? (a.updated_at < b.updated_at ? 1 : -1) : a.id < b.id ? -1 : 1))[0];

    if (mine) {
      checkWidgetDeviceColumns(locale, timeZone, appVersion);
      await ctx.db.patch(
        mine._id,
        withTouch(mine, {
          widget_push_token: args.p_widget_push_token,
          locale,
          time_zone_id: timeZone,
          app_version: appVersion,
          last_seen_at: nowIso(),
          disabled_at: undefined,
        }),
      );
      return mine.id;
    }

    checkWidgetDeviceColumns(locale, timeZone, appVersion);
    const now = nowIso();
    const id = newUuid();
    await ctx.db.insert("widget_push_devices", {
      id,
      user_id: userId,
      widget_kind: btrim(args.p_widget_kind),
      widget_push_token: args.p_widget_push_token,
      widget_push_token_hash: tokenHash,
      apns_environment: environment,
      locale,
      time_zone_id: timeZone,
      app_version: appVersion,
      last_seen_at: now,
      revision: 1,
      created_at: now,
      updated_at: now,
    });
    return id;
  },
});

/** The length checks from the `widget_push_devices` table. Values are already trimmed. */
function checkWidgetDeviceColumns(locale?: string, timeZone?: string, appVersion?: string): void {
  if (locale !== undefined && (charLength(locale) < 2 || charLength(locale) > 64)) {
    checkViolation("widget_push_devices", "widget_push_devices_locale_check");
  }
  if (timeZone !== undefined && charLength(timeZone) > 128) {
    checkViolation("widget_push_devices", "widget_push_devices_time_zone_id_check");
  }
  if (appVersion !== undefined && charLength(appVersion) > 64) {
    checkViolation("widget_push_devices", "widget_push_devices_app_version_check");
  }
}
