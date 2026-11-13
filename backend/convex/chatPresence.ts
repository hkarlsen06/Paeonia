import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import type { ReaderCtx } from "./lib/db";
import { getByUuid } from "./lib/db";
import { visibleAnswersOf } from "./lib/dailyQuestions";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";
import { chatOpenRoom, chatTypingRoom, onlineUserIds, setPresent } from "./lib/presence";
import { isChatSubjectAvailable, subjectRoomKey, threadIdOfSubject, threadSubjectArgs, threadSubjectOf } from "./lib/threadSubjects";
import { nowIso } from "./lib/time";

// Typing dots, the open chat and read receipts for chats, and the "seen" mark on a partner's answer. New in
// Convex; there was no SQL version. A chat is named by its subject (`lib/threadSubjects.ts`): a
// daily question, a memory, a story, a game kind, or the couple chat, which has no id. Typing is kept by the presence component
// (lib/presence.ts), and chat reads are small rows. The app writes both while a chat is open and
// reads them through one live query, `get_chat_presence`. Seen answers show up in the daily
// question rows.

/**
 * Typing ends this long after the last heartbeat, such as when the app was killed mid-typing.
 * The app sends one at most every 2.5 seconds while the person types, and keeps the dots 2 more
 * seconds after typing ends, which covers a short gap between heartbeats.
 */
const TYPING_TIMEOUT_MS = 4_000;

/**
 * An open chat ends this long after the last heartbeat. The app sends one every 10 seconds while
 * the chat is on screen and says when it leaves, so this only matters when the app was killed.
 */
const CHAT_OPEN_TIMEOUT_MS = 30_000;

/** Couple access and the subject's room key, or the failure to return. */
async function chatRoomKey(ctx: ReaderCtx, userId: string, coupleId: string, args: Parameters<typeof threadSubjectOf>[0]) {
  const subject = threadSubjectOf(args);
  if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
    return fail("42501", "active entitled couple access is required");
  }
  if (!(await isChatSubjectAvailable(ctx, coupleId, subject))) {
    return fail("22023", "chat subject was not found");
  }
  return subjectRoomKey(subject);
}

async function instanceCoupleId(ctx: ReaderCtx, instanceId: string): Promise<string | null> {
  const instance = await getByUuid(ctx, "daily_question_instances", instanceId);
  if (!instance || instance.status === "shuffled") return null;
  return instance.couple_id;
}

/**
 * Marks the caller as typing in a chat, or not. The app sends `true` while the person types
 * (at most every 2.5 seconds) and `false` when they stop or send. The caller names the couple
 * and must be an active, entitled member of it. A chat is one room per couple and subject, and
 * it works before the chat's thread exists.
 */
export const set_chat_typing = mutation({
  args: { p_couple_id: v.string(), ...threadSubjectArgs, p_is_typing: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const key = await chatRoomKey(ctx, userId, coupleId, args);
    await setPresent(ctx, chatTypingRoom(coupleId, key), userId, args.p_is_typing, TYPING_TIMEOUT_MS);
    return null;
  },
});

/**
 * Marks the caller as having the chat on screen, or not. The app sends `true` every 10 seconds
 * while the chat is on screen and in front, and `false` when it leaves. The partner's game screen
 * shows it, so they know why a move takes a while. Same access rules as typing.
 */
export const set_chat_open = mutation({
  args: { p_couple_id: v.string(), ...threadSubjectArgs, p_is_open: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const key = await chatRoomKey(ctx, userId, coupleId, args);
    await setPresent(ctx, chatOpenRoom(coupleId, key), userId, args.p_is_open, CHAT_OPEN_TIMEOUT_MS);
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
    if (existing && (existing.last_read_message_created_at > message.created_at ||
        (existing.last_read_message_created_at === message.created_at && existing.last_read_message_id >= message.id))) return null;
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
 * Whether the partner has the chat open, is typing in it, and how far they have read. It reads no
 * clock: the presence component ends typing and the open chat after their timeouts, which updates
 * this query.
 */
export const get_chat_presence = query({
  args: { p_couple_id: v.string(), ...threadSubjectArgs },
  handler: async (ctx, args) => {
    const empty = { partner_in_chat: false, partner_typing: false, partner_last_read_message_id: null, partner_read_at: null };
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const subject = threadSubjectOf(args);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) return empty;

    const key = subjectRoomKey(subject);
    const partnerIn = async (room: string) => (await onlineUserIds(ctx, room)).some((id) => id !== userId);
    const typing = await partnerIn(chatTypingRoom(coupleId, key));
    // Typing counts as being in the chat, so a typing heartbeat that beats the first open one still shows.
    const inChat = typing || (await partnerIn(chatOpenRoom(coupleId, key)));

    const threadId = await threadIdOfSubject(ctx, coupleId, subject);
    const read = threadId
      ? (
          await ctx.db
            .query("thread_read_states")
            .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", threadId))
            .collect()
        ).find((row) => row.user_id !== userId)
      : undefined;

    return {
      partner_in_chat: inChat,
      partner_typing: typing,
      partner_last_read_message_id: read?.last_read_message_id ?? null,
      partner_read_at: read?.read_at ?? null,
    };
  },
});
