import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, requireByUuid } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import {
  assertCorpseAssetUsable,
  corpseGameJson,
  dealIdeas,
  deckSeed,
  figureJson,
  findIdea,
  getCorpseGame,
  getFigureStar,
  hasStrip,
  isPartIndex,
  MAX_HISTORY_PAGE,
  patchCorpseGame,
  progressAfter,
  RECENT_FIGURES,
  revealSeenAt,
  turnPushPart,
  type CorpseFigure,
  type CorpseGame,
} from "./lib/exquisiteCorpse";
import { enqueueGamePush, getGameSettings, requireCoupleAccess, requireGameSettings, requirePartnerId } from "./lib/games";
import { newUuid, optionalUuidArg, uuidArg } from "./lib/ids";
import { applyCoupleActivity } from "./lib/streaks";
import { nowIso } from "./lib/time";

// Exquisite corpse functions. The rules and decisions are in docs/games/exquisite-corpse.md.
// Helpers and json shapes are in lib/exquisiteCorpse.ts. Settings, invites, presence, and the relay
// ticket are shared by all games and live in games.ts.

const nullableString = v.optional(v.union(v.null(), v.string()));

// --- Shared lookups ---------------------------------------------------------

/** The game by id, for a caller who may access its couple. Fails with 42501 otherwise. */
async function requireGame(ctx: ReaderCtx, userId: string, gameId: string): Promise<CorpseGame> {
  const game = await getByUuid(ctx, "exquisite_corpse_games", gameId);
  if (!game) return fail("42501", "active entitled game access is required");
  await requireCoupleAccess(ctx, userId, game.couple_id);
  return game;
}

/** The finished figure by id, for a caller who may access its couple. 42501 when missing, 23514 while it is still in progress. */
async function requireFinishedFigure(ctx: ReaderCtx, userId: string, figureId: string): Promise<CorpseFigure> {
  const figure = await getByUuid(ctx, "exquisite_corpse_figures", figureId);
  if (!figure) return fail("42501", "active entitled game access is required");
  await requireCoupleAccess(ctx, userId, figure.couple_id);
  if (figure.finished_at === undefined) return fail("23514", "the creature is not finished yet");
  return figure;
}

// --- The game and its screen -------------------------------------------------

/**
 * Gets or creates the couple's Exquisite corpse game. The caller starts: figure 1, the head, their
 * turn. Needs a partner and the game settings, so the app runs setup before this.
 * Result: `{ game_id, created }`.
 */
export const ensure_exquisite_corpse_game = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getCorpseGame(ctx, coupleId);
    if (existing) return { game_id: existing.id, created: false };

    await requirePartnerId(ctx, coupleId, userId);
    await requireGameSettings(ctx, coupleId);
    const id = newUuid();
    const now = nowIso();
    await ctx.db.insert("exquisite_corpse_games", {
      id,
      couple_id: coupleId,
      created_by_user_id: userId,
      turn_user_id: userId,
      turn_started_at: now,
      figure_number: 1,
      part_index: 0,
      figures_finished: 0,
      version: 1,
      created_at: now,
      updated_at: now,
    });
    return { game_id: id, created: true };
  },
});

/**
 * Everything the Exquisite corpse screen shows, for the caller. Subscribe to it after
 * `ensure_exquisite_corpse_game`. It does not read the clock.
 *
 * Result: `{ user_id, partner_user_id, couple_id, game, current_figure, recent_figures, ideas }`.
 * `game` is null before the game exists. `current_figure` is the figure in progress, or null between
 * figures. `recent_figures` are the latest 10 finished figures, newest first. A figure has `id`,
 * `number`, `starter_user_id`, `created_at`, `finished_at`, `my_reveal_seen_at`, `starred_by_me`, and
 * `parts` in drawing order. A part has `id`, `part_index`, `drawer_user_id`, `created_at`,
 * `strip_media_asset_id`, `drawing_media_asset_id`, and `idea`. The drawing id and the idea are null
 * unless the caller drew the part or the figure is finished. The strip id is there for the head and body.
 *
 * `ideas` is a deck of 12 `{ id, text }` for the next part in the game language while it is the
 * caller's turn, and empty otherwise. The shuffle is seeded with the game, the figure number, and the
 * part, so reopening the game deals the same deck.
 */
export const get_exquisite_corpse = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const game = await getCorpseGame(ctx, coupleId);
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;

    const current = game?.figure_id ? await getByUuid(ctx, "exquisite_corpse_figures", game.figure_id) : null;
    const recent = [];
    if (game) {
      const figures = ctx.db
        .query("exquisite_corpse_figures")
        .withIndex("by_game_id_number", (q) => q.eq("game_id", game.id))
        .order("desc");
      for await (const figure of figures) {
        if (figure.finished_at === undefined) continue;
        recent.push(await figureJson(ctx, figure, userId));
        if (recent.length === RECENT_FIGURES) break;
      }
    }

    const settings = await getGameSettings(ctx, coupleId);
    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      game: game ? corpseGameJson(game) : null,
      current_figure: current ? await figureJson(ctx, current, userId) : null,
      recent_figures: recent,
      ideas:
        game && partnerId && settings && game.turn_user_id === userId
          ? dealIdeas(settings.language, game.part_index, deckSeed(game))
          : [],
    };
  },
});

// --- The turn ---------------------------------------------------------------

/**
 * Sends the caller's part. The head (index 0) starts the figure `p_figure_id`, which the phone made up,
 * and the body and legs join it. The turn passes to the partner after every part, and the legs finish
 * the figure. The partner gets a push unless the game is open on their phone. Every part counts as the
 * streak activity.
 *
 * `p_drawing_media_asset_id` is the full part. `p_strip_media_asset_id` is its bottom, clipped on the
 * phone: required for the head and body, refused for the legs. `p_idea_id` is the idea on the chip, if
 * any. Its text is stored with the part. The request hash covers every argument.
 *
 * Result: `{ figure_id, part_id, part_index, figure_finished, created_at }`.
 */
export const submit_exquisite_corpse_part = mutation({
  args: {
    p_game_id: v.string(),
    p_figure_id: v.string(),
    p_part_id: v.string(),
    p_part_index: v.number(),
    p_drawing_media_asset_id: v.string(),
    p_strip_media_asset_id: nullableString,
    p_idea_id: nullableString,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const gameId = uuidArg(args.p_game_id);
    const figureId = uuidArg(args.p_figure_id);
    const partId = uuidArg(args.p_part_id);
    const partIndex = args.p_part_index;
    const drawingId = uuidArg(args.p_drawing_media_asset_id);
    const stripId = optionalUuidArg(args.p_strip_media_asset_id);
    const ideaId = args.p_idea_id ?? undefined;
    if (!isPartIndex(partIndex)) fail("22023", "part index must be 0, 1, or 2");
    if (hasStrip(partIndex) && stripId === undefined) fail("22023", "the head and the body need a strip");
    if (!hasStrip(partIndex) && stripId !== undefined) fail("22023", "the legs take no strip");
    if (ideaId !== undefined && findIdea(partIndex, ideaId, "en") === null) fail("22023", "the idea is not on the list for this part");

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "submit_exquisite_corpse_part",
        scope: "games",
        request: ["submit_exquisite_corpse_part", gameId, figureId, partId, partIndex, drawingId, stripId ?? "", ideaId ?? ""],
      }),
      async () => {
        const game = await requireGame(ctx, userId, gameId);
        if (game.turn_user_id !== userId) fail("42501", "it is not your turn");
        if (partIndex !== game.part_index) fail("23514", "this part is out of date");
        if (partIndex === 0) {
          if (game.figure_id !== undefined) fail("23514", "this figure is out of date");
          if (await getByUuid(ctx, "exquisite_corpse_figures", figureId)) uniqueViolation("exquisite_corpse_figures_pkey");
        } else if (figureId !== game.figure_id) {
          fail("23514", "this figure is out of date");
        }
        if (await getByUuid(ctx, "exquisite_corpse_parts", partId)) uniqueViolation("exquisite_corpse_parts_pkey");

        const part = { id: partId, couple_id: game.couple_id, game_id: game.id };
        await assertCorpseAssetUsable(ctx, userId, part, drawingId, "exquisite_corpse_drawing");
        if (stripId !== undefined) await assertCorpseAssetUsable(ctx, userId, part, stripId, "exquisite_corpse_strip");
        const partnerId = await requirePartnerId(ctx, game.couple_id, userId);
        // The idea's text comes from the couple's language when the id is in that list, else from the other one.
        const idea =
          ideaId === undefined ? null : findIdea(partIndex, ideaId, (await requireGameSettings(ctx, game.couple_id)).language);

        const now = nowIso();
        if (partIndex === 0) {
          await ctx.db.insert("exquisite_corpse_figures", {
            id: figureId,
            couple_id: game.couple_id,
            game_id: game.id,
            number: game.figure_number,
            starter_user_id: userId,
            created_at: now,
            updated_at: now,
          });
        }
        await ctx.db.insert("exquisite_corpse_parts", {
          id: partId,
          couple_id: game.couple_id,
          game_id: game.id,
          figure_id: figureId,
          figure_number: game.figure_number,
          part_index: partIndex,
          drawer_user_id: userId,
          drawing_media_asset_id: drawingId,
          strip_media_asset_id: stripId,
          idea_id: idea?.id,
          idea_text: idea?.text,
          created_at: now,
        });
        const next = progressAfter(game, partIndex, figureId);
        if (next.figureFinished) {
          const figure = await requireByUuid(ctx, "exquisite_corpse_figures", figureId);
          await ctx.db.patch(figure._id, { finished_at: now, updated_at: now });
        }
        await patchCorpseGame(ctx, game, {
          figure_id: next.figure_id,
          figure_number: next.figure_number,
          part_index: next.part_index,
          figures_finished: next.figures_finished,
          turn_user_id: partnerId,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
        });

        await enqueueGamePush(ctx, {
          kind: next.figureFinished ? "game_result" : "game_turn_ready",
          game_kind: "exquisite_corpse",
          couple_id: game.couple_id,
          game_id: game.id,
          round_id: figureId,
          actor_user_id: userId,
          recipient_user_id: partnerId,
          dedupe_key: next.figureFinished ? `exquisite_corpse:finished:${figureId}` : `exquisite_corpse:turn:${partId}`,
          skipIfPresent: true,
          ...(next.figureFinished ? {} : { step: turnPushPart(partIndex) }),
        });
        await applyCoupleActivity(ctx, {
          couple_id: game.couple_id,
          user_id: userId,
          couple_day_id: await getOrCreateCoupleDayAt(ctx, game.couple_id, now),
          activity_kind: "game_turn_completed",
          occurred_at: now,
          dedupe_key: `game_turn_completed:${partId}`,
          metadata: { game_id: game.id, figure_id: figureId, part_id: partId },
        });
        return { figure_id: figureId, part_id: partId, part_index: partIndex, figure_finished: next.figureFinished, created_at: now };
      },
    );
  },
});

// --- After the figure: reveal, stars ----------------------------------------

/**
 * Records that the caller dismissed the finished figure's reveal. It sets the caller's own field once
 * and keeps the first time, so a second device or a retry changes nothing. The figure must be finished.
 * Result: `{ figure_id, reveal_seen_at }`.
 */
export const mark_exquisite_corpse_reveal_seen = mutation({
  args: { p_figure_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const figure = await requireFinishedFigure(ctx, userId, uuidArg(args.p_figure_id));
    const earlier = revealSeenAt(figure, userId);
    const seenAt = earlier ?? nowIso();
    if (earlier === undefined) {
      const seen = figure.starter_user_id === userId ? { starter_reveal_seen_at: seenAt } : { partner_reveal_seen_at: seenAt };
      await ctx.db.patch(figure._id, { ...seen, updated_at: seenAt });
    }
    return { figure_id: figure.id, reveal_seen_at: seenAt };
  },
});

/**
 * Stars or unstars a finished figure for the caller. Stars are private: the partner is not told.
 * Setting the current value again changes nothing. Result: `{ figure_id, starred }`.
 */
export const set_exquisite_corpse_star = mutation({
  args: { p_figure_id: v.string(), p_starred: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const figure = await requireFinishedFigure(ctx, userId, uuidArg(args.p_figure_id));
    const existing = await getFigureStar(ctx, figure.id, userId);
    if (args.p_starred && !existing) {
      await ctx.db.insert("exquisite_corpse_stars", {
        couple_id: figure.couple_id,
        user_id: userId,
        figure_id: figure.id,
        figure_number: figure.number,
        created_at: nowIso(),
      });
    } else if (!args.p_starred && existing) {
      await ctx.db.delete(existing._id);
    }
    return { figure_id: figure.id, starred: args.p_starred };
  },
});

// --- History ----------------------------------------------------------------

/**
 * The couple's finished figures, newest first by number and strictly before
 * `p_before_figure_number`. `p_limit` is capped at 50. With `p_starred_only` it returns only the
 * figures the caller starred. It does not read the clock.
 *
 * Result: `{ figures, next_before_figure_number }`. Each figure has the shape of `get_exquisite_corpse`,
 * with every part visible. Pass `next_before_figure_number` as the next `p_before_figure_number`; it is
 * null when there are no more figures.
 */
export const get_exquisite_corpse_history = query({
  args: {
    p_starred_only: v.boolean(),
    p_before_figure_number: v.optional(v.union(v.null(), v.number())),
    p_limit: v.number(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    if (!Number.isFinite(args.p_limit) || args.p_limit < 1) fail("23514", "limit must be 1 or more");
    const before = args.p_before_figure_number ?? Number.MAX_SAFE_INTEGER;
    if (Number.isNaN(before)) fail("23514", "figure number cursor must be a number");
    const limit = Math.min(Math.floor(args.p_limit), MAX_HISTORY_PAGE);

    const found: CorpseFigure[] = [];
    let more = false;
    // Takes one figure more than the limit to learn whether another page exists.
    const take = (figure: CorpseFigure | null): boolean => {
      if (!figure || figure.finished_at === undefined) return false;
      if (found.length === limit) {
        more = true;
        return true;
      }
      found.push(figure);
      return false;
    };
    if (args.p_starred_only) {
      const stars = ctx.db
        .query("exquisite_corpse_stars")
        .withIndex("by_couple_id_user_id_figure_number", (q) =>
          q.eq("couple_id", coupleId).eq("user_id", userId).lt("figure_number", before),
        )
        .order("desc");
      for await (const star of stars) {
        if (take(await getByUuid(ctx, "exquisite_corpse_figures", star.figure_id))) break;
      }
    } else {
      const figures = ctx.db
        .query("exquisite_corpse_figures")
        .withIndex("by_couple_id_number", (q) => q.eq("couple_id", coupleId).lt("number", before))
        .order("desc");
      for await (const figure of figures) {
        if (take(figure)) break;
      }
    }

    const result = [];
    for (const figure of found) result.push(await figureJson(ctx, figure, userId));
    return { figures: result, next_before_figure_number: more ? found[found.length - 1].number : null };
  },
});
