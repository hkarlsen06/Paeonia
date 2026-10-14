import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import { enqueueGamePush, getGameSettings, requireGameSettings, requirePartnerId } from "./lib/games";
import { newUuid, uuidArg } from "./lib/ids";
import {
  canEndAt,
  findOpening,
  findWord,
  getStoryChainGame,
  getStoryStar,
  lineUsesDare,
  markContentUsed,
  MAX_HISTORY_PAGE,
  mustEndAt,
  normalizeDareWord,
  openingChoices,
  patchStory,
  patchStoryChainGame,
  requireStoryLine,
  requireStoryTitle,
  storyJson,
  wordChoices,
  type Story,
  type StoryChainGame,
} from "./lib/storyChain";
import { applyCoupleActivity } from "./lib/streaks";
import { nowIso } from "./lib/time";

// Story Chain functions. The rules and decisions are in docs/games/story-chain.md. Rules and
// helpers are in lib/storyChain.ts. Settings, invites, presence, and the relay ticket are shared
// by all games and live in games.ts.

const nullableString = v.optional(v.union(v.null(), v.string()));

/** The story and its game, for a caller who may access the couple. Fails with 42501 otherwise. */
async function requireStory(ctx: ReaderCtx, userId: string, storyId: string): Promise<{ story: Story; game: StoryChainGame }> {
  const story = await getByUuid(ctx, "story_chain_stories", storyId);
  const game = story ? await getByUuid(ctx, "story_chain_games", story.game_id) : null;
  if (!story || !game || !(await canAccessCoupleContent(ctx, userId, story.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return { story, game };
}

async function requireGameById(ctx: ReaderCtx, userId: string, gameId: string): Promise<StoryChainGame> {
  const game = await getByUuid(ctx, "story_chain_games", gameId);
  if (!game || !(await canAccessCoupleContent(ctx, userId, game.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return game;
}

// --- The game and its screen -------------------------------------------------

/** Gets or creates the couple's Story Chain game. The caller starts the first story. Needs the game settings. */
export const ensure_story_chain_game = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await requireGameSettings(ctx, coupleId);
    await requirePartnerId(ctx, coupleId, userId);
    const existing = await getStoryChainGame(ctx, coupleId);
    if (existing) return { game_id: existing.id, created: false };

    const now = nowIso();
    const id = newUuid();
    await ctx.db.insert("story_chain_games", {
      id,
      couple_id: coupleId,
      state: "choosing_opening",
      turn_user_id: userId,
      turn_number: 1,
      story_count: 0,
      finished_count: 0,
      turn_started_at: now,
      version: 1,
      created_by_user_id: userId,
      created_at: now,
      updated_at: now,
    });
    return { game_id: id, created: true };
  },
});

/**
 * Everything the game screen shows: the game, the current story and the one before it, and the
 * choices of the partner whose turn it is. The choices are a seeded pick from the couple's game
 * language, so they stay the same until the turn changes and follow a language change at once.
 */
export const get_story_chain = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
    const game = await getStoryChainGame(ctx, coupleId);
    const base = { user_id: userId, partner_user_id: partnerId, couple_id: coupleId };
    if (!game) {
      return { ...base, game: null, current_story: null, previous_story: null, opening_choices: null, word_choices: null };
    }

    const [current, previous] = await ctx.db
      .query("story_chain_stories")
      .withIndex("by_game_id_story_number", (q) => q.eq("game_id", game.id))
      .order("desc")
      .take(2);
    const settings = await getGameSettings(ctx, coupleId);
    const isMyTurn = game.turn_user_id === userId;
    const nextLineNumber = current ? current.lines.length + 1 : 1;
    const offersOpenings = isMyTurn && settings !== null && game.state === "choosing_opening";
    const offersWords =
      isMyTurn && settings !== null && game.state === "writing" && current?.state === "writing" && !mustEndAt(nextLineNumber);

    return {
      ...base,
      game: {
        id: game.id,
        state: game.state,
        turn_user_id: game.turn_user_id,
        turn_number: game.turn_number,
        current_story_id: game.current_story_id ?? null,
        story_count: game.story_count,
        finished_count: game.finished_count,
        turn_started_at: game.turn_started_at,
        version: game.version,
      },
      current_story: current ? await storyJson(ctx, current, userId) : null,
      previous_story: previous ? await storyJson(ctx, previous, userId) : null,
      opening_choices: offersOpenings ? await openingChoices(ctx, game, settings.language) : null,
      word_choices: offersWords ? await wordChoices(ctx, game, settings.language) : null,
    };
  },
});

/** One story by id, for "Our stories". Null when it does not exist or the caller can't see it. */
export const get_story_chain_story = query({
  args: { p_story_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const story = await getByUuid(ctx, "story_chain_stories", uuidArg(args.p_story_id));
    if (!story || !(await canAccessCoupleContent(ctx, userId, story.couple_id))) return null;
    return await storyJson(ctx, story, userId);
  },
});

// --- Moves -------------------------------------------------------------------

/**
 * Starts the next story, with one of Paeonia's openings or without one. The starter keeps the
 * turn and writes line 1. The client names the story, so a line queued offline can point at it.
 */
export const start_story = mutation({
  args: { p_game_id: v.string(), p_story_id: v.string(), p_opening_id: nullableString, ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const gameId = uuidArg(args.p_game_id);
    const storyId = uuidArg(args.p_story_id);
    const openingId = args.p_opening_id ?? null;
    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, { kind: "start_story", scope: "story_chain", request: ["start_story", gameId, storyId, openingId] }),
      async () => {
        const game = await requireGameById(ctx, userId, gameId);
        if (game.turn_user_id !== userId) fail("42501", "not your turn");
        if (game.state !== "choosing_opening") fail("23514", "the story has already started");
        if (await getByUuid(ctx, "story_chain_stories", storyId)) uniqueViolation("story_chain_stories_pkey");
        // Any language's opening is taken, so a pick made offline before a language change still counts.
        const { language } = await requireGameSettings(ctx, game.couple_id);
        const opening = openingId === null ? null : findOpening(openingId, language);
        if (openingId !== null && !opening) fail("23514", "opening is not available");

        const now = nowIso();
        const storyNumber = game.story_count + 1;
        await ctx.db.insert("story_chain_stories", {
          id: storyId,
          game_id: game.id,
          couple_id: game.couple_id,
          story_number: storyNumber,
          starter_user_id: userId,
          ...(opening ? { opening_id: opening.id, opening_text: opening.text } : {}),
          state: "writing",
          lines: [],
          seen_by: [],
          created_at: now,
          updated_at: now,
        });
        if (opening) await markContentUsed(ctx, game, "opening", opening.language, opening.id);
        await patchStoryChainGame(ctx, game, { state: "writing", current_story_id: storyId, story_count: storyNumber });
        return { story_id: storyId, story_number: storyNumber };
      },
    );
  },
});

/**
 * Adds the caller's line to the current story and passes the turn. The server numbers the line.
 * A line must use the word the previous line gave it. From line 8 the writer may end the story,
 * and line 20 always ends it. A line that ends the story can't give a word.
 */
export const add_story_line = mutation({
  args: {
    p_story_id: v.string(),
    p_line_id: v.string(),
    p_text: v.string(),
    p_is_last: v.boolean(),
    p_dare_word: nullableString,
    p_dare_word_id: nullableString,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const storyId = uuidArg(args.p_story_id);
    const lineId = uuidArg(args.p_line_id);
    const text = requireStoryLine(args.p_text);
    const dareWordId = args.p_dare_word_id ?? null;
    const dareInput = args.p_dare_word ?? null;
    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "add_story_line",
        scope: "story_chain",
        request: ["add_story_line", storyId, lineId, text, args.p_is_last, dareInput, dareWordId],
      }),
      async () => {
        const { story, game } = await requireStory(ctx, userId, storyId);
        if (game.turn_user_id !== userId) fail("42501", "not your turn");
        if (game.state !== "writing" || story.state !== "writing" || game.current_story_id !== story.id) {
          fail("23514", "the story is not waiting for a line");
        }
        if (story.lines.some((line) => line.id === lineId)) uniqueViolation("story_chain_lines_pkey");

        const number = story.lines.length + 1;
        const dareToUse = story.lines.at(-1)?.dare_word;
        if (dareToUse && !lineUsesDare(text, dareToUse)) fail("23514", "the line must use the dare word");
        if (args.p_is_last && !canEndAt(number)) fail("23514", "a story can end from line 8");
        const isLast = args.p_is_last || mustEndAt(number);

        let dare: { word: string; wordId?: string; language?: "en" | "nb" } | null = null;
        if (dareWordId !== null || dareInput !== null) {
          if (isLast) fail("23514", "the last line can't give a word");
          if (dareWordId !== null) {
            const { language } = await requireGameSettings(ctx, game.couple_id);
            const entry = findWord(dareWordId, language);
            if (!entry) return fail("23514", "dare word is not available");
            dare = { word: entry.text, wordId: entry.id, language: entry.language };
          } else {
            dare = { word: normalizeDareWord(dareInput ?? "") };
          }
        }

        const partnerId = await requirePartnerId(ctx, game.couple_id, userId);
        const now = nowIso();
        await patchStory(ctx, story, {
          lines: [
            ...story.lines,
            {
              id: lineId,
              number,
              author_user_id: userId,
              text,
              ...(dare ? { dare_word: dare.word } : {}),
              ...(dare?.wordId ? { dare_word_id: dare.wordId } : {}),
              created_at: now,
            },
          ],
          ...(isLast ? { state: "titling" as const, last_line_user_id: userId } : {}),
        });
        if (dare?.wordId && dare.language) await markContentUsed(ctx, game, "word", dare.language, dare.wordId);
        await patchStoryChainGame(ctx, game, {
          state: isLast ? "titling" : "writing",
          turn_user_id: partnerId,
          turn_number: game.turn_number + 1,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
        });
        await enqueueGamePush(ctx, {
          kind: "game_turn_ready",
          game_kind: "story_chain",
          couple_id: game.couple_id,
          game_id: game.id,
          // The line, so a push that waited while the turn went around never counts for a later turn.
          round_id: lineId,
          actor_user_id: userId,
          recipient_user_id: partnerId,
          dedupe_key: `story_chain_turn:${lineId}`,
          skipIfPresent: true,
          ...(isLast ? { step: "last_line" } : {}),
        });
        await applyCoupleActivity(ctx, {
          couple_id: game.couple_id,
          user_id: userId,
          couple_day_id: await getOrCreateCoupleDayAt(ctx, game.couple_id, now),
          activity_kind: "game_turn_completed",
          occurred_at: now,
          dedupe_key: `game_turn_completed:${lineId}`,
          metadata: { game_id: game.id, story_id: story.id, line_id: lineId },
        });
        return { line_id: lineId, number, story_state: isLast ? "titling" : "writing" };
      },
    );
  },
});

/**
 * Names a story whose last line was written by the partner. The story is finished, the namer has
 * seen it, and the namer starts the next story.
 */
export const name_story = mutation({
  args: { p_story_id: v.string(), p_title: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const storyId = uuidArg(args.p_story_id);
    const title = requireStoryTitle(args.p_title);
    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, { kind: "name_story", scope: "story_chain", request: ["name_story", storyId, title] }),
      async () => {
        const { story, game } = await requireStory(ctx, userId, storyId);
        if (game.turn_user_id !== userId) fail("42501", "not your turn");
        if (game.state !== "titling" || story.state !== "titling" || game.current_story_id !== story.id) {
          fail("23514", "the story is not waiting for a title");
        }
        const partnerId = await requirePartnerId(ctx, game.couple_id, userId);
        const now = nowIso();
        await patchStory(ctx, story, {
          state: "finished",
          title,
          titled_by_user_id: userId,
          finished_at: now,
          seen_by: [userId],
        });
        await patchStoryChainGame(ctx, game, {
          state: "choosing_opening",
          turn_user_id: userId,
          turn_number: game.turn_number + 1,
          finished_count: game.finished_count + 1,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
        });
        await enqueueGamePush(ctx, {
          kind: "game_result",
          game_kind: "story_chain",
          couple_id: game.couple_id,
          game_id: game.id,
          round_id: story.id,
          actor_user_id: userId,
          recipient_user_id: partnerId,
          dedupe_key: `story_chain_named:${story.id}`,
          skipIfPresent: true,
        });
        return { story_id: story.id, title };
      },
    );
  },
});

/** Marks a finished story as seen by the caller, so no phone of theirs shows its reveal again. */
export const mark_story_seen = mutation({
  args: { p_story_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { story, game } = await requireStory(ctx, userId, uuidArg(args.p_story_id));
    if (story.state !== "finished") fail("23514", "the story is not finished");
    if (!story.seen_by.includes(userId)) {
      await patchStory(ctx, story, { seen_by: [...story.seen_by, userId] });
      // The version moves, so a phone never takes a read from before the mark over one after it.
      await patchStoryChainGame(ctx, game, {});
    }
    return { story_id: story.id };
  },
});

/** Sets the caller's private star on a finished story. The server sets the given value, so a retry changes nothing. */
export const set_story_star = mutation({
  args: { p_story_id: v.string(), p_starred: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { story, game } = await requireStory(ctx, userId, uuidArg(args.p_story_id));
    if (story.state !== "finished") fail("23514", "only a finished story can be starred");
    const existing = await getStoryStar(ctx, story.id, userId);
    // A change moves the version, so a phone never takes a read from before the star over one after it.
    if (args.p_starred !== (existing !== null)) await patchStoryChainGame(ctx, game, {});
    if (args.p_starred && !existing) {
      await ctx.db.insert("story_chain_stars", {
        couple_id: story.couple_id,
        story_id: story.id,
        user_id: userId,
        story_number: story.story_number,
        created_at: nowIso(),
      });
    } else if (!args.p_starred && existing) {
      await ctx.db.delete(existing._id);
    }
    return { story_id: story.id, starred: args.p_starred };
  },
});

// --- Our stories -------------------------------------------------------------

/**
 * The couple's finished stories, newest first, paged by story number. With `p_starred_only` only
 * the caller's starred stories. `next_before_story_number` is null on the last page.
 */
export const get_story_chain_history = query({
  args: {
    p_starred_only: v.boolean(),
    p_before_story_number: v.optional(v.union(v.null(), v.number())),
    p_limit: v.number(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    // NaN would pass the clamp below and turn the page into the whole history.
    if (!Number.isFinite(args.p_limit)) fail("23514", "limit must be a number");
    const limit = Math.max(1, Math.min(MAX_HISTORY_PAGE, Math.floor(args.p_limit)));
    const before = args.p_before_story_number ?? null;

    const stories: Story[] = [];
    let hasMore = false;
    if (args.p_starred_only) {
      const stars = ctx.db
        .query("story_chain_stars")
        .withIndex("by_couple_id_user_id_story_number", (q) => {
          const base = q.eq("couple_id", coupleId).eq("user_id", userId);
          return before === null ? base : base.lt("story_number", before);
        })
        .order("desc");
      for await (const star of stars) {
        const story = await getByUuid(ctx, "story_chain_stories", star.story_id);
        if (story?.state !== "finished") continue;
        if (stories.length === limit) {
          hasMore = true;
          break;
        }
        stories.push(story);
      }
    } else {
      const all = ctx.db
        .query("story_chain_stories")
        .withIndex("by_couple_id_story_number", (q) => {
          const base = q.eq("couple_id", coupleId);
          return before === null ? base : base.lt("story_number", before);
        })
        .order("desc");
      for await (const story of all) {
        if (story.state !== "finished") continue;
        if (stories.length === limit) {
          hasMore = true;
          break;
        }
        stories.push(story);
      }
    }

    const items = [];
    for (const story of stories) {
      items.push({
        id: story.id,
        story_number: story.story_number,
        title: story.title ?? "",
        first_line: story.opening_text ?? story.lines[0]?.text ?? "",
        line_count: story.lines.length,
        finished_at: story.finished_at ?? story.updated_at,
        starred_by_me: (await getStoryStar(ctx, story.id, userId)) !== null,
      });
    }
    return { stories: items, next_before_story_number: hasMore ? (stories.at(-1)?.story_number ?? null) : null };
  },
});
