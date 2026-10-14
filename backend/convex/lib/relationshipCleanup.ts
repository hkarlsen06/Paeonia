import type { Doc } from "../_generated/dataModel";
import { deleteCoupleGameRows } from "./gameRegistry";
import { deleteLatestLocationsForCouple } from "./relationshipEnd";
import { withTouch, withUpdatedAt, type WriterCtx } from "./db";
import { tombstoneReportTargets } from "./reports";
import { createRelationshipSyncEvent } from "./syncEvents";

// ponytail: one couple's cleanup and purge each run inside one Convex mutation, so a couple
// with more than about 8000 content rows (Convex's per-transaction write limit) will not
// finish. Upgrade path: delete in chunks and reschedule until the couple is empty.

const PURGE_SCOPE = { relationship_content: "purge", location: "purge", widget_cache: "purge", pending_uploads: "purge" };

function softDeleteFields(row: { deleted_at?: string; moderation_status: Doc<"memories">["moderation_status"] }, now: string) {
  return {
    deleted_at: row.deleted_at ?? now,
    moderation_status: row.moderation_status === "visible" ? ("hidden" as const) : row.moderation_status,
  };
}

async function emitMemberEvents(
  ctx: WriterCtx,
  couple: Doc<"couples">,
  reason: "relationship_cleanup" | "relationship_hard_purge",
): Promise<number> {
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const member of members) {
    await createRelationshipSyncEvent(ctx, {
      user_id: member.user_id,
      couple_id: couple.id,
      initiated_by_user_id: null,
      event_kind: "content_purged",
      reason,
      relationship_status: "deleted",
      member_status: member.status,
      ended_at: couple.ended_at ?? null,
      delete_after: couple.delete_after ?? null,
      local_purge_scope: PURGE_SCOPE,
    });
  }
  return members.length;
}

async function coupleInstances(ctx: WriterCtx, coupleId: string) {
  const days = await ctx.db
    .query("couple_days")
    .withIndex("by_couple_id_starts_at", (q) => q.eq("couple_id", coupleId))
    .collect();
  const instances: Doc<"daily_question_instances">[] = [];
  for (const day of days) {
    instances.push(
      ...(await ctx.db
        .query("daily_question_instances")
        .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) => q.eq("couple_day_id", day.id))
        .collect()),
    );
  }
  return { days, instances };
}

async function coupleAnswers(ctx: WriterCtx, instances: Doc<"daily_question_instances">[]) {
  const answers: Doc<"daily_question_answers">[] = [];
  for (const instance of instances) {
    answers.push(
      ...(await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id))
        .collect()),
    );
  }
  return answers;
}

async function coupleAssets(ctx: WriterCtx, coupleId: string) {
  return await ctx.db
    .query("media_assets")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
    .collect();
}

/**
 * Port of `internal.cleanup_expired_relationship_content` for one couple: hides
 * the content, queues the media for storage deletion, drops shared locations,
 * marks the couple deleted, and tells each member. Returns the media count.
 * Orphan queueing is skipped on purpose: the final step queues every asset of the couple.
 */
export async function cleanupCoupleContent(
  ctx: WriterCtx,
  couple: Doc<"couples">,
  now: string,
): Promise<{ queued_media_count: number; sync_event_count: number }> {
  const { instances } = await coupleInstances(ctx, couple.id);
  for (const answer of await coupleAnswers(ctx, instances)) {
    await ctx.db.patch(answer._id, withUpdatedAt(softDeleteFields(answer, now)));
  }
  const threads = await ctx.db
    .query("conversation_threads")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const thread of threads) {
    await ctx.db.patch(thread._id, withUpdatedAt(softDeleteFields(thread, now)));
    const messages = await ctx.db
      .query("thread_messages")
      .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", thread.id))
      .collect();
    for (const message of messages) {
      await ctx.db.patch(message._id, withUpdatedAt(softDeleteFields(message, now)));
    }
  }

  const memories = await ctx.db
    .query("memories")
    .withIndex("by_couple_id_memory_date_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const memory of memories) {
    await ctx.db.patch(memory._id, withTouch(memory, softDeleteFields(memory, now)));
    const notes = await ctx.db
      .query("memory_notes")
      .withIndex("by_memory_id_user_id", (q) => q.eq("memory_id", memory.id))
      .collect();
    for (const note of notes) {
      await ctx.db.patch(note._id, withTouch(note, softDeleteFields(note, now)));
    }
    const media = await ctx.db
      .query("memory_media")
      .withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", memory.id))
      .collect();
    for (const item of media) {
      await ctx.db.patch(item._id, withUpdatedAt(softDeleteFields(item, now)));
    }
  }

  const canvases = await ctx.db
    .query("widget_canvases")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const canvas of canvases) {
    await ctx.db.patch(canvas._id, withUpdatedAt({ deleted_at: canvas.deleted_at ?? now }));
    const revisions = await ctx.db
      .query("widget_drawing_revisions")
      .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvas.id))
      .collect();
    for (const revision of revisions) {
      await ctx.db.patch(revision._id, withUpdatedAt(softDeleteFields(revision, now)));
    }
  }

  // Game rows have no soft delete. Their drawing media is queued with the couple's other media below.
  await deleteCoupleGameRows(ctx, couple.id);

  let queued = 0;
  for (const asset of await coupleAssets(ctx, couple.id)) {
    if (asset.bucket === "report-snapshots" || asset.storage_delete_status === "deleted") continue;
    queued += 1;
    await ctx.db.patch(
      asset._id,
      withUpdatedAt({
        deleted_at: asset.deleted_at ?? now,
        storage_delete_status:
          asset.storage_delete_status === "retrying" ? ("retrying" as const) : ("pending" as const),
        last_storage_delete_error: undefined,
      }),
    );
  }

  await deleteLatestLocationsForCouple(ctx, couple.id);
  const current = (await ctx.db.get(couple._id))!;
  if (current.status === "ended") {
    await ctx.db.patch(couple._id, withUpdatedAt({ status: "deleted" as const }));
  }
  const events = await emitMemberEvents(ctx, couple, "relationship_cleanup");
  return { queued_media_count: queued, sync_event_count: events };
}

/** True when a deleted couple is ready for the hard purge. */
export async function isPurgeable(ctx: WriterCtx, couple: Doc<"couples">): Promise<boolean> {
  const assets = await coupleAssets(ctx, couple.id);
  if (assets.some((asset) => asset.bucket !== "report-snapshots" && asset.storage_delete_status !== "deleted")) {
    return false;
  }
  const events = await ctx.db
    .query("relationship_sync_events")
    .withIndex("by_couple_id_created_at_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  return !events.some((event) => event.event_kind === "content_purged" && event.reason === "relationship_hard_purge");
}

/**
 * Port of `internal.purge_deleted_relationship_content` for one couple. Hard
 * deletes the couple's content. Each report target keeps its snapshot and loses
 * its live reference first.
 */
export async function purgeCoupleContent(
  ctx: WriterCtx,
  couple: Doc<"couples">,
): Promise<{ media_rows_deleted: number; content_rows_deleted: number; sync_event_count: number }> {
  let contentDeleted = 0;
  const remove = async (row: { _id: Parameters<WriterCtx["db"]["delete"]>[0] }) => {
    await ctx.db.delete(row._id);
    contentDeleted += 1;
  };

  const { days, instances } = await coupleInstances(ctx, couple.id);
  const answers = await coupleAnswers(ctx, instances);
  for (const answer of answers) {
    await tombstoneReportTargets(ctx, "daily_answer", answer.id);
    for (const table of ["daily_answer_media", "daily_answer_partner_choice", "daily_answer_text"] as const) {
      const rows =
        table === "daily_answer_media"
          ? await ctx.db.query(table).withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", answer.id)).collect()
          : await ctx.db.query(table).withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id)).collect();
      for (const row of rows) await remove(row);
    }
  }
  for (const instance of instances) {
    const links = await ctx.db
      .query("daily_question_threads")
      .withIndex("by_instance_id", (q) => q.eq("instance_id", instance.id))
      .collect();
    for (const link of links) await remove(link);
  }
  for (const state of await ctx.db
    .query("daily_answer_seen_states")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    await remove(state);
  }

  const threads = await ctx.db
    .query("conversation_threads")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", couple.id))
    .collect();
  const memories = await ctx.db
    .query("memories")
    .withIndex("by_couple_id_memory_date_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const memory of memories) {
    const links = await ctx.db
      .query("memory_threads")
      .withIndex("by_memory_id", (q) => q.eq("memory_id", memory.id))
      .collect();
    for (const link of links) await remove(link);
  }
  for (const thread of threads) {
    const messages = await ctx.db
      .query("thread_messages")
      .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", thread.id))
      .collect();
    for (const message of messages) {
      const media = await ctx.db
        .query("thread_message_media")
        .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", message.id))
        .collect();
      for (const item of media) {
        await tombstoneReportTargets(ctx, "thread_message_media", {
          message_id: message.id,
          media_asset_id: item.media_asset_id,
        });
        await remove(item);
      }
      await tombstoneReportTargets(ctx, "thread_message", message.id);
      await remove(message);
    }
    for (const readState of await ctx.db
      .query("thread_read_states")
      .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", thread.id))
      .collect()) {
      await remove(readState);
    }
    await remove(thread);
  }

  for (const memory of memories) {
    for (const item of await ctx.db
      .query("memory_media")
      .withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", memory.id))
      .collect()) {
      await tombstoneReportTargets(ctx, "memory_media", item.id);
      await remove(item);
    }
    for (const note of await ctx.db
      .query("memory_notes")
      .withIndex("by_memory_id_user_id", (q) => q.eq("memory_id", memory.id))
      .collect()) {
      await tombstoneReportTargets(ctx, "memory_note", note.id);
      await remove(note);
    }
    await tombstoneReportTargets(ctx, "memory", memory.id);
    await remove(memory);
  }

  for (const canvas of await ctx.db
    .query("widget_canvases")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    for (const revision of await ctx.db
      .query("widget_drawing_revisions")
      .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvas.id))
      .collect()) {
      await tombstoneReportTargets(ctx, "widget_drawing_revision", revision.id);
      await remove(revision);
    }
    await remove(canvas);
  }

  // Normally gone since cleanup. This covers a purge that runs without it.
  contentDeleted += await deleteCoupleGameRows(ctx, couple.id);

  for (const day of days) {
    for (const event of await ctx.db
      .query("couple_activity_events")
      .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", day.id))
      .collect()) {
      await remove(event);
    }
  }
  for (const event of await ctx.db
    .query("couple_activity_events")
    .withIndex("by_couple_id_couple_day_id_activity_kind", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    await remove(event);
  }
  for (const streak of await ctx.db
    .query("streak_states")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    await remove(streak);
  }
  for (const shuffle of await ctx.db
    .query("daily_question_shuffles")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    await remove(shuffle);
  }
  for (const answer of answers) await remove(answer);
  for (const instance of instances) await remove(instance);
  for (const day of days) {
    for (const challenge of await ctx.db
      .query("daily_challenges")
      .withIndex("by_couple_day_id_user_id", (q) => q.eq("couple_day_id", day.id))
      .collect()) {
      await remove(challenge);
    }
    await remove(day);
  }
  for (const preference of await ctx.db
    .query("location_sharing_preferences")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    await remove(preference);
  }

  let mediaDeleted = 0;
  for (const asset of await coupleAssets(ctx, couple.id)) {
    await tombstoneReportTargets(ctx, "media_asset", asset.id);
    if (asset.bucket !== "report-snapshots" && asset.storage_delete_status === "deleted") {
      await ctx.db.delete(asset._id);
      mediaDeleted += 1;
    }
  }

  const events = await emitMemberEvents(ctx, couple, "relationship_hard_purge");
  return { media_rows_deleted: mediaDeleted, content_rows_deleted: contentDeleted, sync_event_count: events };
}
