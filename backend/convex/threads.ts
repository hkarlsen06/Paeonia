import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import {
  canAccessCoupleContent,
  getCurrentEntitledCoupleId,
  isActiveCoupleMember,
} from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { dailyQuestionThreadLink, isSharedRound, loadQuestionRounds } from "./lib/dailyQuestionRounds";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { checkViolation, fail, uniqueViolation } from "./lib/errors";
import { newUuid, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import { enqueuePartnerNotification } from "./lib/notifications";
import { consumeRateLimit } from "./lib/rateLimits";
import { reactionArg } from "./lib/reactions";
import { applyCoupleActivity } from "./lib/streaks";
import { btrimToNull, charLength } from "./lib/text";
import { nowIso } from "./lib/time";
import { topicOfQuestion } from "./lib/topics";

const nullableMediaIds = v.optional(v.union(v.null(), v.array(v.string())));

/** Port of `assert_conversation_thread_allowed`. */
async function assertConversationThreadAllowed(ctx: ReaderCtx, coupleId: string, creatorUserId: string): Promise<void> {
  if (!(await isActiveCoupleMember(ctx, creatorUserId, coupleId))) {
    fail("23514", "thread creator must be an active couple member");
  }
}

/** Port of `assert_daily_question_thread_allowed`. */
async function assertDailyQuestionThreadAllowed(ctx: ReaderCtx, coupleId: string, threadId: string): Promise<void> {
  const thread = await getByUuid(ctx, "conversation_threads", threadId);
  if (!thread) fail("23503", "thread was not found");
  if (thread.kind !== "daily_question") fail("23514", "daily question thread must use daily_question kind");
  if (coupleId !== thread.couple_id) fail("23514", "daily question thread couple mismatch");
}

/** Port of `assert_memory_thread_allowed`. */
async function assertMemoryThreadAllowed(ctx: ReaderCtx, threadId: string): Promise<void> {
  const thread = await getByUuid(ctx, "conversation_threads", threadId);
  if (!thread) fail("23503", "thread was not found");
  if (thread.kind !== "memory") fail("23514", "memory thread must use memory kind");
}

/** Port of `assert_thread_message_allowed`. */
async function assertThreadMessageAllowed(ctx: ReaderCtx, threadId: string, senderUserId: string): Promise<void> {
  const thread = await getByUuid(ctx, "conversation_threads", threadId);
  if (
    !thread ||
    thread.deleted_at !== undefined ||
    thread.moderation_status !== "visible" ||
    !(await isActiveCoupleMember(ctx, senderUserId, thread.couple_id))
  ) {
    fail("23514", "message sender must be an active visible thread member");
  }
}

/** Port of `assert_thread_message_media_allowed`. */
async function assertThreadMessageMediaAllowed(ctx: ReaderCtx, messageId: string, mediaAssetId: string): Promise<void> {
  const message = await getByUuid(ctx, "thread_messages", messageId);
  if (!message) fail("23503", "thread message was not found");
  const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
  if (!thread) fail("23503", "conversation thread was not found");
  const asset = await getByUuid(ctx, "media_assets", mediaAssetId);
  if (
    !asset ||
    asset.owner_user_id !== message.sender_user_id ||
    asset.couple_id !== thread.couple_id ||
    asset.reserved_parent_kind !== "thread_message_media" ||
    asset.reserved_parent_id !== messageId ||
    !["thread_media", "voice_note"].includes(asset.upload_purpose) ||
    !["image", "voice"].includes(asset.media_type) ||
    asset.upload_status !== "finalized" ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", "thread message media asset is not usable");
  }
}

/** Inserts a conversation_threads row after `assert_conversation_thread_allowed`. */
async function insertConversationThread(
  ctx: WriterCtx,
  row: { couple_id: string; kind: "daily_question" | "memory"; created_by_user_id: string },
): Promise<string> {
  await assertConversationThreadAllowed(ctx, row.couple_id, row.created_by_user_id);
  const id = newUuid();
  const now = nowIso();
  await ctx.db.insert("conversation_threads", {
    id,
    ...row,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  return id;
}

/**
 * Port of the `handle_thread_message_created` trigger. Records the streak
 * activity, then queues the partner alert. Push problems never fail the send.
 */
export async function handleThreadMessageCreated(ctx: WriterCtx, message: Doc<"thread_messages">): Promise<void> {
  if (message.deleted_at !== undefined || message.moderation_status !== "visible") return;
  const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
  if (!thread || thread.deleted_at !== undefined || thread.moderation_status !== "visible") return;
  const dailyLink = await ctx.db
    .query("daily_question_threads")
    .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
    .unique();
  const memoryLink = await ctx.db
    .query("memory_threads")
    .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
    .unique();
  if (!dailyLink && !memoryLink) return;

  await applyCoupleActivity(ctx, {
    couple_id: thread.couple_id,
    user_id: message.sender_user_id,
    couple_day_id: await getOrCreateCoupleDayAt(ctx, thread.couple_id, message.created_at),
    activity_kind: "thread_message_sent",
    occurred_at: message.created_at,
    dedupe_key: `thread_message_sent:${message.id}`,
    metadata: { thread_id: message.thread_id },
  });

  const payload: Record<string, unknown> = {
    type: "thread_message_sent",
    couple_id: thread.couple_id,
    thread_id: message.thread_id,
    message_id: message.id,
    actor_user_id: message.sender_user_id,
  };
  if (dailyLink) {
    Object.assign(payload, {
      route: "daily",
      deeplink: `paeonia://daily/chat?questionId=${dailyLink.question_id}`,
      question_id: dailyLink.question_id,
    });
  } else {
    Object.assign(payload, { route: "memories", deeplink: "paeonia://memories", memory_id: memoryLink!.memory_id });
  }
  try {
    await enqueuePartnerNotification(ctx, {
      couple_id: thread.couple_id,
      actor_user_id: message.sender_user_id,
      kind: "thread_message_sent",
      payload,
      dedupe_key: `thread_message_sent:${message.id}`,
      redaction_level: "private",
      apns_push_type: "alert",
      apns_collapse_id: `thread:${message.thread_id}`,
      scheduled_for: nowIso(),
    });
  } catch {
    // Push delivery must never make sending a message fail.
  }
}

/** A reply must point at a shown message in the same thread. */
async function assertReplyTargetAllowed(ctx: ReaderCtx, threadId: string, replyToMessageId: string): Promise<void> {
  const target = await getByUuid(ctx, "thread_messages", replyToMessageId);
  if (!target || target.thread_id !== threadId) fail("23514", "reply target must be in the same thread");
  if (target.deleted_at !== undefined || target.moderation_status !== "visible") {
    fail("23514", "reply target is not available");
  }
}

/**
 * A reply to an answer must point at a shown answer to the thread's question, on a day
 * whose answers the sender can read: their own answer, or the partner's on a day they
 * answered too.
 */
async function assertAnswerReplyTargetAllowed(
  ctx: ReaderCtx,
  threadId: string,
  userId: string,
  replyToAnswerId: string,
): Promise<void> {
  const link = await ctx.db
    .query("daily_question_threads")
    .withIndex("by_thread_id", (q) => q.eq("thread_id", threadId))
    .unique();
  const answer = await getByUuid(ctx, "daily_question_answers", replyToAnswerId);
  const instance = answer ? await getByUuid(ctx, "daily_question_instances", answer.instance_id) : null;
  if (!link || !instance || instance.couple_id !== link.couple_id || instance.question_id !== link.question_id) {
    fail("23514", "reply target must be in the same thread");
  }
  const rounds = await loadQuestionRounds(ctx, link.couple_id, link.question_id);
  const round = rounds.find((item) => item.answers.some((visible) => visible.id === replyToAnswerId));
  if (!round || !round.answers.some((visible) => visible.user_id === userId)) {
    fail("23514", "reply target is not available");
  }
}

/** What a new message replies to: an earlier message, an answer to the question, or nothing. */
export type ThreadMessageReply = { messageId?: string; answerId?: string };

/** Port of `internal.insert_thread_message`. Returns the new message id. */
export async function insertThreadMessage(
  ctx: WriterCtx,
  userId: string,
  threadId: string,
  body: string | null | undefined,
  mediaAssetIds: string[] | null | undefined,
  reply: ThreadMessageReply = {},
): Promise<string> {
  const thread = await getByUuid(ctx, "conversation_threads", threadId);
  if (
    !thread ||
    thread.deleted_at !== undefined ||
    thread.moderation_status !== "visible" ||
    !(await canAccessCoupleContent(ctx, userId, thread.couple_id))
  ) {
    fail("42501", "active entitled thread access is required");
  }

  const mediaIds = (mediaAssetIds ?? []).map(uuidArg);
  if (mediaIds.length > 10) fail("23514", "thread messages can include at most 10 media assets");
  if (new Set(mediaIds).size !== mediaIds.length) fail("23514", "thread message media asset ids must be unique");
  const normalizedBody = btrimToNull(body);
  if (normalizedBody !== null && charLength(normalizedBody) > 4000) {
    fail("23514", "thread message body is too long");
  }
  if (normalizedBody === null && mediaIds.length === 0) fail("23514", "thread message must include text or media");

  let messageId = newUuid();
  if (mediaIds.length > 0) {
    const firstAsset = await getByUuid(ctx, "media_assets", mediaIds[0]);
    if (!firstAsset) fail("23514", "thread message media asset is not usable");
    messageId = firstAsset.reserved_parent_id;
  }

  await assertThreadMessageAllowed(ctx, thread.id, userId);
  if (reply.messageId !== undefined && reply.answerId !== undefined) {
    fail("23514", "a message can reply to one message or answer");
  }
  if (reply.messageId !== undefined) await assertReplyTargetAllowed(ctx, thread.id, reply.messageId);
  if (reply.answerId !== undefined) await assertAnswerReplyTargetAllowed(ctx, thread.id, userId, reply.answerId);
  if (await getByUuid(ctx, "thread_messages", messageId)) uniqueViolation("thread_messages_pkey");
  const now = nowIso();
  const docId = await ctx.db.insert("thread_messages", {
    id: messageId,
    thread_id: thread.id,
    sender_user_id: userId,
    body: normalizedBody ?? undefined,
    reply_to_message_id: reply.messageId,
    reply_to_answer_id: reply.answerId,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  await handleThreadMessageCreated(ctx, (await ctx.db.get(docId))!);

  for (const [index, mediaAssetId] of mediaIds.entries()) {
    await assertThreadMessageMediaAllowed(ctx, messageId, mediaAssetId);
    const sortOrder = index + 1;
    if (sortOrder > 10) checkViolation("thread_message_media", "thread_message_media_sort_order_check");
    await ctx.db.insert("thread_message_media", {
      message_id: messageId,
      media_asset_id: mediaAssetId,
      sort_order: sortOrder,
    });
  }
  return messageId;
}

function mediaFingerprint(body: string | null | undefined, mediaIds: string[] | null | undefined): [string, string[]] {
  return [btrimToNull(body) ?? "", (mediaIds ?? []).map(uuidArg)];
}

/** A reply adds its target to the request. A plain message adds nothing. */
function replyFingerprint(reply: ThreadMessageReply): string[] {
  if (reply.messageId !== undefined) return [reply.messageId];
  if (reply.answerId !== undefined) return [`answer:${reply.answerId}`];
  return [];
}

export const send_thread_message = mutation({
  args: {
    p_thread_id: v.string(),
    p_body: v.optional(v.union(v.null(), v.string())),
    p_media_asset_ids: nullableMediaIds,
    p_reply_to_message_id: v.optional(v.union(v.null(), v.string())),
    p_reply_to_answer_id: v.optional(v.union(v.null(), v.string())),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const threadId = uuidArg(args.p_thread_id);
    const reply = {
      messageId: optionalUuidArg(args.p_reply_to_message_id),
      answerId: optionalUuidArg(args.p_reply_to_answer_id),
    };
    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "send_thread_message",
        scope: "conversation_threads",
        request: [
          "send_thread_message",
          threadId,
          ...mediaFingerprint(args.p_body, args.p_media_asset_ids),
          ...replyFingerprint(reply),
        ],
      }),
      async () => {
        await consumeRateLimit(ctx, "threadMessage", userId);
        const messageId = await insertThreadMessage(ctx, userId, threadId, args.p_body, args.p_media_asset_ids, reply);
        return { thread_id: threadId, message_id: messageId };
      },
    );
    return [stored];
  },
});

/** How long after sending the sender can still change a message's text. */
export const MESSAGE_EDIT_WINDOW_MS = 5 * 60 * 1000;

/**
 * Replaces the text of the caller's own message within five minutes of sending.
 * Voice messages have no text to change, and a photo message keeps a caption.
 * Saving the same text again changes nothing. The live message query carries
 * the edit to both phones, so there is no push.
 */
export const edit_thread_message = mutation({
  args: { p_message_id: v.string(), p_body: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const message = await getByUuid(ctx, "thread_messages", uuidArg(args.p_message_id));
    if (!message || message.sender_user_id !== userId) fail("42501", "only the sender can edit a message");
    const thread = await getByUuid(ctx, "conversation_threads", message.thread_id);
    if (
      !thread ||
      thread.deleted_at !== undefined ||
      thread.moderation_status !== "visible" ||
      !(await canAccessCoupleContent(ctx, userId, thread.couple_id))
    ) {
      fail("42501", "active entitled thread access is required");
    }
    if (message.deleted_at !== undefined || message.moderation_status !== "visible") {
      fail("23514", "message is not available");
    }
    if (Date.now() - Date.parse(message.created_at) > MESSAGE_EDIT_WINDOW_MS) {
      fail("23514", "messages can only be edited for 5 minutes after sending");
    }
    if (message.body === undefined) fail("23514", "only messages with text can be edited");
    // A photo's caption can change. A voice message has nothing to read, so it can't.
    for (const link of await ctx.db
      .query("thread_message_media")
      .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", message.id))
      .collect()) {
      if ((await getByUuid(ctx, "media_assets", link.media_asset_id))?.media_type === "voice") {
        fail("23514", "only messages with text can be edited");
      }
    }
    const body = btrimToNull(args.p_body);
    if (body === null) fail("23514", "an edited message must keep its text");
    if (charLength(body) > 4000) fail("23514", "thread message body is too long");
    if (body === message.body) return null;

    await consumeRateLimit(ctx, "threadMessage", userId);
    const now = nowIso();
    await ctx.db.patch(message._id, { body, edited_at: now, updated_at: now });
    return null;
  },
});

/**
 * Sets the caller's emoji reaction to a shown message, their own or the partner's, or
 * clears it with a null `p_emoji`. A plain write without a client operation, so the same
 * call twice changes nothing. The live message query brings the reaction to both phones,
 * so there is no push.
 */
export const set_thread_message_reaction = mutation({
  args: { p_message_id: v.string(), p_emoji: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const message = await getByUuid(ctx, "thread_messages", uuidArg(args.p_message_id));
    const thread = message ? await getByUuid(ctx, "conversation_threads", message.thread_id) : null;
    if (!message || !thread || !(await canAccessCoupleContent(ctx, userId, thread.couple_id))) {
      return fail("42501", "active entitled thread access is required");
    }
    if (
      thread.deleted_at !== undefined ||
      thread.moderation_status !== "visible" ||
      message.deleted_at !== undefined ||
      message.moderation_status !== "visible"
    ) {
      fail("23514", "reaction target is not available");
    }
    const emoji = reactionArg(args.p_emoji);

    const existing = await ctx.db
      .query("thread_message_reactions")
      .withIndex("by_message_id_user_id", (q) => q.eq("message_id", message.id).eq("user_id", userId))
      .unique();
    if (emoji === null) {
      if (existing) await ctx.db.delete(existing._id);
      return null;
    }
    if (existing?.emoji === emoji) return null;
    await consumeRateLimit(ctx, "threadMessage", userId);
    if (existing) {
      await ctx.db.patch(existing._id, withUpdatedAt({ emoji }));
    } else {
      const now = nowIso();
      await ctx.db.insert("thread_message_reactions", {
        message_id: message.id,
        thread_id: thread.id,
        user_id: userId,
        emoji,
        created_at: now,
        updated_at: now,
      });
    }
    return null;
  },
});

/**
 * Starts the chat about a question with its first message, or adds to the chat that
 * already exists. A couple has one chat per question, whatever day the question came
 * back on. Starting it needs a day on which both partners answered the question.
 * The caller names the couple, so a message queued offline in one couple can never land
 * in the chat of a couple the user joined later. The first message can reply to an answer,
 * since the answers are on the page before anyone has written.
 */
export const create_daily_question_thread_with_message = mutation({
  args: {
    p_couple_id: v.string(),
    p_question_id: v.string(),
    p_body: v.optional(v.union(v.null(), v.string())),
    p_media_asset_ids: nullableMediaIds,
    p_reply_to_answer_id: v.optional(v.union(v.null(), v.string())),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    const questionId = uuidArg(args.p_question_id);
    const reply = { answerId: optionalUuidArg(args.p_reply_to_answer_id) };
    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "create_daily_question_thread_with_message",
        scope: "conversation_threads",
        request: [
          "create_daily_question_thread_with_message",
          coupleId,
          questionId,
          ...mediaFingerprint(args.p_body, args.p_media_asset_ids),
          ...replyFingerprint(reply),
        ],
      }),
      async () => {
        await consumeRateLimit(ctx, "threadMessage", userId);
        if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
          return fail("42501", "active entitled couple access is required");
        }
        if (!(await getByUuid(ctx, "questions", questionId))) {
          return fail("22023", "daily question was not found");
        }

        const rounds = await loadQuestionRounds(ctx, coupleId, questionId);
        if (!rounds.some((round) => round.answers.some((answer) => answer.user_id === userId))) {
          fail("42501", "you must answer this daily question before starting its thread");
        }
        if (!rounds.some(isSharedRound)) {
          fail("23514", "daily question thread requires both partners to answer");
        }

        const existing = await dailyQuestionThreadLink(ctx, coupleId, questionId);
        let threadId = existing?.thread_id;
        if (!threadId) {
          threadId = await insertConversationThread(ctx, {
            couple_id: coupleId,
            kind: "daily_question",
            created_by_user_id: userId,
          });
          await assertDailyQuestionThreadAllowed(ctx, coupleId, threadId);
          await ctx.db.insert("daily_question_threads", {
            couple_id: coupleId,
            question_id: questionId,
            thread_id: threadId,
            created_at: nowIso(),
          });
        }
        const messageId = await insertThreadMessage(ctx, userId, threadId, args.p_body, args.p_media_asset_ids, reply);
        return { thread_id: threadId, message_id: messageId };
      },
    );
    return [stored];
  },
});

export const create_memory_thread_with_message = mutation({
  args: {
    p_memory_id: v.string(),
    p_body: v.optional(v.union(v.null(), v.string())),
    p_media_asset_ids: nullableMediaIds,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const memoryId = uuidArg(args.p_memory_id);
    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "create_memory_thread_with_message",
        scope: "conversation_threads",
        request: [
          "create_memory_thread_with_message",
          memoryId,
          ...mediaFingerprint(args.p_body, args.p_media_asset_ids),
        ],
      }),
      async () => {
        await consumeRateLimit(ctx, "threadMessage", userId);
        const memory = await getByUuid(ctx, "memories", memoryId);
        if (
          !memory ||
          memory.deleted_at !== undefined ||
          memory.moderation_status !== "visible" ||
          !(await canAccessCoupleContent(ctx, userId, memory.couple_id))
        ) {
          return fail("42501", "active entitled memory access is required");
        }
        const existing = await ctx.db
          .query("memory_threads")
          .withIndex("by_memory_id", (q) => q.eq("memory_id", memory.id))
          .unique();
        let threadId = existing?.thread_id;
        if (!threadId) {
          threadId = await insertConversationThread(ctx, {
            couple_id: memory.couple_id,
            kind: "memory",
            created_by_user_id: userId,
          });
          await assertMemoryThreadAllowed(ctx, threadId);
          await ctx.db.insert("memory_threads", { memory_id: memory.id, thread_id: threadId, created_at: nowIso() });
        }
        const messageId = await insertThreadMessage(ctx, userId, threadId, args.p_body, args.p_media_asset_ids);
        return { thread_id: threadId, message_id: messageId };
      },
    );
    return [stored];
  },
});

export const get_conversation_threads = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const threads = await ctx.db
      .query("conversation_threads")
      .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
      .collect();

    const rows = [];
    for (const thread of threads) {
      const daily = await ctx.db
        .query("daily_question_threads")
        .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
        .unique();
      // A question chat opens only while some day of the question has both answers visible.
      // Leave it out once they are deleted or hidden, so the app never lists a chat the
      // user can't open.
      if (daily) {
        if (!(await loadQuestionRounds(ctx, coupleId, daily.question_id)).some(isSharedRound)) continue;
      }
      // A topic question's chat says which topic it is in.
      const topic = daily ? await topicOfQuestion(ctx, daily.question_id) : null;
      const memory = await ctx.db
        .query("memory_threads")
        .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
        .unique();
      const last = await ctx.db
        .query("thread_messages")
        .withIndex("by_thread_id_created_at_id", (q) => q.eq("thread_id", thread.id))
        .order("desc")
        .first();
      const visible =
        thread.deleted_at === undefined &&
        thread.moderation_status === "visible" &&
        last !== null &&
        last.deleted_at === undefined &&
        last.moderation_status === "visible";
      // What the newest message carries when it has no text, so the preview can say
      // "Photo" or "Voice message".
      const lastMedia = visible
        ? await ctx.db
            .query("thread_message_media")
            .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", last.id))
            .first()
        : null;
      const lastMediaAsset = lastMedia ? await getByUuid(ctx, "media_assets", lastMedia.media_asset_id) : null;
      // How far the caller has read, from any of their devices, so an unread mark clears everywhere.
      const viewerRead = await ctx.db
        .query("thread_read_states")
        .withIndex("by_thread_id_user_id", (q) => q.eq("thread_id", thread.id).eq("user_id", userId))
        .unique();
      rows.push({
        thread_id: thread.id,
        couple_id: thread.couple_id,
        kind: thread.kind,
        daily_question_id: orNull(daily?.question_id),
        memory_id: orNull(memory?.memory_id),
        created_by_user_id: thread.created_by_user_id,
        created_at: thread.created_at,
        updated_at: thread.updated_at,
        deleted_at: orNull(thread.deleted_at),
        moderation_status: thread.moderation_status,
        last_message_id: orNull(last?.id),
        last_message_at: orNull(last?.created_at),
        last_message_sender_user_id: orNull(last?.sender_user_id),
        last_message_deleted_at: orNull(last?.deleted_at),
        last_message_moderation_status: orNull(last?.moderation_status),
        last_message_body: visible ? orNull(last.body) : null,
        last_message_media_type: orNull(lastMediaAsset?.media_type),
        viewer_read_through_at: orNull(viewerRead?.last_read_message_created_at),
        topic_key: orNull(topic?.key),
        private_topic: topic?.private ?? false,
      });
    }
    // order by last_message_at desc (Postgres puts nulls first for desc), created_at desc, thread_id
    return rows.sort((a, b) => {
      if (a.last_message_at !== b.last_message_at) {
        if (a.last_message_at === null) return -1;
        if (b.last_message_at === null) return 1;
        return a.last_message_at < b.last_message_at ? 1 : -1;
      }
      if (a.created_at !== b.created_at) return a.created_at < b.created_at ? 1 : -1;
      return a.thread_id < b.thread_id ? -1 : 1;
    });
  },
});

const MAX_MESSAGE_PAGE = 100;

/**
 * One page of a thread's messages, oldest first. Without a cursor it is the newest page.
 * `p_before_created_at` and `p_before_message_id` are the oldest message the app has, and
 * give the page just before it. `has_more` is true when older messages remain.
 */
export const get_thread_messages = query({
  args: {
    p_thread_id: v.string(),
    p_limit: v.number(),
    p_before_created_at: v.optional(v.union(v.null(), v.string())),
    p_before_message_id: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (!Number.isFinite(args.p_limit) || args.p_limit < 1) fail("23514", "limit must be 1 or more");
    const limit = Math.min(Math.floor(args.p_limit), MAX_MESSAGE_PAGE);
    const thread = await getByUuid(ctx, "conversation_threads", uuidArg(args.p_thread_id));
    if (!thread || !(await canAccessCoupleContent(ctx, userId, thread.couple_id))) return { messages: [], has_more: false };

    const beforeAt = args.p_before_created_at ? timestampArg(args.p_before_created_at) : null;
    const beforeId = args.p_before_message_id ? uuidArg(args.p_before_message_id) : "";
    const threadVisible = thread.deleted_at === undefined && thread.moderation_status === "visible";
    const newestFirst = ctx.db
      .query("thread_messages")
      .withIndex("by_thread_id_created_at_id", (q) =>
        beforeAt === null ? q.eq("thread_id", thread.id) : q.eq("thread_id", thread.id).lte("created_at", beforeAt),
      )
      .order("desc");
    const messages = [];
    let hasMore = false;
    for await (const message of newestFirst) {
      // Messages sharing the cursor's millisecond sort by id, so skip the ones already sent.
      if (message.created_at === beforeAt && message.id >= beforeId) continue;
      if (messages.length === limit) {
        hasMore = true;
        break;
      }
      messages.push(message);
    }
    messages.reverse();
    const rows = [];
    for (const message of messages) {
      const messageVisible = threadVisible && message.deleted_at === undefined && message.moderation_status === "visible";
      const links = (
        await ctx.db
          .query("thread_message_media")
          .withIndex("by_message_id_sort_order", (q) => q.eq("message_id", message.id))
          .collect()
      ).sort((a, b) => a.sort_order - b.sort_order || (a.media_asset_id < b.media_asset_id ? -1 : 1));
      const mediaAssetIds: string[] = [];
      // The shown attachments with what the app needs to lay them out before downloading.
      const media = [];
      const mediaStates = [];
      for (const link of links) {
        const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
        if (!asset) continue;
        if (
          messageVisible &&
          asset.reserved_parent_kind === "thread_message_media" &&
          asset.reserved_parent_id === message.id &&
          asset.upload_status === "finalized" &&
          asset.storage_delete_status === "none" &&
          asset.moderation_status === "visible" &&
          asset.deleted_at === undefined
        ) {
          mediaAssetIds.push(link.media_asset_id);
          media.push({
            media_asset_id: link.media_asset_id,
            media_type: asset.media_type,
            width: orNull(asset.width),
            height: orNull(asset.height),
            duration_ms: orNull(asset.duration_ms),
          });
        }
        mediaStates.push({
          media_asset_id: link.media_asset_id,
          sort_order: link.sort_order,
          asset_deleted_at: orNull(asset.deleted_at),
          asset_moderation_status: asset.moderation_status,
          asset_storage_delete_status: asset.storage_delete_status,
          updated_at: asset.updated_at,
        });
      }
      // Who reacted with what. A removed message shows none.
      const reactions = messageVisible
        ? (
            await ctx.db
              .query("thread_message_reactions")
              .withIndex("by_message_id_user_id", (q) => q.eq("message_id", message.id))
              .collect()
          ).map((reaction) => ({ user_id: reaction.user_id, emoji: reaction.emoji }))
        : [];
      rows.push({
        thread_id: thread.id,
        message_id: message.id,
        sender_user_id: message.sender_user_id,
        body: messageVisible ? orNull(message.body) : null,
        reply_to_message_id: orNull(message.reply_to_message_id),
        reply_to_answer_id: orNull(message.reply_to_answer_id),
        created_at: message.created_at,
        edited_at: orNull(message.edited_at),
        deleted_at: orNull(message.deleted_at),
        moderation_status: message.moderation_status,
        media_asset_ids: mediaAssetIds,
        media,
        media_states: mediaStates,
        reactions,
      });
    }
    return { messages: rows, has_more: hasMore };
  },
});
