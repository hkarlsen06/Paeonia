import type { WriterCtx, ReaderCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { fail } from "./errors";
import { isCorpseAssetReferenced } from "./exquisiteCorpse"; // Exquisite corpse
import { addMs, nowIso } from "./time";
import type { Doc } from "../_generated/dataModel";

/**
 * Orphan queueing replaces deferred constraint triggers. Postgres ran them at
 * commit time, after every write in the transaction. Call these helpers after
 * the mutation's last write to the referencing rows so liveness is judged on
 * the final state.
 */

/** Port of `internal.media_asset_has_live_reference`. */
export async function mediaAssetHasLiveReference(ctx: ReaderCtx, assetId: string): Promise<boolean> {
  const byPhoto = await ctx.db
    .query("profiles")
    .withIndex("by_profile_photo_asset_id", (q) => q.eq("profile_photo_asset_id", assetId))
    .collect();
  const byProvider = await ctx.db
    .query("profiles")
    .withIndex("by_provider_profile_photo_asset_id", (q) => q.eq("provider_profile_photo_asset_id", assetId))
    .collect();
  if ([...byPhoto, ...byProvider].some((profile) => profile.deleted_at === undefined)) {
    return true;
  }

  const answerMedia = await ctx.db
    .query("daily_answer_media")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", assetId))
    .collect();
  for (const link of answerMedia) {
    const answer = await getByUuid(ctx, "daily_question_answers", link.answer_id);
    if (answer && answer.deleted_at === undefined) return true;
  }

  const memoryMedia = await ctx.db
    .query("memory_media")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", assetId))
    .collect();
  for (const link of memoryMedia) {
    if (link.deleted_at !== undefined) continue;
    const memory = await getByUuid(ctx, "memories", link.memory_id);
    if (memory && memory.deleted_at === undefined) return true;
  }

  const stories = await ctx.db
    .query("stories")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", assetId))
    .collect();
  if (stories.some((story) => story.deleted_at === undefined)) return true;

  const messageMedia = await ctx.db
    .query("thread_message_media")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", assetId))
    .collect();
  for (const link of messageMedia) {
    const message = await getByUuid(ctx, "thread_messages", link.message_id);
    if (!message || message.deleted_at !== undefined) continue;
    const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
    if (thread && thread.deleted_at === undefined) return true;
  }

  const revisions = await ctx.db
    .query("widget_drawing_revisions")
    .withIndex("by_payload_media_asset_id", (q) => q.eq("payload_media_asset_id", assetId))
    .collect();
  for (const revision of revisions) {
    if (revision.deleted_at !== undefined) continue;
    const canvas = await getByUuid(ctx, "widget_canvases", revision.canvas_id);
    if (canvas && canvas.deleted_at === undefined) return true;
  }

  const moves = await ctx.db
    .query("game_moves")
    .withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing_media_asset_id", assetId))
    .first();
  if (moves !== null) return true;
  return await isCorpseAssetReferenced(ctx, assetId); // Exquisite corpse
}

function isQueueable(asset: Doc<"media_assets">): boolean {
  return (
    asset.bucket !== "report-snapshots" &&
    asset.upload_status === "finalized" &&
    asset.upload_finalized_at !== undefined &&
    (asset.storage_delete_status === "none" || asset.storage_delete_status === "failed")
  );
}

async function queueForDelete(ctx: WriterCtx, asset: Doc<"media_assets">): Promise<void> {
  await ctx.db.patch(
    asset._id,
    withUpdatedAt({
      deleted_at: asset.deleted_at ?? nowIso(),
      storage_delete_status: "pending" as const,
      last_storage_delete_error: undefined,
    }),
  );
}

/**
 * Port of `internal.queue_orphaned_media_asset_for_delete`. Marks a finalized
 * asset for storage deletion when nothing live references it. Returns true when
 * the asset was queued.
 */
export async function queueOrphanedMediaAssetForDelete(
  ctx: WriterCtx,
  assetId: string | null | undefined,
): Promise<boolean> {
  const asset = await getByUuid(ctx, "media_assets", assetId);
  if (!asset || !isQueueable(asset) || (await mediaAssetHasLiveReference(ctx, asset.id))) {
    return false;
  }
  await queueForDelete(ctx, asset);
  return true;
}

// A client uploads media first and attaches it in a later write, which can wait
// in the device's offline queue for days. The sweep leaves recent uploads alone
// so that write still finds its media.
const UNATTACHED_UPLOAD_GRACE_MS = 7 * 24 * 3_600_000;

/**
 * Port of `internal.queue_orphaned_media_assets_for_delete`: the sweep for
 * orphans that no write path caught. Visits one page of `limit` healthy assets,
 * oldest first, and returns the cursor for the next page (null when done). The
 * first page also retries failed deletions. Skips assets finalized within
 * `UNATTACHED_UPLOAD_GRACE_MS`.
 */
export async function queueOrphanedMediaAssetsForDelete(
  ctx: WriterCtx,
  limit = 200,
  cursor: string | null = null,
): Promise<{ queued: number; continueCursor: string | null }> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
    return fail("23514", "orphaned media queue limit is out of range");
  }
  const finalizedBefore = addMs(nowIso(), -UNATTACHED_UPLOAD_GRACE_MS);
  const page = await ctx.db
    .query("media_assets")
    .withIndex("by_storage_delete_status_updated_at", (q) => q.eq("storage_delete_status", "none"))
    .paginate({ cursor, numItems: limit });
  const failed =
    cursor === null
      ? await ctx.db
          .query("media_assets")
          .withIndex("by_storage_delete_status_updated_at", (q) => q.eq("storage_delete_status", "failed"))
          .take(limit)
      : [];
  let queued = 0;
  for (const asset of [...page.page, ...failed]) {
    if (asset.upload_finalized_at !== undefined && asset.upload_finalized_at > finalizedBefore) continue;
    if (isQueueable(asset) && !(await mediaAssetHasLiveReference(ctx, asset.id))) {
      await queueForDelete(ctx, asset);
      queued += 1;
    }
  }
  return { queued, continueCursor: page.isDone ? null : page.continueCursor };
}

/**
 * Port of `queue_old_media_asset_if_orphaned`. Call after a link row is deleted
 * or repointed, with the old media asset id. Covers daily_answer_media,
 * memory_media, thread_message_media, widget_drawing_revisions (payload asset),
 * and profile photos (pass both old photo ids).
 */
export async function queueOldMediaAssetIfOrphaned(
  ctx: WriterCtx,
  ...oldAssetIds: (string | null | undefined)[]
): Promise<void> {
  for (const assetId of oldAssetIds) {
    await queueOrphanedMediaAssetForDelete(ctx, assetId);
  }
}

/** Port of `queue_daily_answer_media_assets_if_orphaned`. Call after soft deleting an answer. */
export async function queueDailyAnswerMediaAssetsIfOrphaned(ctx: WriterCtx, answerId: string): Promise<void> {
  const links = await ctx.db
    .query("daily_answer_media")
    .withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", answerId))
    .collect();
  for (const link of links) await queueOrphanedMediaAssetForDelete(ctx, link.media_asset_id);
}

/** Port of `queue_memory_media_assets_if_orphaned`. Call after soft deleting a memory. */
export async function queueMemoryMediaAssetsIfOrphaned(ctx: WriterCtx, memoryId: string): Promise<void> {
  const links = await ctx.db
    .query("memory_media")
    .withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", memoryId))
    .collect();
  for (const link of links) await queueOrphanedMediaAssetForDelete(ctx, link.media_asset_id);
}

/** Port of `queue_thread_message_media_assets_if_orphaned`. Call after soft deleting a message. */
export async function queueThreadMessageMediaAssetsIfOrphaned(ctx: WriterCtx, messageId: string): Promise<void> {
  const links = await ctx.db
    .query("thread_message_media")
    .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", messageId))
    .collect();
  for (const link of links) await queueOrphanedMediaAssetForDelete(ctx, link.media_asset_id);
}

/** Port of `queue_thread_media_assets_if_orphaned`. Call after soft deleting a thread. */
export async function queueThreadMediaAssetsIfOrphaned(ctx: WriterCtx, threadId: string): Promise<void> {
  const messages = await ctx.db
    .query("thread_messages")
    .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", threadId))
    .collect();
  for (const message of messages) await queueThreadMessageMediaAssetsIfOrphaned(ctx, message.id);
}

/** Port of `queue_widget_payloads_if_orphaned`. Call after soft deleting a canvas. */
export async function queueWidgetPayloadsIfOrphaned(ctx: WriterCtx, canvasId: string): Promise<void> {
  const revisions = await ctx.db
    .query("widget_drawing_revisions")
    .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvasId))
    .collect();
  for (const revision of revisions) await queueOrphanedMediaAssetForDelete(ctx, revision.payload_media_asset_id);
}
