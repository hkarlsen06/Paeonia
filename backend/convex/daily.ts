import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query, type MutationCtx } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { runClientOperation } from "./lib/clientOperations";
import { findCoupleDayAt, getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { getByUuid, type ReaderCtx } from "./lib/db";
import {
  getDailyAnswerDetails,
  getDailyAnswerDetailsForContext,
  getDailyAnswerHistoryDetails,
  resetDailyChallengeForCouple,
  submitDailyAnswer,
  updateDailyAnswerPartnerChoice,
  updateDailyAnswerText,
  type ClientOperationArgs,
} from "./lib/dailyAnswers";
import {
  DAILY_QUESTION_SLOTS,
  ensureDailyChallengeSlots,
  getDailyQuestionsForCoupleDay,
  getDailyQuestionsHistory,
  getTodayDailyQuestionsForContext,
  insertDailyQuestionInstance,
  pickDailyQuestionVersion,
} from "./lib/dailyQuestions";
import { addRoundInfo } from "./lib/dailyQuestionRounds";
import { fail } from "./lib/errors";
import { newUuid, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import {
  getCoupleStreakForCouple,
  getCoupleStreakParticipationForDay,
  readCoupleStreak,
  type CoupleStreak,
} from "./lib/streaks";
import { addDaysToInstant, nowIso } from "./lib/time";

/**
 * Daily questions and answers. Writes are mutations. Reads are queries, so the iOS
 * client can both call them once and subscribe to them. Return values keep the
 * shape PostgREST returned for the Supabase RPCs.
 */

const nullableString = v.optional(v.union(v.null(), v.string()));

const clientOperationArgs = {
  p_client_operation_id: v.string(),
  p_client_id: v.string(),
  p_client_sequence: v.number(),
  p_local_created_at: nullableString,
};

const DAILY_SHUFFLE_LIMIT = 30;
const SHUFFLE_EXCLUDE_DAYS = 14;

type OperationArgs = {
  p_client_operation_id: string;
  p_client_id: string;
  p_client_sequence: number;
  p_local_created_at?: string | null;
};

function operationFrom(args: OperationArgs): ClientOperationArgs {
  if (args.p_local_created_at === null || args.p_local_created_at === undefined) {
    return fail("23514", "daily operation timestamp is required");
  }
  return {
    clientOperationId: uuidArg(args.p_client_operation_id),
    clientId: uuidArg(args.p_client_id),
    clientSequence: args.p_client_sequence,
    localCreatedAt: timestampArg(args.p_local_created_at),
  };
}

// ---- today's challenge ----

async function startChallenge(ctx: MutationCtx, userId: string, args: OperationArgs): Promise<string> {
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const operation = operationFrom(args);
  const stored = await runClientOperation(
    ctx,
    userId,
    {
      client_operation_id: operation.clientOperationId,
      client_id: operation.clientId,
      client_sequence: operation.clientSequence,
      local_created_at: operation.localCreatedAt,
      operation_kind: "start_daily_challenge",
      idempotency_scope: "daily_challenges",
      request: { kind: "start_daily_challenge", couple_id: coupleId, local_created_at: operation.localCreatedAt },
    },
    async () => {
      const coupleDayId = await getOrCreateCoupleDayAt(ctx, coupleId, operation.localCreatedAt);
      await ensureDailyChallengeSlots(ctx, coupleDayId);
      return { couple_day_id: coupleDayId };
    },
  );
  return stored.couple_day_id;
}

async function shuffleQuestion(
  ctx: MutationCtx,
  userId: string,
  args: OperationArgs & { p_slot_number: number },
): Promise<string> {
  const slot = args.p_slot_number;
  if (!Number.isInteger(slot) || slot < 1 || slot > DAILY_QUESTION_SLOTS) {
    fail("23514", "slot number is out of range");
  }
  const operation = operationFrom(args);
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const stored = await runClientOperation(
    ctx,
    userId,
    {
      client_operation_id: operation.clientOperationId,
      client_id: operation.clientId,
      client_sequence: operation.clientSequence,
      local_created_at: operation.localCreatedAt,
      operation_kind: "shuffle_daily_question",
      idempotency_scope: "daily_challenges",
      request: {
        kind: "shuffle_daily_question",
        couple_id: coupleId,
        user_id: userId,
        slot_number: slot,
        local_created_at: operation.localCreatedAt,
      },
    },
    async () => {
      const coupleDayId = await getOrCreateCoupleDayAt(ctx, coupleId, operation.localCreatedAt);
      await ensureDailyChallengeSlots(ctx, coupleDayId);

      const shuffles = await ctx.db
        .query("daily_question_shuffles")
        .withIndex("by_couple_day_id_user_id", (q) => q.eq("couple_day_id", coupleDayId).eq("user_id", userId))
        .collect();
      if (shuffles.length >= DAILY_SHUFFLE_LIMIT) {
        fail("23514", "daily shuffle limit reached");
      }

      const active = await ctx.db
        .query("daily_question_instances")
        .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) =>
          q.eq("couple_day_id", coupleDayId).eq("seeded_for_user_id", userId).eq("status", "active").eq("slot_number", slot),
        )
        .first();
      if (!active) {
        return fail("22023", "active daily question slot was not found");
      }
      const answered = await ctx.db
        .query("daily_question_answers")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", active.id).eq("user_id", userId))
        .first();
      if (answered && answered.deleted_at === undefined) {
        fail("23514", "answered daily questions cannot be shuffled");
      }

      const skippedVersion = await getByUuid(ctx, "question_versions", active.question_version_id);
      const skippedQuestionId = skippedVersion!.question_id;
      const pickedVersionId = await pickDailyQuestionVersion(ctx, coupleDayId, userId, skippedQuestionId);

      const now = nowIso();
      await ctx.db.patch(active._id, { status: "shuffled", replaced_at: now });
      const replacementId = await insertDailyQuestionInstance(ctx, {
        couple_day_id: coupleDayId,
        question_version_id: pickedVersionId,
        seeded_for_user_id: userId,
        slot_number: slot,
      });
      await ctx.db.patch(active._id, { replaced_by_instance_id: replacementId });
      // assert_daily_question_shuffle_valid holds: both instances share this day, user, and slot.
      await ctx.db.insert("daily_question_shuffles", {
        id: newUuid(),
        couple_id: coupleId,
        couple_day_id: coupleDayId,
        user_id: userId,
        question_id: skippedQuestionId,
        skipped_instance_id: active.id,
        replacement_instance_id: replacementId,
        slot_number: slot,
        skipped_at: now,
        exclude_until: addDaysToInstant(now, SHUFFLE_EXCLUDE_DAYS),
      });
      return { replacement_instance_id: replacementId, couple_day_id: coupleDayId };
    },
  );
  return stored.couple_day_id;
}

function byString(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * The snapshot row. `couple_day_id`, `local_date`, `starts_at`, and `ends_at` describe the couple day
 * the snapshot is for (null when today has no couple day yet), so the client knows when to start a new day.
 */
async function snapshotRow(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
  source: { kind: "today" } | { kind: "day"; day: Doc<"couple_days"> },
  streak: CoupleStreak,
) {
  const now = nowIso();
  const day = source.kind === "day" ? source.day : await findCoupleDayAt(ctx, coupleId, now);
  const questions =
    source.kind === "day"
      ? await getDailyQuestionsForCoupleDay(ctx, userId, source.day)
      : await getTodayDailyQuestionsForContext(ctx, userId, coupleId);
  await addRoundInfo(ctx, userId, coupleId, questions);
  const answerDetails = await getDailyAnswerDetailsForContext(
    ctx,
    questions.map((row) => row.couple_day_id),
    userId,
    coupleId,
  );
  const participation = day
    ? await getCoupleStreakParticipationForDay(ctx, coupleId, userId, day.id)
    : { current_user_contributed_today: false, partner_contributed_today: false };
  questions.sort((a, b) => {
    if (a.is_current_day !== b.is_current_day) return a.is_current_day ? -1 : 1;
    return (
      byString(b.starts_at, a.starts_at) ||
      byString(a.seeded_for_user_id, b.seeded_for_user_id) ||
      a.slot_number - b.slot_number ||
      byString(a.instance_id, b.instance_id)
    );
  });
  answerDetails.sort(
    (a, b) =>
      byString(a.couple_day_id, b.couple_day_id) ||
      a.slot_number - b.slot_number ||
      byString(a.answered_at, b.answered_at) ||
      byString(a.answer_id, b.answer_id),
  );
  // A day snapshot must not change with the clock, so its generated_at is the newest
  // data timestamp. The iOS decoder needs the field, so it cannot be dropped.
  const generatedAt =
    source.kind === "day"
      ? [source.day.starts_at, ...answerDetails.map((row) => row.answered_at)].reduce((a, b) => (a > b ? a : b))
      : now;
  return [
    {
      questions,
      answer_details: answerDetails,
      streak: { ...streak, ...participation },
      generated_at: generatedAt,
      couple_day_id: day?.id ?? null,
      local_date: day?.local_date ?? null,
      starts_at: day?.starts_at ?? null,
      ends_at: day?.ends_at ?? null,
    },
  ];
}

/**
 * Port of `internal.get_today_daily_challenge_snapshot` for the mutations: the snapshot of the couple day
 * the operation targeted, or today when it is unknown. Also stores a restore offer if the streak just broke.
 */
async function snapshotAfterOperation(ctx: MutationCtx, userId: string, coupleDayId: string | null) {
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const streak = await getCoupleStreakForCouple(ctx, coupleId);
  const day = coupleDayId === null ? null : await getByUuid(ctx, "couple_days", coupleDayId);
  const source = day && day.couple_id === coupleId ? ({ kind: "day", day } as const) : ({ kind: "today" } as const);
  return await snapshotRow(ctx, userId, coupleId, source, streak);
}

export const start_daily_challenge_snapshot = mutation({
  args: clientOperationArgs,
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleDayId = await startChallenge(ctx, userId, args);
    return await snapshotAfterOperation(ctx, userId, coupleDayId);
  },
});

/**
 * Today's snapshot by the server clock. A query, so it is right for one-shot reads. Convex reruns a query only
 * when data it read changes, so a result that depends on the clock can come back stale after midnight, even to a
 * new subscription with the same arguments. `p_day_key` is ignored. A client changes it once per day (for
 * example to the previous day's `ends_at`) so each day is a separate cached query. Subscribers that know their
 * couple day should use `get_daily_challenge_snapshot` instead.
 */
export const get_today_daily_challenge_snapshot = query({
  args: { p_day_key: v.optional(v.string()) },
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    return await snapshotRow(ctx, userId, coupleId, { kind: "today" }, await readCoupleStreak(ctx, coupleId));
  },
});

/**
 * The snapshot for one couple day, built only from stored data (apart from the streak counts, which read the
 * clock). Every write that changes it touches a row it reads, so a subscription stays current until `ends_at`.
 * After that the client calls `start_daily_challenge_snapshot` and subscribes to the new `couple_day_id`.
 */
export const get_daily_challenge_snapshot = query({
  args: { p_couple_day_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const day = await getByUuid(ctx, "couple_days", uuidArg(args.p_couple_day_id));
    // An unknown day and a day of another couple fail the same way, so ids do not leak.
    if (!day || !(await canAccessCoupleContent(ctx, userId, day.couple_id))) {
      return fail("42501", "active entitled couple access is required");
    }
    return await snapshotRow(ctx, userId, day.couple_id, { kind: "day", day }, await readCoupleStreak(ctx, day.couple_id));
  },
});

export const shuffle_daily_question_snapshot = mutation({
  args: { p_slot_number: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleDayId = await shuffleQuestion(ctx, userId, args);
    return await snapshotAfterOperation(ctx, userId, coupleDayId);
  },
});

// ---- answers ----

export const submit_daily_answer = mutation({
  args: { p_instance_id: v.string(), p_payload: v.any(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const operation = operationFrom(args);
    return await submitDailyAnswer(ctx, userId, uuidArg(args.p_instance_id), args.p_payload, operation);
  },
});

export const update_daily_answer_text = mutation({
  args: { p_instance_id: v.string(), p_text: nullableString, ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const operation = operationFrom(args);
    return await updateDailyAnswerText(ctx, userId, uuidArg(args.p_instance_id), args.p_text, operation);
  },
});

export const update_daily_answer_partner_choice = mutation({
  args: { p_instance_id: v.string(), p_selected_user_id: nullableString, ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const operation = operationFrom(args);
    return await updateDailyAnswerPartnerChoice(
      ctx,
      userId,
      uuidArg(args.p_instance_id),
      optionalUuidArg(args.p_selected_user_id),
      operation,
    );
  },
});

// ---- answer reads ----

export const get_daily_answer_details = query({
  args: { p_couple_day_id: v.string() },
  handler: async (ctx, args) =>
    await getDailyAnswerDetails(ctx, await requireUserId(ctx), uuidArg(args.p_couple_day_id)),
});

export const get_daily_questions_history = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const rows = await getDailyQuestionsHistory(ctx, userId, coupleId);
    await addRoundInfo(ctx, userId, coupleId, rows);
    return rows;
  },
});

export const get_daily_answer_history_details = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await getDailyAnswerHistoryDetails(ctx, userId, await getCurrentEntitledCoupleId(ctx, userId));
  },
});

// ---- operator ----

/** Wipes today's answers, skips, and instances for a couple and seeds fresh slots. Run with `npx convex run`. */
export const reset_daily_challenge_for_testing = internalMutation({
  args: { p_couple_id: nullableString },
  handler: async (ctx, args) => {
    if (args.p_couple_id === null || args.p_couple_id === undefined) {
      return fail("22023", "p_couple_id is required");
    }
    return await resetDailyChallengeForCouple(ctx, uuidArg(args.p_couple_id));
  },
});
