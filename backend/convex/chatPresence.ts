import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull } from "./lib/db";
import { dailyQuestionThreadLink } from "./lib/dailyQuestionRounds";
import { visibleAnswersOf } from "./lib/dailyQuestions";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";
import { chatTypingRoom, onlineUserIds, setPresent } from "./lib/presence";
import { nowIso } from "./lib/time";

// Typing dots and read receipts for daily question chats, and the "seen" mark on a
// partner's answer. New in Convex; there was no SQL version. Typing is kept by the presence
// component (lib/presence.ts), and chat reads are small rows. The app writes both while a chat
// is open and reads them through one live query, `get_daily_chat_presence`. Seen answers show
// up in the daily question rows.

/**
 * Typing ends this long after the last heartbeat, such as when the app was killed mid-typing.
 * The app sends one at most every 2.5 seconds while the person types, and keeps the dots 2 more
 * seconds after typing ends, which covers a short gap between heartbeats.
 */
const TYPING_TIMEOUT_MS = 4_000;

async function instanceCoupleId(ctx: ReaderCtx, instanceId: string): Promise<string | null> {
  const instance = await getByUuid(ctx, "daily_question_instances", instanceId);
  if (!instance || instance.status === "shuffled") return null;
  return instance.couple_id;
}

/**
 * Marks the caller as typing in a question's chat, or not. The app sends `true` while
 * the person types (at most every 2.5 seconds) and `false` when they stop or send.
 * The caller names the couple and must be an active, entitled member of it. One question's
 * chat is one room per couple.
 */
export const set_daily_chat_typing = mutation({
  args: { p_couple_id: v.string(), p_question_id: v.string(), p_is_typing: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const questionId = uuidArg(args.p_question_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      return fail("42501", "active entitled couple access is required");
    }
    if (!(await getByUuid(ctx, "questions", questionId))) {
      return fail("22023", "daily question was not found");
    }
    await setPresent(ctx, chatTypingRoom(coupleId, questionId), userId, args.p_is_typing, TYPING_TIMEOUT_MS);
    return null;
  },
});

/**
 * Records that the caller has read the thread up to `p_message_id`. The mark only moves
 * forward, so a late call for an older message changes nothing.
 */
export const mark_thread_read = mutation({
  args: { p_thread_id: v.string(), p_message_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const threadId = uuidArg(args.p_thread_id);
    const messageId = uuidArg(args.p_message_id);
    const thread = await getByUuid(ctx, "conversation_threads", threadId);
    if (
      !thread ||
      thread.deleted_at !== undefined ||
      thread.moderation_status !== "visible" ||
      !(await canAccessCoupleContent(ctx, userId, thread.couple_id))
    ) {
      return fail("42501", "active entitled thread access is required");
    }
    const message = await getByUuid(ctx, "thread_messages", messageId);
    if (!message || message.thread_id !== threadId) {
      return fail("23514", "read message must be in the thread");
    }
    const existing = await ctx.db
      .query("thread_read_states")
      .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", threadId).eq("user_id", userId))
      .unique();
    if (existing && existing.last_read_message_created_at >= message.created_at) return null;
    const row = {
      last_read_message_id: messageId,
      last_read_message_created_at: message.created_at,
      read_at: nowIso(),
    };
    if (existing) {
      await ctx.db.patch(existing._id, row);
    } else {
      await ctx.db.insert("thread_read_states", { thread_id: threadId, user_id: userId, ...row });
    }
    return null;
  },
});

/**
 * Records that the caller has seen the partner's answer to a daily question. Only an
 * answer the caller can read counts: both people must have a visible answer. The first
 * mark stays, so a later call changes nothing.
 */
export const mark_daily_answer_seen = mutation({
  args: { p_instance_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const instanceId = uuidArg(args.p_instance_id);
    const coupleId = await instanceCoupleId(ctx, instanceId);
    if (!coupleId || !(await canAccessCoupleContent(ctx, userId, coupleId))) {
      return fail("42501", "active entitled couple access is required");
    }
    const answers = await visibleAnswersOf(ctx, instanceId);
    if (!answers.some((answer) => answer.user_id === userId) || !answers.some((answer) => answer.user_id !== userId)) {
      return fail("23514", "partner answer is not visible yet");
    }
    const existing = await ctx.db
      .query("daily_answer_seen_states")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId).eq("user_id", userId))
      .unique();
    if (existing) return null;
    await ctx.db.insert("daily_answer_seen_states", {
      instance_id: instanceId,
      couple_id: coupleId,
      user_id: userId,
      seen_at: nowIso(),
    });
    return null;
  },
});

/**
 * The partner's typing and read state in a question's chat. It reads no clock: the presence
 * component ends typing `TYPING_TIMEOUT_MS` after the last heartbeat, which updates this query.
 */
export const get_daily_chat_presence = query({
  args: { p_couple_id: v.string(), p_question_id: v.string() },
  handler: async (ctx, args) => {
    const empty = { partner_typing: false, partner_last_read_message_id: null, partner_read_at: null };
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const questionId = uuidArg(args.p_question_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) return empty;

    const typing = (await onlineUserIds(ctx, chatTypingRoom(coupleId, questionId))).some((id) => id !== userId);

    const link = await dailyQuestionThreadLink(ctx, coupleId, questionId);
    const read = link
      ? (
          await ctx.db
            .query("thread_read_states")
            .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", link.thread_id))
            .collect()
        ).find((row) => row.user_id !== userId)
      : undefined;

    return {
      partner_typing: typing,
      partner_last_read_message_id: orNull(read?.last_read_message_id),
      partner_read_at: orNull(read?.read_at),
    };
  },
});
