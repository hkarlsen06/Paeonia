import { v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { getOrCreateCoupleDayAt } from "./coupleDays";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { fail } from "./errors";
import { newUuid, timestampArg } from "./ids";
import { isJsonObject, jsonbByteLength } from "./json";
import { enqueuePartnerNotification, enqueueWidgetPushForUser, enqueueWidgetUpdateAlert } from "./notifications";
import { applyCoupleActivity } from "./streaks";
import { btrim, btrimToNull, charLength } from "./text";
import { nowIso } from "./time";

/**
 * Widget drawing revisions: the payload checks, the canvas, and the revision insert with its
 * side effects. `widget:submit_widget_drawing_revision` and the first day drafts share them.
 */

export const MAX_WIDGET_PAYLOAD_BYTES = 2_097_152;
const nullableInt = v.optional(v.union(v.null(), v.number()));

/** The payload description the app sends with a drawing. */
export const widgetDrawingPayloadArgs = {
  p_payload_media_asset_id: v.string(),
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
};

export type WidgetDrawingPayload = {
  payloadBytes: number;
  uncompressedBytes: number;
  compression: "none" | "gzip";
  strokeCount: number | undefined;
  pointCount: number | undefined;
  bounds: unknown;
  sha256: string;
  validatedAt: string;
  rendererVersion: string;
  validationVersion: string;
};

/** Checks and normalizes the payload description. */
export function parseWidgetDrawingPayload(args: {
  p_payload_bytes: number;
  p_uncompressed_bytes?: number | null;
  p_compression?: string | null;
  p_stroke_count?: number | null;
  p_point_count?: number | null;
  p_bounds?: unknown;
  p_sha256_hex: string;
  p_client_decode_validated_at: string;
  p_client_renderer_version: string;
  p_client_validation_version: string;
}): WidgetDrawingPayload {
  const compression = btrim(args.p_compression ?? "none").toLowerCase();
  if (compression !== "none" && compression !== "gzip") {
    fail("23514", "widget drawing compression is not supported");
  }
  const payloadBytes = args.p_payload_bytes;
  if (!(payloadBytes > 0) || payloadBytes > MAX_WIDGET_PAYLOAD_BYTES) {
    fail("23514", "widget drawing payload bytes are out of range");
  }
  const uncompressedBytes = args.p_uncompressed_bytes ?? payloadBytes;
  if (!(uncompressedBytes > 0) || uncompressedBytes > MAX_WIDGET_PAYLOAD_BYTES) {
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
  const rendererVersion = btrimToNull(args.p_client_renderer_version);
  const validationVersion = btrimToNull(args.p_client_validation_version);
  if (
    rendererVersion === null ||
    charLength(rendererVersion) > 80 ||
    validationVersion === null ||
    charLength(validationVersion) > 80
  ) {
    return fail("23514", "widget drawing client validation metadata is invalid");
  }
  const validatedAt = timestampArg(args.p_client_decode_validated_at);
  if (Date.parse(validatedAt) > Date.now() + 5 * 60_000) {
    fail("23514", "widget drawing client decode validation timestamp is invalid");
  }
  return {
    payloadBytes,
    uncompressedBytes,
    compression,
    strokeCount,
    pointCount,
    bounds,
    sha256: args.p_sha256_hex.toLowerCase(),
    validatedAt,
    rendererVersion,
    validationVersion,
  };
}

/** The values the request hash of a drawing write covers, in a fixed order. */
export function widgetDrawingPayloadHashFields(payload: WidgetDrawingPayload): unknown[] {
  return [
    payload.payloadBytes,
    payload.uncompressedBytes,
    payload.compression,
    payload.strokeCount ?? "",
    payload.pointCount ?? "",
    payload.bounds ?? "",
    payload.sha256,
    payload.validatedAt,
    payload.rendererVersion,
    payload.validationVersion,
  ];
}

/** Whether `asset` is a finalized drawing upload by `ownerUserId` at `storagePath` that matches `payload`. */
export function isUsableWidgetPayloadAsset(
  asset: Doc<"media_assets">,
  expected: { ownerUserId: string; coupleId: string | undefined; storagePath: string; payload: WidgetDrawingPayload },
): boolean {
  return (
    asset.owner_user_id === expected.ownerUserId &&
    asset.couple_id === expected.coupleId &&
    asset.reserved_parent_kind === "widget_drawing_revision" &&
    asset.bucket === "widget-drawings" &&
    asset.storage_path === expected.storagePath &&
    asset.media_type === "drawing_payload" &&
    asset.upload_purpose === "widget_drawing_payload" &&
    asset.expected_media_type === "drawing_payload" &&
    asset.expected_bucket === "widget-drawings" &&
    asset.upload_status === "finalized" &&
    asset.upload_finalized_at !== undefined &&
    asset.byte_size === expected.payload.payloadBytes &&
    asset.byte_size <= MAX_WIDGET_PAYLOAD_BYTES &&
    ["application/octet-stream", "application/x-pkdrawing"].includes(asset.mime_type ?? "") &&
    asset.sha256 === expected.payload.sha256 &&
    asset.storage_delete_status === "none" &&
    asset.moderation_status === "visible" &&
    asset.deleted_at === undefined
  );
}

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

/** The couple's canvas, created on first use. The caller checks couple access. */
export async function getOrCreateWidgetCanvas(ctx: WriterCtx, coupleId: string): Promise<Doc<"widget_canvases">> {
  const canvas = await ctx.db
    .query("widget_canvases")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
  if (canvas) return canvas;
  await assertWidgetCanvasCoupleAllowed(ctx, coupleId);
  const now = nowIso();
  const docId = await ctx.db.insert("widget_canvases", {
    id: newUuid(),
    couple_id: coupleId,
    created_at: now,
    updated_at: now,
  });
  return (await ctx.db.get(docId))!;
}

/**
 * Port of the `handle_widget_drawing_revision_created` trigger: streak activity,
 * the silent WidgetKit refresh, the silent app refresh, and, with `alert`, the visible alert.
 */
async function handleWidgetDrawingRevisionCreated(
  ctx: WriterCtx,
  revision: Doc<"widget_drawing_revisions">,
  alert: boolean,
): Promise<void> {
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
  if (!alert) return;
  // Alert: lock-screen banner, gated on the partner's alert toggle.
  await enqueueWidgetUpdateAlert(ctx, {
    couple_id: canvas.couple_id,
    author_user_id: revision.author_user_id,
    canvas_id: revision.canvas_id,
    revision_id: revision.id,
  });
}

/**
 * Inserts a revision whose author and payload asset the caller has checked, runs its side
 * effects, and makes it the canvas's active revision. `alert: false` sends the partner
 * the silent refreshes only. Returns the revision and the canvas's new `updated_at`.
 */
export async function insertWidgetDrawingRevision(
  ctx: WriterCtx,
  canvas: Doc<"widget_canvases">,
  input: {
    id: string;
    authorUserId: string;
    parentRevisionId: string | undefined;
    payloadMediaAssetId: string;
    payload: WidgetDrawingPayload;
    alert: boolean;
  },
): Promise<{ revision: Doc<"widget_drawing_revisions">; updatedAt: string }> {
  const { payload } = input;
  const now = nowIso();
  const docId = await ctx.db.insert("widget_drawing_revisions", {
    id: input.id,
    canvas_id: canvas.id,
    author_user_id: input.authorUserId,
    parent_revision_id: input.parentRevisionId,
    payload_media_asset_id: input.payloadMediaAssetId,
    payload_bytes: payload.payloadBytes,
    format: "pkdrawing",
    format_version: 1,
    uncompressed_bytes: payload.uncompressedBytes,
    compression: payload.compression,
    stroke_count: payload.strokeCount,
    point_count: payload.pointCount,
    bounds: payload.bounds,
    renderer_version: 1,
    client_decode_validated_at: payload.validatedAt,
    client_renderer_version: payload.rendererVersion,
    client_validation_version: payload.validationVersion,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  const revision = (await ctx.db.get(docId))!;
  await handleWidgetDrawingRevisionCreated(ctx, revision, input.alert);

  await assertWidgetCanvasActiveRevisionAllowed(ctx, canvas.id, revision.id);
  const updatedAt = nowIso();
  await ctx.db.patch(canvas._id, { active_revision_id: revision.id, updated_at: updatedAt });
  return { revision, updatedAt };
}
