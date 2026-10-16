import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { isSupersededClientOperation, runClientOperation } from "./lib/clientOperations";
import { getByUuid, orNull, type ReaderCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { enqueueStoryPostedNotification } from "./lib/notifications";
import { consumeRateLimit } from "./lib/rateLimits";
import { charLength } from "./lib/text";
import { addMs, nowIso } from "./lib/time";

// A story is a photo with an optional short caption that one partner posts as an
// "I thought about you" check-in. The phone shows it in a ring on Home for 24 hours after
// `created_at`, then keeps it in the Stories archive. The server stores no expiry and runs no cron.

/** The app caps captions at 100 characters. Code points are counted here, so an emoji never trips it. */
const MAX_CAPTION_CODE_POINTS = 200;
/** The app caps notes at 60 characters. */
const MAX_NOTE_CODE_POINTS = 120;
/** A note shows for this long after it was set, then the cron deletes it. */
const NOTE_LIFETIME_MS = 24 * 3_600_000;
/** Expired notes one cron run deletes before it schedules the next. */
const EXPIRED_NOTES_PER_RUN = 100;

function noteRow(row: Doc<"couple_notes">) {
  return { user_id: row.user_id, text: row.text, created_at: row.created_at };
}

async function coupleNote(ctx: ReaderCtx, coupleId: string, userId: string) {
  return await ctx.db
    .query("couple_notes")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .unique();
}

function storyRow(row: Doc<"stories">) {
  return {
    id: row.id,
    author_user_id: row.author_user_id,
    media_asset_id: row.media_asset_id,
    caption: orNull(row.caption),
    created_at: row.created_at,
    seen_at: orNull(row.seen_at),
  };
}

/** The story as stored now, or null when it is missing, deleted, or another couple's. */
async function currentStory(ctx: ReaderCtx, storyId: string, coupleId: string) {
  const row = await getByUuid(ctx, "stories", storyId);
  return row && row.couple_id === coupleId && row.deleted_at === undefined ? storyRow(row) : null;
}

/**
 * The caller's couple's stories, newest first, and each partner's note. The app subscribes to
 * this and works out the 24 hours on Home from `created_at` on the phone. Fails with `42501`
 * without an entitled couple.
 * ponytail: returns every story. Page it once a couple has around a thousand stories.
 */
export const get_stories = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const rows = await ctx.db
      .query("stories")
      .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
      .order("desc")
      .collect();
    const notes = await ctx.db
      .query("couple_notes")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId))
      .collect();
    return {
      couple_id: coupleId,
      stories: rows.filter((row) => row.deleted_at === undefined).map(storyRow),
      notes: notes.map(noteRow),
    };
  },
});

/**
 * Posts the story `p_story_id` with the finalized photo `p_media_asset_id`. The phone picks
 * the id, so a post and its retries are the same write. The caption is trimmed, and an empty
 * one means none. Queues a push to the partner that never holds the caption. Returns the
 * story as stored now, also on a replay, or null when its author deleted it since.
 */
export const post_story = mutation({
  args: {
    p_story_id: v.string(),
    p_media_asset_id: v.string(),
    p_caption: v.optional(v.union(v.null(), v.string())),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const storyId = uuidArg(args.p_story_id);
    const assetId = uuidArg(args.p_media_asset_id);
    const caption = args.p_caption?.trim() || undefined;
    if (caption !== undefined && charLength(caption) > MAX_CAPTION_CODE_POINTS) {
      fail("23514", `story caption must be at most ${MAX_CAPTION_CODE_POINTS} characters`);
    }
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "post_story",
      scope: `story:${storyId}`,
      request: { kind: "post_story", couple_id: coupleId, id: storyId, media_asset_id: assetId, caption: caption ?? null },
    });
    await runClientOperation(ctx, userId, input, async () => {
      await consumeRateLimit(ctx, "storyPost", userId);
      await assertNoPendingAccountDeletion(ctx, userId);

      const existing = await getByUuid(ctx, "stories", storyId);
      if (existing) {
        if (existing.couple_id !== coupleId || existing.author_user_id !== userId) {
          return fail("42501", "story belongs to someone else");
        }
        return null;
      }

      const asset = await getByUuid(ctx, "media_assets", assetId);
      if (!asset || asset.owner_user_id !== userId || asset.couple_id !== coupleId) {
        return fail("42501", "story photo is not available");
      }
      if (
        asset.upload_purpose !== "story_photo" ||
        asset.media_type !== "image" ||
        asset.reserved_parent_kind !== "story" ||
        asset.reserved_parent_id !== storyId ||
        asset.upload_status !== "finalized" ||
        asset.storage_delete_status !== "none" ||
        asset.moderation_status !== "visible" ||
        asset.deleted_at !== undefined
      ) {
        return fail("23514", "story photo is not usable");
      }

      const docId = await ctx.db.insert("stories", {
        id: storyId,
        couple_id: coupleId,
        author_user_id: userId,
        media_asset_id: assetId,
        caption,
        created_at: nowIso(),
      });
      await enqueueStoryPostedNotification(ctx, (await ctx.db.get(docId))!);
      return null;
    });
    // Read after the operation, so a replay returns today's row (with `seen_at`) and not the
    // answer the first call stored.
    return await currentStory(ctx, storyId, coupleId);
  },
});

/** Deletes the story `p_story_id`. Only its author may. A missing or already deleted one is fine. */
export const delete_story = mutation({
  args: { p_story_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const storyId = uuidArg(args.p_story_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "delete_story",
      scope: `story:${storyId}`,
      request: { kind: "delete_story", couple_id: coupleId, id: storyId },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "stories", storyId);
      if (!existing || existing.deleted_at !== undefined) return null;
      if (existing.couple_id !== coupleId || existing.author_user_id !== userId) {
        return fail("42501", "only the author can delete a story");
      }
      await ctx.db.patch(existing._id, { deleted_at: nowIso() });
      await queueOrphanedMediaAssetForDelete(ctx, existing.media_asset_id);
      return null;
    });
    return null;
  },
});

/**
 * Records that the partner opened the story `p_story_id`. Keeps the first time. The author
 * opening their own story, a missing story, and a deleted one change nothing.
 */
export const mark_story_seen = mutation({
  args: { p_story_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const storyId = uuidArg(args.p_story_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const story = await getByUuid(ctx, "stories", storyId);
    if (!story || story.deleted_at !== undefined) return null;
    if (story.couple_id !== coupleId) return fail("42501", "story belongs to another couple");
    if (story.author_user_id !== userId && story.seen_at === undefined) {
      await ctx.db.patch(story._id, { seen_at: nowIso() });
    }
    return null;
  },
});

/**
 * Sets the caller's note, or removes it when `p_text` is null or blank. A new note replaces the
 * old one and starts its 24 hours again. A late retry that a newer write from the same phone
 * already replaced changes nothing. Returns the note as stored now, or null when there is none.
 */
export const set_note = mutation({
  args: { p_text: v.union(v.null(), v.string()), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const text = args.p_text?.trim() || null;
    if (text !== null && charLength(text) > MAX_NOTE_CODE_POINTS) {
      fail("23514", `note must be at most ${MAX_NOTE_CODE_POINTS} characters`);
    }
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "set_note",
      scope: `couple:${coupleId}:note`,
      request: { kind: "set_note", couple_id: coupleId, text },
    });
    await runClientOperation(ctx, userId, input, async () => {
      await consumeRateLimit(ctx, "noteSet", userId);
      await assertNoPendingAccountDeletion(ctx, userId);
      if (await isSupersededClientOperation(ctx, userId, input)) return null;
      const existing = await coupleNote(ctx, coupleId, userId);
      if (text === null) {
        if (existing) await ctx.db.delete(existing._id);
      } else if (existing) {
        await ctx.db.patch(existing._id, { text, created_at: nowIso() });
      } else {
        await ctx.db.insert("couple_notes", { couple_id: coupleId, user_id: userId, text, created_at: nowIso() });
      }
      return null;
    });
    const current = await coupleNote(ctx, coupleId, userId);
    return current ? noteRow(current) : null;
  },
});

/**
 * Deletes notes whose 24 hours are over, so a note is gone once it leaves Home and not only
 * hidden. The live query then drops it from both phones. Runs from the delete-expired-notes
 * cron, `EXPIRED_NOTES_PER_RUN` at a time, and schedules itself again while more are due.
 * Stories are not touched: they stay in the Stories archive in Memories.
 */
export const delete_expired_notes = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = addMs(nowIso(), -NOTE_LIFETIME_MS);
    const expired = await ctx.db
      .query("couple_notes")
      .withIndex("by_created_at", (q) => q.lte("created_at", cutoff))
      .take(EXPIRED_NOTES_PER_RUN);
    for (const note of expired) await ctx.db.delete(note._id);
    if (expired.length === EXPIRED_NOTES_PER_RUN) {
      await ctx.scheduler.runAfter(0, internal.stories.delete_expired_notes, {});
    }
    return { deleted: expired.length };
  },
});
