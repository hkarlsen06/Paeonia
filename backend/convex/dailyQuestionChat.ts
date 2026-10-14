import { v } from "convex/values";
import { query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { detailRow, type DailyAnswerDetailRow } from "./lib/dailyAnswers";
import { dailyQuestionThreadLink, isSharedRound, loadCoupleRounds } from "./lib/dailyQuestionRounds";
import { addSeenStates, QuestionContentReader, questionRow, type DailyQuestionRow } from "./lib/dailyQuestions";
import { getByUuid } from "./lib/db";
import { fail } from "./lib/errors";
import { uuidArg } from "./lib/ids";

/**
 * The question page: every round of one question in the named couple, oldest first,
 * with the answers each round lets the viewer read. The reveal rule applies per round.
 * The viewer always reads their own answer, and reads the partner's answer in a round
 * only after answering that same round.
 *
 * `questions` and `answer_details` have the shapes of the daily snapshot, so the app
 * builds a round the way it builds a question row. `thread_id` is the question's chat,
 * or null before anyone has written in it or while no round has both answers.
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
    const rounds = (await loadCoupleRounds(ctx, coupleId)).get(questionId) ?? [];

    const reader = new QuestionContentReader(ctx);
    const questions: DailyQuestionRow[] = [];
    const answerDetails: DailyAnswerDetailRow[] = [];
    for (const { day, instance, answers } of rounds) {
      const content = await reader.get(instance.question_version_id);
      if (!content) continue;
      const own = answers.find((answer) => answer.user_id === userId) ?? null;
      const partner = answers.find((answer) => answer.user_id !== userId) ?? null;
      questions.push(questionRow(day, instance, content, own, partner, own !== null && partner !== null, false));
      for (const answer of answers) {
        answerDetails.push(await detailRow(ctx, userId, day, instance, answer, answer.user_id === userId || own !== null));
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
    };
  },
});
