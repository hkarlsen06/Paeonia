import { getByUuid, type ReaderCtx } from "./db";
import { isUsableMediaAsset } from "./mediaAssetState";

/** Call only after the game's projection permits this full drawing, never for a folded strip. */
export async function gameDrawingDescription(ctx: ReaderCtx, assetId: string | undefined): Promise<string | null> {
  if (!assetId) return null;
  const asset = await getByUuid(ctx, "media_assets", assetId);
  return asset && asset.media_type === "drawing_payload" && isUsableMediaAsset(asset) &&
    asset.upload_finalized_at !== undefined
    ? asset.accessibility_text ?? null : null;
}
