import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";

// Whether a game still shows a media file. The orphan sweep (mediaOrphans.ts) asks, and it is
// reached from modules with live queries (memories, widget). These two reads stay out of the game
// libraries so the sweep does not pull every game's code into those modules' import graph.

/** The Guess My Spot round that shows `assetId`, if one does. A deleted round shows no photo. */
export async function roundWithPhoto(ctx: ReaderCtx, assetId: string): Promise<Doc<"guess_my_spot_rounds"> | null> {
  const round = await ctx.db
    .query("guess_my_spot_rounds")
    .withIndex("by_photo_media_asset_id", (q) => q.eq("photo_media_asset_id", assetId))
    .first();
  return round && round.deleted_at === undefined ? round : null;
}

/** Whether an Exquisite Corpse part holds the asset as its drawing or its strip. The orphan sweep leaves such assets alone. */
export async function isCorpseAssetReferenced(ctx: ReaderCtx, assetId: string): Promise<boolean> {
  const byDrawing = await ctx.db
    .query("exquisite_corpse_parts")
    .withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing_media_asset_id", assetId))
    .first();
  if (byDrawing) return true;
  const byStrip = await ctx.db
    .query("exquisite_corpse_parts")
    .withIndex("by_strip_media_asset_id", (q) => q.eq("strip_media_asset_id", assetId))
    .first();
  return byStrip !== null;
}
