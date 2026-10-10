import type { WriterCtx } from "./db";
import { fail } from "./errors";
import { nowIso } from "./time";

/** Report target kinds that have a live row to delete. 'conduct' targets have none. */
export type TombstoneTargetKind =
  | "daily_answer"
  | "memory"
  | "memory_note"
  | "memory_media"
  | "thread_message"
  | "thread_message_media"
  | "widget_drawing_revision"
  | "media_asset"
  | "profile";

/**
 * Port of the `tombstone_content_report_target` trigger. Call before hard
 * deleting a reportable row. Clears the report's live reference and stamps
 * `live_target_deleted_at`, so the report keeps its snapshot.
 *
 * `id` is the row's uuid `id` (the user id for 'profile'). For
 * 'thread_message_media' pass `{ message_id, media_asset_id }`.
 */
export async function tombstoneReportTargets(
  ctx: WriterCtx,
  targetKind: TombstoneTargetKind,
  id: string | { message_id: string; media_asset_id: string },
): Promise<void> {
  const now = nowIso();
  const clear = async (
    rows: { _id: import("../_generated/dataModel").Id<"content_report_targets">; live_target_deleted_at?: string }[],
    cleared: Record<string, undefined>,
  ) => {
    for (const row of rows) {
      await ctx.db.patch(row._id, { ...cleared, live_target_deleted_at: row.live_target_deleted_at ?? now });
    }
  };
  const matching = <T extends { target_kind: string }>(rows: T[]) =>
    rows.filter((row) => row.target_kind === targetKind);

  if (typeof id !== "string") {
    if (targetKind !== "thread_message_media") {
      fail("23514", `content report tombstone trigger is not configured for ${targetKind}`);
    }
    const rows = await ctx.db
      .query("content_report_targets")
      .withIndex("by_message_media_message_id_message_media_asset_id", (q) =>
        q.eq("message_media_message_id", id.message_id).eq("message_media_asset_id", id.media_asset_id),
      )
      .collect();
    await clear(matching(rows), { message_media_message_id: undefined, message_media_asset_id: undefined });
    return;
  }

  const byIndex = async (
    index:
      | "by_daily_answer_id"
      | "by_memory_id"
      | "by_memory_note_id"
      | "by_memory_media_id"
      | "by_message_id"
      | "by_widget_drawing_revision_id"
      | "by_media_asset_id"
      | "by_profile_user_id",
    field: string,
  ) => {
    const rows = await ctx.db
      .query("content_report_targets")
      .withIndex(index as "by_memory_id", (q) => q.eq(field as "memory_id", id))
      .collect();
    await clear(matching(rows), { [field]: undefined });
  };

  switch (targetKind) {
    case "daily_answer":
      return await byIndex("by_daily_answer_id", "daily_answer_id");
    case "memory":
      return await byIndex("by_memory_id", "memory_id");
    case "memory_note":
      return await byIndex("by_memory_note_id", "memory_note_id");
    case "memory_media":
      return await byIndex("by_memory_media_id", "memory_media_id");
    case "thread_message":
      return await byIndex("by_message_id", "message_id");
    case "widget_drawing_revision":
      return await byIndex("by_widget_drawing_revision_id", "widget_drawing_revision_id");
    case "media_asset":
      return await byIndex("by_media_asset_id", "media_asset_id");
    case "profile":
      return await byIndex("by_profile_user_id", "profile_user_id");
    default:
      return fail("23514", `content report tombstone trigger is not configured for ${targetKind}`);
  }
}

