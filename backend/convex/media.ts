import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { httpAction, internalMutation, internalQuery, mutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { hmacSha256Hex, timingSafeEqual } from "./lib/crypto";
import { getByUuid, withUpdatedAt } from "./lib/db";
import { checkViolation, fail, uniqueViolation } from "./lib/errors";
import { isJsonObject } from "./lib/json";
import { newUuid, optionalTimestampArg, optionalUuidArg, uuidArg } from "./lib/ids";
import {
  canReadMediaAsset,
  mediaByteLimit,
  mediaExtensionMatchesType,
  mediaMimeMatchesType,
  normalizeMediaFileExtension,
} from "./lib/mediaAssets";
import { mediaAssetHasLiveReference, queueOrphanedMediaAssetsForDelete } from "./lib/mediaOrphans";
import { btrim } from "./lib/text";
import { addMs, nowIso } from "./lib/time";

type MediaAsset = Doc<"media_assets">;

const HOUR_MS = 3_600_000;
const nullableInt = v.optional(v.union(v.null(), v.number()));

// --- Signed download URLs ---------------------------------------------------

function mediaUrlSecret(): string {
  const secret = process.env.PAEONIA_MEDIA_URL_SECRET;
  if (!secret) throw new Error("PAEONIA_MEDIA_URL_SECRET is not set");
  return secret;
}

/** `GET /media` link for an asset, valid until `expiresAtSeconds` (unix time). */
export async function signMediaUrl(assetId: string, expiresAtSeconds: number): Promise<string> {
  const site = process.env.CONVEX_SITE_URL;
  if (!site) throw new Error("CONVEX_SITE_URL is not set");
  const sig = await hmacSha256Hex(mediaUrlSecret(), `${assetId}.${expiresAtSeconds}`);
  return `${site.replace(/\/+$/, "")}/media?asset=${assetId}&exp=${expiresAtSeconds}&sig=${sig}`;
}

// --- Upload reservation -----------------------------------------------------

export const create_pending_media_upload = mutation({
  args: {
    ...clientOperationArgs,
    p_reserved_parent_kind: v.string(),
    p_reserved_parent_id: v.string(),
    p_upload_purpose: v.string(),
    p_media_type: v.string(),
    p_file_extension: v.string(),
    p_couple_id: v.optional(v.union(v.null(), v.string())),
    p_upload_expires_at: v.optional(v.union(v.null(), v.string())),
    p_path_context: v.optional(v.union(v.null(), v.any())),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const parentId = uuidArg(args.p_reserved_parent_id);
    const pathContext = args.p_path_context ?? {};
    if (!isJsonObject(pathContext)) fail("23514", "path context must be an object");
    const extension = normalizeMediaFileExtension(args.p_file_extension);
    if (!mediaExtensionMatchesType(args.p_media_type, extension)) {
      fail("23514", "file extension does not match media type");
    }
    const coupleArg = optionalUuidArg(args.p_couple_id);
    const requestedExpiry = optionalTimestampArg(args.p_upload_expires_at);
    const nowMs = Date.now();
    const expiresAt = requestedExpiry ?? new Date(nowMs + HOUR_MS).toISOString();
    if (Date.parse(expiresAt) <= nowMs + 5 * 60_000 || Date.parse(expiresAt) > nowMs + 24 * HOUR_MS) {
      fail("23514", "upload expiration is out of range");
    }

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "create_pending_media_upload",
        scope: "media_assets",
        request: [
          "create_pending_media_upload",
          args.p_reserved_parent_kind,
          parentId,
          args.p_upload_purpose,
          args.p_media_type,
          extension,
          coupleArg ?? "",
          requestedExpiry === undefined ? "server_generated" : expiresAt,
          pathContext,
        ],
      }),
      async () => {
        const assetId = newUuid();
        let bucket: MediaAsset["bucket"];
        let coupleId: string | undefined;
        let storagePath: string;
        const purpose = args.p_upload_purpose;
        const kind = args.p_reserved_parent_kind;
        const mediaType = args.p_media_type;

        if (purpose === "profile_photo") {
          if (kind !== "profile_photo" || parentId !== userId || mediaType !== "image" || coupleArg !== undefined) {
            fail("23514", "profile photo upload contract is invalid");
          }
          bucket = "profile-photos";
          storagePath = `${userId}/${assetId}.${extension}`;
        } else if (["memory_photo", "voice_note", "daily_answer_media", "thread_media"].includes(purpose)) {
          if (coupleArg === undefined) fail("23514", "relationship media requires a couple id");
          if (!(await canAccessCoupleContent(ctx, userId, coupleArg))) {
            fail("42501", "active entitled couple access is required");
          }
          const contractOk =
            (purpose === "memory_photo" && kind === "memory_media" && mediaType === "image") ||
            (purpose === "voice_note" &&
              ["memory_media", "daily_answer_media", "thread_message_media"].includes(kind) &&
              mediaType === "voice") ||
            (purpose === "daily_answer_media" && kind === "daily_answer_media" && mediaType === "image") ||
            (purpose === "thread_media" && kind === "thread_message_media" && mediaType === "image");
          if (!contractOk) fail("23514", "relationship media upload contract is invalid");
          bucket = "couple-media";
          coupleId = coupleArg;
          storagePath = `${coupleArg}/${mediaType}/${assetId}.${extension}`;
        } else if (purpose === "widget_drawing_payload") {
          if (kind !== "widget_drawing_revision" || mediaType !== "drawing_payload" || coupleArg === undefined) {
            fail("23514", "widget drawing upload contract is invalid");
          }
          if (!(await canAccessCoupleContent(ctx, userId, coupleArg))) {
            fail("42501", "active entitled couple access is required");
          }
          const rawCanvasId = pathContext.canvas_id;
          if (rawCanvasId === undefined || rawCanvasId === null || rawCanvasId === "") {
            fail("23514", "widget drawing uploads require a canvas id");
          }
          const canvasId = uuidArg(rawCanvasId);
          bucket = "widget-drawings";
          coupleId = coupleArg;
          storagePath = `${coupleArg}/${canvasId}/revisions/${parentId}/drawing.${extension}`;
        } else if (purpose === "report_snapshot") {
          return fail("42501", "report snapshot uploads require a trusted service path");
        } else {
          return fail("23514", "upload purpose is not supported");
        }

        const clash = await ctx.db
          .query("media_assets")
          .withIndex("by_bucket_storage_path", (q) => q.eq("bucket", bucket).eq("storage_path", storagePath))
          .first();
        if (clash) uniqueViolation("media_assets_bucket_storage_path_unique_idx");
        const now = nowIso();
        await ctx.db.insert("media_assets", {
          id: assetId,
          owner_user_id: userId,
          couple_id: coupleId,
          reserved_parent_kind: kind as MediaAsset["reserved_parent_kind"],
          reserved_parent_id: parentId,
          reserved_by_client_operation_id: uuidArg(args.p_client_operation_id),
          bucket,
          storage_path: storagePath,
          media_type: mediaType as MediaAsset["media_type"],
          upload_purpose: purpose as MediaAsset["upload_purpose"],
          expected_media_type: mediaType as MediaAsset["media_type"],
          expected_bucket: bucket,
          upload_status: "pending",
          upload_expires_at: expiresAt,
          moderation_status: "visible",
          storage_delete_status: "none",
          storage_delete_attempts: 0,
          created_at: now,
          updated_at: now,
        });
        return { media_asset_id: assetId, bucket, storage_path: storagePath, upload_expires_at: expiresAt };
      },
    );
    // A replay gets a fresh upload URL, because Convex upload URLs are short lived.
    // The URL itself authorizes the upload, so re-check the live reservation and
    // couple access first: a replay skips the checks inside the operation body.
    // This is what Supabase's `can_upload_reserved_media_object` policy enforced.
    const asset = await ctx.db
      .query("media_assets")
      .withIndex("by_uuid", (q) => q.eq("id", stored.media_asset_id))
      .unique();
    if (!asset || asset.owner_user_id !== userId) {
      return fail("42501", "media upload reservation is not available");
    }
    if (asset.couple_id !== undefined && !(await canAccessCoupleContent(ctx, userId, asset.couple_id))) {
      fail("42501", "active entitled couple access is required");
    }
    // A queued daily answer retries reserve, upload, and finalize with the same operations
    // until it is sent, so a replay must not fail for good. A finalized asset replays as is.
    // Finalize then replays too and ignores the new bytes, which the orphan blob sweep
    // removes. A reservation that ran out before any upload is renewed.
    const now = nowIso();
    const live = asset.deleted_at === undefined && (asset.upload_status === "finalized" || asset.upload_status === "pending");
    const ranOut =
      asset.storage_id === undefined &&
      (asset.upload_status === "expired" || (asset.upload_status === "pending" && asset.deleted_at === undefined)) &&
      asset.upload_expires_at <= now;
    if (ranOut) {
      await assertNoPendingAccountDeletion(ctx, userId);
      await ctx.db.patch(
        asset._id,
        withUpdatedAt({
          upload_status: "pending" as const,
          upload_expires_at: expiresAt,
          deleted_at: undefined,
          storage_delete_status: "none" as const,
          storage_deleted_at: undefined,
        }),
      );
    } else if (!live) {
      return fail("42501", "media upload reservation is not available");
    }
    return [
      {
        ...stored,
        upload_expires_at: ranOut ? expiresAt : asset.upload_expires_at,
        upload_url: await ctx.storage.generateUploadUrl(),
      },
    ];
  },
});

// --- Finalize ---------------------------------------------------------------

/** Lowercase content type without parameters such as `; charset=utf-8`. */
function baseContentType(contentType: string | undefined): string {
  return (contentType ?? "").split(";")[0].trim().toLowerCase();
}

/** `_storage.sha256` as lowercase hex. The docs say hex, the backend has stored base64, so accept both. */
function storageSha256Hex(value: string): string {
  if (/^[0-9a-fA-F]{64}$/.test(value)) return value.toLowerCase();
  try {
    return Array.from(atob(value), (char) => char.charCodeAt(0).toString(16).padStart(2, "0")).join("");
  } catch {
    return "";
  }
}

export const finalize_media_upload = mutation({
  args: {
    p_media_asset_id: v.string(),
    p_reserved_by_client_operation_id: v.string(),
    ...clientOperationArgs,
    p_bucket: v.string(),
    p_storage_path: v.string(),
    p_storage_id: v.string(),
    p_reserved_parent_kind: v.string(),
    p_reserved_parent_id: v.string(),
    p_upload_purpose: v.string(),
    p_media_type: v.string(),
    p_mime_type: v.optional(v.union(v.null(), v.string())),
    p_byte_size: v.number(),
    p_sha256_hex: v.optional(v.union(v.null(), v.string())),
    p_width: nullableInt,
    p_height: nullableInt,
    p_duration_ms: nullableInt,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_sha256_hex == null || !/^[0-9a-fA-F]{64}$/.test(args.p_sha256_hex)) {
      fail("22023", "sha256 must be a 64 character hex string");
    }
    const sha256 = args.p_sha256_hex.toLowerCase();
    const mimeType = btrim(args.p_mime_type).toLowerCase();
    const assetId = uuidArg(args.p_media_asset_id);
    const reservedBy = uuidArg(args.p_reserved_by_client_operation_id);
    const parentId = uuidArg(args.p_reserved_parent_id);
    const width = args.p_width ?? undefined;
    const height = args.p_height ?? undefined;
    const durationMs = args.p_duration_ms ?? undefined;

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "finalize_media_upload",
        scope: "media_assets",
        request: [
          "finalize_media_upload",
          assetId,
          reservedBy,
          args.p_bucket,
          args.p_storage_path,
          args.p_reserved_parent_kind,
          parentId,
          args.p_upload_purpose,
          args.p_media_type,
          mimeType,
          args.p_byte_size,
          sha256,
          width ?? "",
          height ?? "",
          durationMs ?? "",
        ],
      }),
      async () => {
        const asset = await getByUuid(ctx, "media_assets", assetId);
        if (!asset) return fail("22023", "media asset was not found");
        if (asset.owner_user_id !== userId) fail("42501", "media asset is owned by another user");
        if (asset.couple_id !== undefined && !(await canAccessCoupleContent(ctx, userId, asset.couple_id))) {
          fail("42501", "active entitled couple access is required");
        }
        if (
          asset.reserved_by_client_operation_id !== reservedBy ||
          asset.bucket !== args.p_bucket ||
          asset.storage_path !== args.p_storage_path ||
          asset.reserved_parent_kind !== args.p_reserved_parent_kind ||
          asset.reserved_parent_id !== parentId ||
          asset.upload_purpose !== args.p_upload_purpose ||
          asset.expected_media_type !== args.p_media_type ||
          asset.expected_bucket !== args.p_bucket
        ) {
          fail("23514", "finalize request does not match the reserved upload");
        }
        if (!(args.p_byte_size > 0) || args.p_byte_size > mediaByteLimit(args.p_media_type)) {
          fail("23514", "byte size is out of range");
        }
        if (!mediaMimeMatchesType(args.p_media_type, mimeType)) {
          fail("23514", "mime type does not match media type");
        }
        if (args.p_media_type === "image" && (width === undefined || height === undefined)) {
          fail("23514", "image uploads require dimensions");
        }
        if (args.p_media_type === "voice" && durationMs === undefined) {
          fail("23514", "voice uploads require duration");
        }

        // The reserved object must exist. A finalized asset checks its own blob, so a retry
        // that uploaded the bytes again does not fail.
        const storageId =
          asset.upload_status === "finalized" && asset.storage_id
            ? asset.storage_id
            : ctx.db.system.normalizeId("_storage", args.p_storage_id);
        const blob = storageId ? await ctx.db.system.get(storageId) : null;
        if (!storageId || !blob) return fail("22023", "reserved storage object was not found");

        if (asset.upload_status === "finalized") {
          if (
            asset.byte_size === args.p_byte_size &&
            asset.mime_type === mimeType &&
            asset.sha256 === sha256 &&
            asset.width === width &&
            asset.height === height &&
            asset.duration_ms === durationMs
          ) {
            return {
              media_asset_id: asset.id,
              upload_status: asset.upload_status,
              upload_finalized_at: asset.upload_finalized_at!,
            };
          }
          fail("23505", "finalized media metadata cannot be changed");
        }
        if (asset.upload_status !== "pending") fail("23514", "media asset is not pending upload");
        if (asset.upload_expires_at <= nowIso()) fail("22023", "media upload reservation is expired");
        if (asset.deleted_at !== undefined || asset.storage_delete_status !== "none") {
          fail("23514", "media asset is queued for deletion");
        }

        // The bytes must be what the app described. A thrown error rolls the whole mutation back,
        // so a rejected blob cannot be deleted here. `sweep_orphan_storage` removes it later.
        if (blob.size !== args.p_byte_size) fail("23514", "byte size is out of range");
        if (baseContentType(blob.contentType) !== mimeType) fail("23514", "mime type does not match media type");
        if (storageSha256Hex(blob.sha256) !== sha256) fail("23514", "uploaded file does not match its sha256 checksum");
        const taken = await ctx.db
          .query("media_assets")
          .withIndex("by_storage_id", (q) => q.eq("storage_id", storageId))
          .first();
        if (taken) uniqueViolation("media_assets_storage_id_unique_idx");
        if ([width, height, durationMs].some((value) => value !== undefined && !(value > 0))) {
          checkViolation("media_assets", "media_assets_dimensions_check");
        }

        const finalizedAt = nowIso();
        await ctx.db.patch(
          asset._id,
          withUpdatedAt({
            upload_status: "finalized" as const,
            mime_type: mimeType,
            byte_size: args.p_byte_size,
            sha256,
            width,
            height,
            duration_ms: durationMs,
            upload_finalized_at: finalizedAt,
            storage_id: storageId,
          }),
        );
        return { media_asset_id: asset.id, upload_status: "finalized", upload_finalized_at: finalizedAt };
      },
    );
    return [stored];
  },
});

// --- Download ---------------------------------------------------------------

export const get_media_signed_url = mutation({
  args: {
    p_media_asset_id: v.string(),
    p_expires_in_seconds: nullableInt,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const expiresIn = args.p_expires_in_seconds ?? 900;
    if (!Number.isInteger(expiresIn) || expiresIn < 60 || expiresIn > 3600) {
      fail("23514", "signed URL expiration is out of range");
    }
    const asset = await getByUuid(ctx, "media_assets", uuidArg(args.p_media_asset_id));
    if (!asset || !(await canReadMediaAsset(ctx, userId, asset))) {
      return fail("42501", "media asset is not available");
    }
    const expiresAtSeconds = Math.floor(Date.now() / 1000) + expiresIn;
    return [
      {
        media_asset_id: asset.id,
        bucket: asset.bucket,
        storage_path: asset.storage_path,
        expires_in_seconds: expiresIn,
        signed_url_expires_at: new Date(expiresAtSeconds * 1000).toISOString(),
        signed_url: await signMediaUrl(asset.id, expiresAtSeconds),
      },
    ];
  },
});

/** What `GET /media` needs to serve an asset, or null when it cannot be served. */
export const get_media_serve_target = internalQuery({
  args: { media_asset_id: v.string() },
  handler: async (ctx, args) => {
    const asset = await getByUuid(ctx, "media_assets", args.media_asset_id);
    if (
      !asset ||
      !asset.storage_id ||
      asset.upload_status !== "finalized" ||
      asset.storage_delete_status !== "none" ||
      asset.moderation_status !== "visible"
    ) {
      return null;
    }
    return { storage_id: asset.storage_id, mime_type: asset.mime_type ?? "application/octet-stream" };
  },
});

/**
 * `GET /media?asset=&exp=&sig=`. The signature from `get_media_signed_url` is the
 * only credential, so the link works without an auth header until `exp`.
 */
export const serve_media = httpAction(async (ctx, request) => {
  const params = new URL(request.url).searchParams;
  const asset = params.get("asset") ?? "";
  const exp = params.get("exp") ?? "";
  const sig = params.get("sig") ?? "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(asset) || !/^\d{1,12}$/.test(exp)) {
    return new Response("invalid media link", { status: 400 });
  }
  const secret = process.env.PAEONIA_MEDIA_URL_SECRET;
  if (!secret) return new Response("media links are not configured", { status: 500 });
  const expected = await hmacSha256Hex(secret, `${asset}.${exp}`);
  if (!timingSafeEqual(expected, sig.toLowerCase())) {
    return new Response("invalid media link", { status: 403 });
  }
  const expiresAtMs = Number(exp) * 1000;
  if (expiresAtMs < Date.now()) return new Response("media link expired", { status: 403 });

  const target = await ctx.runQuery(internal.media.get_media_serve_target, { media_asset_id: asset });
  const blob = target ? await ctx.storage.get(target.storage_id) : null;
  if (!target || !blob) return new Response("not found", { status: 404 });
  const maxAge = Math.max(0, Math.floor((expiresAtMs - Date.now()) / 1000));
  return new Response(blob, {
    status: 200,
    headers: {
      "Content-Type": target.mime_type,
      "Cache-Control": `private, max-age=${maxAge}`,
      "X-Content-Type-Options": "nosniff",
    },
  });
});

// --- Deletion ---------------------------------------------------------------

export const mark_media_for_deletion = mutation({
  args: { p_media_asset_id: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    const userId = await requireUserId(ctx);
    const asset = await getByUuid(ctx, "media_assets", uuidArg(args.p_media_asset_id));
    if (
      !asset ||
      asset.owner_user_id !== userId ||
      asset.bucket !== "profile-photos" ||
      asset.couple_id !== undefined ||
      asset.reserved_parent_kind !== "profile_photo" ||
      asset.storage_delete_status === "deleted" ||
      (await mediaAssetHasLiveReference(ctx, asset.id))
    ) {
      return false;
    }
    await ctx.db.patch(
      asset._id,
      withUpdatedAt({
        deleted_at: asset.deleted_at ?? nowIso(),
        storage_delete_status:
          asset.storage_delete_status === "pending" || asset.storage_delete_status === "retrying"
            ? asset.storage_delete_status
            : ("pending" as const),
        last_storage_delete_error: undefined,
      }),
    );
    return true;
  },
});

// --- Storage cleanup --------------------------------------------------------
// Replaces claim_expired_pending_uploads, claim_media_storage_deletes,
// mark_media_storage_deleted, mark_media_storage_delete_failed, and the
// cleanup-media-storage Edge Function. Convex can delete a blob inside a
// mutation, so claim, delete, and mark happen in one transaction.

const STORAGE_DELETE_RETRY_MS = 15 * 60_000;
const STORAGE_DELETE_MAX_ATTEMPTS = 5;
const CLEANUP_LIMIT = 100;
// Reservations last at most 24 hours, so an unreferenced blob older than that is garbage.
const ORPHAN_BLOB_MIN_AGE_MS = 25 * HOUR_MS;
const ORPHAN_BLOB_WINDOW_MS = 24 * HOUR_MS;

/** Port of `claim_expired_pending_uploads`. A pending upload has no blob attached, so it is marked deleted directly. */
export async function expirePendingUploads(ctx: MutationCtx, now: string, limit: number): Promise<number> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) fail("23514", "pending upload claim limit is out of range");
  const expired = await ctx.db
    .query("media_assets")
    .withIndex("by_upload_status_upload_expires_at", (q) => q.eq("upload_status", "pending").lte("upload_expires_at", now))
    .take(limit);
  let count = 0;
  for (const asset of expired) {
    if (asset.storage_delete_status === "deleted") continue;
    await ctx.db.patch(
      asset._id,
      withUpdatedAt({
        upload_status: "expired" as const,
        deleted_at: asset.deleted_at ?? now,
        storage_delete_status: "deleted" as const,
        storage_deleted_at: now,
        storage_delete_attempts: asset.storage_delete_attempts + 1,
        last_storage_delete_error: undefined,
      }),
    );
    count += 1;
  }
  return count;
}

/**
 * Port of `claim_media_storage_deletes` plus the Edge Function loop. Deletes the
 * blob of every queued asset that nothing live references. Failed deletes retry
 * after `retryAfterMs` until `maxAttempts`, then stay 'failed'.
 */
export async function deleteQueuedMediaStorage(
  ctx: MutationCtx,
  options: { now: string; limit: number; retryAfterMs: number; maxAttempts: number },
): Promise<{ claimed: number; deleted: number; failed: number }> {
  const { now, limit, retryAfterMs, maxAttempts } = options;
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) fail("23514", "storage delete claim limit is out of range");
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 25) {
    fail("23514", "storage delete max attempts is out of range");
  }
  const retryBefore = addMs(now, -retryAfterMs);
  const picked: MediaAsset[] = [];
  for (const status of ["pending", "retrying"] as const) {
    const queued = ctx.db
      .query("media_assets")
      .withIndex("by_storage_delete_status_updated_at", (q) => q.eq("storage_delete_status", status));
    for await (const asset of queued) {
      if (picked.length >= limit) break;
      if (asset.storage_delete_attempts >= maxAttempts) continue;
      if (status === "retrying" && asset.updated_at > retryBefore) continue;
      if (await mediaAssetHasLiveReference(ctx, asset.id)) continue;
      picked.push(asset);
    }
  }

  let deleted = 0;
  let failed = 0;
  for (const asset of picked) {
    const attempts = asset.storage_delete_attempts + 1;
    try {
      if (asset.storage_id && (await ctx.db.system.get(asset.storage_id))) {
        await ctx.storage.delete(asset.storage_id);
      }
      await ctx.db.patch(
        asset._id,
        withUpdatedAt({
          deleted_at: asset.deleted_at ?? now,
          storage_delete_status: "deleted" as const,
          storage_deleted_at: now,
          storage_delete_attempts: attempts,
          last_storage_delete_error: undefined,
          storage_id: undefined,
        }),
      );
      deleted += 1;
    } catch (error) {
      failed += 1;
      const message = (error instanceof Error ? error.message : String(error)).slice(0, 4000);
      await ctx.db.patch(
        asset._id,
        withUpdatedAt({
          storage_delete_status: attempts >= maxAttempts ? ("failed" as const) : ("retrying" as const),
          storage_delete_attempts: attempts,
          last_storage_delete_error: message === "" ? undefined : message,
        }),
      );
    }
  }
  return { claimed: picked.length, deleted, failed };
}

/**
 * Deletes blobs that no asset points at. Uploads that never finish, and uploads
 * that `finalize_media_upload` rejected, leave such blobs, and nothing else
 * would find them. Looks only at blobs created in a 24 hour window that ends
 * 25 hours ago. Run it at least every 24 hours, and every blob gets checked.
 */
export async function sweepOrphanStorage(ctx: MutationCtx, limit: number): Promise<number> {
  const newest = Date.now() - ORPHAN_BLOB_MIN_AGE_MS;
  const blobs = await ctx.db.system
    .query("_storage")
    .withIndex("by_creation_time", (q) =>
      q.gte("_creationTime", newest - ORPHAN_BLOB_WINDOW_MS).lt("_creationTime", newest),
    )
    .take(limit);
  let removed = 0;
  for (const blob of blobs) {
    const asset = await ctx.db
      .query("media_assets")
      .withIndex("by_storage_id", (q) => q.eq("storage_id", blob._id))
      .first();
    const snapshot = asset
      ? null
      : await ctx.db
          .query("report_snapshot_assets")
          .withIndex("by_storage_id", (q) => q.eq("storage_id", blob._id))
          .first();
    if (!asset && !snapshot) {
      await ctx.storage.delete(blob._id);
      removed += 1;
    }
  }
  return removed;
}

/** The 5 minute job. Expires stale reservations, then deletes queued blobs. */
export const cleanup_media_storage = internalMutation({
  args: {
    limit: v.optional(v.number()),
    max_attempts: v.optional(v.number()),
    retry_after_ms: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = nowIso();
    const limit = args.limit ?? CLEANUP_LIMIT;
    const expired = await expirePendingUploads(ctx, now, limit);
    const storage = await deleteQueuedMediaStorage(ctx, {
      now,
      limit,
      retryAfterMs: args.retry_after_ms ?? STORAGE_DELETE_RETRY_MS,
      maxAttempts: args.max_attempts ?? STORAGE_DELETE_MAX_ATTEMPTS,
    });
    return { expired, ...storage };
  },
});

/** The 6 hour job. Queues orphaned assets nothing caught, then deletes unreferenced blobs. */
export const sweep_orphan_storage = internalMutation({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const queued = await queueOrphanedMediaAssetsForDelete(ctx, args.limit ?? 500);
    const blobs = await sweepOrphanStorage(ctx, args.limit ?? 500);
    return { queued, blobs };
  },
});
