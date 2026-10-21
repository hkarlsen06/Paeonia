import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { isLive, type QuestionRowContent, visibleAnswersOf } from "./dailyQuestions";
import { fail } from "./errors";
import { enqueueNotificationForUser } from "./notifications";
import { addMs, nowIso } from "./time";

/**
 * Question topics: extra questions grouped by theme, which a couple answers as many of as they like,
 * apart from the daily questions. Each topic is a `topic` question collection. A started question is a
 * `daily_question_instances` row with `topic_collection_id` and no `couple_day_id`, so the daily reads
 * never see it, while answers, the reveal rule, seen marks, reports and the question's chat work as for
 * daily questions. Whoever answers first starts it (`seeded_for_user_id`), and the partner answers the
 * same instance. A topic marked `private` (Flirt) is kept off the lock screen: its chat pushes name only
 * the sender. The topic reads take a topic's names and questions from its `topic_catalog` row
 * (`lib/topicCatalog.ts`), which the catalog sync rebuilds.
 */

/** At most one "new answers" topic push per person in this window. */
export const TOPIC_PUSH_INTERVAL_MS = 3 * 60 * 60 * 1000;

export type TopicSummary = {
  topic_key: string;
  collection_id: string;
  sort_order: number;
  private: boolean;
  title_en: string;
  subtitle_en: string;
  title_nb: string;
  subtitle_nb: string;
  total_count: number;
  together_count: number;
  for_you_count: number;
  waiting_for_partner_count: number;
};

/** An active topic's catalog row. `lib/topicCatalog.ts` builds it from the question catalog tables. */
export type Topic = Doc<"topic_catalog">;

export type TopicQuestion = Topic["questions"][number];

function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Active topics with both names, in shelf order. */
export async function activeTopics(ctx: ReaderCtx): Promise<Topic[]> {
  const topics = await ctx.db.query("topic_catalog").collect();
  return topics.sort((a, b) => a.sort_order - b.sort_order || compareStrings(a.key, b.key));
}

/** An active topic by key, or fails with 22023 like an unknown one. */
export async function requireActiveTopic(ctx: ReaderCtx, key: string): Promise<Topic> {
  const topic = await ctx.db
    .query("topic_catalog")
    .withIndex("by_key", (q) => q.eq("key", key))
    .first();
  return topic ?? fail("22023", "topic was not found");
}

/** A catalog question as the content `questionRow` shows. */
export function topicQuestionContent(question: TopicQuestion): QuestionRowContent {
  return {
    question: { id: question.question_id, key: question.question_key },
    version: { id: question.question_version_id },
    en: { prompt: question.prompt_en, short_prompt: question.short_prompt_en, option_a: question.option_a_en, option_b: question.option_b_en },
    nb: { prompt: question.prompt_nb, short_prompt: question.short_prompt_nb, option_a: question.option_a_nb, option_b: question.option_b_nb },
    answer_kinds: question.answer_kinds,
  };
}

/** The couple's live instances of one topic, by question id. */
export async function topicInstances(
  ctx: ReaderCtx,
  coupleId: string,
  collectionId: string,
): Promise<Map<string, Doc<"daily_question_instances">>> {
  const rows = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_id_topic_collection_id", (q) => q.eq("couple_id", coupleId).eq("topic_collection_id", collectionId))
    .collect();
  return new Map(rows.filter(isLive).map((row) => [row.question_id, row]));
}

/** The couple's live instance of a topic question, or null before anyone answered it. */
export async function topicInstanceFor(
  ctx: ReaderCtx,
  coupleId: string,
  questionId: string,
): Promise<Doc<"daily_question_instances"> | null> {
  const rows = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId).eq("question_id", questionId))
    .collect();
  return rows.find((row) => row.topic_collection_id !== undefined && isLive(row)) ?? null;
}

export async function skipRow(ctx: ReaderCtx, coupleId: string, questionId: string) {
  return await ctx.db
    .query("topic_question_skips")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId).eq("question_id", questionId))
    .first();
}

/** The questions the couple put aside. */
export async function skippedQuestionIds(ctx: ReaderCtx, coupleId: string): Promise<Set<string>> {
  const rows = await ctx.db
    .query("topic_question_skips")
    .withIndex("by_couple_id_question_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  return new Set(rows.map((row) => row.question_id));
}

/** Who has answered an instance, as seen by `viewerId`. */
export async function answerState(ctx: ReaderCtx, instance: Doc<"daily_question_instances">, viewerId: string) {
  const answers = await visibleAnswersOf(ctx, instance.id);
  const own = answers.find((answer) => answer.user_id === viewerId) ?? null;
  const partner = answers.find((answer) => answer.user_id !== viewerId) ?? null;
  return { answers, own, partner };
}

/**
 * The started questions of a topic that are in its catalog, by question id, with who answered.
 * `seen` is whether the viewer opened the partner's answer since both answered.
 */
export type TopicStates = Map<
  string,
  Awaited<ReturnType<typeof answerState>> & { instance: Doc<"daily_question_instances">; seen: boolean }
>;

/**
 * The couple's started questions of `topic`, read once for both the topic screen and its card.
 * Questions in `leaveOut` are not read, so the shelf does not load answers it never counts.
 */
export async function topicStates(
  ctx: ReaderCtx,
  topic: Topic,
  coupleId: string,
  viewerId: string,
  leaveOut: Set<string> = new Set(),
): Promise<TopicStates> {
  const inTopic = new Set(topic.questions.map((question) => question.question_id));
  const states: TopicStates = new Map();
  for (const [questionId, instance] of await topicInstances(ctx, coupleId, topic.collection_id)) {
    if (!inTopic.has(questionId) || leaveOut.has(questionId)) continue;
    const state = await answerState(ctx, instance, viewerId);
    const seen =
      state.own !== null &&
      state.partner !== null &&
      (await ctx.db
        .query("daily_answer_seen_states")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", viewerId))
        .unique()) !== null;
    states.set(questionId, { instance, ...state, seen });
  }
  return states;
}

/**
 * A topic's card: its names and the counts over questions the couple has not put aside. A question
 * is for the viewer while the partner answered and the viewer has not, and again once both answered
 * until the viewer opens the partner's answer. The app icon badge counts the same questions.
 */
export function topicSummary(topic: Topic, skipped: Set<string>, states: TopicStates): TopicSummary {
  let together = 0;
  let forYou = 0;
  let waitingForPartner = 0;
  for (const [questionId, { own, partner, seen }] of states) {
    if (skipped.has(questionId)) continue;
    if (own && partner) {
      together += 1;
      if (!seen) forYou += 1;
    } else if (partner) forYou += 1;
    else if (own) waitingForPartner += 1;
  }
  return {
    topic_key: topic.key,
    collection_id: topic.collection_id,
    sort_order: topic.sort_order,
    private: topic.private,
    title_en: topic.title_en,
    subtitle_en: topic.subtitle_en,
    title_nb: topic.title_nb,
    subtitle_nb: topic.subtitle_nb,
    total_count: topic.questions.filter((question) => !skipped.has(question.question_id)).length,
    together_count: together,
    for_you_count: forYou,
    waiting_for_partner_count: waitingForPartner,
  };
}

/** The topic of a question, or null for a daily question. */
export async function topicOfQuestion(ctx: ReaderCtx, questionId: string): Promise<Doc<"question_collections"> | null> {
  const question = await getByUuid(ctx, "questions", questionId);
  const collection = question ? await getByUuid(ctx, "question_collections", question.collection_id) : null;
  return collection?.kind === "topic" ? collection : null;
}

/** Whether a topic question waits for `userId`, by the rule of `topicSummary`. */
export async function hasTopicWaiting(ctx: ReaderCtx, coupleId: string, userId: string): Promise<boolean> {
  return (await topicsWaitingCount(ctx, coupleId, userId)) > 0;
}

/** How many topic questions wait for `userId`: the Topics cards' "for you" counts added up. */
export async function topicsWaitingCount(ctx: ReaderCtx, coupleId: string, userId: string): Promise<number> {
  const skipped = await skippedQuestionIds(ctx, coupleId);
  let count = 0;
  for (const topic of await activeTopics(ctx)) {
    count += topicSummary(topic, skipped, await topicStates(ctx, topic, coupleId, userId, skipped)).for_you_count;
  }
  return count;
}

/**
 * How far back the outbox can hold a topic push that still matters: one queued up to an interval before it
 * is due, plus an interval since it went out, plus room for send retries.
 */
const TOPIC_PUSH_LOOKBACK_MS = 2 * TOPIC_PUSH_INTERVAL_MS + 60 * 60 * 1000;

/** The recipient's recent `topics_waiting` rows, one per device and push. */
async function recentTopicPushes(ctx: ReaderCtx, recipientId: string, now: string) {
  const rows = await ctx.db
    .query("notification_outbox")
    .withIndex("by_recipient_user_id_created_at", (q) =>
      q.eq("recipient_user_id", recipientId).gte("created_at", addMs(now, -TOPIC_PUSH_LOOKBACK_MS)),
    )
    .collect();
  return rows.filter((row) => row.kind === "topics_waiting");
}

/**
 * Whether a topic push due now must wait: another topic push to the same person (not this push's
 * row for another device, which shares its `scheduled_for`) went out less than the interval ago.
 * The send-time check drops such a row, so the spacing holds between real sends.
 */
export async function topicPushTooSoon(
  ctx: ReaderCtx,
  recipientId: string,
  scheduledFor: string,
  now: string,
): Promise<boolean> {
  const since = addMs(now, -TOPIC_PUSH_INTERVAL_MS);
  return (await recentTopicPushes(ctx, recipientId, now)).some(
    (row) => row.scheduled_for !== scheduledFor && row.sent_at !== undefined && row.sent_at > since,
  );
}

/**
 * Queues the "new answers" push for `recipientId` when something now waits for them. At most one is
 * pending per person, and it covers every answer until it goes out. The next goes out no sooner than
 * `TOPIC_PUSH_INTERVAL_MS` after the last one was actually sent (its `sent_at`, so retries count).
 * The send checks again that something still waits (`pushQueue.rowStillWanted`). The push never
 * names a topic or a question.
 */
export async function queueTopicPush(
  ctx: WriterCtx,
  coupleId: string,
  actorId: string,
  recipientId: string,
): Promise<void> {
  if (!(await hasTopicWaiting(ctx, coupleId, recipientId))) return;
  const now = nowIso();
  const recent = await recentTopicPushes(ctx, recipientId, now);
  if (recent.some((row) => row.sent_at === undefined && row.failed_at === undefined)) return;
  const lastSent = recent.reduce<string | null>(
    (latest, row) => (row.sent_at !== undefined && (latest === null || row.sent_at > latest) ? row.sent_at : latest),
    null,
  );
  const nextAllowed = lastSent === null ? now : addMs(lastSent, TOPIC_PUSH_INTERVAL_MS);
  const scheduledFor = nextAllowed > now ? nextAllowed : now;
  await enqueueNotificationForUser(ctx, {
    recipient_user_id: recipientId,
    kind: "topics_waiting",
    payload: {
      type: "topics_waiting",
      couple_id: coupleId,
      actor_user_id: actorId,
      route: "topics",
      deeplink: "paeonia://topics",
    },
    dedupe_key: `topics_waiting:${recipientId}:${scheduledFor}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `topics:${coupleId}`,
    scheduled_for: scheduledFor,
  });
}
