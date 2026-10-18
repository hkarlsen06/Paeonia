import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import {
  assertAnswerPayloadShape,
  detailRow,
  insertDailyAnswer,
  parseAnswerPayload,
  type DailyAnswerDetailRow,
} from "./lib/dailyAnswers";
import {
  addSeenStates,
  instanceDay,
  optionLabels,
  QuestionContentReader,
  questionRow,
  type DailyQuestionRow,
} from "./lib/dailyQuestions";
import { getByUuid, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { timestampArg, uuidArg } from "./lib/ids";
import { applyCoupleActivity } from "./lib/streaks";
import {
  activeTopics,
  adultGate,
  answerState,
  assertTopicOpen,
  queueTopicPush,
  requireActiveTopic,
  skippedQuestionIds,
  skipRow,
  topicInstanceFor,
  topicInstances,
  topicIsOpen,
  topicOfQuestion,
  topicQuestions,
  topicSummary,
  type TopicSummary,
} from "./lib/topics";
import { nowIso } from "./lib/time";

/** Question topics. See `lib/topics.ts` for how a topic question is stored. */

const nullableString = v.optional(v.union(v.null(), v.string()));

type TopicQuestionRow = {
  question_id: string;
  question_key: string;
  question_version_id: string;
  sort_order: number;
  prompt_en: string;
  short_prompt_en: string;
  prompt_nb: string;
  short_prompt_nb: string;
  answer_kinds: string[];
  option_a_en: string | null;
  option_b_en: string | null;
  option_a_nb: string | null;
  option_b_nb: string | null;
  is_skipped: boolean;
  /** The started question, shaped like a daily question row. Null before anyone answered it. */
  row: DailyQuestionRow | null;
};

/** The shelf: every topic the couple can see, with its counts. */
export const get_topics_overview = query({
  args: {},
  handler: async (ctx): Promise<{ topics: TopicSummary[]; adult_topics_hidden_by_viewer: boolean }> => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const gate = await adultGate(ctx, coupleId, userId);
    const skipped = await skippedQuestionIds(ctx, coupleId);
    const reader = new QuestionContentReader(ctx);
    const topics: TopicSummary[] = [];
    for (const topic of await activeTopics(ctx)) {
      if (topic.collection.adults_only && gate.hidden) continue;
      topics.push(await topicSummary(ctx, reader, topic, coupleId, userId, gate, skipped));
    }
    return { topics, adult_topics_hidden_by_viewer: gate.hiddenByViewer };
  },
});

/** One topic's questions, with the started ones as daily-shaped rows and their answers under the reveal rule. */
export const get_topic = query({
  args: { p_topic_key: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const topic = await requireActiveTopic(ctx, args.p_topic_key);
    const gate = await adultGate(ctx, coupleId, userId);
    if (!topicIsOpen(topic.collection, gate)) {
      return fail("42501", "adult topic is not open");
    }
    const skipped = await skippedQuestionIds(ctx, coupleId);
    const reader = new QuestionContentReader(ctx);
    const instances = await topicInstances(ctx, coupleId, topic.collection.id);
    const questions: TopicQuestionRow[] = [];
    const startedRows: DailyQuestionRow[] = [];
    const answerDetails: DailyAnswerDetailRow[] = [];
    for (const { question, content } of await topicQuestions(ctx, reader, topic.collection.id)) {
      let row: DailyQuestionRow | null = null;
      const instance = instances.get(question.id);
      const day = instance ? await instanceDay(ctx, instance) : null;
      const instanceContent = instance ? await reader.get(instance.question_version_id) : null;
      if (instance && day && instanceContent) {
        const { answers, own, partner } = await answerState(ctx, instance, userId);
        row = questionRow(day, instance, instanceContent, own, partner, own !== null && partner !== null, false);
        row.topic_key = topic.collection.key!;
        // A couple answers a topic question once, so its one round is the whole chat.
        row.earlier_round_count = 0;
        row.latest_earlier_round_local_date = null;
        row.chat_available = own !== null && partner !== null;
        startedRows.push(row);
        for (const answer of answers) {
          answerDetails.push(await detailRow(ctx, userId, day, instance, answer, answer.user_id === userId || own !== null));
        }
      }
      questions.push({
        question_id: question.id,
        question_key: question.key,
        question_version_id: content.version.id,
        sort_order: question.sort_order ?? 0,
        prompt_en: content.en.prompt,
        short_prompt_en: content.en.short_prompt,
        prompt_nb: content.nb.prompt,
        short_prompt_nb: content.nb.short_prompt,
        answer_kinds: content.answer_kinds,
        ...optionLabels(content),
        is_skipped: skipped.has(question.id),
        row,
      });
    }
    await addSeenStates(ctx, userId, startedRows);
    return {
      topic: await topicSummary(ctx, reader, topic, coupleId, userId, gate, skipped),
      questions,
      answer_details: answerDetails,
    };
  },
});

/** The topic of a question the caller may answer or skip now. */
async function requireOpenTopicQuestion(ctx: Parameters<typeof topicOfQuestion>[0], questionId: string, coupleId: string, userId: string) {
  const question = await getByUuid(ctx, "questions", questionId);
  const topic = await topicOfQuestion(ctx, questionId);
  if (!question || question.status !== "active" || !topic || topic.status !== "active") {
    return fail("22023", "topic question was not found");
  }
  await assertTopicOpen(ctx, topic, coupleId, userId);
  return { question, topic };
}

/**
 * Answers a topic question. The first answer starts the question with `p_instance_id`. A partner who
 * answers later joins the same instance, so the returned `instance_id` can differ from the one sent.
 */
export const submit_topic_answer = mutation({
  args: {
    p_question_id: v.string(),
    p_instance_id: v.string(),
    p_payload: v.any(),
    p_client_operation_id: v.string(),
    p_client_id: v.string(),
    p_client_sequence: v.number(),
    p_local_created_at: nullableString,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const questionId = uuidArg(args.p_question_id);
    const instanceId = uuidArg(args.p_instance_id);
    if (args.p_local_created_at === null || args.p_local_created_at === undefined) {
      return fail("23514", "daily operation timestamp is required");
    }
    const localCreatedAt = timestampArg(args.p_local_created_at);
    const body = assertAnswerPayloadShape(args.p_payload);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    return await runClientOperation(
      ctx,
      userId,
      {
        client_operation_id: uuidArg(args.p_client_operation_id),
        client_id: uuidArg(args.p_client_id),
        client_sequence: args.p_client_sequence,
        local_created_at: localCreatedAt,
        operation_kind: "submit_topic_answer",
        idempotency_scope: "daily_challenges",
        request: { kind: "submit_topic_answer", question_id: questionId, instance_id: instanceId, payload: args.p_payload },
      },
      async () => {
        const { topic } = await requireOpenTopicQuestion(ctx, questionId, coupleId, userId);
        const now = nowIso();
        const dayId = await getOrCreateCoupleDayAt(ctx, coupleId, now);
        let instance = await topicInstanceFor(ctx, coupleId, questionId);
        if (!instance) {
          if (await getByUuid(ctx, "daily_question_instances", instanceId)) {
            return fail("23505", "daily_question_instances_pkey");
          }
          const version = await ctx.db
            .query("question_versions")
            .withIndex("by_question_id_status", (q) => q.eq("question_id", questionId).eq("status", "active"))
            .first();
          if (!version) return fail("22023", "topic question was not found");
          await ctx.db.insert("daily_question_instances", {
            id: instanceId,
            couple_id: coupleId,
            question_id: questionId,
            question_version_id: version.id,
            seeded_for_user_id: userId,
            slot_number: 0,
            status: "active",
            topic_collection_id: topic.id,
            started_couple_day_id: dayId,
            created_at: now,
          });
          instance = (await getByUuid(ctx, "daily_question_instances", instanceId))!;
        }
        const parsed = await parseAnswerPayload(ctx, userId, instance, body);
        await insertDailyAnswer(ctx, { userId, instance, ...parsed, notifyPartner: false });
        // Answering a question the couple put aside brings it back.
        const skip = await skipRow(ctx, coupleId, questionId);
        if (skip) await ctx.db.delete(skip._id);
        await applyCoupleActivity(ctx, {
          couple_id: coupleId,
          user_id: userId,
          couple_day_id: dayId,
          activity_kind: "topic_answer_submitted",
          occurred_at: now,
          dedupe_key: `topic_answer_submitted:${parsed.answerId}`,
          metadata: { source: "topic" },
        });
        for (const member of await listActiveMembers(ctx, coupleId)) {
          if (member.user_id !== userId) await queueTopicPush(ctx, coupleId, userId, member.user_id);
        }
        return { answer_id: parsed.answerId, instance_id: instance.id };
      },
    );
  },
});

/** Puts a topic question aside for the couple, or brings it back. Nobody is told who did it. */
export const set_topic_question_skipped = mutation({
  args: { p_question_id: v.string(), p_skipped: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const questionId = uuidArg(args.p_question_id);
    await requireOpenTopicQuestion(ctx, questionId, coupleId, userId);
    const existing = await skipRow(ctx, coupleId, questionId);
    if (args.p_skipped && !existing) {
      await ctx.db.insert("topic_question_skips", { couple_id: coupleId, question_id: questionId, skipped_at: nowIso() });
    } else if (!args.p_skipped && existing) {
      await ctx.db.delete(existing._id);
    }
    return null;
  },
});

/**
 * Saves the caller's age check for adults-only topics: `confirmed` when the phone said 18 or older,
 * `hidden` for anything else. The phone reports only that, never an age or a reason.
 */
export const set_adult_topics_status = mutation({
  args: { p_status: v.union(v.literal("confirmed"), v.literal("hidden")) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const member = (await listActiveMembers(ctx, coupleId)).find((row) => row.user_id === userId);
    if (!member) return fail("42501", "active entitled couple access is required");
    if (member.adult_topics !== args.p_status) {
      await ctx.db.patch(member._id, withUpdatedAt({ adult_topics: args.p_status, adult_topics_at: nowIso() }));
    }
    return null;
  },
});
