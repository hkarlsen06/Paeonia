import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { reactionsOf } from "./reactions";
import { isUsableMediaAsset } from "./mediaAssetState";

/** The shared safe wire projection for a message page or a merged game timeline. */
export async function projectThreadMessages(ctx: ReaderCtx, thread: Doc<"conversation_threads">, messages: Doc<"thread_messages">[]) {
  const threadVisible = thread.deleted_at === undefined && thread.moderation_status === "visible";
  const rows = [];
  for (const message of messages) {
    // A message its sender took back stays as a bare marker: no text, media or reactions.
    if (threadVisible && message.deleted_at !== undefined && message.moderation_status === "visible") {
      rows.push({
        thread_id: thread.id,
        message_id: message.id,
        sender_user_id: message.sender_user_id,
        body: null,
        reply_to_message_id: null,
        reply_to_answer_id: null,
        reply_to_game_result_source: null,
        created_at: message.created_at,
        edited_at: null,
        deleted_at: message.deleted_at,
        moderation_status: message.moderation_status,
        media_asset_ids: [],
        media: [],
        media_states: [],
        reactions: [],
      });
      continue;
    }
    const messageVisible = threadVisible && message.deleted_at === undefined && message.moderation_status === "visible";
    const links = (
      await ctx.db
        .query("thread_message_media")
        .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", message.id))
        .collect()
    ).sort((a, b) => a.sort_order - b.sort_order || (a.media_asset_id < b.media_asset_id ? -1 : 1));
    const mediaAssetIds: string[] = [];
    // The shown attachments with what the app needs to lay them out before downloading.
    const media = [];
    const mediaStates = [];
    for (const link of links) {
      const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
      if (!asset) continue;
      if (
        messageVisible &&
        asset.reserved_parent_kind === "thread_message_media" &&
        asset.reserved_parent_id === message.id &&
        isUsableMediaAsset(asset)
      ) {
        mediaAssetIds.push(link.media_asset_id);
        media.push({
          media_asset_id: link.media_asset_id,
          media_type: asset.media_type,
          accessibility_text: asset.accessibility_text ?? null,
          width: asset.width ?? null,
          height: asset.height ?? null,
          duration_ms: asset.duration_ms ?? null,
        });
      }
      mediaStates.push({
        media_asset_id: link.media_asset_id,
        sort_order: link.sort_order,
        asset_deleted_at: asset.deleted_at ?? null,
        asset_moderation_status: asset.moderation_status,
        asset_storage_delete_status: asset.storage_delete_status,
        updated_at: asset.updated_at,
      });
    }
    // Who reacted with what. A removed message shows none.
    const reactions = messageVisible ? await reactionsOf(ctx, "thread_message", message.id) : [];
    rows.push({
      thread_id: thread.id,
      message_id: message.id,
      sender_user_id: message.sender_user_id,
      body: messageVisible ? message.body ?? null : null,
      reply_to_message_id: message.reply_to_message_id ?? null,
      reply_to_answer_id: message.reply_to_answer_id ?? null,
      reply_to_game_result_source: message.reply_to_game_result_source ?? null,
      created_at: message.created_at,
      edited_at: message.edited_at ?? null,
      deleted_at: message.deleted_at ?? null,
      moderation_status: message.moderation_status,
      media_asset_ids: mediaAssetIds,
      media,
      media_states: mediaStates,
      reactions,
    });
  }
  return rows;
}
