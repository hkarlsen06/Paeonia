import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { detailRow, type DailyAnswerDetailRow } from "./lib/dailyAnswers";
import { dailyQuestionThreadLink, isSharedRound, loadQuestionRounds } from "./lib/dailyQuestionRounds";
import {
  addSeenStates,
  isLive,
  isVisibleAnswer,
  QuestionContentReader,
  questionRow,
  visibleAnswersOf,
  type DailyQuestionRow,
} from "./lib/dailyQuestions";
import { getByUuid, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";
import { consumeRateLimit } from "./lib/rateLimits";
import { reactionArg } from "./lib/reactions";
import { nowIso } from "./lib/time";
import { topicOfQuestion } from "./lib/topics";

type AnswerReactionRow = { answer_id: string; user_id: string; emoji: string };

/**
 * The question page: every round of one question in the named couple, oldest first,
 * with the answers each round lets the viewer read. The reveal rule applies per round.
 * The viewer always reads their own answer, and reads the partner's answer in a round
 * only after answering that same round.
 *
 * `questions` and `answer_details` have the shapes of the daily snapshot, so the app
 * builds a round the way it builds a question row. `thread_id` is the question's chat,
 * or null before anyone has written in it or while no round has both answers.
 * `reactions` holds the emoji reactions on the answers the viewer can read.
 */
export const get_daily_question_chat = query({
  args: { p_couple_id: v.string(), p_question_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
      return fail("42501", "active entitled couple access is required");
    }
    const questionId = uuidArg(args.p_question_id);
    const topic = await topicOfQuestion(ctx, questionId);
    const rounds = await loadQuestionRounds(ctx, coupleId, questionId);

    const reader = new QuestionContentReader(ctx);
    const questions: DailyQuestionRow[] = [];
    const answerDetails: DailyAnswerDetailRow[] = [];
    const reactions: AnswerReactionRow[] = [];
    for (const { day, instance, answers } of rounds) {
      const content = await reader.get(instance.question_version_id);
      if (!content) continue;
      const own = answers.find((answer) => answer.user_id === userId) ?? null;
      const partner = answers.find((answer) => answer.user_id !== userId) ?? null;
      const row = questionRow(day, instance, content, own, partner, own !== null && partner !== null, false);
      row.topic_key = topic?.key ?? null;
      questions.push(row);
      for (const answer of answers) {
        const canView = answer.user_id === userId || own !== null;
        answerDetails.push(await detailRow(ctx, userId, day, instance, answer, canView));
        if (!canView) continue;
        for (const reaction of await ctx.db
          .query("daily_answer_reactions")
          .withIndex("by_answer_id_user_id", (q) => q.eq("answer_id", answer.id))
          .collect()) {
          reactions.push({ answer_id: answer.id, user_id: reaction.user_id, emoji: reaction.emoji });
        }
      }
    }
    await addSeenStates(ctx, userId, questions);
    const chatAvailable = rounds.some(isSharedRound);
    for (const row of questions) row.chat_available = chatAvailable;

    const link = await dailyQuestionThreadLink(ctx, coupleId, questionId);
    const thread = link ? await getByUuid(ctx, "conversation_threads", link.thread_id) : null;
    const hasThread =
      thread !== null && thread.deleted_at === undefined && thread.moderation_status === "visible" && chatAvailable;
    return {
      thread_id: hasThread ? thread.id : null,
      questions,
      answer_details: answerDetails,
      reactions,
    };
  },
});

/**
 * Sets the caller's emoji reaction to an answer, or clears it with a null `p_emoji`.
 * Only an answer the caller can read in the question chat can get a reaction: their own,
 * or the partner's on a day the caller answered too. A plain write without a client
 * operation, so the same call twice changes nothing. The live chat query brings the
 * reaction to both phones, so there is no push.
 */
export const set_daily_answer_reaction = mutation({
  args: { p_answer_id: v.string(), p_emoji: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const answer = await getByUuid(ctx, "daily_question_answers", uuidArg(args.p_answer_id));
    const instance = answer ? await getByUuid(ctx, "daily_question_instances", answer.instance_id) : null;
    if (!answer || !instance || !(await canAccessCoupleContent(ctx, userId, instance.couple_id))) {
      return fail("42501", "active entitled couple access is required");
    }
    if (!isVisibleAnswer(answer) || !isLive(instance)) fail("23514", "reaction target is not available");
    if (!(await visibleAnswersOf(ctx, instance.id)).some((own) => own.user_id === userId)) {
      fail("42501", "you must answer this daily question before reacting");
    }
    const emoji = reactionArg(args.p_emoji);

    const existing = await ctx.db
      .query("daily_answer_reactions")
      .withIndex("by_answer_id_user_id", (q) => q.eq("answer_id", answer.id).eq("user_id", userId))
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
      await ctx.db.insert("daily_answer_reactions", {
        answer_id: answer.id,
        couple_id: instance.couple_id,
        user_id: userId,
        emoji,
        created_at: now,
        updated_at: now,
      });
    }
    return null;
  },
});
