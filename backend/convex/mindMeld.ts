import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { dataEpoch, enqueueGamePush, requirePartnerId } from "./lib/games";
import { newUuid, uuidArg } from "./lib/ids";
import {
  matchKey,
  MAX_ROUNDS,
  newestGame,
  normalizeWord,
  patchGame,
  roundOutcome,
  sendDueMindMeldReminders,
  validateWord,
  WORD_PROBLEM_MESSAGES,
  type RoundOutcome,
} from "./lib/mindMeld";
import { applyCoupleActivity } from "./lib/streaks";
import { nowIso } from "./lib/time";

// Mind Meld. The rules and decisions are in docs/games/mind-meld.md. The tables, the word rules,
// and the hooks the shared games code calls are in lib/mindMeld.ts.

type Game = Doc<"mind_meld_games">;
type Round = Doc<"mind_meld_rounds">;
type Word = Doc<"mind_meld_words">;

/** The most games one history page returns. */
const MAX_HISTORY_PAGE = 50;

// --- Lookups ----------------------------------------------------------------

/** The rounds of a game, oldest first. */
async function roundsOf(ctx: ReaderCtx, gameId: string): Promise<Round[]> {
  return await ctx.db
    .query("mind_meld_rounds")
    .withIndex("by_game_id_round_number", (q) => q.eq("game_id", gameId))
    .collect();
}

async function wordsOfGame(ctx: ReaderCtx, gameId: string): Promise<Word[]> {
  return await ctx.db
    .query("mind_meld_words")
    .withIndex("by_game_id", (q) => q.eq("game_id", gameId))
    .collect();
}

/** The round and its game, for a caller who may access the couple. Fails with 42501 otherwise. */
async function requireRound(ctx: ReaderCtx, userId: string, roundId: string): Promise<{ round: Round; game: Game }> {
  const round = await getByUuid(ctx, "mind_meld_rounds", roundId);
  const game = round ? await getByUuid(ctx, "mind_meld_games", round.game_id) : null;
  if (!round || !game || !(await canAccessCoupleContent(ctx, userId, round.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return { round, game };
}

async function requireGame(ctx: ReaderCtx, userId: string, gameId: string): Promise<Game> {
  const game = await getByUuid(ctx, "mind_meld_games", gameId);
  if (!game || !(await canAccessCoupleContent(ctx, userId, game.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return game;
}

// --- Writes -----------------------------------------------------------------

async function insertRound(ctx: WriterCtx, game: { id: string; couple_id: string }, roundNumber: number): Promise<void> {
  const now = nowIso();
  await ctx.db.insert("mind_meld_rounds", {
    id: newUuid(),
    game_id: game.id,
    couple_id: game.couple_id,
    round_number: roundNumber,
    state: "open",
    created_at: now,
    updated_at: now,
  });
}

/** Starts game number `previous + 1` with an open round 1. Returns the game id. */
async function insertGame(ctx: WriterCtx, coupleId: string, userId: string, previous: Game | null): Promise<string> {
  const id = newUuid();
  const now = nowIso();
  await ctx.db.insert("mind_meld_games", {
    id,
    couple_id: coupleId,
    game_number: (previous?.game_number ?? 0) + 1,
    state: "playing",
    end_seen_by_user: {},
    version: 1,
    created_by_user_id: userId,
    created_at: now,
    updated_at: now,
  });
  await insertRound(ctx, { id, couple_id: coupleId }, 1);
  return id;
}

// --- Reads ------------------------------------------------------------------

type Overview = {
  /** Oldest first. */
  games: Game[];
  melds: Map<string, { meld_number: number; is_record: boolean }>;
  stats: { melds: number; fewest_rounds: number | null; games: number };
};

/**
 * Every game of the couple, the meld numbers, and the couple's numbers. `games` in the stats counts
 * finished games. A meld took as many rounds as the game's `rounds_taken`, so no round is read.
 * ponytail: reads every game row of the couple on each call. One couple finishes a few games a day,
 * so a year is about a thousand small rows. Keep a counter row on the couple if this gets slow.
 */
async function loadOverview(ctx: ReaderCtx, coupleId: string): Promise<Overview> {
  const games = await ctx.db
    .query("mind_meld_games")
    .withIndex("by_couple_id_game_number", (q) => q.eq("couple_id", coupleId))
    .collect();
  const melds = new Map<string, { meld_number: number; is_record: boolean }>();
  let fewest: number | null = null;
  for (const game of games) {
    if (game.state !== "melded") continue;
    const taken = game.rounds_taken ?? 0;
    melds.set(game.id, { meld_number: melds.size + 1, is_record: fewest !== null && taken < fewest });
    fewest = fewest === null ? taken : Math.min(fewest, taken);
  }
  return {
    games,
    melds,
    stats: { melds: melds.size, fewest_rounds: fewest, games: games.filter((game) => game.state !== "playing").length },
  };
}

/** The partner's word comes only with a revealed round. */
function roundJson(round: Round, words: Word[], userId: string) {
  const mine = words.find((word) => word.round_id === round.id && word.user_id === userId);
  const theirs = words.find((word) => word.round_id === round.id && word.user_id !== userId);
  return {
    id: round.id,
    round_number: round.round_number,
    state: round.state,
    outcome: orNull(round.outcome),
    counted_by_user_id: orNull(round.counted_by_user_id),
    my_word: orNull(mine?.word),
    my_locked_at: orNull(mine?.locked_at),
    partner_locked: theirs !== undefined,
    partner_locked_at: orNull(theirs?.locked_at),
    partner_word: round.state === "revealed" ? orNull(theirs?.word) : null,
    revealed_at: orNull(round.revealed_at),
    my_reveal_seen_at: orNull(mine?.reveal_seen_at),
  };
}

async function gameJson(ctx: ReaderCtx, overview: Overview, game: Game, userId: string) {
  const words = await wordsOfGame(ctx, game.id);
  const rounds = await roundsOf(ctx, game.id);
  const meld = overview.melds.get(game.id);
  return {
    id: game.id,
    game_number: game.game_number,
    state: game.state,
    end_reason: orNull(game.end_reason),
    ended_by_user_id: orNull(game.ended_by_user_id),
    ended_at: orNull(game.ended_at),
    max_rounds: MAX_ROUNDS,
    my_end_seen_at: orNull(game.end_seen_by_user[userId]),
    meld_number: meld?.meld_number ?? null,
    is_record: meld?.is_record ?? false,
    created_by_user_id: game.created_by_user_id,
    created_at: game.created_at,
    updated_at: game.updated_at,
    version: game.version,
    rounds: rounds.map((round) => roundJson(round, words, userId)),
  };
}

/**
 * Everything the Mind Meld screen shows, for the caller. Subscribe to it. It does not read the clock.
 *
 * Result: `{ user_id, partner_user_id, couple_id, current, previous, stats }`. `current` is the
 * couple's newest game in any state, and null before the first game. `previous` is the game before
 * it, only while the caller has not seen its ending. A game carries its rounds, oldest first, and a
 * round carries the partner's word only once it is revealed. `meld_number` is the game's place among
 * the couple's melds, and `is_record` means it took fewer rounds than every earlier meld. `stats` is
 * `{ melds, fewest_rounds, games }`, with `games` counting finished games.
 */
export const get_mind_meld = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
    const overview = await loadOverview(ctx, coupleId);
    const current = overview.games.at(-1);
    const before = overview.games.at(-2);
    const previous = before && before.end_seen_by_user[userId] === undefined ? before : undefined;
    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      data_epoch: dataEpoch(),
      current: current ? await gameJson(ctx, overview, current, userId) : null,
      previous: previous ? await gameJson(ctx, overview, previous, userId) : null,
      stats: overview.stats,
    };
  },
});

/**
 * The couple's finished games, newest first, with their revealed rounds only. `p_before_game_number`
 * is the cursor, and `next_before_game_number` is null on the last page. The limit is capped at 50.
 *
 * Result: `{ games, next_before_game_number, stats }`. A game is `{ id, game_number, state,
 * end_reason, ended_by_user_id, created_at, ended_at, meld_number, rounds }` and a round is
 * `{ round_number, my_word, partner_word, outcome, counted_by_user_id }`.
 */
export const get_mind_meld_history = query({
  args: { p_before_game_number: v.optional(v.union(v.null(), v.number())), p_limit: v.number() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    if (!Number.isFinite(args.p_limit) || args.p_limit < 1) fail("23514", "limit must be 1 or more");
    const before = args.p_before_game_number ?? Number.MAX_SAFE_INTEGER;
    if (Number.isNaN(before)) fail("23514", "game number cursor must be a number");
    const limit = Math.min(Math.floor(args.p_limit), MAX_HISTORY_PAGE);

    const overview = await loadOverview(ctx, coupleId);
    const finished = overview.games.filter((game) => game.state !== "playing" && game.game_number < before).reverse();
    const games = [];
    for (const game of finished.slice(0, limit)) {
      const words = await wordsOfGame(ctx, game.id);
      const rounds = (await roundsOf(ctx, game.id)).filter((round) => round.state === "revealed");
      games.push({
        id: game.id,
        game_number: game.game_number,
        state: game.state,
        end_reason: orNull(game.end_reason),
        ended_by_user_id: orNull(game.ended_by_user_id),
        created_at: game.created_at,
        ended_at: orNull(game.ended_at),
        meld_number: overview.melds.get(game.id)?.meld_number ?? null,
        rounds: rounds.map((round) => {
          const shown = roundJson(round, words, userId);
          return {
            round_number: shown.round_number,
            my_word: shown.my_word,
            partner_word: shown.partner_word,
            outcome: shown.outcome,
            counted_by_user_id: shown.counted_by_user_id,
          };
        }),
      });
    }
    return {
      games,
      next_before_game_number: finished.length > limit ? games[games.length - 1].game_number : null,
      stats: overview.stats,
    };
  },
});

// --- The game ---------------------------------------------------------------

/** Starts a new game at round 1 unless one is in play, and returns the game in play either way. */
export const start_mind_meld_game = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await requirePartnerId(ctx, coupleId, userId);
    const newest = await newestGame(ctx, coupleId);
    if (newest?.state === "playing") return { game_id: newest.id, created: false };
    return { game_id: await insertGame(ctx, coupleId, userId, newest), created: true };
  },
});

/**
 * Ends the game in play (reason `restart`) and starts a new one, or, when `p_game_id` already
 * ended, returns the newer game in play, or starts a new game when none is. This is "Start over"
 * and "Play again". A stale game id from the other partner's phone is safe to send.
 */
export const restart_mind_meld = mutation({
  args: { p_game_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const game = await requireGame(ctx, userId, uuidArg(args.p_game_id));
    const coupleId = game.couple_id;
    await requirePartnerId(ctx, coupleId, userId);
    if (game.state === "playing") {
      const now = nowIso();
      await patchGame(ctx, game, {
        state: "ended",
        end_reason: "restart",
        ended_by_user_id: userId,
        ended_at: now,
        end_seen_by_user: { ...game.end_seen_by_user, [userId]: now },
      });
      return { game_id: await insertGame(ctx, coupleId, userId, game), created: true };
    }
    const newest = await newestGame(ctx, coupleId);
    if (newest?.state === "playing") return { game_id: newest.id, created: false };
    return { game_id: await insertGame(ctx, coupleId, userId, newest), created: true };
  },
});

/**
 * Locks in the caller's word for an open round. The second lock-in reveals the round and decides the
 * outcome: a match melds the game, a miss or near miss opens the next round, and a round 10 without
 * a match ends the game (reason `rounds`). Counts toward the streak, once per round and person.
 * Queues the turn push after the first lock-in and the result push after the second.
 *
 * Result: `{ round_id, round_state, outcome, game_state, locked_at }`. `outcome` is null while the
 * round is open.
 */
export const lock_mind_meld_word = mutation({
  args: { p_round_id: v.string(), p_word: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    const word = normalizeWord(args.p_word);
    const problem = validateWord(word);
    if (problem) fail("23514", WORD_PROBLEM_MESSAGES[problem]);

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "lock_mind_meld_word",
        scope: "games",
        request: ["lock_mind_meld_word", roundId, word],
      }),
      async () => {
        const { round, game } = await requireRound(ctx, userId, roundId);
        if (game.state !== "playing" || round.state !== "open") fail("23514", "this round is already finished");
        const partnerId = await requirePartnerId(ctx, game.couple_id, userId);

        const words = await wordsOfGame(ctx, game.id);
        if (words.some((item) => item.round_id === round.id && item.user_id === userId)) {
          fail("23505", "you already locked in a word this round");
        }
        const key = matchKey(word);
        const revealedIds = new Set((await roundsOf(ctx, game.id)).filter((item) => item.state === "revealed").map((item) => item.id));
        if (words.some((item) => revealedIds.has(item.round_id) && item.match_key === key)) {
          fail("23514", "that word was already used in this game");
        }

        const now = nowIso();
        await ctx.db.insert("mind_meld_words", {
          round_id: round.id,
          game_id: game.id,
          couple_id: game.couple_id,
          user_id: userId,
          word,
          match_key: key,
          locked_at: now,
        });

        const partnerWord = words.find((item) => item.round_id === round.id && item.user_id === partnerId);
        let outcome: RoundOutcome | null = null;
        let gameState: Game["state"] = game.state;
        if (!partnerWord) {
          await ctx.db.patch(round._id, withUpdatedAt({ waiting_since: now }));
          await patchGame(ctx, game);
          await enqueueGamePush(ctx, {
            kind: "game_turn_ready",
            game_kind: "mind_meld",
            couple_id: game.couple_id,
            game_id: game.id,
            round_id: round.id,
            actor_user_id: userId,
            recipient_user_id: partnerId,
            dedupe_key: `game_turn_ready:${round.id}`,
            skipIfPresent: true,
          });
        } else {
          outcome = roundOutcome(partnerWord.word, word);
          await ctx.db.patch(
            round._id,
            withUpdatedAt({ state: "revealed" as const, outcome, revealed_at: now, waiting_since: undefined }),
          );
          if (outcome === "match") {
            gameState = "melded";
            await patchGame(ctx, game, { state: "melded", ended_at: now, rounds_taken: round.round_number });
          } else if (round.round_number >= MAX_ROUNDS) {
            gameState = "ended";
            await patchGame(ctx, game, { state: "ended", end_reason: "rounds", ended_at: now });
          } else {
            await insertRound(ctx, game, round.round_number + 1);
            await patchGame(ctx, game);
          }
          await enqueueGamePush(ctx, {
            kind: "game_result",
            game_kind: "mind_meld",
            couple_id: game.couple_id,
            game_id: game.id,
            round_id: round.id,
            actor_user_id: userId,
            recipient_user_id: partnerId,
            dedupe_key: `game_result:${round.id}`,
            skipIfPresent: true,
          });
        }

        await applyCoupleActivity(ctx, {
          couple_id: game.couple_id,
          user_id: userId,
          couple_day_id: await getOrCreateCoupleDayAt(ctx, game.couple_id, now),
          activity_kind: "game_turn_completed",
          occurred_at: now,
          dedupe_key: `game_turn_completed:${round.id}:${userId}`,
          metadata: { game_id: game.id, round_id: round.id },
        });
        return {
          round_id: round.id,
          round_state: partnerWord ? ("revealed" as const) : ("open" as const),
          outcome,
          game_state: gameState,
          locked_at: now,
        };
      },
    );
  },
});

/**
 * Counts a near miss as a match: the game melds and the open round after it goes away with any word
 * already locked in for it. Either partner may call it. Safe to repeat: a counted round returns as is.
 * The round must be the game's latest revealed round, and the game in play or ended after round 10.
 *
 * Result: `{ round_id, game_id, game_state }`.
 */
export const count_mind_meld_round = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { round, game } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (round.counted_by_user_id !== undefined) return { round_id: round.id, game_id: game.id, game_state: game.state };

    const rounds = await roundsOf(ctx, game.id);
    const latestRevealed = rounds.filter((item) => item.state === "revealed").at(-1);
    const countable = game.state === "playing" || (game.state === "ended" && game.end_reason === "rounds");
    if (!countable || round.state !== "revealed" || round.outcome !== "near" || latestRevealed?._id !== round._id) {
      fail("23514", "this round can't be counted");
    }

    const open = rounds.find((item) => item.state === "open");
    if (open) {
      const locked = await ctx.db
        .query("mind_meld_words")
        .withIndex("by_round_id_user_id", (q) => q.eq("round_id", open.id))
        .collect();
      for (const word of locked) await ctx.db.delete(word._id);
      await ctx.db.delete(open._id);
    }
    await ctx.db.patch(round._id, withUpdatedAt({ counted_by_user_id: userId }));
    await patchGame(ctx, game, {
      state: "melded",
      end_reason: undefined,
      ended_at: nowIso(),
      rounds_taken: latestRevealed.round_number,
    });
    return { round_id: round.id, game_id: game.id, game_state: "melded" as const };
  },
});

// --- Seen marks -------------------------------------------------------------

/** Keeps the first time the caller saw the revealed round. Safe to repeat. Result: `{ round_id, reveal_seen_at }`. */
export const mark_mind_meld_reveal_seen = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { round, game } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (round.state !== "revealed") fail("23514", "the round is not revealed yet");
    const mine = await ctx.db
      .query("mind_meld_words")
      .withIndex("by_round_id_user_id", (q) => q.eq("round_id", round.id).eq("user_id", userId))
      .unique();
    if (!mine) return fail("23514", "you did not lock in a word this round");
    if (mine.reveal_seen_at !== undefined) return { round_id: round.id, reveal_seen_at: mine.reveal_seen_at };

    const now = nowIso();
    await ctx.db.patch(mine._id, { reveal_seen_at: now });
    await patchGame(ctx, game);
    return { round_id: round.id, reveal_seen_at: now };
  },
});

/** Keeps the first time the caller saw the ending of a finished game. Safe to repeat. Result: `{ game_id, end_seen_at }`. */
export const mark_mind_meld_end_seen = mutation({
  args: { p_game_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const game = await requireGame(ctx, userId, uuidArg(args.p_game_id));
    if (game.state === "playing") fail("23514", "this game is still in play");
    const seen = game.end_seen_by_user[userId];
    if (seen !== undefined) return { game_id: game.id, end_seen_at: seen };

    const now = nowIso();
    await patchGame(ctx, game, { end_seen_by_user: { ...game.end_seen_by_user, [userId]: now } });
    return { game_id: game.id, end_seen_at: now };
  },
});

// --- Reminders --------------------------------------------------------------

/**
 * The single reminder for a round that waited 72 hours for the partner who has not locked in.
 * Returns the number of pushes queued. `mindMeldBackend.sendDueTurnReminders` runs the same code.
 */
export const send_due_mind_meld_reminders = internalMutation({
  args: {},
  handler: async (ctx) => await sendDueMindMeldReminders(ctx, nowIso()),
});
