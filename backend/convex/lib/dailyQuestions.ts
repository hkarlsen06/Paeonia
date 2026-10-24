import type { Doc } from "../_generated/dataModel";
import { findCoupleDayAt, resolveCoupleDayAnchor } from "./coupleDays";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, requireByUuid } from "./db";
import { fail, uniqueViolation } from "./errors";
import { newUuid } from "./ids";
import { addDaysToInstant, localDateOf, nowIso } from "./time";

/**
 * Daily question selection and the question read models. A couple day has one active
 * instance, the question both partners answer that day. Each partner answers it once, and
 * each sees the other's answer once both have answered.
 */

/** Carried-over exchanges older than this many days stay out of the today read model. */
// ponytail: SQL scanned every couple day. A bounded window keeps the mutation's reads flat. Raise it if a
// question left unanswered for longer than this must still show up.
export const CARRY_OVER_LOOKBACK_DAYS = 30;

export type DailyQuestionRow = {
  couple_day_id: string;
  couple_id: string;
  local_date: string;
  effective_local_date?: string;
  starts_at: string;
  ends_at: string;
  instance_id: string;
  instance_status: string;
  question_id: string;
  question_version_id: string;
  question_key: string;
  prompt_en: string;
  short_prompt_en: string;
  prompt_nb: string;
  short_prompt_nb: string;
  answer_kinds: string[];
  /** The two labels of a "pick one of two" (`either_or`) question. Null for every other question. */
  option_a_en: string | null;
  option_b_en: string | null;
  option_a_nb: string | null;
  option_b_nb: string | null;
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

/** The part of a question's content that `questionRow` shows. `QuestionContent` has all of it. */
export type QuestionRowContent = {
  question: Pick<Doc<"questions">, "id" | "key">;
  version: Pick<Doc<"question_versions">, "id">;
  en: Pick<Doc<"question_version_localizations">, "prompt" | "short_prompt" | "option_a" | "option_b">;
  nb: Pick<Doc<"question_version_localizations">, "prompt" | "short_prompt" | "option_a" | "option_b">;
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

/** A version's "pick one of two" labels, or nulls when its kinds don't include `either_or`. */
export function optionLabels(content: QuestionRowContent) {
  const either = content.answer_kinds.includes("either_or");
  return {
    option_a_en: either ? (content.en.option_a ?? null) : null,
    option_b_en: either ? (content.en.option_b ?? null) : null,
    option_a_nb: either ? (content.nb.option_a ?? null) : null,
    option_b_nb: either ? (content.nb.option_b ?? null) : null,
  };
}

export function questionRow(
  day: Doc<"couple_days">,
  instance: Doc<"daily_question_instances">,
  content: QuestionRowContent,
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
    instance_status: instance.status,
    question_id: content.question.id,
    question_version_id: content.version.id,
    question_key: content.question.key,
    prompt_en: content.en.prompt,
    short_prompt_en: content.en.short_prompt,
    prompt_nb: content.nb.prompt,
    short_prompt_nb: content.nb.short_prompt,
    answer_kinds: content.answer_kinds,
    ...optionLabels(content),
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
    .withIndex("by_couple_day_id_status", (q) => q.eq("couple_day_id", coupleDayId))
    .collect();
}

/** False for a question someone skipped. */
export function isLive(instance: Doc<"daily_question_instances">): boolean {
  return instance.status === "active";
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
      const otherAnswer = answers.find((answer) => answer.user_id !== currentUserId);
      const latest = [viewerAnswer?.created_at, otherAnswer?.created_at]
        .filter((value): value is string => value !== undefined)
        .sort()
        .pop();
      // One partner answered and the other has not yet, so the exchange is still open.
      const waiting = (viewerAnswer === undefined) !== (otherAnswer === undefined);
      const finishedToday = latest !== undefined && localDateOf(latest, frame.anchorTimeZoneId) === todayLocalDate;
      if (waiting || finishedToday) {
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
    return (
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

/** When the couple last got each question as a daily question, by stable question id. */
export type QuestionHistory = Map<string, string>;

/**
 * Reads the couple's daily instances, one per couple day plus skipped ones. Skipped questions
 * don't count, since a skip has its own exclusion window.
 */
export async function loadCoupleQuestionHistory(ctx: ReaderCtx, coupleId: string): Promise<QuestionHistory> {
  const instances = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  const latest: QuestionHistory = new Map();
  for (const instance of instances) {
    if (isTopicInstance(instance) || !isLive(instance)) continue;
    const seen = latest.get(instance.question_id);
    if (seen === undefined || instance.created_at > seen) latest.set(instance.question_id, instance.created_at);
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
 * A random active system question for the couple's day: ready, not already used on this day,
 * not recently skipped by the couple, and not given to the couple before (or long enough ago
 * when it can resurface). When no question passes those rules, the picker falls back to the
 * usable question the couple got longest ago, whether or not it can resurface. It fails only
 * when no usable question is left at all.
 */
export async function pickDailyQuestionVersion(
  ctx: ReaderCtx,
  coupleId: string,
  coupleDayId: string,
  excludedQuestionId: string | null,
): Promise<string> {
  // Skipped instances of the day too, so a skip never brings back a question the couple had today.
  const excludedQuestionIds = new Set((await instancesOfDay(ctx, coupleDayId)).map((instance) => instance.question_id));
  if (excludedQuestionId !== null) excludedQuestionIds.add(excludedQuestionId);
  return await pickQuestionVersion(ctx, {
    coupleId,
    excludedQuestionIds,
    history: await loadCoupleQuestionHistory(ctx, coupleId),
    acceptsKinds: () => true,
  });
}

/**
 * The selection rules of `pickDailyQuestionVersion` without a couple day: a random usable
 * version of an active system question outside `excludedQuestionIds`, preferring questions
 * not in `history` or that may come back, then the one in `history` longest ago. Without a
 * couple (a first day draft) no skips apply.
 */
export async function pickQuestionVersion(
  ctx: ReaderCtx,
  options: {
    coupleId: string | null;
    excludedQuestionIds: Set<string>;
    history: QuestionHistory;
    acceptsKinds: AnswerKindFilter;
  },
): Promise<string> {
  const { coupleId, excludedQuestionIds, history, acceptsKinds } = options;
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

  const usedBefore: { questionId: string; lastUsedAt: string }[] = [];
  for (const question of shuffled(questions)) {
    if (excludedQuestionIds.has(question.id)) continue;
    const skipped =
      coupleId !== null &&
      (await ctx.db
        .query("daily_question_shuffles")
        .withIndex("by_couple_id_question_id_exclude_until", (q) =>
          q.eq("couple_id", coupleId).eq("question_id", question.id).gt("exclude_until", now),
        )
        .first());
    if (skipped) continue;
    const lastUsedAt = history.get(question.id);
    if (
      lastUsedAt !== undefined &&
      !(question.resurfaceable && lastUsedAt <= subtractMonths(now, question.resurface_after_months ?? 6))
    ) {
      usedBefore.push({ questionId: question.id, lastUsedAt });
      continue;
    }
    const versionId = await usableVersionId(ctx, question.id, acceptsKinds);
    if (versionId) return versionId;
  }
  // ponytail: oldest first, resurfaceable or not. Add a resurfaceable-first tier if repeats of questions
  // marked as one-time ever matter more than repeats of resurfaceable ones.
  usedBefore.sort((a, b) => compareStrings(a.lastUsedAt, b.lastUsedAt));
  for (const { questionId } of usedBefore) {
    const versionId = await usableVersionId(ctx, questionId, acceptsKinds);
    if (versionId) return versionId;
  }
  return fail("22023", "no eligible daily questions are available");
}

/** The day's question, or null before it is seeded. */
export async function activeInstanceOfDay(
  ctx: ReaderCtx,
  coupleDayId: string,
): Promise<Doc<"daily_question_instances"> | null> {
  return await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_status", (q) => q.eq("couple_day_id", coupleDayId).eq("status", "active"))
    .first();
}

/** Write helper for daily `daily_question_instances`. A couple day has at most one active instance. */
export async function insertDailyQuestionInstance(
  ctx: WriterCtx,
  input: { couple_day_id: string; question_version_id: string },
): Promise<string> {
  const day = await requireByUuid(ctx, "couple_days", input.couple_day_id);
  if (await activeInstanceOfDay(ctx, input.couple_day_id)) {
    uniqueViolation("daily_question_instances_active_day_unique_idx");
  }
  const version = await requireByUuid(ctx, "question_versions", input.question_version_id);
  const id = newUuid();
  await ctx.db.insert("daily_question_instances", {
    id,
    couple_day_id: input.couple_day_id,
    couple_id: day.couple_id,
    question_id: version.question_id,
    question_version_id: input.question_version_id,
    status: "active",
    created_at: nowIso(),
  });
  return id;
}

/** Seeds the couple day's question when it has none yet. */
export async function ensureDailyQuestion(ctx: WriterCtx, coupleDayId: string): Promise<void> {
  if (await activeInstanceOfDay(ctx, coupleDayId)) return;
  const day = await getByUuid(ctx, "couple_days", coupleDayId);
  if (!day) {
    fail("22023", "couple day was not found");
  }
  const versionId = await pickDailyQuestionVersion(ctx, day.couple_id, coupleDayId, null);
  await insertDailyQuestionInstance(ctx, { couple_day_id: coupleDayId, question_version_id: versionId });
}
