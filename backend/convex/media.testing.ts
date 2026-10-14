// Shared fixtures for the media, memories, threads, and widget tests. The two dots in the
// file name keep Convex from bundling it, and vitest does not run it.
import { api } from "./_generated/api";
import { sha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { nowIso } from "./lib/time";
import type { TestConvex, TestUser } from "./test.setup";

export function setMediaEnv() {
  process.env.PAEONIA_MEDIA_URL_SECRET = "test-media-secret";
  process.env.CONVEX_SITE_URL = "https://actions.example.test";
}

let sequence = 0;
const clientId = newUuid();

/** Fresh client-operation arguments. Pass `operationId` to replay an operation. */
export function op(operationId: string = newUuid()) {
  sequence += 1;
  return {
    p_client_operation_id: operationId,
    p_client_id: clientId,
    p_client_sequence: sequence,
    p_local_created_at: nowIso(),
  };
}

/** The error a failed Convex function threw: `{ code, message }`. */
export async function failure(promise: Promise<unknown>): Promise<{ code: string; message: string }> {
  try {
    await promise;
  } catch (error) {
    const data = (error as { data?: unknown }).data;
    if (data && typeof data === "object" && "code" in data) {
      return data as { code: string; message: string };
    }
    throw error;
  }
  throw new Error("expected the call to fail");
}

/** Stores bytes the way an upload URL does, including the content type Convex records. */
export async function storeBlob(t: TestConvex, bytes: Uint8Array, contentType: string): Promise<string> {
  return await t.run(async (ctx) => {
    const storageId = await ctx.storage.store(new Blob([bytes as BlobPart], { type: contentType }));
    // convex-test does not record the content type, the real backend does.
    await ctx.db.patch(storageId as never, { contentType } as never);
    return storageId;
  });
}

export type UploadSpec = {
  kind: "memory_media" | "thread_message_media" | "daily_answer_media" | "widget_drawing_revision" | "game_move" | "exquisite_corpse_part" | "profile_photo";
  purpose: "memory_photo" | "voice_note" | "thread_media" | "daily_answer_media" | "widget_drawing_payload" | "game_drawing_payload" | "exquisite_corpse_drawing" | "exquisite_corpse_strip" | "profile_photo";
  mediaType: "image" | "voice" | "drawing_payload";
  extension: string;
  mime: string;
  parentId?: string;
  coupleId?: string;
  canvasId?: string;
  gameId?: string;
  bytes?: Uint8Array;
};

export type Uploaded = {
  assetId: string;
  parentId: string;
  storageId: string;
  bucket: string;
  storagePath: string;
  bytes: Uint8Array;
  sha256: string;
  reserveOperationId: string;
};

export const photo = (coupleId: string, kind: UploadSpec["kind"] = "memory_media", purpose: UploadSpec["purpose"] = "memory_photo"): UploadSpec => ({
  kind,
  purpose,
  mediaType: "image",
  extension: "jpg",
  mime: "image/jpeg",
  coupleId,
});

/** Reserves, uploads, and finalizes one asset, like the app does. */
export async function uploadAsset(t: TestConvex, user: TestUser, spec: UploadSpec): Promise<Uploaded> {
  const parentId = spec.parentId ?? newUuid();
  const bytes = spec.bytes ?? new TextEncoder().encode(`bytes-${newUuid()}`);
  const reserveOperationId = newUuid();
  const [reservation] = await user.as.mutation(api.media.create_pending_media_upload, {
    ...op(reserveOperationId),
    p_reserved_parent_kind: spec.kind,
    p_reserved_parent_id: parentId,
    p_upload_purpose: spec.purpose,
    p_media_type: spec.mediaType,
    p_file_extension: spec.extension,
    ...(spec.coupleId ? { p_couple_id: spec.coupleId } : {}),
    ...(spec.canvasId ? { p_path_context: { canvas_id: spec.canvasId } } : {}),
    ...(spec.gameId ? { p_path_context: { game_id: spec.gameId } } : {}),
  });
  const storageId = await storeBlob(t, bytes, spec.mime);
  const sha256 = await sha256Hex(bytes);
  await user.as.mutation(api.media.finalize_media_upload, {
    ...op(),
    p_media_asset_id: reservation.media_asset_id,
    p_reserved_by_client_operation_id: reserveOperationId,
    p_bucket: reservation.bucket,
    p_storage_path: reservation.storage_path,
    p_storage_id: storageId,
    p_reserved_parent_kind: spec.kind,
    p_reserved_parent_id: parentId,
    p_upload_purpose: spec.purpose,
    p_media_type: spec.mediaType,
    p_mime_type: spec.mime,
    p_byte_size: bytes.length,
    p_sha256_hex: sha256,
    ...(spec.mediaType === "image" ? { p_width: 100, p_height: 80 } : {}),
    ...(spec.mediaType === "voice" ? { p_duration_ms: 1500 } : {}),
  });
  return {
    assetId: reservation.media_asset_id,
    parentId,
    storageId,
    bucket: reservation.bucket,
    storagePath: reservation.storage_path,
    bytes,
    sha256,
    reserveOperationId,
  };
}

/** Ends the couple the way leave_relationship does: the leaver is 'left', the partner gets a notice. */
export async function endCouple(t: TestConvex, coupleId: string, leaverUserId: string): Promise<void> {
  await t.run(async (ctx) => {
    const couple = await ctx.db
      .query("couples")
      .withIndex("by_pair_id_status")
      .filter((q) => q.eq(q.field("id"), coupleId))
      .unique();
    await ctx.db.patch(couple!._id, { status: "ended", ended_at: nowIso() });
    const members = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
      .collect();
    for (const member of members) {
      await ctx.db.patch(member._id, {
        status: member.user_id === leaverUserId ? "left" : "ended_notice_pending",
      });
    }
  });
}

/** A user who belongs to no couple. */
export { createSignedInUser } from "./test.setup";
