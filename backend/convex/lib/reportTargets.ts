import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull } from "./db";
import { canAccessCoupleContent } from "./access";
import { fail } from "./errors";
import { newUuid } from "./ids";
import { addMs, nowIso } from "./time";

const REPORTABLE_MEMBER_STATUSES = ["active", "left", "ended_notice_pending", "ended_notice_seen"];
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isReportableCouple(couple: Doc<"couples">, now: string): boolean {
  return (
    couple.status === "active" ||
    (couple.status === "ended" && couple.delete_after !== undefined && couple.delete_after > now)
  );
}

/** Port of `internal.can_report_relationship_content`. */
export async function canReportRelationshipContent(
  ctx: ReaderCtx,
  coupleId: string,
  userId: string,
): Promise<boolean> {
  const member = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .unique();
  if (!member || !REPORTABLE_MEMBER_STATUSES.includes(member.status)) return false;
  const couple = await getByUuid(ctx, "couples", coupleId);
  return couple !== null && isReportableCouple(couple, nowIso());
}

/**
 * Port of `internal.find_reportable_relationship_between`. The newest couple
 * both users belong to, active first, then ended couples still inside the
 * retention window.
 */
export async function findReportableRelationshipBetween(
  ctx: ReaderCtx,
  reporterUserId: string,
  reportedUserId: string,
): Promise<{ couple_id: string; pair_id: string } | null> {
  const now = nowIso();
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", reporterUserId))
    .collect();
  let best: Doc<"couples"> | null = null;
  for (const reporter of memberships) {
    if (!REPORTABLE_MEMBER_STATUSES.includes(reporter.status)) continue;
    const reported = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", reporter.couple_id).eq("user_id", reportedUserId))
      .unique();
    if (!reported || !REPORTABLE_MEMBER_STATUSES.includes(reported.status)) continue;
    const couple = await getByUuid(ctx, "couples", reporter.couple_id);
    if (!couple || !isReportableCouple(couple, now)) continue;
    const better =
      !best ||
      (couple.status === "active" && best.status !== "active") ||
      ((couple.status === "active") === (best.status === "active") && couple.created_at > best.created_at);
    if (better) best = couple;
  }
  return best ? { couple_id: best.id, pair_id: best.pair_id } : null;
}

export type ResolvedReportTarget = {
  target_kind: string;
  reported_user_id: string;
  couple_id: string;
  pair_id: string;
  snapshot: Record<string, unknown>;
};

function stripNulls(value: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== null && item !== undefined));
}

/** The conditions `resolve_content_report_target` and the snapshot copy put on a media asset. */
function isReportableAsset(asset: Doc<"media_assets"> | null): asset is Doc<"media_assets"> {
  return (
    asset !== null &&
    asset.upload_status === "finalized" &&
    asset.storage_delete_status === "none" &&
    asset.moderation_status === "visible" &&
    asset.deleted_at === undefined
  );
}

async function pairIdOf(ctx: ReaderCtx, coupleId: string | undefined): Promise<string | null> {
  const couple = await getByUuid(ctx, "couples", coupleId);
  return couple?.pair_id ?? null;
}

async function reportableMediaIds(
  ctx: ReaderCtx,
  links: { media_asset_id: string; keep?: boolean }[],
): Promise<string[]> {
  const ids: string[] = [];
  for (const link of links) {
    if (link.keep === false) continue;
    if (isReportableAsset(await getByUuid(ctx, "media_assets", link.media_asset_id))) ids.push(link.media_asset_id);
  }
  return ids;
}

/**
 * Port of `internal.resolve_content_report_target`. Returns null when the target
 * is missing or not reportable by `reporterUserId`. Fails with 23514 for an
 * unsupported kind or a missing `thread_message_media` asset id.
 */
export async function resolveContentReportTarget(
  ctx: ReaderCtx,
  reporterUserId: string,
  targetKind: string,
  targetId: string,
  targetAuxId: string | undefined,
): Promise<ResolvedReportTarget | null> {
  switch (targetKind) {
    case "daily_answer": {
      const answer = await getByUuid(ctx, "daily_question_answers", targetId);
      if (!answer || answer.deleted_at !== undefined || answer.moderation_status !== "visible") return null;
      const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
      const coupleDay = await getByUuid(ctx, "couple_days", instance?.couple_day_id);
      if (!instance || !coupleDay) return null;
      const pairId = await pairIdOf(ctx, coupleDay.couple_id);
      if (!pairId) return null;
      // Port of `internal.can_view_daily_answer`, evaluated for the reporter.
      if (!(await canAccessCoupleContent(ctx, reporterUserId, coupleDay.couple_id))) return null;
      if (answer.user_id !== reporterUserId) {
        const own = await ctx.db
          .query("daily_question_answers")
          .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", answer.instance_id).eq("user_id", reporterUserId))
          .unique();
        if (!own || own.deleted_at !== undefined || own.moderation_status !== "visible") return null;
      }
      const text = await ctx.db
        .query("daily_answer_text")
        .withIndex("by_answer_id", (q) => q.eq("answer_id", answer.id))
        .unique();
      const links = await ctx.db
        .query("daily_answer_media")
        .withIndex("by_answer_id_sort_order", (q) => q.eq("answer_id", answer.id))
        .collect();
      return {
        target_kind: targetKind,
        reported_user_id: answer.user_id,
        couple_id: coupleDay.couple_id,
        pair_id: pairId,
        snapshot: stripNulls({
          target_kind: targetKind,
          daily_answer_id: answer.id,
          answer_user_id: answer.user_id,
          created_at: answer.created_at,
          moderation_status: answer.moderation_status,
          text_body: text?.body,
          media_asset_ids: await reportableMediaIds(ctx, links),
        }),
      };
    }
    case "memory": {
      const memory = await getByUuid(ctx, "memories", targetId);
      if (!memory || memory.deleted_at !== undefined || memory.moderation_status !== "visible") return null;
      const pairId = await pairIdOf(ctx, memory.couple_id);
      if (!pairId) return null;
      const links = await ctx.db
        .query("memory_media")
        .withIndex("by_memory_id_sort_order", (q) => q.eq("memory_id", memory.id))
        .collect();
      return {
        target_kind: targetKind,
        reported_user_id:
          memory.last_edited_by_user_id !== reporterUserId ? memory.last_edited_by_user_id : memory.created_by_user_id,
        couple_id: memory.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          memory_id: memory.id,
          title: memory.title,
          memory_date: memory.memory_date,
          created_by_user_id: memory.created_by_user_id,
          last_edited_by_user_id: memory.last_edited_by_user_id,
          moderation_status: memory.moderation_status,
          media_asset_ids: await reportableMediaIds(
            ctx,
            links.map((link) => ({
              media_asset_id: link.media_asset_id,
              keep: link.deleted_at === undefined && link.moderation_status === "visible",
            })),
          ),
        },
      };
    }
    case "memory_note": {
      const note = await getByUuid(ctx, "memory_notes", targetId);
      if (!note || note.deleted_at !== undefined || note.moderation_status !== "visible") return null;
      const memory = await getByUuid(ctx, "memories", note.memory_id);
      if (!memory || memory.deleted_at !== undefined || memory.moderation_status !== "visible") return null;
      const pairId = await pairIdOf(ctx, memory.couple_id);
      if (!pairId) return null;
      return {
        target_kind: targetKind,
        reported_user_id: note.user_id,
        couple_id: memory.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          memory_note_id: note.id,
          memory_id: note.memory_id,
          note_user_id: note.user_id,
          body: note.body,
          moderation_status: note.moderation_status,
        },
      };
    }
    case "memory_media": {
      const link = await getByUuid(ctx, "memory_media", targetId);
      if (!link || link.deleted_at !== undefined || link.moderation_status !== "visible") return null;
      const memory = await getByUuid(ctx, "memories", link.memory_id);
      if (!memory || memory.deleted_at !== undefined || memory.moderation_status !== "visible") return null;
      const pairId = await pairIdOf(ctx, memory.couple_id);
      if (!pairId || !isReportableAsset(await getByUuid(ctx, "media_assets", link.media_asset_id))) return null;
      return {
        target_kind: targetKind,
        reported_user_id: link.owner_user_id,
        couple_id: memory.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          memory_media_id: link.id,
          memory_id: link.memory_id,
          media_asset_id: link.media_asset_id,
          owner_user_id: link.owner_user_id,
          moderation_status: link.moderation_status,
        },
      };
    }
    case "thread_message": {
      const message = await getByUuid(ctx, "thread_messages", targetId);
      if (!message || message.deleted_at !== undefined || message.moderation_status !== "visible") return null;
      const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
      if (!thread || thread.deleted_at !== undefined || thread.moderation_status !== "visible") return null;
      const pairId = await pairIdOf(ctx, thread.couple_id);
      if (!pairId) return null;
      const links = await ctx.db
        .query("thread_message_media")
        .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", message.id))
        .collect();
      return {
        target_kind: targetKind,
        reported_user_id: message.sender_user_id,
        couple_id: thread.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          message_id: message.id,
          thread_id: message.thread_id,
          sender_user_id: message.sender_user_id,
          body: orNull(message.body),
          moderation_status: message.moderation_status,
          media_asset_ids: await reportableMediaIds(ctx, links),
        },
      };
    }
    case "thread_message_media": {
      if (targetAuxId === undefined) {
        return fail("23514", "thread message media reports require a media asset id");
      }
      const link = await ctx.db
        .query("thread_message_media")
        .withIndex("by_message_id_media_asset_id", (q) => q.eq("message_id", targetId).eq("media_asset_id", targetAuxId))
        .unique();
      if (!link) return null;
      const message = await getByUuid(ctx, "thread_messages", link.message_id);
      if (!message || message.deleted_at !== undefined || message.moderation_status !== "visible") return null;
      const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
      if (!thread || thread.deleted_at !== undefined || thread.moderation_status !== "visible") return null;
      const pairId = await pairIdOf(ctx, thread.couple_id);
      if (!pairId || !isReportableAsset(await getByUuid(ctx, "media_assets", link.media_asset_id))) return null;
      return {
        target_kind: targetKind,
        reported_user_id: message.sender_user_id,
        couple_id: thread.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          message_id: message.id,
          media_asset_id: link.media_asset_id,
          sender_user_id: message.sender_user_id,
        },
      };
    }
    case "widget_drawing_revision": {
      const revision = await getByUuid(ctx, "widget_drawing_revisions", targetId);
      if (!revision || revision.deleted_at !== undefined || revision.moderation_status !== "visible") return null;
      const canvas = await getByUuid(ctx, "widget_canvases", revision.canvas_id);
      if (!canvas || canvas.deleted_at !== undefined) return null;
      const pairId = await pairIdOf(ctx, canvas.couple_id);
      if (!pairId || !isReportableAsset(await getByUuid(ctx, "media_assets", revision.payload_media_asset_id))) {
        return null;
      }
      return {
        target_kind: targetKind,
        reported_user_id: revision.author_user_id,
        couple_id: canvas.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          widget_drawing_revision_id: revision.id,
          canvas_id: revision.canvas_id,
          author_user_id: revision.author_user_id,
          payload_media_asset_id: revision.payload_media_asset_id,
          moderation_status: revision.moderation_status,
        },
      };
    }
    case "media_asset": {
      const asset = await getByUuid(ctx, "media_assets", targetId);
      if (!isReportableAsset(asset) || asset.couple_id === undefined) return null;
      const pairId = await pairIdOf(ctx, asset.couple_id);
      if (!pairId) return null;
      return {
        target_kind: targetKind,
        reported_user_id: asset.owner_user_id,
        couple_id: asset.couple_id,
        pair_id: pairId,
        snapshot: {
          target_kind: targetKind,
          media_asset_id: asset.id,
          owner_user_id: asset.owner_user_id,
          bucket: asset.bucket,
          storage_path: asset.storage_path,
          media_type: asset.media_type,
          upload_purpose: asset.upload_purpose,
          moderation_status: asset.moderation_status,
        },
      };
    }
    case "profile":
    case "conduct": {
      const relationship = await findReportableRelationshipBetween(ctx, reporterUserId, targetId);
      if (!relationship) return null;
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", targetId))
        .unique();
      if (targetKind === "profile" && (!profile || profile.deleted_at !== undefined || profile.moderation_status !== "visible")) {
        return null;
      }
      return {
        target_kind: targetKind,
        reported_user_id: targetId,
        couple_id: relationship.couple_id,
        pair_id: relationship.pair_id,
        snapshot: stripNulls({
          target_kind: targetKind,
          reported_user_id: targetId,
          profile_display_name: profile?.display_name,
          profile_photo_asset_id: profile?.profile_photo_asset_id,
          profile_moderation_status: profile?.moderation_status,
        }),
      };
    }
    default:
      return fail("23514", "report target kind is not supported");
  }
}

function snapshotMediaIds(snapshot: Record<string, unknown>): string[] {
  const candidates: unknown[] = [
    ...(Array.isArray(snapshot.media_asset_ids) ? snapshot.media_asset_ids : []),
    snapshot.media_asset_id,
    snapshot.payload_media_asset_id,
    snapshot.profile_photo_asset_id,
  ];
  const ids = new Set<string>();
  for (const candidate of candidates) {
    if (typeof candidate === "string" && UUID_PATTERN.test(candidate)) ids.add(candidate.toLowerCase());
  }
  return [...ids].sort();
}

/**
 * Port of `internal.enqueue_report_snapshot_assets`. Queues a copy of every
 * finalized, visible media asset the snapshot references. Returns the number of
 * rows queued.
 */
export async function enqueueReportSnapshotAssets(
  ctx: WriterCtx,
  reportId: string,
  targetSnapshot: Record<string, unknown>,
): Promise<number> {
  let queued = 0;
  for (const assetId of snapshotMediaIds(targetSnapshot)) {
    const asset = await getByUuid(ctx, "media_assets", assetId);
    if (
      !isReportableAsset(asset) ||
      asset.bucket === "report-snapshots" ||
      asset.upload_finalized_at === undefined ||
      asset.byte_size === undefined ||
      asset.sha256 === undefined
    ) {
      continue;
    }
    const id = newUuid();
    const extension = /\.[A-Za-z0-9]{1,16}$/.exec(asset.storage_path)?.[0].toLowerCase() ?? "";
    const now = nowIso();
    await ctx.db.insert("report_snapshot_assets", {
      id,
      report_id: reportId,
      source_media_asset_id: asset.id,
      source_bucket: asset.bucket as "profile-photos" | "couple-media" | "widget-drawings",
      source_storage_path: asset.storage_path,
      bucket: "report-snapshots",
      storage_path: `${reportId}/${id}${extension}`,
      media_type: asset.media_type,
      byte_size: asset.byte_size,
      sha256: asset.sha256,
      copy_status: "pending_copy",
      copy_attempts: 0,
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      created_at: now,
      updated_at: now,
    });
    queued += 1;
  }
  return queued;
}

/** Retention for snapshots after the first moderation action: 180 days. */
export function snapshotDeleteAfter(from: string = nowIso()): string {
  return addMs(from, 180 * 86_400_000);
}
