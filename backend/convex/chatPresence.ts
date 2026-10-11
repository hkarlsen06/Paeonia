import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull } from "./lib/db";
import { visibleAnswersOf } from "./lib/dailyQuestions";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";
import { nowIso } from "./lib/time";

// Typing dots and read receipts for daily question chats, and the "seen" mark on a
// partner's answer. New in Convex; there was no SQL version. Typing and chat reads are
// small rows the app writes while a chat is open and reads through one live query,
// `get_daily_chat_presence`. Seen answers show up in the daily question rows.

/** Typing rows nobody refreshed for this long are deleted by the cleanup cron. */
const STALE_TYPING_MS = 10 * 60_000;

async function instanceCoupleId(ctx: ReaderCtx, instanceId: string): Promise<string | null> {
  const instance = await getByUuid(ctx, "daily_question_instances", instanceId);
  if (!instance || instance.status === "shuffled") return null;
  const day = await getByUuid(ctx, "couple_days", instance.couple_day_id);
  return day?.couple_id ?? null;
}

/**
 * Marks the caller as typing in a question's chat, or not. The app sends `true` while
 * the person types (at most every few seconds) and `false` when they stop or send.
 */
export const set_daily_chat_typing = mutation({
  args: { p_instance_id: v.string(), p_is_typing: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const instanceId = uuidArg(args.p_instance_id);
    const coupleId = await instanceCoupleId(ctx, instanceId);
    if (!coupleId || !(await canAccessCoupleContent(ctx, userId, coupleId))) {
      return fail("42501", "active entitled couple access is required");
    }
    const existing = await ctx.db
      .query("daily_chat_typing")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId).eq("user_id", userId))
      .unique();
    if (!args.p_is_typing) {
      if (existing) await ctx.db.delete(existing._id);
      return null;
    }
    const now = nowIso();
    if (existing) {
      await ctx.db.patch(existing._id, { typing_at: now });
    } else {
      await ctx.db.insert("daily_chat_typing", {
        instance_id: instanceId,
        couple_id: coupleId,
        user_id: userId,
        typing_at: now,
      });
    }
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
 * The partner's typing and read state in a question's chat. Returns timestamps, not a
 * yes or no, because a query must not read the clock: the app hides the typing dots
 * itself once `partner_typing_at` is a few seconds old.
 */
export const get_daily_chat_presence = query({
  args: { p_instance_id: v.string() },
  handler: async (ctx, args) => {
    const empty = { partner_typing_at: null, partner_last_read_message_id: null, partner_read_at: null };
    const userId = await requireUserId(ctx);
    const instanceId = uuidArg(args.p_instance_id);
    const coupleId = await instanceCoupleId(ctx, instanceId);
    if (!coupleId || !(await canAccessCoupleContent(ctx, userId, coupleId))) return empty;

    const typing = (
      await ctx.db
        .query("daily_chat_typing")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId))
        .collect()
    ).find((row) => row.user_id !== userId);

    const link = await ctx.db
      .query("daily_question_threads")
      .withIndex("by_instance_id", (q) => q.eq("instance_id", instanceId))
      .unique();
    const read = link
      ? (
          await ctx.db
            .query("thread_read_states")
            .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", link.thread_id))
            .collect()
        ).find((row) => row.user_id !== userId)
      : undefined;

    return {
      partner_typing_at: orNull(typing?.typing_at),
      partner_last_read_message_id: orNull(read?.last_read_message_id),
      partner_read_at: orNull(read?.read_at),
    };
  },
});

/** Deletes typing rows left behind by an app that closed while someone was typing. */
export const cleanup_stale_daily_chat_typing = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = new Date(Date.now() - STALE_TYPING_MS).toISOString();
    const stale = await ctx.db
      .query("daily_chat_typing")
      .withIndex("by_typing_at", (q) => q.lt("typing_at", cutoff))
      .take(200);
    for (const row of stale) await ctx.db.delete(row._id);
    return stale.length;
  },
});
