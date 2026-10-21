/// <reference types="vite/client" />
// Shared helpers for the question chat tests. The two dots in the file name keep Convex from bundling this file.
import { seedCatalog, type SeededQuestion } from "./daily.setup";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { newUuid } from "./lib/ids";
import type { TestConvex, TestCouple, TestUser } from "./test.setup";

/** One active question with a text answer kind. */
export async function seedQuestion(t: TestConvex, key = `q_${newUuid().slice(0, 8)}`): Promise<SeededQuestion> {
  const [question] = await seedCatalog(t, [{ key }]);
  return question;
}

/**
 * One round of a question: a live instance on the couple day containing `at`, with a
 * visible answer from each listed user. `texts` gives a user's answer text.
 */
export async function answeredRound(
  t: TestConvex,
  couple: TestCouple,
  question: SeededQuestion,
  options: { answeredBy?: TestUser[]; at?: string; texts?: Record<string, string>; seededFor?: TestUser } = {},
): Promise<string> {
  const instanceId = newUuid();
  const at = options.at ?? new Date().toISOString();
  await t.run(async (ctx) => {
    const dayId = await getOrCreateCoupleDayAt(ctx, couple.coupleId, at);
    await ctx.db.insert("daily_question_instances", {
      id: instanceId,
      couple_day_id: dayId,
      couple_id: couple.coupleId,
      question_id: question.id,
      question_version_id: question.versionId,
      seeded_for_user_id: (options.seededFor ?? couple.first).userId,
      slot_number: 1,
      status: "active",
      created_at: at,
    });
    for (const user of options.answeredBy ?? [couple.first, couple.second]) {
      const answerId = newUuid();
      await ctx.db.insert("daily_question_answers", {
        id: answerId,
        instance_id: instanceId,
        user_id: user.userId,
        moderation_status: "visible",
        created_at: at,
        updated_at: at,
      });
      const text = options.texts?.[user.userId];
      if (text !== undefined) await ctx.db.insert("daily_answer_text", { answer_id: answerId, couple_id: couple.coupleId, body: text });
    }
  });
  return instanceId;
}

/** The id of `user`'s answer in a round. */
export async function answerIdOf(t: TestConvex, instanceId: string, user: TestUser): Promise<string> {
  return await t.run(async (ctx) => {
    const answer = await ctx.db
      .query("daily_question_answers")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId).eq("user_id", user.userId))
      .unique();
    return answer!.id;
  });
}
