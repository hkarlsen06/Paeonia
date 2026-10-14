import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import {
  boardGameView,
  enqueueBoardGamePush,
  getBoardGame,
  getBoardGameMark,
  patchBoardGame,
  pickBoardGamePhoto,
  rulesFor,
  type BoardGame,
} from "./lib/boardGameStore";
import { BOARD_GAME_KINDS, replay } from "./lib/boardGames";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, omitNulls, withUpdatedAt } from "./lib/db";
import { fail } from "./lib/errors";
import { requireGameSettings, requirePartnerId } from "./lib/games";
import { newUuid, uuidArg } from "./lib/ids";
import { applyCoupleActivity } from "./lib/streaks";
import { charLength } from "./lib/text";
import { nowIso } from "./lib/time";
import { literals } from "./lib/validators";

// Board games: Connect Four, Dots and Boxes and Ultimate Tic-Tac-Toe. The design is in
// docs/games/board-games.md. The pure rules are in lib/<camelKind>.ts and the database
// helpers are in lib/boardGameStore.ts. The server stores the move list and replays it.
//
// Every function needs an active, entitled couple member. Writes also refuse a user whose
// account deletion is pending.

const boardGameKind = literals(...BOARD_GAME_KINDS);
const nullableString = v.optional(v.union(v.null(), v.string()));

/** A stake is 1 to 60 characters on one line. */
const MAX_STAKE_CHARACTERS = 60;
/** A mark is at most 48 KB of PKDrawing data. */
const MAX_MARK_BYTES = 48 * 1024;
const MAX_MARK_BASE64_CHARS = (MAX_MARK_BYTES / 3) * 4;

// --- Shared lookups ---------------------------------------------------------

/** The active partner of `userId`, or null. */
async function findPartnerId(ctx: ReaderCtx, coupleId: string, userId: string): Promise<string | null> {
  return (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
}

/** The game, for a caller who may access its couple. Fails with 42501 otherwise. */
async function requireBoardGameById(ctx: ReaderCtx, userId: string, gameId: string): Promise<BoardGame> {
  const game = await getByUuid(ctx, "board_games", gameId);
  if (!game || !(await canAccessCoupleContent(ctx, userId, game.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return game;
}

/** Fails with 40001 when the phone's copy of the game is not the current one. */
function assertCurrentVersion(game: BoardGame, expectedVersion: number): void {
  if (game.version !== expectedVersion) fail("40001", "the game has changed");
}

// --- Reads ------------------------------------------------------------------

/**
 * The couple's board games for the caller, in the order connect_four, dots_and_boxes,
 * ultimate_tic_tac_toe. A game the couple has not started is missing from `games`. The query does
 * not read the clock, so subscribe to it after `ensure_board_game`.
 *
 * Each game: `{ id, kind, game_number, status, version, first_user_id, moves, turn_user_id,
 * winner_user_id, win_line, stake, stake_by_user_id, photo_media_asset_id, my_wins, partner_wins,
 * draws, games_finished, previous, started_at, finished_at, turn_started_at, updated_at }`.
 * `turn_user_id` is null once the game is finished and `winner_user_id` is null for a draw. A photo id
 * is null once its memory is gone. `previous` is the last finished game after a rematch:
 * `{ game_number, first_user_id, moves, winner_user_id, win_line, stake, photo_media_asset_id, finished_at }`.
 */
export const get_board_games = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await findPartnerId(ctx, coupleId, userId);
    const games = [];
    for (const kind of BOARD_GAME_KINDS) {
      const game = await getBoardGame(ctx, coupleId, kind);
      if (game) games.push(await boardGameView(ctx, game, userId, partnerId));
    }
    return { user_id: userId, partner_user_id: partnerId, couple_id: coupleId, games };
  },
});

/**
 * Both marks of the couple, each as `{ drawing, updated_at }` (base64 PKDrawing data) or null
 * while that partner has none. It is its own subscription, so a move never resends the drawings.
 */
export const get_board_game_marks = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await findPartnerId(ctx, coupleId, userId);
    const mark = async (markUserId: string | null) => {
      const row = markUserId ? await getBoardGameMark(ctx, coupleId, markUserId) : null;
      return row ? { drawing: row.drawing, updated_at: row.updated_at } : null;
    };
    return { user_id: userId, mine: await mark(userId), partner: await mark(partnerId) };
  },
});

// --- Starting a game --------------------------------------------------------

/**
 * Gets or creates the couple's game of this kind and returns it in the shape of `get_board_games`.
 * The caller is player one of a new game and moves first. A new Dots and Boxes game gets a random
 * photo from the couple's Memories. Needs the game settings, so the app runs setup before this.
 */
export const ensure_board_game = mutation({
  args: { p_kind: boardGameKind },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await requirePartnerId(ctx, coupleId, userId);
    const existing = await getBoardGame(ctx, coupleId, args.p_kind);
    if (existing) return await boardGameView(ctx, existing, userId, partnerId);

    await requireGameSettings(ctx, coupleId);
    const now = nowIso();
    await ctx.db.insert("board_games", {
      id: newUuid(),
      couple_id: coupleId,
      kind: args.p_kind,
      game_number: 1,
      status: "playing",
      first_user_id: userId,
      moves: [],
      turn_user_id: userId,
      win_line: [],
      photo_media_asset_id: args.p_kind === "dots_and_boxes" ? await pickBoardGamePhoto(ctx, userId, coupleId) : undefined,
      wins_by_user: {},
      draws: 0,
      games_finished: 0,
      started_at: now,
      turn_started_at: now,
      version: 1,
      created_by_user_id: userId,
      created_at: now,
      updated_at: now,
    });
    return await boardGameView(ctx, (await getBoardGame(ctx, coupleId, args.p_kind))!, userId, partnerId);
  },
});

/** The game as the caller may see it now. Checks access again. */
async function currentBoardGameView(ctx: ReaderCtx, userId: string, gameId: string) {
  const game = await requireBoardGameById(ctx, userId, gameId);
  const partnerId = await requirePartnerId(ctx, game.couple_id, userId);
  return await boardGameView(ctx, game, userId, partnerId);
}

// --- Moves ------------------------------------------------------------------

/** The stake to store: null for none, or the trimmed text. Fails with 23514 when the text is not allowed. */
function normalizeStake(stake: string | null, game: BoardGame, userId: string): string | null {
  const text = (stake ?? "").trim();
  if (text === "") return null;
  const allowed =
    game.moves.length === 0 &&
    game.first_user_id === userId &&
    charLength(text) <= MAX_STAKE_CHARACTERS &&
    !/[\n\r\u0085\u2028\u2029]/.test(text);
  if (!allowed) fail("23514", "that stake is not allowed");
  return text;
}

/**
 * Plays one move: a column in Connect Four, a line in Dots and Boxes, a cell in Ultimate Tic-Tac-Toe.
 * It fails with 40001 `the game has changed` when `p_expected_version` is not the current version or
 * the game is over, 42501 `it is not your turn`, and 23514 `that move is not allowed` for a move the
 * rules refuse. The starter can send `p_stake` with the first move only. An empty stake means none.
 * Returns the game in the shape of `get_board_games`, as it is now. A retry of the same operation
 * changes nothing and returns the game as it is now too. Every accepted move counts as the `game_turn_completed` streak activity.
 * A move that passes the turn queues `game_turn_ready` for the partner and a move that ends the game queues
 * `game_result` instead. A Dots and Boxes extra turn queues nothing. Both are skipped while the partner has
 * the game open, and their `round_id` is the turn token `<game number>:<move count>` (see `boardGameTurnToken`).
 */
export const make_move = mutation({
  args: {
    p_game_id: v.string(),
    p_expected_version: v.number(),
    p_move: v.number(),
    p_stake: nullableString,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const gameId = uuidArg(args.p_game_id);
    const stakeArg = args.p_stake ?? null;
    // Access is checked on every call, a replay too, so a stored answer never outlives the couple.
    await requireBoardGameById(ctx, userId, gameId);

    await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "make_board_game_move",
        scope: "games",
        request: ["make_board_game_move", gameId, args.p_expected_version, args.p_move, stakeArg],
      }),
      async () => {
        const game = await requireBoardGameById(ctx, userId, gameId);
        assertCurrentVersion(game, args.p_expected_version);
        if (game.status !== "playing") fail("40001", "the game has changed");
        if (game.turn_user_id !== userId) fail("42501", "it is not your turn");

        const rules = rulesFor(game.kind);
        const before = replay(rules, game.moves);
        if (before === null) return fail("XX000", "the stored game is not valid");
        const after = rules.apply(before, args.p_move);
        if (after === null) return fail("23514", "that move is not allowed");
        const stake = normalizeStake(stakeArg, game, userId);

        const partnerId = await requirePartnerId(ctx, game.couple_id, userId);
        const playerOneId = game.first_user_id;
        const playerTwoId = playerOneId === userId ? partnerId : userId;
        const now = nowIso();
        const outcome = rules.outcome(after);
        let turnPatch: Parameters<typeof patchBoardGame>[2];
        if (outcome) {
          const winnerId = outcome.winner === null ? undefined : outcome.winner === 1 ? playerOneId : playerTwoId;
          turnPatch = {
            status: "finished",
            turn_user_id: undefined,
            winner_user_id: winnerId,
            win_line: outcome.line,
            finished_at: now,
            games_finished: game.games_finished + 1,
            ...(winnerId === undefined
              ? { draws: game.draws + 1 }
              : { wins_by_user: { ...game.wins_by_user, [winnerId]: (game.wins_by_user[winnerId] ?? 0) + 1 } }),
            // A finished game waits for nobody, so the turn reminder must skip it.
            turn_reminder_sent_at: now,
          };
        } else {
          const nextUserId = rules.next(after) === 1 ? playerOneId : playerTwoId;
          // A Dots and Boxes extra turn stays with the mover and keeps the turn clock.
          turnPatch =
            nextUserId === userId
              ? { turn_user_id: nextUserId }
              : { turn_user_id: nextUserId, turn_started_at: now, turn_reminder_sent_at: undefined };
        }
        const updated = await patchBoardGame(ctx, game, {
          moves: [...game.moves, args.p_move],
          ...(stake === null ? {} : { stake, stake_by_user_id: userId }),
          ...turnPatch,
        });

        await applyCoupleActivity(ctx, {
          couple_id: game.couple_id,
          user_id: userId,
          couple_day_id: await getOrCreateCoupleDayAt(ctx, game.couple_id, now),
          activity_kind: "game_turn_completed",
          occurred_at: now,
          dedupe_key: `game_turn_completed:${game.id}:${game.game_number}:${updated.moves.length}`,
          metadata: { game_id: game.id, kind: game.kind },
        });
        // The turn passed (or the game ended) when the mover is no longer the one to move. A Dots and Boxes extra turn queues nothing.
        if (updated.turn_user_id !== userId) await enqueueBoardGamePush(ctx, updated, userId, partnerId);
        // The operation record keeps only this receipt, never the game's content.
        return { game_id: game.id };
      },
    );
    return await currentBoardGameView(ctx, userId, gameId);
  },
});

/**
 * Starts the next game on the same row once the current one is finished. The partner who did not
 * start the last game starts this one. The finished game moves to `previous`, and the stake is
 * cleared. Fails with 40001 for a stale version, so two taps at once start one game, and with 23514
 * `the game is not over` while the game is still playing. Queues `game_turn_ready` for the new starter when
 * that is the partner. Returns the new game.
 */
export const start_rematch = mutation({
  args: { p_game_id: v.string(), p_expected_version: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const gameId = uuidArg(args.p_game_id);
    await requireBoardGameById(ctx, userId, gameId);

    await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "start_board_game_rematch",
        scope: "games",
        request: ["start_board_game_rematch", gameId, args.p_expected_version],
      }),
      async () => {
        const game = await requireBoardGameById(ctx, userId, gameId);
        assertCurrentVersion(game, args.p_expected_version);
        if (game.status !== "finished") fail("23514", "the game is not over");

        const partnerId = await requirePartnerId(ctx, game.couple_id, userId);
        const starterId = game.first_user_id === userId ? partnerId : userId;
        const now = nowIso();
        const updated = await patchBoardGame(ctx, game, {
          previous: omitNulls({
            game_number: game.game_number,
            first_user_id: game.first_user_id,
            moves: game.moves,
            winner_user_id: game.winner_user_id,
            win_line: game.win_line,
            stake: game.stake,
            photo_media_asset_id: game.photo_media_asset_id,
            finished_at: game.finished_at ?? game.updated_at,
          }),
          game_number: game.game_number + 1,
          status: "playing",
          first_user_id: starterId,
          moves: [],
          turn_user_id: starterId,
          winner_user_id: undefined,
          win_line: [],
          stake: undefined,
          stake_by_user_id: undefined,
          photo_media_asset_id: game.kind === "dots_and_boxes" ? await pickBoardGamePhoto(ctx, userId, game.couple_id) : undefined,
          started_at: now,
          finished_at: undefined,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
        });
        // The new starter moves next. Starting the game yourself needs no push.
        if (starterId !== userId) await enqueueBoardGamePush(ctx, updated, userId, starterId);
        return { game_id: updated.id };
      },
    );
    return await currentBoardGameView(ctx, userId, gameId);
  },
});

// --- Marks ------------------------------------------------------------------

/** The decoded size of a canonical base64 string, or null when the text is not base64. */
function base64ByteLength(text: string): number | null {
  if (text.length === 0 || text.length > MAX_MARK_BASE64_CHARS || text.length % 4 !== 0) return null;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(text)) return null;
  const padding = text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0;
  return (text.length / 4) * 3 - padding;
}

/**
 * Saves the caller's mark, base64 PKDrawing data that decodes to 1 to 49152 bytes, or removes it
 * when `p_drawing` is null. Fails with 23514 `that mark is not allowed` for anything else.
 * Returns `{ updated_at }`, or null after a removal.
 */
export const set_board_game_mark = mutation({
  args: { p_drawing: v.union(v.string(), v.null()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getBoardGameMark(ctx, coupleId, userId);

    if (args.p_drawing === null) {
      if (existing) await ctx.db.delete(existing._id);
      return null;
    }
    if (base64ByteLength(args.p_drawing) === null) return fail("23514", "that mark is not allowed");

    if (existing) {
      const patch = withUpdatedAt({ drawing: args.p_drawing });
      await ctx.db.patch(existing._id, patch);
      return { updated_at: patch.updated_at };
    }
    const now = nowIso();
    await ctx.db.insert("board_game_marks", {
      couple_id: coupleId,
      user_id: userId,
      drawing: args.p_drawing,
      created_at: now,
      updated_at: now,
    });
    return { updated_at: now };
  },
});
