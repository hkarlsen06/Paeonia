import type { Doc } from "../_generated/dataModel";
import { listActiveMembers } from "./access";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { isLive, type DailyQuestionRow, visibleAnswersOf } from "./dailyQuestions";

/**
 * A couple has one chat per question. Each time the question comes back it is a new
 * round: one live daily question instance with at least one visible answer. The chat
 * shows every round, oldest first. These helpers find a couple's rounds and answer
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
 * Every round of every question in the couple, oldest first, by question id. A round
 * is found through its answers, so an instance nobody answered is not a round.
 */
// ponytail: this reads each partner's whole answer history, about two rows a day. Add a
// question id to the instance rows and index it with the couple if couples get years of history.
export async function loadCoupleRounds(ctx: ReaderCtx, coupleId: string): Promise<Map<string, QuestionRound[]>> {
  const instanceIds = new Set<string>();
  for (const member of await listActiveMembers(ctx, coupleId)) {
    const answers = await ctx.db
      .query("daily_question_answers")
      .withIndex("by_user_id_created_at", (q) => q.eq("user_id", member.user_id))
      .collect();
    for (const answer of answers) {
      if (answer.deleted_at === undefined && answer.moderation_status === "visible") instanceIds.add(answer.instance_id);
    }
  }

  const questionByVersion = new Map<string, string | null>();
  const rounds = new Map<string, QuestionRound[]>();
  for (const instanceId of instanceIds) {
    const instance = await getByUuid(ctx, "daily_question_instances", instanceId);
    if (!instance || !isLive(instance)) continue;
    const day = await getByUuid(ctx, "couple_days", instance.couple_day_id);
    if (!day || day.couple_id !== coupleId) continue;
    let questionId = questionByVersion.get(instance.question_version_id);
    if (questionId === undefined) {
      questionId = (await getByUuid(ctx, "question_versions", instance.question_version_id))?.question_id ?? null;
      questionByVersion.set(instance.question_version_id, questionId);
    }
    if (questionId === null) continue;
    const round = { day, instance, answers: await visibleAnswersOf(ctx, instance.id) };
    rounds.set(questionId, [...(rounds.get(questionId) ?? []), round]);
  }
  for (const list of rounds.values()) list.sort(compareRounds);
  return rounds;
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
  if (rows.length === 0) return;
  const rounds = await loadCoupleRounds(ctx, coupleId);
  for (const row of rows) {
    const list = rounds.get(row.question_id) ?? [];
    const earlier = list.filter(
      (round) => round.day.starts_at < row.starts_at && round.answers.some((answer) => answer.user_id === viewerId),
    );
    row.earlier_round_count = earlier.length;
    row.latest_earlier_round_local_date = earlier.at(-1)?.day.local_date ?? null;
    row.chat_available = list.some(isSharedRound);
  }
}
