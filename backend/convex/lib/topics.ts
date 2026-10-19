import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { isLive, QuestionContentReader, type QuestionContent, visibleAnswersOf } from "./dailyQuestions";
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
 * the sender.
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

export type Topic = {
  collection: Doc<"question_collections">;
  en: Doc<"question_collection_localizations">;
  nb: Doc<"question_collection_localizations">;
};

export type TopicQuestion = { question: Doc<"questions">; content: QuestionContent };

function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

async function topicFromCollection(ctx: ReaderCtx, collection: Doc<"question_collections">): Promise<Topic | null> {
  const rows = await ctx.db
    .query("question_collection_localizations")
    .withIndex("by_collection_id_locale", (q) => q.eq("collection_id", collection.id))
    .collect();
  const en = rows.find((row) => row.locale === "en");
  const nb = rows.find((row) => row.locale === "nb");
  return en && nb && collection.key ? { collection, en, nb } : null;
}

/** Active topics with both names, in shelf order. */
export async function activeTopics(ctx: ReaderCtx): Promise<Topic[]> {
  const collections = await ctx.db
    .query("question_collections")
    .withIndex("by_kind_status", (q) => q.eq("kind", "topic").eq("status", "active"))
    .collect();
  const topics: Topic[] = [];
  for (const collection of collections) {
    const topic = await topicFromCollection(ctx, collection);
    if (topic) topics.push(topic);
  }
  return topics.sort(
    (a, b) =>
      (a.collection.sort_order ?? 0) - (b.collection.sort_order ?? 0) ||
      compareStrings(a.collection.key!, b.collection.key!),
  );
}

/** An active topic by key, or fails with 22023 like an unknown one. */
export async function requireActiveTopic(ctx: ReaderCtx, key: string): Promise<Topic> {
  const collection = await ctx.db
    .query("question_collections")
    .withIndex("by_kind_key", (q) => q.eq("kind", "topic").eq("key", key))
    .unique();
  const topic = collection && collection.status === "active" ? await topicFromCollection(ctx, collection) : null;
  return topic ?? fail("22023", "topic was not found");
}

/** The topic's active questions that have a usable active version, in order. */
export async function topicQuestions(ctx: ReaderCtx, reader: QuestionContentReader, collectionId: string): Promise<TopicQuestion[]> {
  const questions = await ctx.db
    .query("questions")
    .withIndex("by_collection_id_status", (q) => q.eq("collection_id", collectionId).eq("status", "active"))
    .collect();
  const result: TopicQuestion[] = [];
  for (const question of questions) {
    const version = await ctx.db
      .query("question_versions")
      .withIndex("by_question_id_status", (q) => q.eq("question_id", question.id).eq("status", "active"))
      .first();
    const content = version ? await reader.get(version.id) : null;
    if (content && content.answer_kinds.length >= 1 && content.answer_kinds.length <= 2) {
      result.push({ question, content });
    }
  }
  return result.sort(
    (a, b) => (a.question.sort_order ?? 0) - (b.question.sort_order ?? 0) || compareStrings(a.question.key, b.question.key),
  );
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

/** A topic's card: its names and the counts over questions the couple has not put aside. */
export async function topicSummary(
  ctx: ReaderCtx,
  reader: QuestionContentReader,
  topic: Topic,
  coupleId: string,
  viewerId: string,
  skipped: Set<string>,
): Promise<TopicSummary> {
  const { collection } = topic;
  const questions = (await topicQuestions(ctx, reader, collection.id)).filter((item) => !skipped.has(item.question.id));
  const instances = await topicInstances(ctx, coupleId, collection.id);
  let together = 0;
  let forYou = 0;
  let waitingForPartner = 0;
  for (const { question } of questions) {
    const instance = instances.get(question.id);
    if (!instance) continue;
    const { own, partner } = await answerState(ctx, instance, viewerId);
    if (own && partner) together += 1;
    else if (partner) forYou += 1;
    else if (own) waitingForPartner += 1;
  }
  return {
    topic_key: collection.key!,
    collection_id: collection.id,
    sort_order: collection.sort_order ?? 0,
    private: collection.private ?? false,
    title_en: topic.en.title,
    subtitle_en: topic.en.subtitle,
    title_nb: topic.nb.title,
    subtitle_nb: topic.nb.subtitle,
    total_count: questions.length,
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

/**
 * Whether something in a topic waits for `userId`: a question the partner answered that the
 * user has not answered or put aside, or a question both answered whose partner answer the user has
 * not seen yet.
 */
export async function hasTopicWaiting(ctx: ReaderCtx, coupleId: string, userId: string): Promise<boolean> {
  const skipped = await skippedQuestionIds(ctx, coupleId);
  for (const { collection } of await activeTopics(ctx)) {
    for (const instance of (await topicInstances(ctx, coupleId, collection.id)).values()) {
      const { own, partner } = await answerState(ctx, instance, userId);
      if (!partner) continue;
      if (!own) {
        if (!skipped.has(instance.question_id)) return true;
        continue;
      }
      const seen = await ctx.db
        .query("daily_answer_seen_states")
        .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", userId))
        .unique();
      if (!seen) return true;
    }
  }
  return false;
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
