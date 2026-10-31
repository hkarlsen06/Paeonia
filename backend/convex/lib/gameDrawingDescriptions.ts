import { getByUuid, type ReaderCtx } from "./db";

/** Call only after the game's projection permits this full drawing, never for a folded strip. */
export async function gameDrawingDescription(ctx: ReaderCtx, assetId: string | undefined): Promise<string | null> {
  if (!assetId) return null;
  const asset = await getByUuid(ctx, "media_assets", assetId);
  return asset && asset.media_type === "drawing_payload" && asset.upload_status === "finalized" &&
    asset.upload_finalized_at !== undefined && asset.deleted_at === undefined &&
    asset.moderation_status === "visible" && asset.storage_delete_status === "none"
    ? asset.accessibility_text ?? null : null;
}
