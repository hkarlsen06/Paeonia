import type { Doc } from "../_generated/dataModel";
import { deleteCoupleGameRows } from "./gameRegistry";
import { deleteHeartsForCouple } from "./hearts";
import { deleteLatestLocationsForCouple } from "./relationshipEnd";
import { withTouch, withUpdatedAt, type WriterCtx } from "./db";
import { tombstoneReportTargets } from "./reports";
import { createRelationshipSyncEvent } from "./syncEvents";
import { nowIso } from "./time";

/**
 * How many rows one cleanup or purge mutation may change. A row costs up to about eight database
 * calls, and a mutation may make 4096. A couple with more rows takes several mutations, each
 * scheduled by the one before it (see `relationship.ts`).
 */
export const ROWS_PER_CHUNK = 400;

/** Rows a chunk may still change. Callers that run a whole couple in one go pass nothing. */
export type ChunkBudget = { left: number };

const unlimited = (): ChunkBudget => ({ left: 1_000_000 });

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

/** Deletes the couple's notes. Returns the rows deleted. */
async function deleteCoupleNotes(ctx: WriterCtx, coupleId: string): Promise<number> {
  const notes = await ctx.db
    .query("couple_notes")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const note of notes) await ctx.db.delete(note._id);
  return notes.length;
}

/** Deletes the couple's countdowns and clears its members' birthdays. Returns the rows changed. */
async function deleteCoupleDates(ctx: WriterCtx, coupleId: string): Promise<number> {
  const countdowns = await ctx.db
    .query("countdowns")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const countdown of countdowns) await ctx.db.delete(countdown._id);
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  const withBirthday = members.filter((member) => member.birthday !== undefined);
  for (const member of withBirthday) await ctx.db.patch(member._id, withUpdatedAt({ birthday: undefined }));
  return countdowns.length + withBirthday.length;
}

// Both reads use couple-wide indexes, so a couple with years of daily questions costs a
// handful of database calls instead of a few per day.
async function coupleInstances(ctx: WriterCtx, coupleId: string) {
  const days = await ctx.db
    .query("couple_days")
    .withIndex("by_couple_id_starts_at", (q) => q.eq("couple_id", coupleId))
    .collect();
  const instances = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  return { days, instances };
}

/** The members' answers to the couple's instances. An answer is always by a member of its couple. */
async function coupleAnswers(ctx: WriterCtx, coupleId: string, instances: Doc<"daily_question_instances">[]) {
  const instanceIds = new Set(instances.map((instance) => instance.id));
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  const answers: Doc<"daily_question_answers">[] = [];
  for (const member of members) {
    const own = await ctx.db
      .query("daily_question_answers")
      .withIndex("by_user_id_created_at", (q) => q.eq("user_id", member.user_id))
      .collect();
    answers.push(...own.filter((answer) => instanceIds.has(answer.instance_id)));
  }
  return answers;
}

async function coupleAssets(ctx: WriterCtx, coupleId: string) {
  return await ctx.db
    .query("media_assets")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
    .collect();
}

/** True when hiding the row would change it. A hidden row is skipped, so a repeated chunk does no extra writes. */
const needsHiding = (row: { deleted_at?: string; moderation_status: Doc<"memories">["moderation_status"] }) =>
  row.deleted_at === undefined || row.moderation_status === "visible";

/**
 * Port of `internal.cleanup_expired_relationship_content` for one couple: hides
 * the content, queues the media for storage deletion, drops shared locations,
 * marks the couple deleted, and tells each member. Orphan queueing is skipped on purpose:
 * the final step queues every asset of the couple.
 *
 * It changes at most `budget.left` rows. When the budget runs out it returns `done: false`
 * and the caller runs it again. Rows hidden by an earlier chunk are skipped.
 * ponytail: each chunk rereads the couple's content to find what is left. Page by cursor if a couple's threads reach tens of thousands of messages.
 */
export async function cleanupCoupleContent(
  ctx: WriterCtx,
  couple: Doc<"couples">,
  now: string,
  budget: ChunkBudget = unlimited(),
): Promise<{ done: boolean; queued_media_count: number; sync_event_count: number }> {
  let queued = 0;
  const unfinished = () => ({ done: false, queued_media_count: queued, sync_event_count: 0 });

  const { instances } = await coupleInstances(ctx, couple.id);
  for (const answer of await coupleAnswers(ctx, couple.id, instances)) {
    if (!needsHiding(answer)) continue;
    if (budget.left <= 0) return unfinished();
    await ctx.db.patch(answer._id, withUpdatedAt(softDeleteFields(answer, now)));
    budget.left -= 1;
  }
  const threads = await ctx.db
    .query("conversation_threads")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const thread of threads) {
    if (needsHiding(thread)) {
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(thread._id, withUpdatedAt(softDeleteFields(thread, now)));
      budget.left -= 1;
    }
    const messages = await ctx.db
      .query("thread_messages")
      .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", thread.id))
      .collect();
    for (const message of messages) {
      if (!needsHiding(message)) continue;
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(message._id, withUpdatedAt(softDeleteFields(message, now)));
      budget.left -= 1;
    }
  }

  const memories = await ctx.db
    .query("memories")
    .withIndex("by_couple_id_memory_date_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const memory of memories) {
    if (needsHiding(memory)) {
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(memory._id, withTouch(memory, softDeleteFields(memory, now)));
      budget.left -= 1;
    }
    const notes = await ctx.db
      .query("memory_notes")
      .withIndex("by_memory_id_user_id", (q) => q.eq("memory_id", memory.id))
      .collect();
    for (const note of notes) {
      if (!needsHiding(note)) continue;
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(note._id, withTouch(note, softDeleteFields(note, now)));
      budget.left -= 1;
    }
    const media = await ctx.db
      .query("memory_media")
      .withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", memory.id))
      .collect();
    for (const item of media) {
      if (!needsHiding(item)) continue;
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(item._id, withUpdatedAt(softDeleteFields(item, now)));
      budget.left -= 1;
    }
  }

  for (const story of await ctx.db
    .query("stories")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    if (story.deleted_at !== undefined) continue;
    if (budget.left <= 0) return unfinished();
    await ctx.db.patch(story._id, { deleted_at: now });
    budget.left -= 1;
  }

  const canvases = await ctx.db
    .query("widget_canvases")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect();
  for (const canvas of canvases) {
    if (canvas.deleted_at === undefined) {
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(canvas._id, withUpdatedAt({ deleted_at: now }));
      budget.left -= 1;
    }
    const revisions = await ctx.db
      .query("widget_drawing_revisions")
      .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvas.id))
      .collect();
    for (const revision of revisions) {
      if (!needsHiding(revision)) continue;
      if (budget.left <= 0) return unfinished();
      await ctx.db.patch(revision._id, withUpdatedAt(softDeleteFields(revision, now)));
      budget.left -= 1;
    }
  }

  // Game rows have no soft delete. Their drawing media is queued with the couple's other media below.
  // The registry deletes them in one go, so a couple with a long game history can still be large.
  budget.left -= await deleteCoupleGameRows(ctx, couple.id);

  for (const asset of await coupleAssets(ctx, couple.id)) {
    const status = asset.storage_delete_status;
    if (asset.bucket === "report-snapshots" || status === "deleted") continue;
    // Queued by an earlier chunk or before the cleanup.
    if ((status === "pending" || status === "retrying") && asset.deleted_at !== undefined) continue;
    if (budget.left <= 0) return unfinished();
    queued += 1;
    await ctx.db.patch(
      asset._id,
      withUpdatedAt({
        deleted_at: asset.deleted_at ?? now,
        storage_delete_status: status === "retrying" ? ("retrying" as const) : ("pending" as const),
        last_storage_delete_error: undefined,
      }),
    );
    budget.left -= 1;
  }

  await deleteLatestLocationsForCouple(ctx, couple.id);
  await deleteHeartsForCouple(ctx, couple.id);
  await deleteCoupleDates(ctx, couple.id);
  await deleteCoupleNotes(ctx, couple.id);
  const current = (await ctx.db.get(couple._id))!;
  if (current.status === "ended") {
    await ctx.db.patch(couple._id, withUpdatedAt({ status: "deleted" as const }));
  }
  const events = await emitMemberEvents(ctx, couple, "relationship_cleanup");
  return { done: true, queued_media_count: queued, sync_event_count: events };
}

/** True when every stored file of a deleted couple is gone, which is when the hard purge may start. */
export async function isPurgeable(ctx: WriterCtx, couple: Doc<"couples">): Promise<boolean> {
  for await (const asset of ctx.db
    .query("media_assets")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", couple.id))) {
    if (asset.bucket !== "report-snapshots" && asset.storage_delete_status !== "deleted") return false;
  }
  return true;
}

/**
 * Port of `internal.purge_deleted_relationship_content` for one couple. Hard
 * deletes the couple's content. Each report target keeps its snapshot and loses
 * its live reference first.
 *
 * It changes at most `budget.left` rows. When the budget runs out it returns `done: false`
 * and the caller runs it again, and the rows deleted so far are gone from the next read.
 * The last chunk sets `purged_at` on the couple, which takes it out of the purge range.
 */
export async function purgeCoupleContent(
  ctx: WriterCtx,
  couple: Doc<"couples">,
  budget: ChunkBudget = unlimited(),
): Promise<{ done: boolean; media_rows_deleted: number; content_rows_deleted: number; sync_event_count: number }> {
  let contentDeleted = 0;
  let mediaDeleted = 0;
  const unfinished = () => ({
    done: false,
    media_rows_deleted: mediaDeleted,
    content_rows_deleted: contentDeleted,
    sync_event_count: 0,
  });
  const remove = async (row: { _id: Parameters<WriterCtx["db"]["delete"]>[0] }) => {
    await ctx.db.delete(row._id);
    contentDeleted += 1;
    budget.left -= 1;
  };

  const { days, instances } = await coupleInstances(ctx, couple.id);
  for (const instance of instances) {
    for (const answer of await ctx.db
      .query("daily_question_answers")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id))
      .collect()) {
      if (budget.left <= 0) return unfinished();
      await tombstoneReportTargets(ctx, "daily_answer", answer.id);
      for (const table of [
        "daily_answer_media",
        "daily_answer_partner_choice",
        "daily_answer_option_choice",
        "daily_answer_text",
      ] as const) {
        const rows =
          table === "daily_answer_media"
            ? await ctx.db.query(table).withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", answer.id)).collect()
            : await ctx.db.query(table).withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id)).collect();
        for (const row of rows) await remove(row);
      }
      await remove(answer);
    }
    if (budget.left <= 0) return unfinished();
    await remove(instance);
  }
  for (const link of await ctx.db
    .query("daily_question_threads")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", couple.id))
    .take(Math.max(budget.left, 1))) {
    if (budget.left <= 0) return unfinished();
    await remove(link);
  }
  for (const state of await ctx.db
    .query("daily_answer_seen_states")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .take(Math.max(budget.left, 1))) {
    if (budget.left <= 0) return unfinished();
    await remove(state);
  }
  for (const skip of await ctx.db
    .query("topic_question_skips")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", couple.id))
    .take(Math.max(budget.left, 1))) {
    if (budget.left <= 0) return unfinished();
    await remove(skip);
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
    for (const link of links) {
      if (budget.left <= 0) return unfinished();
      await remove(link);
    }
  }
  for (const thread of threads) {
    const messages = await ctx.db
      .query("thread_messages")
      .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", thread.id))
      .take(Math.max(budget.left, 1));
    for (const message of messages) {
      if (budget.left <= 0) return unfinished();
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
    // A full read of messages may leave more behind.
    if (budget.left <= 0) return unfinished();
    for (const readState of await ctx.db
      .query("thread_read_states")
      .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", thread.id))
      .collect()) {
      await remove(readState);
    }
    await remove(thread);
  }

  for (const memory of memories) {
    if (budget.left <= 0) return unfinished();
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

  for (const story of await ctx.db
    .query("stories")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", couple.id))
    .take(Math.max(budget.left, 1))) {
    if (budget.left <= 0) return unfinished();
    await remove(story);
  }

  for (const canvas of await ctx.db
    .query("widget_canvases")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id))
    .collect()) {
    for (const revision of await ctx.db
      .query("widget_drawing_revisions")
      .withIndex("by_canvas_id_created_at_id", (q) => q.eq("canvas_id", canvas.id))
      .take(Math.max(budget.left, 1))) {
      if (budget.left <= 0) return unfinished();
      await tombstoneReportTargets(ctx, "widget_drawing_revision", revision.id);
      await remove(revision);
    }
    if (budget.left <= 0) return unfinished();
    await remove(canvas);
  }

  // Normally gone since cleanup. This covers a purge that runs without it.
  // The registry deletes game rows in one go, so a couple with a long game history can still be large.
  const gameRows = await deleteCoupleGameRows(ctx, couple.id);
  contentDeleted += gameRows;
  budget.left -= gameRows;
  for (const deleted of [
    await deleteHeartsForCouple(ctx, couple.id),
    await deleteCoupleDates(ctx, couple.id),
    await deleteCoupleNotes(ctx, couple.id),
  ]) {
    contentDeleted += deleted;
    budget.left -= deleted;
  }

  for (const day of days) {
    for (const event of await ctx.db
      .query("couple_activity_events")
      .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", day.id))
      .take(Math.max(budget.left, 1))) {
      if (budget.left <= 0) return unfinished();
      await remove(event);
    }
  }
  for (const event of await ctx.db
    .query("couple_activity_events")
    .withIndex("by_couple_id_couple_day_id_activity_kind", (q) => q.eq("couple_id", couple.id))
    .take(Math.max(budget.left, 1))) {
    if (budget.left <= 0) return unfinished();
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
    .take(Math.max(budget.left, 1))) {
    if (budget.left <= 0) return unfinished();
    await remove(shuffle);
  }
  for (const day of days) {
    if (budget.left <= 0) return unfinished();
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

  for (const asset of await coupleAssets(ctx, couple.id)) {
    if (budget.left <= 0) return unfinished();
    await tombstoneReportTargets(ctx, "media_asset", asset.id);
    budget.left -= 1;
    if (asset.bucket !== "report-snapshots" && asset.storage_delete_status === "deleted") {
      await ctx.db.delete(asset._id);
      mediaDeleted += 1;
    }
  }

  await ctx.db.patch(couple._id, withUpdatedAt({ purged_at: nowIso() }));
  const events = await emitMemberEvents(ctx, couple, "relationship_hard_purge");
  return { done: true, media_rows_deleted: mediaDeleted, content_rows_deleted: contentDeleted, sync_event_count: events };
}
