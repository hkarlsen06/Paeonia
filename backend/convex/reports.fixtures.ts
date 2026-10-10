// Shared fixtures for the report and moderation tests. The two dots keep Convex from bundling this file.
import type { Id } from "./_generated/dataModel";
import { sha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import type { TestConvex, TestCouple } from "./test.setup";

export const NOW = "2026-10-10T11:00:00.000Z";

export function operation(sequence = 1) {
  return {
    p_client_operation_id: newUuid(),
    p_client_id: "00000000-0000-0000-0000-00000000d101",
    p_client_sequence: sequence,
    p_local_created_at: NOW,
  };
}

/** A finalized, visible media asset with real bytes in file storage. */
export async function makeAsset(
  t: TestConvex,
  couple: TestCouple,
  options: { bytes?: string; path?: string; bucket?: "couple-media" | "profile-photos"; ownerUserId?: string } = {},
) {
  const bytes = new TextEncoder().encode(options.bytes ?? "photo-bytes");
  const storageId: Id<"_storage"> = await t.run((ctx) => ctx.storage.store(new Blob([bytes])));
  const sha = await sha256Hex(bytes);
  const id = newUuid();
  await t.run((ctx) =>
    ctx.db.insert("media_assets", {
      id,
      owner_user_id: options.ownerUserId ?? couple.first.userId,
      couple_id: couple.coupleId,
      reserved_parent_kind: "memory_media",
      reserved_parent_id: newUuid(),
      reserved_by_client_operation_id: newUuid(),
      bucket: options.bucket ?? "couple-media",
      storage_path: options.path ?? `${couple.coupleId}/${id}.jpg`,
      media_type: "image",
      upload_purpose: "memory_photo",
      expected_media_type: "image",
      expected_bucket: options.bucket ?? "couple-media",
      mime_type: "image/jpeg",
      byte_size: bytes.length,
      sha256: sha,
      upload_status: "finalized",
      upload_expires_at: NOW,
      upload_finalized_at: NOW,
      moderation_status: "visible",
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      storage_id: storageId,
      created_at: NOW,
      updated_at: NOW,
    }),
  );
  return { id, storageId, sha, size: bytes.length };
}

/** A visible memory written by the first partner, with optional photos. */
export async function makeMemory(t: TestConvex, couple: TestCouple, assetIds: string[] = []) {
  const id = newUuid();
  const mediaIds: string[] = [];
  await t.run(async (ctx) => {
    await ctx.db.insert("memories", {
      id,
      couple_id: couple.coupleId,
      title: "Our trip",
      memory_date: "2026-09-01",
      created_by_user_id: couple.first.userId,
      last_edited_by_user_id: couple.first.userId,
      revision: 1,
      moderation_status: "visible",
      created_at: NOW,
      updated_at: NOW,
    });
    for (const [index, assetId] of assetIds.entries()) {
      const mediaId = newUuid();
      mediaIds.push(mediaId);
      await ctx.db.insert("memory_media", {
        id: mediaId,
        memory_id: id,
        media_asset_id: assetId,
        owner_user_id: couple.first.userId,
        sort_order: index,
        moderation_status: "visible",
        created_at: NOW,
        updated_at: NOW,
      });
    }
  });
  return { id, mediaIds };
}

