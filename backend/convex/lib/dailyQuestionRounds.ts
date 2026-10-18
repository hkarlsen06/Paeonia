import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { instanceDay, isLive, type DailyQuestionRow, visibleAnswersOf } from "./dailyQuestions";

/**
 * A couple has one chat per question. Each time the question comes back it is a new
 * round: one live daily question instance with at least one visible answer. The chat
 * shows every round, oldest first. These helpers find a question's rounds and answer
 * what the question rows need to know about them.
 */

export type QuestionRound = {
  day: Doc<"couple_days">;
  instance: Doc<"daily_question_instances">;
  /** The visible answers on the instance. */
  answers: Doc<"daily_question_answers">[];
};

/** Both partners have a visible answer in the round. */
export function isSharedRound(round: QuestionRound): boolean {
  return new Set(round.answers.map((answer) => answer.user_id)).size >= 2;
}

function compareRounds(a: QuestionRound, b: QuestionRound): number {
  return (
    (a.day.starts_at < b.day.starts_at ? -1 : a.day.starts_at > b.day.starts_at ? 1 : 0) ||
    (a.instance.created_at < b.instance.created_at ? -1 : a.instance.created_at > b.instance.created_at ? 1 : 0) ||
    a.instance._creationTime - b.instance._creationTime
  );
}

/**
 * Every round of one question in the couple, oldest first. A round is a live instance
 * with a visible answer, so an instance nobody answered is not a round.
 */
export async function loadQuestionRounds(ctx: ReaderCtx, coupleId: string, questionId: string): Promise<QuestionRound[]> {
  const instances = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId).eq("question_id", questionId))
    .collect();
  const rounds: QuestionRound[] = [];
  for (const instance of instances) {
    if (!isLive(instance)) continue;
    const day = await instanceDay(ctx, instance);
    if (!day) continue;
    const answers = await visibleAnswersOf(ctx, instance.id);
    if (answers.length > 0) rounds.push({ day, instance, answers });
  }
  return rounds.sort(compareRounds);
}

/** The thread of a couple's chat about a question, or null before anyone has written. */
export async function dailyQuestionThreadLink(ctx: ReaderCtx, coupleId: string, questionId: string) {
  return await ctx.db
    .query("daily_question_threads")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId).eq("question_id", questionId))
    .unique();
}

/**
 * Adds what the viewer needs to know about the other rounds of each row's question:
 * how many earlier days they answered it, the latest of those days, and whether the
 * question's chat can start. Same-day rounds do not count as earlier.
 */
export async function addRoundInfo(
  ctx: ReaderCtx,
  viewerId: string,
  coupleId: string,
  rows: DailyQuestionRow[],
): Promise<void> {
  const rounds = new Map<string, QuestionRound[]>();
  for (const row of rows) {
    if (!rounds.has(row.question_id)) rounds.set(row.question_id, await loadQuestionRounds(ctx, coupleId, row.question_id));
    const list = rounds.get(row.question_id)!;
    const earlier = list.filter(
      (round) => round.day.starts_at < row.starts_at && round.answers.some((answer) => answer.user_id === viewerId),
    );
    row.earlier_round_count = earlier.length;
    row.latest_earlier_round_local_date = earlier.at(-1)?.day.local_date ?? null;
    row.chat_available = list.some(isSharedRound);
  }
}
