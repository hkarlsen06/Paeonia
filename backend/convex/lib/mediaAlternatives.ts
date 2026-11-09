import { v, type Infer } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { getCurrentEntitledCoupleId } from "./access";
import { clientOperationArgs, toClientOperation } from "./clientOperationArgs";
import { isSupersededClientOperation, runClientOperation } from "./clientOperations";
import { getByUuid, withUpdatedAt, type WriterCtx } from "./db";
import { fail } from "./errors";
import { uuidArg } from "./ids";
import { isJsonObject } from "./json";
import { isChatSubjectAvailable, subjectOfThread } from "./threadSubjects";
import { isUsableMediaAsset } from "./mediaAssetState";

export const mediaAlternativeTarget = v.union(
  v.object({ kind: v.literal("chat"), message_id: v.string(), media_asset_id: v.string() }),
  v.object({ kind: v.literal("daily"), answer_id: v.string() }),
  v.object({ kind: v.literal("story"), story_id: v.string() }),
  v.object({ kind: v.literal("guess_my_spot"), round_id: v.string() }),
  v.object({ kind: v.literal("draw_and_guess"), round_id: v.string() }),
  v.object({ kind: v.literal("exquisite_corpse"), part_id: v.string() }),
  v.object({ kind: v.literal("widget_drawing"), revision_id: v.string() }),
);

export const updateMediaAlternativeArgs = {
  p_target: mediaAlternativeTarget,
  p_text: v.string(),
  ...clientOperationArgs,
};

type Target = Infer<typeof mediaAlternativeTarget>;
const inputValidator = v.object(updateMediaAlternativeArgs);
type Input = Infer<typeof inputValidator>;
type Writable = { kind: "asset"; row: Doc<"media_assets"> }
  | { kind: "answer"; row: Doc<"daily_question_answers"> }
  | { kind: "widget"; row: Doc<"widget_drawing_revisions"> };

function normalizedTarget(target: Target): Target {
  switch (target.kind) {
    case "chat": return { kind: "chat", message_id: uuidArg(target.message_id), media_asset_id: uuidArg(target.media_asset_id) };
    case "daily": return { kind: "daily", answer_id: uuidArg(target.answer_id) };
    case "story": return { kind: "story", story_id: uuidArg(target.story_id) };
    case "guess_my_spot": return { kind: "guess_my_spot", round_id: uuidArg(target.round_id) };
    case "draw_and_guess": return { kind: "draw_and_guess", round_id: uuidArg(target.round_id) };
    case "exquisite_corpse": return { kind: "exquisite_corpse", part_id: uuidArg(target.part_id) };
    case "widget_drawing": return { kind: "widget_drawing", revision_id: uuidArg(target.revision_id) };
  }
}

function scope(target: Target): string {
  switch (target.kind) {
    case "chat": return `media-alternative:${target.media_asset_id}`;
    case "daily": return `answer-alternative:${target.answer_id}`;
    case "story": return `story-alternative:${target.story_id}`;
    case "guess_my_spot": return `guess-my-spot-alternative:${target.round_id}`;
    case "draw_and_guess": return `draw-and-guess-alternative:${target.round_id}`;
    case "exquisite_corpse": return `exquisite-corpse-alternative:${target.part_id}`;
    case "widget_drawing": return `widget-drawing-alternative:${target.revision_id}`;
  }
}

function requireUsableAsset(
  asset: Doc<"media_assets"> | null, userId: string, coupleId: string,
  mediaTypes: readonly Doc<"media_assets">["media_type"][] = ["image", "voice"],
) {
  if (!asset || asset.owner_user_id !== userId || asset.couple_id !== coupleId ||
      !isUsableMediaAsset(asset) || !mediaTypes.includes(asset.media_type)) {
    return fail("42501", "media description is not writable");
  }
  return asset;
}

async function writableTarget(ctx: WriterCtx, userId: string, coupleId: string, target: Target): Promise<Writable> {
  switch (target.kind) {
    case "widget_drawing": {
      const revision = await getByUuid(ctx, "widget_drawing_revisions", target.revision_id);
      const canvas = revision ? await getByUuid(ctx, "widget_canvases", revision.canvas_id) : null;
      if (!revision || revision.author_user_id !== userId || revision.deleted_at !== undefined ||
          revision.moderation_status !== "visible" || !canvas || canvas.couple_id !== coupleId ||
          canvas.deleted_at !== undefined) return fail("42501", "media description is not writable");
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", revision.payload_media_asset_id),
        userId, coupleId, ["drawing_payload"]);
      if (asset.reserved_parent_kind !== "widget_drawing_revision" || asset.reserved_parent_id !== revision.id ||
          asset.upload_purpose !== "widget_drawing_payload" || asset.storage_path !== `${coupleId}/${canvas.id}/revisions/${revision.id}/drawing.pkdrawing`) {
        fail("42501", "media description is not writable");
      }
      return { kind: "widget", row: revision };
    }
    case "draw_and_guess": {
      const round = await getByUuid(ctx, "game_moves", target.round_id);
      const game = round ? await getByUuid(ctx, "games", round.game_id) : null;
      if (!round || round.drawer_user_id !== userId || round.couple_id !== coupleId ||
          !game || game.couple_id !== coupleId || !round.drawing_media_asset_id) {
        return fail("42501", "media description is not writable");
      }
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", round.drawing_media_asset_id),
        userId, coupleId, ["drawing_payload"]);
      if (asset.reserved_parent_kind !== "game_move" || asset.reserved_parent_id !== round.id ||
          asset.upload_purpose !== "game_drawing_payload") fail("42501", "media description is not writable");
      return { kind: "asset", row: asset };
    }
    case "exquisite_corpse": {
      const part = await getByUuid(ctx, "exquisite_corpse_parts", target.part_id);
      const figure = part ? await getByUuid(ctx, "exquisite_corpse_figures", part.figure_id) : null;
      const game = figure ? await getByUuid(ctx, "exquisite_corpse_games", figure.game_id) : null;
      if (!part || part.drawer_user_id !== userId || part.couple_id !== coupleId ||
          !figure || figure.couple_id !== coupleId || !game || game.couple_id !== coupleId) {
        return fail("42501", "media description is not writable");
      }
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", part.drawing_media_asset_id),
        userId, coupleId, ["drawing_payload"]);
      if (asset.reserved_parent_kind !== "exquisite_corpse_part" || asset.reserved_parent_id !== part.id ||
          asset.upload_purpose !== "exquisite_corpse_drawing") fail("42501", "media description is not writable");
      return { kind: "asset", row: asset };
    }
    case "guess_my_spot": {
      const round = await getByUuid(ctx, "guess_my_spot_rounds", target.round_id);
      if (!round || round.sender_user_id !== userId || round.couple_id !== coupleId || round.deleted_at !== undefined) {
        return fail("42501", "media description is not writable");
      }
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", round.photo_media_asset_id), userId, coupleId);
      if (asset.reserved_parent_kind !== "guess_my_spot_round" || asset.reserved_parent_id !== round.id ||
          asset.upload_purpose !== "guess_my_spot_photo" || asset.media_type !== "image") {
        fail("42501", "media description is not writable");
      }
      return { kind: "asset", row: asset };
    }
    case "chat": {
      const message = await getByUuid(ctx, "thread_messages", target.message_id);
      const thread = message ? await getByUuid(ctx, "conversation_threads", message.thread_id) : null;
      const subject = thread ? await subjectOfThread(ctx, thread) : null;
      const link = await ctx.db.query("thread_message_media")
        .withIndex("by_message_id_media_asset_id", q => q.eq("message_id", target.message_id).eq("media_asset_id", target.media_asset_id))
        .unique();
      if (!message || message.sender_user_id !== userId || message.deleted_at !== undefined ||
          message.moderation_status !== "visible" || !thread || thread.couple_id !== coupleId ||
          thread.deleted_at !== undefined || thread.moderation_status !== "visible" || !link || !subject ||
          !(await isChatSubjectAvailable(ctx, coupleId, subject))) fail("42501", "media description is not writable");
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", target.media_asset_id), userId, coupleId);
      if (asset.reserved_parent_kind !== "thread_message_media" || asset.reserved_parent_id !== message.id ||
          !["thread_media", "voice_note"].includes(asset.upload_purpose)) fail("42501", "media description is not writable");
      return { kind: "asset", row: asset };
    }
    case "story": {
      const story = await getByUuid(ctx, "stories", target.story_id);
      if (!story || story.author_user_id !== userId || story.couple_id !== coupleId || story.deleted_at !== undefined) {
        return fail("42501", "media description is not writable");
      }
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", story.media_asset_id), userId, coupleId);
      if (asset.reserved_parent_kind !== "story" || asset.reserved_parent_id !== story.id ||
          asset.upload_purpose !== "story_photo" || asset.media_type !== "image") fail("42501", "media description is not writable");
      return { kind: "asset", row: asset };
    }
    case "daily": {
      const answer = await getByUuid(ctx, "daily_question_answers", target.answer_id);
      const instance = answer ? await getByUuid(ctx, "daily_question_instances", answer.instance_id) : null;
      if (!answer || answer.user_id !== userId || answer.deleted_at !== undefined || answer.moderation_status !== "visible" ||
          !instance || instance.couple_id !== coupleId || instance.status !== "active") {
        return fail("42501", "media description is not writable");
      }
      const links = await ctx.db.query("daily_answer_media")
        .withIndex("by_answer_id_sort_order", q => q.eq("answer_id", answer.id)).collect();
      if (links.length !== 1) fail("42501", "media description is not writable");
      const asset = requireUsableAsset(await getByUuid(ctx, "media_assets", links[0].media_asset_id), userId, coupleId);
      if (asset.reserved_parent_kind !== "daily_answer_media" || asset.reserved_parent_id !== answer.id ||
          !["daily_answer_media", "voice_note"].includes(asset.upload_purpose)) fail("42501", "media description is not writable");
      return { kind: "answer", row: answer };
    }
  }
}

/** Corrects an authored alternative, never the sent media, caption, reveal state or effective answer time. */
export async function updateMediaAlternative(ctx: WriterCtx, userId: string, args: Input) {
  const target = normalizedTarget(args.p_target);
  const text = args.p_text.trim();
  if (Array.from(text).length > (target.kind === "widget_drawing" ? 500 : 10000)) fail("23514", "media accessibility text is too long");
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  // Check access and the live reference before replay as well. An old successful write grants no access.
  const writable = await writableTarget(ctx, userId, coupleId, target);
  const input = toClientOperation(args, {
    kind: "update_media_accessibility_text", scope: scope(target), request: { target, text },
  });
  await runClientOperation(ctx, userId, input, async () => {
    if (await isSupersededClientOperation(ctx, userId, input)) return null;
    if (writable.kind === "asset") {
      await ctx.db.patch(writable.row._id, withUpdatedAt({ accessibility_text: text || undefined }));
    } else if (writable.kind === "answer") {
      await ctx.db.patch(writable.row._id, withUpdatedAt({ media_accessibility_text: text || undefined }));
    } else {
      const bounds = isJsonObject(writable.row.bounds) ? { ...writable.row.bounds } : {};
      if (text) bounds.accessibilityText = text;
      else delete bounds.accessibilityText;
      // Same-revision widget readers need an authoritative order even for writes in the same millisecond.
      const updatedAt = new Date(Math.max(Date.now(), Date.parse(writable.row.updated_at) + 1)).toISOString();
      await ctx.db.patch(writable.row._id, { bounds, updated_at: updatedAt });
    }
    return null;
  });
  // A replay or superseded retry returns the currently stored text, not its stale request.
  const current = await writableTarget(ctx, userId, coupleId, target);
  if (current.kind === "widget") {
    const bounds = current.row.bounds;
    return { accessibility_text: isJsonObject(bounds) && typeof bounds.accessibilityText === "string"
      ? bounds.accessibilityText : null, revision_description_version: Date.parse(current.row.updated_at) };
  }
  return { accessibility_text: (current.kind === "asset" ? current.row.accessibility_text : current.row.media_accessibility_text) ?? null };
}
