import type { Doc } from "../_generated/dataModel";

type AssetLifecycle = Pick<Doc<"media_assets">, "upload_status" | "storage_delete_status" | "moderation_status" | "deleted_at">;

/**
 * The upload finished, nothing queued it for deletion, moderation shows it, and nobody deleted it.
 * Every read and every serve of an asset goes through this one check.
 */
export function isUsableMediaAsset(asset: AssetLifecycle): boolean {
  return (
    asset.upload_status === "finalized" &&
    asset.storage_delete_status === "none" &&
    asset.moderation_status === "visible" &&
    asset.deleted_at === undefined
  );
}
