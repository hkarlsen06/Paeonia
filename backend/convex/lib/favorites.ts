import { detailRow } from "./dailyAnswers";
import { loadQuestionRounds } from "./dailyQuestionRounds";
import { isLive, isVisibleAnswer, optionLabels, QuestionContentReader, visibleAnswersOf, instanceDay } from "./dailyQuestions";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import type { FAVORITE_KINDS } from "./validators";
import { payloadIsVisible } from "./widgetDrawings";

/**
 * Favorites: one private list per person for everything that can be saved. A favorite is a row in
 * `favorites` keyed by (user, kind, target). The partner is never told.
 *
 * Adding a kind takes a name in `FAVORITE_KINDS` (validators.ts) and one loader in `LOADERS`. A loader
 * answers "is this target alive in the couple, and what does the Saved list show for it?". The toggle
 * (`favorites:set_favorite`) and the Saved list (`favorites:get_favorite_summaries`) use no other
 * kind-specific code. The iOS side mirrors this with one `FavoriteKind` case.
 */

export type FavoriteKind = (typeof FAVORITE_KINDS)[number];

/**
 * What the Saved list shows for one favorite. One flat shape for every kind, with null for what a kind
 * does not have, so the app decodes one type.
 */
export type FavoriteSummary = {
  /** Daily question and answer: the question whose page opens. */
  question_id: string | null;
  prompt_en: string | null;
  prompt_nb: string | null;
  /** Daily answer and widget drawing: who made it. */
  author_user_id: string | null;
  /** Daily answer: the written text, when it has any. */
  answer_text: string | null;
  /** Daily answer: the label of the picked option, for a "pick one of two" question. */
  option_en: string | null;
  option_nb: string | null;
  /** Daily answer: `photo` or `voice` when the answer has media. */
  media_kind: string | null;
  /** The partner the answer picked, for a "who is more likely" question. */
  selected_user_id: string | null;
  /** Widget drawing: the stored drawing and its bounds, which give the canvas size. */
  media_asset_id: string | null;
  bounds: unknown;
  /** Game items: the round, creature or story number, and the word or title when there is one. */
  number: number | null;
  title: string | null;
  /** When the saved thing was made. */
  occurred_at: string;
};

type Loaded = {
  /** The item's number inside its kind, for games. 0 for the other kinds. */
  ordinal: number;
  summary: FavoriteSummary;
};

/** Null when the target is missing, not in this couple, not finished, hidden or deleted. */
type Loader = (ctx: ReaderCtx, userId: string, coupleId: string, targetId: string) => Promise<Loaded | null>;

function summary(occurredAt: string, fields: Partial<FavoriteSummary> = {}): FavoriteSummary {
  return {
    question_id: null,
    prompt_en: null,
    prompt_nb: null,
    author_user_id: null,
    answer_text: null,
    option_en: null,
    option_nb: null,
    media_kind: null,
    selected_user_id: null,
    media_asset_id: null,
    bounds: null,
    number: null,
    title: null,
    occurred_at: occurredAt,
    ...fields,
  };
}

const LOADERS: Record<FavoriteKind, Loader> = {
  // The target is the question, not one round of it. Its page spans every round it came back on.
  daily_question: async (ctx, _userId, coupleId, questionId) => {
    const rounds = await loadQuestionRounds(ctx, coupleId, questionId);
    const latest = rounds[rounds.length - 1];
    const content = latest ? await new QuestionContentReader(ctx).get(latest.instance.question_version_id) : null;
    if (!latest || !content) return null;
    return {
      ordinal: 0,
      summary: summary(latest.instance.created_at, {
        question_id: questionId,
        prompt_en: content.en.prompt,
        prompt_nb: content.nb.prompt,
      }),
    };
  },

  // The same rule as a reaction: the caller's own answer, or the partner's once the caller answered too.
  daily_answer: async (ctx, userId, coupleId, answerId) => {
    const answer = await getByUuid(ctx, "daily_question_answers", answerId);
    const instance = answer ? await getByUuid(ctx, "daily_question_instances", answer.instance_id) : null;
    if (!answer || !isVisibleAnswer(answer) || !instance || instance.couple_id !== coupleId || !isLive(instance)) {
      return null;
    }
    if (!(await visibleAnswersOf(ctx, instance.id)).some((own) => own.user_id === userId)) return null;
    const day = await instanceDay(ctx, instance);
    const content = await new QuestionContentReader(ctx).get(instance.question_version_id);
    if (!day || !content) return null;
    const detail = await detailRow(ctx, userId, day, instance, answer, true);
    const options = optionLabels(content);
    const picked = detail.selected_option;
    const mediaAsset = detail.media_asset_ids[0] ? await getByUuid(ctx, "media_assets", detail.media_asset_ids[0]) : null;
    return {
      ordinal: 0,
      summary: summary(answer.created_at, {
        question_id: instance.question_id,
        prompt_en: content.en.prompt,
        prompt_nb: content.nb.prompt,
        author_user_id: answer.user_id,
        answer_text: detail.text_body,
        option_en: picked === "a" ? options.option_a_en : picked === "b" ? options.option_b_en : null,
        option_nb: picked === "a" ? options.option_a_nb : picked === "b" ? options.option_b_nb : null,
        media_kind: mediaAsset?.media_type === "image" ? "photo" : mediaAsset?.media_type === "voice" ? "voice" : null,
        selected_user_id: detail.selected_user_id,
      }),
    };
  },

  widget_drawing: async (ctx, _userId, coupleId, revisionId) => {
    const revision = await getByUuid(ctx, "widget_drawing_revisions", revisionId);
    const canvas = revision ? await getByUuid(ctx, "widget_canvases", revision.canvas_id) : null;
    const asset = revision ? await getByUuid(ctx, "media_assets", revision.payload_media_asset_id) : null;
    if (!revision || !canvas || canvas.couple_id !== coupleId || canvas.deleted_at !== undefined) return null;
    if (!payloadIsVisible(revision, asset)) return null;
    return {
      ordinal: 0,
      summary: summary(revision.created_at, {
        author_user_id: revision.author_user_id,
        media_asset_id: revision.payload_media_asset_id,
        bounds: revision.bounds ?? null,
      }),
    };
  },

  game_round: async (ctx, _userId, coupleId, roundId) => {
    const move = await getByUuid(ctx, "game_moves", roundId);
    if (!move || move.couple_id !== coupleId) return null;
    if (move.state !== "solved" && move.state !== "missed") return null;
    return {
      ordinal: move.round_number,
      summary: summary(move.ended_at ?? move.started_at, { number: move.round_number, title: move.word }),
    };
  },

  corpse_figure: async (ctx, _userId, coupleId, figureId) => {
    const figure = await getByUuid(ctx, "exquisite_corpse_figures", figureId);
    if (!figure || figure.couple_id !== coupleId || figure.finished_at === undefined) return null;
    return { ordinal: figure.number, summary: summary(figure.finished_at, { number: figure.number }) };
  },

  story_chain_story: async (ctx, _userId, coupleId, storyId) => {
    const story = await getByUuid(ctx, "story_chain_stories", storyId);
    if (!story || story.couple_id !== coupleId || story.state !== "finished") return null;
    return {
      ordinal: story.story_number,
      summary: summary(story.finished_at ?? story.updated_at, { number: story.story_number, title: story.title ?? null }),
    };
  },
};

/** The target as the caller may favorite it, or null when it is gone or not favoritable. */
export async function loadFavoriteTarget(
  ctx: ReaderCtx,
  userId: string,
  coupleId: string,
  kind: FavoriteKind,
  targetId: string,
): Promise<Loaded | null> {
  return await LOADERS[kind](ctx, userId, coupleId, targetId);
}
