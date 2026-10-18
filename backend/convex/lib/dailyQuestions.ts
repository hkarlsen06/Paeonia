import type { Doc } from "../_generated/dataModel";
import { isActiveCoupleMember, listActiveMembers } from "./access";
import { findCoupleDayAt, resolveCoupleDayAnchor } from "./coupleDays";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, requireByUuid } from "./db";
import { checkViolation, fail, uniqueViolation } from "./errors";
import { newUuid } from "./ids";
import { addDaysToInstant, localDateOf, nowIso } from "./time";

/**
 * Daily question selection and the question read models. Ports of
 * `ensure_daily_challenge_slots`, `pick_daily_question_version`,
 * `get_today_daily_questions_for_context`, and `get_daily_questions_history`.
 */

/** Carried-over exchanges older than this many days stay out of the today read model. */
// ponytail: SQL scanned every couple day. A bounded window keeps the mutation's reads flat. Raise it if a
// question left unanswered for longer than this must still show up.
export const CARRY_OVER_LOOKBACK_DAYS = 30;

/** Daily questions each partner gets and must answer per couple day. */
export const DAILY_QUESTION_SLOTS = 2;

export type DailyQuestionRow = {
  couple_day_id: string;
  couple_id: string;
  local_date: string;
  effective_local_date?: string;
  starts_at: string;
  ends_at: string;
  instance_id: string;
  seeded_for_user_id: string;
  slot_number: number;
  instance_status: string;
  question_id: string;
  question_version_id: string;
  question_key: string;
  prompt_en: string;
  short_prompt_en: string;
  prompt_nb: string;
  short_prompt_nb: string;
  answer_kinds: string[];
  own_answer_id: string | null;
  own_answered_at: string | null;
  partner_answer_id: string | null;
  partner_answered_at: string | null;
  can_view_partner_answer: boolean;
  /** False for exchanges carried over from earlier days, and for every history row. */
  is_current_day: boolean;
  /** When the viewer first saw the partner's answer. */
  partner_answer_seen_at?: string | null;
  /** When the partner first saw the viewer's answer. */
  own_answer_seen_by_partner_at?: string | null;
  /** Earlier days on which the viewer answered this question, in this couple. Set by `addRoundInfo`. */
  earlier_round_count?: number;
  /** The couple-local date of the viewer's latest earlier answer to this question. */
  latest_earlier_round_local_date?: string | null;
  /** Some day of this question has answers from both partners, so its chat can start. */
  chat_available?: boolean;
  /** The topic a topic question belongs to. Null for daily questions. */
  topic_key: string | null;
};

export function isVisibleAnswer(answer: Doc<"daily_question_answers"> | null | undefined): answer is Doc<"daily_question_answers"> {
  return answer !== null && answer !== undefined && answer.deleted_at === undefined && answer.moderation_status === "visible";
}

/** The visible answers on an instance. */
export async function visibleAnswersOf(ctx: ReaderCtx, instanceId: string): Promise<Doc<"daily_question_answers">[]> {
  const answers = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instanceId))
    .collect();
  return answers.filter(isVisibleAnswer);
}

export type QuestionContent = {
  question: Doc<"questions">;
  version: Doc<"question_versions">;
  en: Doc<"question_version_localizations">;
  nb: Doc<"question_version_localizations">;
  answer_kinds: string[];
};

/** Looks question versions up once per call. Returns null when a locale is missing, like the SQL inner joins. */
export class QuestionContentReader {
  private cache = new Map<string, QuestionContent | null>();

  constructor(private ctx: ReaderCtx) {}

  async get(versionId: string): Promise<QuestionContent | null> {
    const cached = this.cache.get(versionId);
    if (cached !== undefined) return cached;
    const content = await this.load(versionId);
    this.cache.set(versionId, content);
    return content;
  }

  private async load(versionId: string): Promise<QuestionContent | null> {
    const version = await getByUuid(this.ctx, "question_versions", versionId);
    const question = version ? await getByUuid(this.ctx, "questions", version.question_id) : null;
    if (!version || !question) return null;
    const localizations = await this.ctx.db
      .query("question_version_localizations")
      .withIndex("by_question_version_id_locale", (q) => q.eq("question_version_id", versionId))
      .collect();
    const en = localizations.find((row) => row.locale === "en");
    const nb = localizations.find((row) => row.locale === "nb");
    if (!en || !nb) return null;
    const kinds = await this.ctx.db
      .query("question_answer_kinds")
      .withIndex("by_question_version_id_answer_kind", (q) => q.eq("question_version_id", versionId))
      .collect();
    return { question, version, en, nb, answer_kinds: kinds.map((row) => row.answer_kind).sort() };
  }
}

export function questionRow(
  day: Doc<"couple_days">,
  instance: Doc<"daily_question_instances">,
  content: QuestionContent,
  ownAnswer: Doc<"daily_question_answers"> | null,
  partnerAnswer: Doc<"daily_question_answers"> | null,
  canViewPartnerAnswer: boolean,
  isCurrentDay: boolean,
): DailyQuestionRow {
  return {
    couple_day_id: day.id,
    couple_id: day.couple_id,
    local_date: day.local_date,
    starts_at: day.starts_at,
    ends_at: day.ends_at,
    instance_id: instance.id,
    seeded_for_user_id: instance.seeded_for_user_id,
    slot_number: instance.slot_number,
    instance_status: instance.status,
    question_id: content.question.id,
    question_version_id: content.version.id,
    question_key: content.question.key,
    prompt_en: content.en.prompt,
    short_prompt_en: content.en.short_prompt,
    prompt_nb: content.nb.prompt,
    short_prompt_nb: content.nb.short_prompt,
    answer_kinds: content.answer_kinds,
    own_answer_id: ownAnswer?.id ?? null,
    own_answered_at: ownAnswer?.created_at ?? null,
    partner_answer_id: partnerAnswer?.id ?? null,
    partner_answered_at: partnerAnswer?.created_at ?? null,
    can_view_partner_answer: canViewPartnerAnswer,
    is_current_day: isCurrentDay,
    topic_key: null,
  };
}

/** Fills in who has seen whose answer. Only an exchange both people answered can have been seen. */
export async function addSeenStates(ctx: ReaderCtx, currentUserId: string, rows: DailyQuestionRow[]): Promise<void> {
  for (const row of rows) {
    row.partner_answer_seen_at = null;
    row.own_answer_seen_by_partner_at = null;
    if (row.own_answer_id === null || row.partner_answer_id === null) continue;
    const states = await ctx.db
      .query("daily_answer_seen_states")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", row.instance_id))
      .collect();
    for (const state of states) {
      if (state.user_id === currentUserId) row.partner_answer_seen_at = state.seen_at;
      else row.own_answer_seen_by_partner_at = state.seen_at;
    }
  }
}

function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

export async function instancesOfDay(ctx: ReaderCtx, coupleDayId: string): Promise<Doc<"daily_question_instances">[]> {
  return await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) => q.eq("couple_day_id", coupleDayId))
    .collect();
}

export function isLive(instance: Doc<"daily_question_instances">): boolean {
  return instance.status === "active" || instance.status === "answered";
}

/** A topic question's instance. It has no couple day, so it never shows up in daily reads. */
export function isTopicInstance(instance: Doc<"daily_question_instances">): boolean {
  return instance.topic_collection_id !== undefined;
}

/** The day an instance is dated by: its daily couple day, or the day a topic question was started on. */
export async function instanceDay(
  ctx: ReaderCtx,
  instance: Doc<"daily_question_instances">,
): Promise<Doc<"couple_days"> | null> {
  return await getByUuid(ctx, "couple_days", instance.couple_day_id ?? instance.started_couple_day_id);
}

/** What "today" means for the today read model. */
type TodayFrame = {
  /** Instant the carry-over window counts back from. */
  now: string;
  anchorTimeZoneId: string;
  todayLocalDate: string;
  currentDay: Doc<"couple_days"> | null;
};

/** Port of `internal.get_today_daily_questions_for_context`. */
export async function getTodayDailyQuestionsForContext(
  ctx: ReaderCtx,
  currentUserId: string,
  coupleId: string,
): Promise<DailyQuestionRow[]> {
  const now = nowIso();
  const anchor = await resolveCoupleDayAnchor(ctx, coupleId);
  return await todayQuestionsForFrame(ctx, currentUserId, coupleId, {
    now,
    anchorTimeZoneId: anchor.anchor_time_zone_id,
    todayLocalDate: localDateOf(now, anchor.anchor_time_zone_id),
    currentDay: await findCoupleDayAt(ctx, coupleId, now),
  });
}

/**
 * The today read model for one specific couple day, taking "today" from the day's
 * own window and anchor zone instead of the clock. The result changes only when
 * the data it reads changes, so a subscribed query stays valid until then.
 */
export async function getDailyQuestionsForCoupleDay(
  ctx: ReaderCtx,
  currentUserId: string,
  day: Doc<"couple_days">,
): Promise<DailyQuestionRow[]> {
  return await todayQuestionsForFrame(ctx, currentUserId, day.couple_id, {
    now: day.starts_at,
    anchorTimeZoneId: day.anchor_time_zone_id,
    todayLocalDate: day.local_date,
    currentDay: day,
  });
}

async function todayQuestionsForFrame(
  ctx: ReaderCtx,
  currentUserId: string,
  coupleId: string,
  frame: TodayFrame,
): Promise<DailyQuestionRow[]> {
  const { now, currentDay, todayLocalDate } = frame;

  type Selected = {
    day: Doc<"couple_days">;
    instance: Doc<"daily_question_instances">;
    isCurrentDay: boolean;
    answers: Doc<"daily_question_answers">[];
  };
  const selected: Selected[] = [];

  if (currentDay) {
    for (const instance of await instancesOfDay(ctx, currentDay.id)) {
      if (isLive(instance)) {
        selected.push({ day: currentDay, instance, isCurrentDay: true, answers: await visibleAnswersOf(ctx, instance.id) });
      }
    }
  }

  const upperBound = currentDay?.starts_at ?? now;
  const earlierDays = await ctx.db
    .query("couple_days")
    .withIndex("by_couple_id_starts_at", (q) =>
      q
        .eq("couple_id", coupleId)
        .gte("starts_at", addDaysToInstant(now, -CARRY_OVER_LOOKBACK_DAYS))
        .lt("starts_at", upperBound),
    )
    .collect();
  for (const day of earlierDays) {
    if (day.id === currentDay?.id) continue;
    for (const instance of await instancesOfDay(ctx, day.id)) {
      if (!isLive(instance)) continue;
      const answers = await visibleAnswersOf(ctx, instance.id);
      const viewerAnswer = answers.find((answer) => answer.user_id === currentUserId);
      const seededAnswer = answers.find((answer) => answer.user_id === instance.seeded_for_user_id);
      const otherAnswer = answers.find((answer) => answer.user_id !== currentUserId);
      const latest = [viewerAnswer?.created_at, otherAnswer?.created_at]
        .filter((value): value is string => value !== undefined)
        .sort()
        .pop();
      const partnerAnsweredMine = instance.seeded_for_user_id !== currentUserId && seededAnswer && !viewerAnswer;
      const iAnsweredMine = instance.seeded_for_user_id === currentUserId && viewerAnswer && !otherAnswer;
      const finishedToday = latest !== undefined && localDateOf(latest, frame.anchorTimeZoneId) === todayLocalDate;
      if (partnerAnsweredMine || iAnsweredMine || finishedToday) {
        selected.push({ day, instance, isCurrentDay: false, answers });
      }
    }
  }

  const reader = new QuestionContentReader(ctx);
  const rows: { row: DailyQuestionRow; day: Doc<"couple_days">; instance: Doc<"daily_question_instances"> }[] = [];
  for (const item of selected) {
    const content = await reader.get(item.instance.question_version_id);
    if (!content) continue;
    const ownAnswer = item.answers.find((answer) => answer.user_id === currentUserId) ?? null;
    const partnerAnswer = item.answers.find((answer) => answer.user_id !== currentUserId) ?? null;
    if (item.isCurrentDay && item.instance.seeded_for_user_id !== currentUserId && !partnerAnswer) continue;
    const row = questionRow(
      item.day,
      item.instance,
      content,
      ownAnswer,
      partnerAnswer,
      partnerAnswer !== null && ownAnswer !== null,
      item.isCurrentDay,
    );
    rows.push({ row, day: item.day, instance: item.instance });
  }

  rows.sort((a, b) => {
    if (a.row.is_current_day !== b.row.is_current_day) return a.row.is_current_day ? -1 : 1;
    if (a.day.starts_at !== b.day.starts_at) return compareStrings(b.day.starts_at, a.day.starts_at);
    const aMine = a.instance.seeded_for_user_id === currentUserId;
    const bMine = b.instance.seeded_for_user_id === currentUserId;
    if (aMine !== bMine) return aMine ? -1 : 1;
    return (
      compareStrings(a.instance.seeded_for_user_id, b.instance.seeded_for_user_id) ||
      a.instance.slot_number - b.instance.slot_number ||
      compareStrings(a.instance.created_at, b.instance.created_at) ||
      a.instance._creationTime - b.instance._creationTime
    );
  });
  const result = rows.map((item) => item.row);
  await addSeenStates(ctx, currentUserId, result);
  return result;
}

/** Port of `internal.get_daily_questions_history`: every instance the viewer answered, newest local day first. */
export async function getDailyQuestionsHistory(
  ctx: ReaderCtx,
  currentUserId: string,
  coupleId: string,
): Promise<DailyQuestionRow[]> {
  // The caller passes the viewer's entitled couple, so can_access_couple_content holds for every row.
  const ownAnswers = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_user_id_created_at", (q) => q.eq("user_id", currentUserId))
    .collect();
  const reader = new QuestionContentReader(ctx);
  const rows: { row: DailyQuestionRow; instance: Doc<"daily_question_instances"> }[] = [];
  for (const ownAnswer of ownAnswers) {
    if (!isVisibleAnswer(ownAnswer)) continue;
    const instance = await getByUuid(ctx, "daily_question_instances", ownAnswer.instance_id);
    // Topic answers live only in their topic.
    if (!instance || !isLive(instance) || isTopicInstance(instance)) continue;
    const day = await getByUuid(ctx, "couple_days", instance.couple_day_id);
    if (!day || day.couple_id !== coupleId) continue;
    const content = await reader.get(instance.question_version_id);
    if (!content) continue;
    const partnerAnswer = (await visibleAnswersOf(ctx, instance.id)).find((answer) => answer.user_id !== currentUserId) ?? null;
    const latest = partnerAnswer && partnerAnswer.created_at > ownAnswer.created_at ? partnerAnswer.created_at : ownAnswer.created_at;
    const row = questionRow(day, instance, content, ownAnswer, partnerAnswer, partnerAnswer !== null, false);
    // Use the zone that anchored the question's day. The couple's current anchor moves when a
    // partner changes time zone, and would move old exchanges to another day in the history.
    row.effective_local_date = localDateOf(latest, day.anchor_time_zone_id);
    rows.push({ row, instance });
  }
  rows.sort(
    (a, b) =>
      compareStrings(b.row.effective_local_date!, a.row.effective_local_date!) ||
      a.row.slot_number - b.row.slot_number ||
      compareStrings(a.instance.created_at, b.instance.created_at),
  );
  const result = rows.map((item) => item.row);
  await addSeenStates(ctx, currentUserId, result);
  return result;
}

// ---- selection and seeding ----

/** `iso` minus whole calendar months. Clamps to the end of a shorter month, like Postgres. */
export function subtractMonths(iso: string, months: number): string {
  const date = new Date(iso);
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() - months);
  const lastDay = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  date.setUTCDate(Math.min(day, lastDay));
  return date.toISOString();
}

/** When the user last answered each question, by stable question id. Soft deleted answers do not count. */
export type AnsweredQuestions = Map<string, string>;

export async function loadAnsweredQuestions(ctx: ReaderCtx, userId: string): Promise<AnsweredQuestions> {
  const answers = await ctx.db
    .query("daily_question_answers")
    .withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId))
    .collect();
  const questionByVersion = new Map<string, string | null>();
  const latest: AnsweredQuestions = new Map();
  for (const answer of answers) {
    if (answer.deleted_at !== undefined) continue;
    const instance = await getByUuid(ctx, "daily_question_instances", answer.instance_id);
    if (!instance || isTopicInstance(instance)) continue;
    let questionId = questionByVersion.get(instance.question_version_id);
    if (questionId === undefined) {
      questionId = (await getByUuid(ctx, "question_versions", instance.question_version_id))?.question_id ?? null;
      questionByVersion.set(instance.question_version_id, questionId);
    }
    if (questionId === null) continue;
    const seen = latest.get(questionId);
    if (seen === undefined || answer.created_at > seen) latest.set(questionId, answer.created_at);
  }
  return latest;
}

function shuffled<T>(items: T[]): T[] {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const other = Math.floor(Math.random() * (index + 1));
    [copy[index], copy[other]] = [copy[other], copy[index]];
  }
  return copy;
}

/** Which answer kinds a picked version may have. Every version needs 1 to 2. */
export type AnswerKindFilter = (kinds: string[]) => boolean;

/** The active version of a question when it has both locales and 1 to 2 answer kinds that `acceptsKinds` allows. */
async function usableVersionId(ctx: ReaderCtx, questionId: string, acceptsKinds: AnswerKindFilter): Promise<string | null> {
  const version = await ctx.db
    .query("question_versions")
    .withIndex("by_question_id_status", (q) => q.eq("question_id", questionId).eq("status", "active"))
    .first();
  if (!version) return null;
  const localizations = await ctx.db
    .query("question_version_localizations")
    .withIndex("by_question_version_id_locale", (q) => q.eq("question_version_id", version.id))
    .collect();
  if (!localizations.some((row) => row.locale === "en") || !localizations.some((row) => row.locale === "nb")) return null;
  const kinds = await ctx.db
    .query("question_answer_kinds")
    .withIndex("by_question_version_id_answer_kind", (q) => q.eq("question_version_id", version.id))
    .collect();
  return kinds.length >= 1 && kinds.length <= 2 && acceptsKinds(kinds.map((row) => row.answer_kind)) ? version.id : null;
}

/**
 * Port of `internal.pick_daily_question_version`: a random active system question
 * that is ready, not already given to the user on this day, not recently skipped,
 * and not answered yet (or answered long enough ago when it can resurface).
 * A couple answers up to four questions per person per day (their own and the
 * partner's), so a small catalog runs dry. When no question passes those rules, the
 * picker falls back to the usable question the user answered longest ago, whether or
 * not it can resurface. It fails only when no usable question is left at all.
 * `answered` can be shared across picks that do not write answers.
 */
export async function pickDailyQuestionVersion(
  ctx: ReaderCtx,
  coupleDayId: string,
  userId: string,
  excludedQuestionId: string | null,
  answered?: AnsweredQuestions,
): Promise<string> {
  // Every instance the user got today, answered and shuffled ones too, so the fallback
  // can never hand out a question the user already has today.
  const todaysInstances = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) =>
      q.eq("couple_day_id", coupleDayId).eq("seeded_for_user_id", userId),
    )
    .collect();
  const excludedQuestionIds = new Set<string>();
  if (excludedQuestionId !== null) excludedQuestionIds.add(excludedQuestionId);
  for (const instance of todaysInstances) {
    const version = await getByUuid(ctx, "question_versions", instance.question_version_id);
    if (version) excludedQuestionIds.add(version.question_id);
  }
  return await pickQuestionVersion(ctx, userId, {
    excludedQuestionIds,
    answered: answered ?? (await loadAnsweredQuestions(ctx, userId)),
    acceptsKinds: () => true,
  });
}

/**
 * The selection rules of `pickDailyQuestionVersion` without a couple day: a random usable
 * version of an active system question outside `excludedQuestionIds`, preferring questions
 * the user has not answered or may see again, then the one answered longest ago.
 */
export async function pickQuestionVersion(
  ctx: ReaderCtx,
  userId: string,
  options: { excludedQuestionIds: Set<string>; answered: AnsweredQuestions; acceptsKinds: AnswerKindFilter },
): Promise<string> {
  const { excludedQuestionIds, answered: history, acceptsKinds } = options;
  const now = nowIso();
  const collection = await ctx.db
    .query("question_collections")
    .withIndex("by_kind_status", (q) => q.eq("kind", "system").eq("status", "active"))
    .first();
  const questions = collection
    ? await ctx.db
        .query("questions")
        .withIndex("by_collection_id_status", (q) => q.eq("collection_id", collection.id).eq("status", "active"))
        .collect()
    : [];

  const answeredBefore: { questionId: string; lastAnsweredAt: string }[] = [];
  for (const question of shuffled(questions)) {
    if (excludedQuestionIds.has(question.id)) continue;
    const skipped = await ctx.db
      .query("daily_question_shuffles")
      .withIndex("by_user_id_question_id_exclude_until", (q) =>
        q.eq("user_id", userId).eq("question_id", question.id).gt("exclude_until", now),
      )
      .first();
    if (skipped) continue;
    const lastAnsweredAt = history.get(question.id);
    if (
      lastAnsweredAt !== undefined &&
      !(question.resurfaceable && lastAnsweredAt <= subtractMonths(now, question.resurface_after_months ?? 6))
    ) {
      answeredBefore.push({ questionId: question.id, lastAnsweredAt });
      continue;
    }
    const versionId = await usableVersionId(ctx, question.id, acceptsKinds);
    if (versionId) return versionId;
  }
  // ponytail: oldest answer first, resurfaceable or not. Add a resurfaceable-first tier if repeats of questions
  // marked as one-time ever matter more than repeats of resurfaceable ones.
  answeredBefore.sort((a, b) => compareStrings(a.lastAnsweredAt, b.lastAnsweredAt));
  for (const { questionId } of answeredBefore) {
    const versionId = await usableVersionId(ctx, questionId, acceptsKinds);
    if (versionId) return versionId;
  }
  return fail("22023", "no eligible daily questions are available");
}

/**
 * Write helper for `daily_question_instances`. Runs the `assert_daily_question_instance_member`
 * trigger and the constraints on the table.
 */
export async function insertDailyQuestionInstance(
  ctx: WriterCtx,
  input: { couple_day_id: string; question_version_id: string; seeded_for_user_id: string; slot_number: number },
): Promise<string> {
  const day = await getByUuid(ctx, "couple_days", input.couple_day_id);
  if (!day || !(await isActiveCoupleMember(ctx, input.seeded_for_user_id, day.couple_id))) {
    fail("23514", "daily question instance user must be an active couple member");
  }
  if (!Number.isInteger(input.slot_number) || input.slot_number < 1 || input.slot_number > DAILY_QUESTION_SLOTS) {
    checkViolation("daily_question_instances", "daily_question_instances_slot_number_check");
  }
  const sameSlot = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) =>
      q
        .eq("couple_day_id", input.couple_day_id)
        .eq("seeded_for_user_id", input.seeded_for_user_id)
        .eq("status", "active")
        .eq("slot_number", input.slot_number),
    )
    .first();
  if (sameSlot) {
    uniqueViolation("daily_question_instances_active_slot_unique_idx");
  }
  const version = await requireByUuid(ctx, "question_versions", input.question_version_id);
  const id = newUuid();
  await ctx.db.insert("daily_question_instances", {
    id,
    couple_day_id: input.couple_day_id,
    couple_id: day.couple_id,
    question_id: version.question_id,
    question_version_id: input.question_version_id,
    seeded_for_user_id: input.seeded_for_user_id,
    slot_number: input.slot_number,
    status: "active",
    created_at: nowIso(),
  });
  return id;
}

/** Port of `internal.ensure_daily_challenge_slots`: a challenge row and the live slots per active member. */
export async function ensureDailyChallengeSlots(ctx: WriterCtx, coupleDayId: string): Promise<void> {
  const day = await getByUuid(ctx, "couple_days", coupleDayId);
  if (!day) {
    fail("22023", "couple day was not found");
  }
  const members = (await listActiveMembers(ctx, day.couple_id)).sort(
    (a, b) => compareStrings(a.joined_at, b.joined_at) || compareStrings(a.user_id, b.user_id),
  );
  for (const member of members) {
    const challenge = await ctx.db
      .query("daily_challenges")
      .withIndex("by_couple_day_id_user_id", (q) => q.eq("couple_day_id", coupleDayId).eq("user_id", member.user_id))
      .unique();
    if (!challenge) {
      // assert_daily_challenge_member holds here: the loop only visits active members of an active couple.
      await ctx.db.insert("daily_challenges", { couple_day_id: coupleDayId, user_id: member.user_id });
    }
    const existing = (
      await ctx.db
        .query("daily_question_instances")
        .withIndex("by_couple_day_id_seeded_for_user_id_status_slot_number", (q) =>
          q.eq("couple_day_id", coupleDayId).eq("seeded_for_user_id", member.user_id),
        )
        .collect()
    ).filter(isLive);
    let answered: AnsweredQuestions | undefined;
    for (let slot = 1; slot <= DAILY_QUESTION_SLOTS; slot += 1) {
      if (existing.some((instance) => instance.slot_number === slot)) continue;
      answered ??= await loadAnsweredQuestions(ctx, member.user_id);
      const versionId = await pickDailyQuestionVersion(ctx, coupleDayId, member.user_id, null, answered);
      await insertDailyQuestionInstance(ctx, {
        couple_day_id: coupleDayId,
        question_version_id: versionId,
        seeded_for_user_id: member.user_id,
        slot_number: slot,
      });
    }
  }
}
