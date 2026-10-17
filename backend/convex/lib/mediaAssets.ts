import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent } from "./access";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { fail } from "./errors";
import { canReadCorpseAsset } from "./exquisiteCorpse"; // Exquisite corpse

/** Port of `internal.media_byte_limit`. */
export function mediaByteLimit(mediaType: string): number {
  switch (mediaType) {
    case "image":
    case "drawing_payload":
      return 10_485_760;
    case "voice":
    case "report_snapshot":
      return 52_428_800;
    default:
      return 0;
  }
}

const MIME_TYPES: Record<string, string[]> = {
  image: ["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"],
  voice: ["audio/mp4", "audio/mpeg", "audio/aac", "audio/wav", "audio/x-caf"],
  drawing_payload: ["application/octet-stream", "application/x-pkdrawing"],
  report_snapshot: ["image/jpeg", "image/png", "application/pdf", "application/json"],
};

const EXTENSIONS: Record<string, string[]> = {
  image: ["jpg", "png", "heic", "heif", "webp"],
  voice: ["m4a", "mp4", "aac", "caf", "wav", "mp3"],
  drawing_payload: ["pkdrawing"],
  report_snapshot: ["jpg", "png", "pdf", "json"],
};

/** Port of `internal.media_mime_matches_type`. Expects a trimmed, lowercase mime type. */
export function mediaMimeMatchesType(mediaType: string, mimeType: string): boolean {
  return (MIME_TYPES[mediaType] ?? []).includes(mimeType.trim().toLowerCase());
}

/** Port of `internal.media_extension_matches_type`. */
export function mediaExtensionMatchesType(mediaType: string, extension: string): boolean {
  return (EXTENSIONS[mediaType] ?? []).includes(extension);
}

/** Port of `internal.normalize_media_file_extension`. */
export function normalizeMediaFileExtension(extension: string | null | undefined): string {
  let normalized = (extension ?? "").replace(/^ +| +$/g, "").toLowerCase();
  normalized = normalized.replace(/^\.+/, "");
  if (!/^[a-z0-9]{1,16}$/.test(normalized)) {
    fail("22023", "file extension is not supported");
  }
  return normalized === "jpeg" ? "jpg" : normalized;
}

/** Port of `internal.can_view_daily_answer` for `userId`. */
export async function canViewDailyAnswer(ctx: ReaderCtx, userId: string, answerId: string): Promise<boolean> {
  const answer = await getByUuid(ctx, "daily_question_answers", answerId);
  if (!answer || answer.deleted_at !== undefined || answer.moderation_status !== "visible") return false;
  const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
  const day = instance ? await getByUuid(ctx, "couple_days", instance.couple_day_id) : null;
  if (!day || !(await canAccessCoupleContent(ctx, userId, day.couple_id))) return false;
  if (answer.user_id === userId) return true;
  const own = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", answer.instance_id).eq("user_id", userId))
    .unique();
  return own !== null && own.deleted_at === undefined && own.moderation_status === "visible";
}

async function canReadProfilePhoto(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  if (asset.owner_user_id === userId) return true;
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", asset.owner_user_id))
    .unique();
  if (
    !profile ||
    (profile.profile_photo_asset_id !== asset.id && profile.provider_profile_photo_asset_id !== asset.id) ||
    profile.moderation_status !== "visible" ||
    profile.deleted_at !== undefined
  ) {
    return false;
  }
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", asset.owner_user_id).eq("status", "active"))
    .collect();
  for (const membership of memberships) {
    if (await canAccessCoupleContent(ctx, userId, membership.couple_id)) return true;
  }
  return false;
}

async function canReadDailyAnswerMedia(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const links = await ctx.db
    .query("daily_answer_media")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", asset.id))
    .collect();
  for (const link of links) {
    if (await canViewDailyAnswer(ctx, userId, link.answer_id)) return true;
  }
  return false;
}

async function canReadThreadMessageMedia(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const links = await ctx.db
    .query("thread_message_media")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", asset.id))
    .collect();
  for (const link of links) {
    const message = await getByUuid(ctx, "thread_messages", link.message_id);
    if (
      !message ||
      asset.reserved_parent_id !== message.id ||
      message.deleted_at !== undefined ||
      message.moderation_status !== "visible"
    ) {
      continue;
    }
    const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
    if (
      !thread ||
      thread.deleted_at !== undefined ||
      thread.moderation_status !== "visible" ||
      thread.couple_id !== asset.couple_id ||
      !(await canAccessCoupleContent(ctx, userId, thread.couple_id))
    ) {
      continue;
    }
    if (thread.kind !== "memory") return true;
    const memoryLink = await ctx.db
      .query("memory_threads")
      .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
      .unique();
    const memory = memoryLink ? await getByUuid(ctx, "memories", memoryLink.memory_id) : null;
    if (memory && memory.deleted_at === undefined && memory.moderation_status === "visible") return true;
  }
  return false;
}

async function canReadMemoryMedia(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const links = await ctx.db
    .query("memory_media")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", asset.id))
    .collect();
  for (const link of links) {
    if (asset.reserved_parent_id !== link.id || link.deleted_at !== undefined || link.moderation_status !== "visible") {
      continue;
    }
    const memory = await getByUuid(ctx, "memories", link.memory_id);
    if (
      memory &&
      memory.deleted_at === undefined &&
      memory.moderation_status === "visible" &&
      memory.couple_id === asset.couple_id &&
      (await canAccessCoupleContent(ctx, userId, memory.couple_id))
    ) {
      return true;
    }
  }
  return false;
}

async function canReadWidgetPayload(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const revisions = await ctx.db
    .query("widget_drawing_revisions")
    .withIndex("by_payload_media_asset_id", (q) => q.eq("payload_media_asset_id", asset.id))
    .collect();
  for (const revision of revisions) {
    if (asset.reserved_parent_id !== revision.id || revision.deleted_at !== undefined || revision.moderation_status !== "visible") {
      continue;
    }
    const canvas = await getByUuid(ctx, "widget_canvases", revision.canvas_id);
    if (
      canvas &&
      canvas.deleted_at === undefined &&
      canvas.couple_id === asset.couple_id &&
      (await canAccessCoupleContent(ctx, userId, canvas.couple_id))
    ) {
      return true;
    }
  }
  return false;
}

async function canReadGameDrawing(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const moves = await ctx.db
    .query("game_moves")
    .withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing_media_asset_id", asset.id))
    .collect();
  return moves.some((move) => move.id === asset.reserved_parent_id && move.couple_id === asset.couple_id) &&
    (await canAccessCoupleContent(ctx, userId, asset.couple_id!));
}

async function canReadStoryPhoto(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const stories = await ctx.db
    .query("stories")
    .withIndex("by_media_asset_id", (q) => q.eq("media_asset_id", asset.id))
    .collect();
  return (
    stories.some((story) => story.id === asset.reserved_parent_id && story.deleted_at === undefined && story.couple_id === asset.couple_id) &&
    (await canAccessCoupleContent(ctx, userId, asset.couple_id!))
  );
}

/** Before pairing, only the inviter reads the drawing their first day draft holds. */
async function canReadFirstDayDrawing(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  if (asset.owner_user_id !== userId || asset.reserved_parent_kind !== "widget_drawing_revision" || asset.bucket !== "widget-drawings") {
    return false;
  }
  const draft = await ctx.db
    .query("first_day_drafts")
    .withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing.media_asset_id", asset.id))
    .first();
  return draft?.user_id === userId;
}

/**
 * Port of `internal.can_read_media_object`, which backed both the
 * `storage.objects` select policy and `get_media_signed_url`.
 */
export async function canReadMediaAsset(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  if (
    asset.bucket === "report-snapshots" ||
    asset.upload_status !== "finalized" ||
    asset.upload_finalized_at === undefined ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    return false;
  }
  if (asset.bucket === "profile-photos" && asset.couple_id === undefined && asset.reserved_parent_kind === "profile_photo") {
    if (await canReadProfilePhoto(ctx, userId, asset)) return true;
  }
  if (asset.couple_id === undefined) return await canReadFirstDayDrawing(ctx, userId, asset);
  switch (asset.reserved_parent_kind) {
    case "daily_answer_media":
      return await canReadDailyAnswerMedia(ctx, userId, asset);
    case "thread_message_media":
      return await canReadThreadMessageMedia(ctx, userId, asset);
    case "memory_media":
      return await canReadMemoryMedia(ctx, userId, asset);
    case "story":
      return await canReadStoryPhoto(ctx, userId, asset);
    case "widget_drawing_revision":
      return asset.bucket === "widget-drawings" && (await canReadWidgetPayload(ctx, userId, asset));
    case "game_move":
      return asset.bucket === "game-drawings" && (await canReadGameDrawing(ctx, userId, asset));
    case "exquisite_corpse_part": // Exquisite corpse
      return asset.bucket === "game-drawings" && (await canReadCorpseAsset(ctx, userId, asset));
    default:
      return false;
  }
}
