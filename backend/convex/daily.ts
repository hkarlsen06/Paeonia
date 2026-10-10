import { v } from "convex/values";
import { internalMutation, mutation, type MutationCtx } from "./_generated/server";
import { getCurrentEntitledCoupleId, getEntitledCoupleIdForUser } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { getByUuid } from "./lib/db";
import {
  getDailyAnswerDetails,
  getDailyAnswerDetailsForContext,
  getDailyAnswerHistoryDetails,
  getDailyAnswerRevealState,
  getQuestionAnswerHistory,
  resetDailyChallengeForCouple,
  submitDailyAnswer,
  updateDailyAnswerPartnerChoice,
  updateDailyAnswerText,
  type ClientOperationArgs,
} from "./lib/dailyAnswers";
import {
  ensureDailyChallengeSlots,
  getDailyQuestionsHistory,
  getTodayDailyQuestionsForContext,
  insertDailyQuestionInstance,
  pickDailyQuestionVersion,
  type DailyQuestionRow,
} from "./lib/dailyQuestions";
import { fail } from "./lib/errors";
import { newUuid, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import { getCoupleStreakForCouple, getCoupleStreakParticipationForUser } from "./lib/streaks";
import { addDaysToInstant, nowIso } from "./lib/time";

/**
 * Daily questions and answers. Every app-callable function is a mutation, including
 * reads, because the iOS client only calls /api/mutation. Return values keep the
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

// ---- catalog ----

export const get_active_question_catalog = mutation({
  args: { p_locale: nullableString },
  handler: async (ctx, args) => {
    await requireUserId(ctx);
    const collection = await ctx.db
      .query("question_collections")
      .withIndex("by_kind_status", (q) => q.eq("kind", "system").eq("status", "active"))
      .first();
    if (!collection) return [];
    const questions = await ctx.db
      .query("questions")
      .withIndex("by_collection_id_status", (q) => q.eq("collection_id", collection.id).eq("status", "active"))
      .collect();
    const rows: Record<string, unknown>[] = [];
    for (const question of questions) {
      const version = await ctx.db
        .query("question_versions")
        .withIndex("by_question_id_status", (q) => q.eq("question_id", question.id).eq("status", "active"))
        .first();
      if (!version) continue;
      const localizations = await ctx.db
        .query("question_version_localizations")
        .withIndex("by_question_version_id_locale", (q) => q.eq("question_version_id", version.id))
        .collect();
      if (!localizations.some((row) => row.locale === "en") || !localizations.some((row) => row.locale === "nb")) continue;
      const kinds = (
        await ctx.db
          .query("question_answer_kinds")
          .withIndex("by_question_version_id_answer_kind", (q) => q.eq("question_version_id", version.id))
          .collect()
      )
        .map((row) => row.answer_kind)
        .sort();
      if (kinds.length < 1 || kinds.length > 2) continue;
      for (const localization of localizations) {
        if (args.p_locale !== null && args.p_locale !== undefined && localization.locale !== args.p_locale) continue;
        rows.push({
          collection_id: collection.id,
          question_id: question.id,
          question_key: question.key,
          question_version_id: version.id,
          version_number: version.version_number,
          locale: localization.locale,
          prompt: localization.prompt,
          short_prompt: localization.short_prompt,
          answer_kinds: kinds,
          resurfaceable: question.resurfaceable,
          resurface_after_months: question.resurface_after_months ?? null,
        });
      }
    }
    return rows.sort(
      (a, b) => byString(a.question_key as string, b.question_key as string) || byString(a.locale as string, b.locale as string),
    );
  },
});

// ---- today's challenge ----

async function startChallenge(ctx: MutationCtx, userId: string, args: OperationArgs): Promise<void> {
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const operation = operationFrom(args);
  await runClientOperation(
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
}

async function shuffleQuestion(
  ctx: MutationCtx,
  userId: string,
  args: OperationArgs & { p_slot_number: number },
): Promise<void> {
  const slot = args.p_slot_number;
  if (!Number.isInteger(slot) || slot < 1 || slot > 3) {
    fail("23514", "slot number is out of range");
  }
  const operation = operationFrom(args);
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  await runClientOperation(
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
      return { replacement_instance_id: replacementId };
    },
  );
}

async function todayQuestions(ctx: MutationCtx, userId: string): Promise<DailyQuestionRow[]> {
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  return await getTodayDailyQuestionsForContext(ctx, userId, coupleId);
}

function byString(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Port of `internal.get_today_daily_challenge_snapshot`: one row with the questions, answer details, and streak. */
async function todaySnapshot(ctx: MutationCtx, userId: string) {
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const questions = await getTodayDailyQuestionsForContext(ctx, userId, coupleId);
  const answerDetails = await getDailyAnswerDetailsForContext(
    ctx,
    questions.map((row) => row.couple_day_id),
    userId,
    coupleId,
  );
  const streak = await getCoupleStreakForCouple(ctx, coupleId);
  const participation = await getCoupleStreakParticipationForUser(ctx, coupleId, userId, nowIso());
  return [
    {
      questions: questions.sort((a, b) => {
        if (a.is_current_day !== b.is_current_day) return a.is_current_day ? -1 : 1;
        return (
          byString(b.starts_at, a.starts_at) ||
          byString(a.seeded_for_user_id, b.seeded_for_user_id) ||
          a.slot_number - b.slot_number ||
          byString(a.instance_id, b.instance_id)
        );
      }),
      answer_details: answerDetails.sort(
        (a, b) =>
          byString(a.couple_day_id, b.couple_day_id) ||
          a.slot_number - b.slot_number ||
          byString(a.answered_at, b.answered_at) ||
          byString(a.answer_id, b.answer_id),
      ),
      streak: { ...streak, ...participation },
      generated_at: nowIso(),
    },
  ];
}

export const start_daily_challenge = mutation({
  args: clientOperationArgs,
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await startChallenge(ctx, userId, args);
    return await todayQuestions(ctx, userId);
  },
});

export const start_daily_challenge_snapshot = mutation({
  args: clientOperationArgs,
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await startChallenge(ctx, userId, args);
    return await todaySnapshot(ctx, userId);
  },
});

export const get_today_daily_challenge_snapshot = mutation({
  args: {},
  handler: async (ctx) => await todaySnapshot(ctx, await requireUserId(ctx)),
});

export const get_today_daily_questions = mutation({
  args: {},
  handler: async (ctx) => await todayQuestions(ctx, await requireUserId(ctx)),
});

export const shuffle_daily_question = mutation({
  args: { p_slot_number: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await shuffleQuestion(ctx, userId, args);
    return await todayQuestions(ctx, userId);
  },
});

export const shuffle_daily_question_snapshot = mutation({
  args: { p_slot_number: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await shuffleQuestion(ctx, userId, args);
    return await todaySnapshot(ctx, userId);
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

export const get_daily_answer_details = mutation({
  args: { p_couple_day_id: v.string() },
  handler: async (ctx, args) =>
    await getDailyAnswerDetails(ctx, await requireUserId(ctx), uuidArg(args.p_couple_day_id)),
});

export const get_daily_answer_details_for_couple_days = mutation({
  args: { p_couple_day_ids: v.optional(v.union(v.null(), v.array(v.string()))) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const dayIds = (args.p_couple_day_ids ?? []).map(uuidArg);
    return await getDailyAnswerDetailsForContext(ctx, dayIds, userId, coupleId);
  },
});

export const get_daily_answer_reveal_state = mutation({
  args: { p_couple_day_id: v.string() },
  handler: async (ctx, args) =>
    await getDailyAnswerRevealState(ctx, await requireUserId(ctx), uuidArg(args.p_couple_day_id)),
});

export const get_daily_questions_history = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await getDailyQuestionsHistory(ctx, userId, await getCurrentEntitledCoupleId(ctx, userId));
  },
});

export const get_daily_answer_history_details = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await getDailyAnswerHistoryDetails(ctx, userId, await getCurrentEntitledCoupleId(ctx, userId));
  },
});

export const get_question_answer_history = mutation({
  args: { p_question_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const questionId = uuidArg(args.p_question_id);
    // can_access_couple_content only passes for the viewer's active entitled couple, so only that couple's answers can show.
    const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
    return coupleId ? await getQuestionAnswerHistory(ctx, userId, coupleId, questionId) : [];
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
