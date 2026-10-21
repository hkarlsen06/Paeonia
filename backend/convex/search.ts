import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { canViewDailyAnswer, CoupleAccessCache } from "./lib/dailyAnswers";
import { isSharedRound, loadQuestionRounds, type QuestionRound } from "./lib/dailyQuestionRounds";
import { instanceDay, isLive, isVisibleAnswer, QuestionContentReader } from "./lib/dailyQuestions";
import type { ReaderCtx } from "./lib/db";
import { getByUuid } from "./lib/db";
import {
  containsEveryToken,
  matchesWordPrefixes,
  searchQueryText,
  searchTokens,
  snippetOf,
} from "./lib/search";
import { topicOfQuestion } from "./lib/topics";
import { literals } from "./lib/validators";

/** The most results of one kind. The app shows the first few and offers the rest. */
const RESULTS_PER_KIND = 30;
/** How many hits a search index returns before the rules below drop some. */
const CANDIDATES = 90;
/** The newest Story Chain stories that are read for text. A couple writes a few of these a month. */
const STORY_SCAN = 200;

type QuestionInfo = {
  rounds: QuestionRound[];
  /** Both partners answered in some round, which is what opens the question's page. */
  shared: boolean;
  topic_key: string | null;
  topic_title: string | null;
};

/** One search over the signed-in couple's content. Every lookup is remembered for the call. */
class CoupleSearch {
  private readonly access: CoupleAccessCache;
  private readonly content: QuestionContentReader;
  private readonly questions = new Map<string, QuestionInfo>();
  private readonly text: string;

  constructor(
    private readonly ctx: ReaderCtx,
    userId: string,
    private readonly coupleId: string,
    private readonly locale: "en" | "nb",
    private readonly tokens: string[],
  ) {
    this.access = new CoupleAccessCache(ctx, userId);
    this.content = new QuestionContentReader(ctx);
    this.text = searchQueryText(tokens);
  }

  private async question(questionId: string): Promise<QuestionInfo> {
    const cached = this.questions.get(questionId);
    if (cached) return cached;
    const rounds = await loadQuestionRounds(this.ctx, this.coupleId, questionId);
    const topic = await topicOfQuestion(this.ctx, questionId);
    const catalog = topic
      ? await this.ctx.db
          .query("topic_catalog")
          .withIndex("by_collection_id", (q) => q.eq("collection_id", topic.id))
          .unique()
      : null;
    const info: QuestionInfo = {
      rounds,
      shared: rounds.some(isSharedRound),
      topic_key: topic?.key ?? null,
      topic_title: catalog ? (this.locale === "nb" ? catalog.title_nb : catalog.title_en) : null,
    };
    this.questions.set(questionId, info);
    return info;
  }

  /** The wording of the question's newest round, in the viewer's language. */
  private async prompt(info: QuestionInfo): Promise<string | null> {
    const newest = info.rounds.at(-1);
    const content = newest ? await this.content.get(newest.instance.question_version_id) : null;
    return content ? content[this.locale].prompt : null;
  }

  /** Questions the couple has talked about, found by their wording. */
  async findQuestions() {
    const hits = await this.ctx.db
      .query("question_version_localizations")
      .withSearchIndex("search_prompt", (q) => q.search("prompt", this.text).eq("locale", this.locale))
      .take(CANDIDATES);
    const found = new Set<string>();
    const rows = [];
    for (const hit of hits) {
      if (!matchesWordPrefixes(hit.prompt, this.tokens)) continue;
      const version = await getByUuid(this.ctx, "question_versions", hit.question_version_id);
      if (!version || found.has(version.question_id)) continue;
      const info = await this.question(version.question_id);
      // Only wording the couple saw, and only a question whose page opens.
      if (!info.shared || !info.rounds.some((round) => round.instance.question_version_id === hit.question_version_id)) {
        continue;
      }
      found.add(version.question_id);
      rows.push({
        question_id: version.question_id,
        prompt: hit.prompt,
        topic_key: info.topic_key,
        topic_title: info.topic_title,
        local_date: info.rounds.at(-1)!.day.local_date,
        round_count: info.rounds.length,
      });
    }
    return rows.sort((a, b) => (a.local_date < b.local_date ? 1 : a.local_date > b.local_date ? -1 : 0)).slice(0, RESULTS_PER_KIND);
  }

  /**
   * Text answers the viewer may read: their own, and the partner's in a round the viewer
   * answered too (the reveal rule of the question page).
   */
  async findAnswers() {
    const hits = await this.ctx.db
      .query("daily_answer_text")
      .withSearchIndex("search_body", (q) => q.search("body", this.text).eq("couple_id", this.coupleId))
      .take(CANDIDATES);
    const rows = [];
    for (const hit of hits) {
      if (!matchesWordPrefixes(hit.body, this.tokens)) continue;
      const answer = await getByUuid(this.ctx, "daily_question_answers", hit.answer_id);
      if (!isVisibleAnswer(answer)) continue;
      const instance = await getByUuid(this.ctx, "daily_question_instances", answer.instance_id);
      if (!instance || !isLive(instance) || instance.couple_id !== this.coupleId) continue;
      const day = await instanceDay(this.ctx, instance);
      if (!day || !(await canViewDailyAnswer(this.ctx, this.access, answer, day))) continue;
      const info = await this.question(instance.question_id);
      const prompt = await this.content.get(instance.question_version_id);
      if (!info.shared || !prompt) continue;
      rows.push({
        answer_id: answer.id,
        instance_id: instance.id,
        question_id: instance.question_id,
        author_user_id: answer.user_id,
        snippet: snippetOf(hit.body, this.tokens),
        prompt: prompt[this.locale].prompt,
        topic_key: info.topic_key,
        topic_title: info.topic_title,
        local_date: day.local_date,
        answered_at: answer.created_at,
      });
    }
    return newestFirst(rows, (row) => row.answered_at);
  }

  /** What a message belongs to, or null when the app has no screen for it or the viewer cannot open it. */
  private async messageTarget(thread: Doc<"conversation_threads">) {
    // A new thread kind adds a case here, and its messages join the results.
    switch (thread.kind) {
      case "daily_question": {
        const link = await this.ctx.db
          .query("daily_question_threads")
          .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
          .unique();
        const info = link ? await this.question(link.question_id) : null;
        if (!link || !info?.shared) return null;
        return {
          question_id: link.question_id,
          memory_id: null,
          context_title: await this.prompt(info),
          topic_title: info.topic_title,
        };
      }
      case "memory": {
        const link = await this.ctx.db
          .query("memory_threads")
          .withIndex("by_thread_id", (q) => q.eq("thread_id", thread.id))
          .unique();
        const memory = link ? await getByUuid(this.ctx, "memories", link.memory_id) : null;
        if (
          !memory ||
          memory.couple_id !== this.coupleId ||
          memory.deleted_at !== undefined ||
          memory.moderation_status !== "visible"
        ) {
          return null;
        }
        return { question_id: null, memory_id: memory.id, context_title: memory.title, topic_title: null };
      }
      default:
        return null;
    }
  }

  /** Chat messages in the couple's visible threads. */
  async findMessages() {
    const hits = await this.ctx.db
      .query("thread_messages")
      .withSearchIndex("search_body", (q) => q.search("body", this.text).eq("couple_id", this.coupleId))
      .take(CANDIDATES);
    const rows = [];
    for (const hit of hits) {
      if (hit.body === undefined || hit.deleted_at !== undefined || hit.moderation_status !== "visible") continue;
      if (!matchesWordPrefixes(hit.body, this.tokens)) continue;
      const thread = await getByUuid(this.ctx, "conversation_threads", hit.thread_id);
      if (
        !thread ||
        thread.couple_id !== this.coupleId ||
        thread.deleted_at !== undefined ||
        thread.moderation_status !== "visible"
      ) {
        continue;
      }
      const target = await this.messageTarget(thread);
      if (!target) continue;
      rows.push({
        message_id: hit.id,
        thread_id: thread.id,
        thread_kind: thread.kind,
        sender_user_id: hit.sender_user_id,
        snippet: snippetOf(hit.body, this.tokens),
        created_at: hit.created_at,
        ...target,
      });
    }
    return newestFirst(rows, (row) => row.created_at);
  }

  /** Finished Story Chain stories, by title, opening and lines. */
  async findStoryChain() {
    const stories = await this.ctx.db
      .query("story_chain_stories")
      .withIndex("by_couple_id_story_number", (q) => q.eq("couple_id", this.coupleId))
      .order("desc")
      .take(STORY_SCAN);
    const rows = [];
    for (const story of stories) {
      if (story.state !== "finished") continue;
      const parts = [story.title, story.opening_text, ...story.lines.map((line) => line.text)].filter(
        (part): part is string => part !== undefined && part !== "",
      );
      if (!containsEveryToken(parts.join("\n"), this.tokens)) continue;
      const shown = parts.find((part) => this.tokens.some((token) => part.toLowerCase().includes(token))) ?? parts[0];
      rows.push({
        story_id: story.id,
        story_number: story.story_number,
        title: story.title ?? null,
        snippet: snippetOf(shown, this.tokens),
        finished_at: story.finished_at ?? story.updated_at,
      });
      if (rows.length === RESULTS_PER_KIND) break;
    }
    return rows;
  }
}

function newestFirst<T>(rows: T[], timestamp: (row: T) => string): T[] {
  return rows
    .sort((a, b) => (timestamp(a) < timestamp(b) ? 1 : timestamp(a) > timestamp(b) ? -1 : 0))
    .slice(0, RESULTS_PER_KIND);
}

/**
 * Search over what the signed-in couple wrote and shared, for the Search screen. The caller
 * must be an active member of an entitled couple, and the couple comes from the session.
 *
 * Memories and stories are not here. The phone keeps them and searches them itself.
 * Everything here follows what the question page and the chats show:
 * - A partner's answer appears only in a round the caller answered too.
 * - A question, answer or message appears only when the question's page can open, which
 *   needs a round where both partners answered.
 * - Removed and hidden answers, messages, threads and memories never appear.
 *
 * The search indexes match the start of words, so "sun" finds "sunset" but "set" does not.
 * `p_locale` picks the wording of questions. A query shorter than two letters finds nothing.
 */
export const search_couple_content = query({
  args: { p_query: v.string(), p_locale: literals("en", "nb") },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const tokens = searchTokens(args.p_query);
    if (tokens.length === 0) return { questions: [], answers: [], messages: [], story_chain: [] };
    const search = new CoupleSearch(ctx, userId, coupleId, args.p_locale, tokens);
    return {
      questions: await search.findQuestions(),
      answers: await search.findAnswers(),
      messages: await search.findMessages(),
      story_chain: await search.findStoryChain(),
    };
  },
});
