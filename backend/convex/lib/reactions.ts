import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import { isLive, isVisibleAnswer, visibleAnswersOf } from "./dailyQuestions";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { memoryDeepLink, storyDeepLink } from "./deepLinks";
import { fail } from "./errors";
import { gameDeepLink, type GameKind } from "./games";
import { uuidArg } from "./ids";
import { enqueueNotificationForUser } from "./notifications";
import { consumeRateLimit } from "./rateLimits";
import { nowIso } from "./time";
import { REACTION_TARGET_KINDS } from "./validators";

/**
 * Emoji reactions. A person has at most one reaction on each thing the couple shares, kept in the
 * `reactions` table under the thing's kind and id. Every kind has one entry in `REACTION_TARGETS`:
 * who may react, and whether the reaction sends a push. `reactions:set_reaction` is the only write.
 * The question chat reads its reactions with its rows (`reactionsOf`). Everything else comes
 * through `reactions:get_reactions`.
 */

export type ReactionTargetKind = (typeof REACTION_TARGET_KINDS)[number];

/** Longest reaction accepted, in UTF-16 units. A family or flag emoji fits. */
const MAX_REACTION_LENGTH = 32;

/** One emoji, such as ❤️, 👍🏽 or 🇳🇴. Letters, digits and words are refused. */
export function isReactionEmoji(value: string): boolean {
  if (value.length === 0 || value.length > MAX_REACTION_LENGTH) return false;
  if (!/^[\p{Extended_Pictographic}\p{Emoji_Component}‍️⃣]+$/u.test(value)) return false;
  if (!/[\p{Extended_Pictographic}\p{Regional_Indicator}]/u.test(value)) return false;
  // Two emoji side by side pass the checks above. A runtime without Segmenter allows them.
  if (typeof Intl.Segmenter !== "function") return true;
  return [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(value)].length === 1;
}

/** The reaction a caller asked for, trimmed, or null to take it back. Fails on anything but one emoji. */
export function reactionArg(value: string | null): string | null {
  if (value === null) return null;
  const emoji = value.trim();
  if (!isReactionEmoji(emoji)) fail("23514", "reaction must be one emoji");
  return emoji;
}

// --- What can get a reaction ---------------------------------------------------

/** What an access check learned about the thing a reaction is on. */
type ResolvedTarget = {
  coupleId: string;
  /**
   * Who is told about a first reaction. `author` tells the person who made the thing, unless they
   * are the one reacting. `partner` tells the other partner, for things both made. `none` sends no
   * push, because the chat shows a reaction to both phones at once.
   */
  notify: { to: "none" } | { to: "author"; authorUserId: string } | { to: "partner"; gameKind: GameKind };
};

type ReactionTargetSpec = {
  /**
   * Fails with `42501` when the caller has no access to the thing and with `23514` when it is gone
   * or not ready for a reaction yet.
   */
  resolve: (ctx: ReaderCtx, userId: string, targetId: string) => Promise<ResolvedTarget>;
};

const NO_ACCESS = "active entitled couple access is required";
const UNAVAILABLE = "reaction target is not available";

async function requireAccess(ctx: ReaderCtx, userId: string, coupleId: string | undefined): Promise<string> {
  if (coupleId === undefined || !(await canAccessCoupleContent(ctx, userId, coupleId))) return fail("42501", NO_ACCESS);
  return coupleId;
}

const none = { to: "none" } as const;

/** One entry per kind. A kind added to `REACTION_TARGET_KINDS` fails to compile until it has one. */
const REACTION_TARGETS: Record<ReactionTargetKind, ReactionTargetSpec> = {
  /** An answer the caller can read in the question chat: their own, or the partner's on a day they answered too. */
  daily_answer: {
    resolve: async (ctx, userId, targetId) => {
      const answer = await getByUuid(ctx, "daily_question_answers", targetId);
      const instance = answer ? await getByUuid(ctx, "daily_question_instances", answer.instance_id) : null;
      const coupleId = await requireAccess(ctx, userId, instance?.couple_id);
      if (!answer || !instance || !isVisibleAnswer(answer) || !isLive(instance)) fail("23514", UNAVAILABLE);
      if (!(await visibleAnswersOf(ctx, instance.id)).some((own) => own.user_id === userId)) {
        fail("42501", "you must answer this daily question before reacting");
      }
      return { coupleId, notify: none };
    },
  },
  /** A shown message, the caller's own or the partner's. */
  thread_message: {
    resolve: async (ctx, userId, targetId) => {
      const message = await getByUuid(ctx, "thread_messages", targetId);
      const thread = message ? await getByUuid(ctx, "conversation_threads", message.thread_id) : null;
      const coupleId = await requireAccess(ctx, userId, thread?.couple_id);
      if (
        !message ||
        !thread ||
        thread.deleted_at !== undefined ||
        thread.moderation_status !== "visible" ||
        message.deleted_at !== undefined ||
        message.moderation_status !== "visible"
      ) {
        fail("23514", UNAVAILABLE);
      }
      return { coupleId, notify: none };
    },
  },
  story: {
    resolve: async (ctx, userId, targetId) => {
      const story = await getByUuid(ctx, "stories", targetId);
      const coupleId = await requireAccess(ctx, userId, story?.couple_id);
      if (!story || story.deleted_at !== undefined) fail("23514", UNAVAILABLE);
      return { coupleId, notify: { to: "author", authorUserId: story.author_user_id } };
    },
  },
  memory: {
    resolve: async (ctx, userId, targetId) => {
      const memory = await getByUuid(ctx, "memories", targetId);
      const coupleId = await requireAccess(ctx, userId, memory?.couple_id);
      if (!memory || memory.deleted_at !== undefined || memory.moderation_status !== "visible") fail("23514", UNAVAILABLE);
      return { coupleId, notify: { to: "author", authorUserId: memory.created_by_user_id } };
    },
  },
  /** A revision of the widget drawing, so the drawing history and the latest drawing take the same reaction. */
  widget_drawing: {
    resolve: async (ctx, userId, targetId) => {
      const revision = await getByUuid(ctx, "widget_drawing_revisions", targetId);
      const canvas = revision ? await getByUuid(ctx, "widget_canvases", revision.canvas_id) : null;
      const coupleId = await requireAccess(ctx, userId, canvas?.couple_id);
      if (
        !revision ||
        !canvas ||
        canvas.deleted_at !== undefined ||
        revision.deleted_at !== undefined ||
        revision.moderation_status !== "visible"
      ) {
        fail("23514", UNAVAILABLE);
      }
      return { coupleId, notify: { to: "author", authorUserId: revision.author_user_id } };
    },
  },
  /** A finished Draw & Guess round that holds a drawing. Both partners can react. */
  draw_and_guess_round: {
    resolve: async (ctx, userId, targetId) => {
      const move = await getByUuid(ctx, "game_moves", targetId);
      const coupleId = await requireAccess(ctx, userId, move?.couple_id);
      if (!move || (move.state !== "solved" && move.state !== "missed") || move.drawing_media_asset_id === undefined) {
        fail("23514", UNAVAILABLE);
      }
      return { coupleId, notify: { to: "partner", gameKind: "draw_and_guess" } };
    },
  },
  /** A finished Odd Creatures figure. */
  exquisite_corpse_figure: {
    resolve: async (ctx, userId, targetId) => {
      const figure = await getByUuid(ctx, "exquisite_corpse_figures", targetId);
      const coupleId = await requireAccess(ctx, userId, figure?.couple_id);
      if (!figure || figure.finished_at === undefined) fail("23514", UNAVAILABLE);
      return { coupleId, notify: { to: "partner", gameKind: "exquisite_corpse" } };
    },
  },
  /** A finished Story Chain story. */
  story_chain_story: {
    resolve: async (ctx, userId, targetId) => {
      const story = await getByUuid(ctx, "story_chain_stories", targetId);
      const coupleId = await requireAccess(ctx, userId, story?.couple_id);
      if (!story || story.state !== "finished") fail("23514", UNAVAILABLE);
      return { coupleId, notify: { to: "partner", gameKind: "story_chain" } };
    },
  },
};

// --- Writing ---------------------------------------------------------------------

/**
 * Sets `userId`'s reaction to a thing, or takes it back with a null `emojiArg`. Access is checked
 * before the emoji, so a stranger learns nothing about what is valid. A plain write without a
 * client operation, so the same call twice changes nothing. A first reaction from this person to
 * things made by the partner tells the partner once. Changing or taking back a reaction never does.
 */
export async function setReaction(
  ctx: WriterCtx,
  userId: string,
  kind: ReactionTargetKind,
  targetIdArg: string,
  emojiArg: string | null,
): Promise<void> {
  const targetId = uuidArg(targetIdArg);
  const target = await REACTION_TARGETS[kind].resolve(ctx, userId, targetId);
  const emoji = reactionArg(emojiArg);

  const existing = await ctx.db
    .query("reactions")
    .withIndex("by_target_kind_target_id_user_id", (q) =>
      q.eq("target_kind", kind).eq("target_id", targetId).eq("user_id", userId),
    )
    .unique();
  if (emoji === null) {
    if (existing) await ctx.db.delete(existing._id);
    return;
  }
  if (existing?.emoji === emoji) return;
  await consumeRateLimit(ctx, "threadMessage", userId);
  if (existing) {
    await ctx.db.patch(existing._id, withUpdatedAt({ emoji }));
    return;
  }
  const now = nowIso();
  await ctx.db.insert("reactions", {
    target_kind: kind,
    target_id: targetId,
    couple_id: target.coupleId,
    user_id: userId,
    emoji,
    created_at: now,
    updated_at: now,
  });
  await notifyOfReaction(ctx, userId, kind, targetId, target, emoji);
}

/**
 * The gentle push for a first reaction: "Robin reacted ❤️", "to your story". It follows the
 * notification setting of the feature the thing belongs to (memories, drawings or games). The key
 * names the person and the thing, so taking the reaction back and putting it on again stays quiet.
 * The payload holds the emoji and the kind, never the content reacted to.
 */
async function notifyOfReaction(
  ctx: WriterCtx,
  actorUserId: string,
  kind: ReactionTargetKind,
  targetId: string,
  target: ResolvedTarget,
  emoji: string,
): Promise<void> {
  if (target.notify.to === "none") return;
  const recipientUserId =
    target.notify.to === "author" ? target.notify.authorUserId : await partnerOf(ctx, target.coupleId, actorUserId);
  if (!recipientUserId || recipientUserId === actorUserId) return;
  const gameKind = target.notify.to === "partner" ? target.notify.gameKind : null;
  const { route, deeplink } = reactionLink(kind, targetId, gameKind);
  await enqueueNotificationForUser(ctx, {
    recipient_user_id: recipientUserId,
    kind: "reaction_added",
    payload: {
      type: "reaction_added",
      couple_id: target.coupleId,
      target_kind: kind,
      target_id: targetId,
      emoji,
      ...(gameKind ? { game_kind: gameKind } : {}),
      actor_user_id: actorUserId,
      route,
      deeplink,
    },
    dedupe_key: `reaction_added:${kind}:${targetId}:${actorUserId}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `reaction_added:${target.coupleId}`,
    scheduled_for: nowIso(),
  });
}

/** Where the push opens: the story, the memory, the drawing screen, or the game the creation belongs to. */
function reactionLink(
  kind: ReactionTargetKind,
  targetId: string,
  gameKind: GameKind | null,
): { route: string; deeplink: string } {
  if (gameKind) return { route: "games", deeplink: gameDeepLink(gameKind) };
  switch (kind) {
    case "memory":
      return { route: "memories", deeplink: memoryDeepLink(targetId) };
    case "widget_drawing":
      return { route: "widget", deeplink: "paeonia://widget/drawing" };
    default:
      return { route: "home", deeplink: storyDeepLink(targetId) };
  }
}

async function partnerOf(ctx: ReaderCtx, coupleId: string, userId: string): Promise<string | null> {
  return (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
}

// --- Reading -----------------------------------------------------------------------

/** One person's reaction, as every read returns it. */
export type ReactionRow = { user_id: string; emoji: string };

/** Everyone's reaction to one thing. At most one row per person. */
export async function reactionsOf(ctx: ReaderCtx, kind: ReactionTargetKind, targetId: string): Promise<ReactionRow[]> {
  const rows = await ctx.db
    .query("reactions")
    .withIndex("by_target_kind_target_id_user_id", (q) => q.eq("target_kind", kind).eq("target_id", targetId))
    .collect();
  return rows.map((row) => ({ user_id: row.user_id, emoji: row.emoji }));
}

/** The kinds `get_reactions` returns. The question chat sends its own with its rows. */
export const FEED_REACTION_KINDS = REACTION_TARGET_KINDS.filter(
  (kind) => kind !== "daily_answer" && kind !== "thread_message",
);

/** Every reaction of the couple on the kinds in `FEED_REACTION_KINDS`. */
export async function coupleReactions(ctx: ReaderCtx, coupleId: string) {
  const reactions: Array<ReactionRow & { target_kind: ReactionTargetKind; target_id: string }> = [];
  for (const kind of FEED_REACTION_KINDS) {
    const rows = await ctx.db
      .query("reactions")
      .withIndex("by_couple_id_target_kind", (q) => q.eq("couple_id", coupleId).eq("target_kind", kind))
      .collect();
    for (const row of rows) {
      reactions.push({ target_kind: kind, target_id: row.target_id, user_id: row.user_id, emoji: row.emoji });
    }
  }
  return reactions;
}

// --- Deleting ------------------------------------------------------------------------

/** Deletes every reaction on one thing. Call it wherever the thing itself is deleted or hidden for good. */
export async function deleteReactionsOf(ctx: WriterCtx, kind: ReactionTargetKind, targetId: string): Promise<number> {
  const rows = await ctx.db
    .query("reactions")
    .withIndex("by_target_kind_target_id_user_id", (q) => q.eq("target_kind", kind).eq("target_id", targetId))
    .collect();
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}

/** Deletes the reactions on every message of a thread, for a thread that is deleted with its subject. */
export async function deleteReactionsOfThread(ctx: WriterCtx, threadId: string): Promise<void> {
  for await (const message of ctx.db
    .query("thread_messages")
    .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", threadId))) {
    await deleteReactionsOf(ctx, "thread_message", message.id);
  }
}

/** Everything one person ever reacted with, for account deletion. */
export async function reactionsByUser(ctx: ReaderCtx, userId: string): Promise<Doc<"reactions">[]> {
  return await ctx.db
    .query("reactions")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .collect();
}
