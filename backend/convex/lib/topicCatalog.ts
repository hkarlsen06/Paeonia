import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid } from "./db";
import { QuestionContentReader, optionLabels } from "./dailyQuestions";
import { stableStringify } from "./json";

/**
 * The `topic_catalog` table: one row per active topic, holding its names and its ready questions
 * with their current wording. The topic reads (`topics:get_topics_overview` and `get_topic`) load
 * these rows instead of walking questions, versions, localizations and answer kinds, which cost
 * about eight documents per question and joined every one of them to the live query's read set.
 *
 * The catalog tables change only in `catalog:sync_catalog`, which calls `rebuildTopicCatalogs` after
 * its last write. Anything else that writes a topic's collection, names, questions, versions,
 * localizations or answer kinds must call it too.
 */

export type TopicCatalogRow = Omit<Doc<"topic_catalog">, "_id" | "_creationTime">;
export type TopicCatalogQuestion = TopicCatalogRow["questions"][number];

function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * What the topic reads show for a collection, or null when the topic is not shown: not an active
 * topic, no key, or a name missing in a language. A question is ready when it is active and its
 * active version has both languages and one or two answer kinds.
 */
async function buildTopicCatalogRow(ctx: ReaderCtx, collection: Doc<"question_collections">): Promise<TopicCatalogRow | null> {
  if (collection.kind !== "topic" || collection.status !== "active" || !collection.key) return null;
  const names = await ctx.db
    .query("question_collection_localizations")
    .withIndex("by_collection_id_locale", (q) => q.eq("collection_id", collection.id))
    .collect();
  const en = names.find((row) => row.locale === "en");
  const nb = names.find((row) => row.locale === "nb");
  if (!en || !nb) return null;

  const reader = new QuestionContentReader(ctx);
  const questions: TopicCatalogQuestion[] = [];
  const active = await ctx.db
    .query("questions")
    .withIndex("by_collection_id_status", (q) => q.eq("collection_id", collection.id).eq("status", "active"))
    .collect();
  for (const question of active) {
    const version = await ctx.db
      .query("question_versions")
      .withIndex("by_question_id_status", (q) => q.eq("question_id", question.id).eq("status", "active"))
      .first();
    const content = version ? await reader.get(version.id) : null;
    if (!content || content.answer_kinds.length < 1 || content.answer_kinds.length > 2) continue;
    const options = optionLabels(content);
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
      option_a_en: options.option_a_en ?? undefined,
      option_b_en: options.option_b_en ?? undefined,
      option_a_nb: options.option_a_nb ?? undefined,
      option_b_nb: options.option_b_nb ?? undefined,
    });
  }
  questions.sort((a, b) => a.sort_order - b.sort_order || compareStrings(a.question_key, b.question_key));
  return {
    collection_id: collection.id,
    key: collection.key,
    sort_order: collection.sort_order ?? 0,
    private: collection.private ?? false,
    title_en: en.title,
    subtitle_en: en.subtitle,
    title_nb: nb.title,
    subtitle_nb: nb.subtitle,
    questions,
  };
}

/** The stored row for a collection and the row the catalog tables now call for. */
async function storedAndWanted(ctx: ReaderCtx, collectionId: string) {
  const collection = await getByUuid(ctx, "question_collections", collectionId);
  const stored = await ctx.db
    .query("topic_catalog")
    .withIndex("by_collection_id", (q) => q.eq("collection_id", collectionId))
    .first();
  const wanted = collection ? await buildTopicCatalogRow(ctx, collection) : null;
  return { stored, wanted };
}

function sameRow(stored: Doc<"topic_catalog">, wanted: TopicCatalogRow): boolean {
  const { _id, _creationTime, ...current } = stored;
  return stableStringify(current) === stableStringify(wanted);
}

/** Whether the collection's `topic_catalog` row matches the catalog tables. The sync uses it to find topics that need a rebuild. */
export async function topicCatalogIsCurrent(ctx: ReaderCtx, collectionId: string): Promise<boolean> {
  const { stored, wanted } = await storedAndWanted(ctx, collectionId);
  return stored && wanted ? sameRow(stored, wanted) : stored === null && wanted === null;
}

/**
 * Brings the `topic_catalog` rows of the given collections in line with the catalog tables. A topic
 * that is no longer shown loses its row. A row that would not change is left alone, so a sync that
 * changes nothing does not re-run the topic queries every phone holds open.
 */
export async function rebuildTopicCatalogs(ctx: WriterCtx, collectionIds: Iterable<string>): Promise<void> {
  for (const collectionId of new Set(collectionIds)) {
    const { stored, wanted } = await storedAndWanted(ctx, collectionId);
    if (!wanted) {
      if (stored) await ctx.db.delete(stored._id);
    } else if (!stored) {
      await ctx.db.insert("topic_catalog", wanted);
    } else if (!sameRow(stored, wanted)) {
      await ctx.db.replace(stored._id, wanted);
    }
  }
}
