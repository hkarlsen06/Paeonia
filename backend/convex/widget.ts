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
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { sha256Hex } from "./lib/crypto";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, orNull, withTouch } from "./lib/db";
import { checkViolation, fail } from "./lib/errors";
import { newUuid, optionalTimestampArg, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import { isJsonObject, jsonbByteLength } from "./lib/json";
import { signLiveTicket } from "./lib/liveTicket";
import { enqueuePartnerNotification, enqueueWidgetPushForUser, enqueueWidgetUpdateAlert } from "./lib/notifications";
import { applyCoupleActivity } from "./lib/streaks";
import { btrim, btrimToNull, charLength } from "./lib/text";
import { nowIso } from "./lib/time";

const MAX_PAYLOAD_BYTES = 2_097_152;
const nullableInt = v.optional(v.union(v.null(), v.number()));

type Revision = Doc<"widget_drawing_revisions">;
type Asset = Doc<"media_assets">;

/** Port of `assert_widget_canvas_couple_allowed`. */
async function assertWidgetCanvasCoupleAllowed(ctx: ReaderCtx, coupleId: string): Promise<void> {
  const couple = await getByUuid(ctx, "couples", coupleId);
  if (!couple || couple.status !== "active") fail("23514", "widget canvas requires an active couple");
}

/** Port of `assert_widget_canvas_active_revision_allowed`. */
async function assertWidgetCanvasActiveRevisionAllowed(
  ctx: ReaderCtx,
  canvasId: string,
  activeRevisionId: string,
): Promise<void> {
  const revision = await getByUuid(ctx, "widget_drawing_revisions", activeRevisionId);
  if (
    !revision ||
    revision.canvas_id !== canvasId ||
    revision.deleted_at !== undefined ||
    revision.moderation_status !== "visible"
  ) {
    fail("23514", "active widget revision must be a visible revision for the same canvas");
  }
}

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
    asset.byte_size > MAX_PAYLOAD_BYTES ||
    asset.sha256 === undefined ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", "widget drawing payload asset is not usable");
  }
}

/**
 * Port of the `handle_widget_drawing_revision_created` trigger: streak activity,
 * the silent WidgetKit refresh, the silent app refresh, and the visible alert.
 */
async function handleWidgetDrawingRevisionCreated(ctx: WriterCtx, revision: Revision): Promise<void> {
  const canvas = await getByUuid(ctx, "widget_canvases", revision.canvas_id);
  if (!canvas) return;
  await applyCoupleActivity(ctx, {
    couple_id: canvas.couple_id,
    user_id: revision.author_user_id,
    couple_day_id: await getOrCreateCoupleDayAt(ctx, canvas.couple_id, revision.created_at),
    activity_kind: "widget_drawing_saved",
    occurred_at: revision.created_at,
    dedupe_key: `widget_drawing_saved:${revision.id}`,
    metadata: { canvas_id: revision.canvas_id },
  });

  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", canvas.couple_id).eq("status", "active"))
    .collect();
  const recipient = members.find((member) => member.user_id !== revision.author_user_id);
  const payload = {
    type: "widget_updated",
    couple_id: canvas.couple_id,
    canvas_id: revision.canvas_id,
    revision_id: revision.id,
    actor_user_id: revision.author_user_id,
    route: "widget",
    deeplink: "paeonia://widget/drawing",
  };
  if (recipient) {
    try {
      await enqueueWidgetPushForUser(ctx, {
        recipient_user_id: recipient.user_id,
        kind: "widget_updated",
        payload,
        dedupe_key: `widgetkit:${revision.id}`,
        apns_collapse_id: `widget:${canvas.couple_id}`,
        scheduled_for: null,
      });
    } catch {
      // WidgetKit push delivery must never make saving a drawing fail.
    }
  }

  // Silent refresh: wakes the partner's app to pull the new drawing.
  await enqueuePartnerNotification(ctx, {
    couple_id: canvas.couple_id,
    actor_user_id: revision.author_user_id,
    kind: "widget_updated",
    payload,
    dedupe_key: `widget_updated:${revision.id}`,
    redaction_level: "private",
    apns_push_type: "background",
    apns_collapse_id: `widget:${canvas.couple_id}`,
    scheduled_for: nowIso(),
  });
  // Alert: lock-screen banner, gated on the partner's alert toggle.
  await enqueueWidgetUpdateAlert(ctx, {
    couple_id: canvas.couple_id,
    author_user_id: revision.author_user_id,
    canvas_id: revision.canvas_id,
    revision_id: revision.id,
  });
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
    let canvas = await ctx.db
      .query("widget_canvases")
      .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
      .unique();
    if (!canvas) {
      await assertWidgetCanvasCoupleAllowed(ctx, coupleId);
      const now = nowIso();
      const docId = await ctx.db.insert("widget_canvases", {
        id: newUuid(),
        couple_id: coupleId,
        created_at: now,
        updated_at: now,
      });
      canvas = (await ctx.db.get(docId))!;
    }
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

function payloadIsVisible(revision: Revision | null, asset: Asset | null): boolean {
  return (
    revision !== null &&
    revision.deleted_at === undefined &&
    revision.moderation_status === "visible" &&
    asset !== null &&
    asset.upload_status === "finalized" &&
    asset.storage_delete_status === "none" &&
    asset.moderation_status === "visible" &&
    asset.deleted_at === undefined
  );
}

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
    p_payload_media_asset_id: v.string(),
    p_parent_revision_id: v.optional(v.union(v.null(), v.string())),
    p_payload_bytes: v.number(),
    p_uncompressed_bytes: nullableInt,
    p_compression: v.optional(v.union(v.null(), v.string())),
    p_stroke_count: nullableInt,
    p_point_count: nullableInt,
    p_bounds: v.optional(v.any()),
    p_sha256_hex: v.string(),
    p_client_decode_validated_at: v.string(),
    p_client_renderer_version: v.string(),
    p_client_validation_version: v.string(),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const canvasId = uuidArg(args.p_canvas_id);
    const assetId = uuidArg(args.p_payload_media_asset_id);
    const parentId = optionalUuidArg(args.p_parent_revision_id);

    const compression = btrim(args.p_compression ?? "none").toLowerCase();
    if (compression !== "none" && compression !== "gzip") {
      fail("23514", "widget drawing compression is not supported");
    }
    const payloadBytes = args.p_payload_bytes;
    if (!(payloadBytes > 0) || payloadBytes > MAX_PAYLOAD_BYTES) {
      fail("23514", "widget drawing payload bytes are out of range");
    }
    const uncompressedBytes = args.p_uncompressed_bytes ?? payloadBytes;
    if (!(uncompressedBytes > 0) || uncompressedBytes > MAX_PAYLOAD_BYTES) {
      fail("23514", "widget drawing uncompressed bytes are out of range");
    }
    if (
      (compression === "none" && uncompressedBytes !== payloadBytes) ||
      (compression === "gzip" && uncompressedBytes < payloadBytes)
    ) {
      fail("23514", "widget drawing compression metadata is invalid");
    }
    const strokeCount = args.p_stroke_count ?? undefined;
    if (strokeCount !== undefined && (strokeCount < 0 || strokeCount > 5000)) {
      fail("23514", "widget drawing stroke count is out of range");
    }
    const pointCount = args.p_point_count ?? undefined;
    if (pointCount !== undefined && (pointCount < 0 || pointCount > 200000)) {
      fail("23514", "widget drawing point count is out of range");
    }
    const bounds = args.p_bounds ?? undefined;
    if (bounds !== undefined && (!isJsonObject(bounds) || jsonbByteLength(bounds) > 2048)) {
      fail("23514", "widget drawing bounds metadata is invalid");
    }
    if (!/^[0-9a-fA-F]{64}$/.test(args.p_sha256_hex)) {
      fail("22023", "widget drawing sha256 must be a 64 character hex string");
    }
    const sha256 = args.p_sha256_hex.toLowerCase();
    const rendererVersion = btrimToNull(args.p_client_renderer_version);
    const validationVersion = btrimToNull(args.p_client_validation_version);
    if (
      rendererVersion === null ||
      charLength(rendererVersion) > 80 ||
      validationVersion === null ||
      charLength(validationVersion) > 80
    ) {
      fail("23514", "widget drawing client validation metadata is invalid");
    }
    const validatedAt = timestampArg(args.p_client_decode_validated_at);
    if (Date.parse(validatedAt) > Date.now() + 5 * 60_000) {
      fail("23514", "widget drawing client decode validation timestamp is invalid");
    }

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
          payloadBytes,
          uncompressedBytes,
          compression,
          strokeCount ?? "",
          pointCount ?? "",
          bounds ?? "",
          sha256,
          validatedAt,
          rendererVersion,
          validationVersion,
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
        if (
          asset.owner_user_id !== userId ||
          asset.couple_id !== canvas.couple_id ||
          asset.reserved_parent_kind !== "widget_drawing_revision" ||
          asset.bucket !== "widget-drawings" ||
          asset.storage_path !== expectedPath ||
          asset.media_type !== "drawing_payload" ||
          asset.upload_purpose !== "widget_drawing_payload" ||
          asset.expected_media_type !== "drawing_payload" ||
          asset.expected_bucket !== "widget-drawings" ||
          asset.upload_status !== "finalized" ||
          asset.upload_finalized_at === undefined ||
          asset.byte_size !== payloadBytes ||
          asset.byte_size > MAX_PAYLOAD_BYTES ||
          !["application/octet-stream", "application/x-pkdrawing"].includes(asset.mime_type ?? "") ||
          asset.sha256 !== sha256 ||
          asset.storage_delete_status !== "none" ||
          asset.moderation_status !== "visible" ||
          asset.deleted_at !== undefined
        ) {
          fail("23514", "widget drawing payload asset is not usable");
        }
        const sameRevision = await getByUuid(ctx, "widget_drawing_revisions", revisionId);
        const sameAsset = await ctx.db
          .query("widget_drawing_revisions")
          .withIndex("by_payload_media_asset_id", (q) => q.eq("payload_media_asset_id", asset.id))
          .first();
        if (sameRevision || sameAsset) fail("23505", "widget drawing payload asset was already saved");

        const revisionRow = {
          id: revisionId,
          canvas_id: canvas.id,
          author_user_id: userId,
          parent_revision_id: parentId,
          payload_media_asset_id: asset.id,
          payload_bytes: payloadBytes,
        };
        await assertWidgetDrawingRevisionAllowed(ctx, userId, revisionRow);
        const now = nowIso();
        const docId = await ctx.db.insert("widget_drawing_revisions", {
          ...revisionRow,
          format: "pkdrawing",
          format_version: 1,
          uncompressed_bytes: uncompressedBytes,
          compression,
          stroke_count: strokeCount,
          point_count: pointCount,
          bounds,
          renderer_version: 1,
          client_decode_validated_at: validatedAt,
          client_renderer_version: rendererVersion,
          client_validation_version: validationVersion,
          moderation_status: "visible",
          created_at: now,
          updated_at: now,
        });
        const revision = (await ctx.db.get(docId))!;
        await handleWidgetDrawingRevisionCreated(ctx, revision);

        await assertWidgetCanvasActiveRevisionAllowed(ctx, canvas.id, revision.id);
        const updatedAt = nowIso();
        await ctx.db.patch(canvas._id, { active_revision_id: revision.id, updated_at: updatedAt });
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
