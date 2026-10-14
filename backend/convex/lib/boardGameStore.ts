import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull, withUpdatedAt } from "./db";
import { canReadMediaAsset } from "./mediaAssets";
import { BOARD_RULES } from "./boardGameRules";
import type { BoardGameKind, BoardRules } from "./boardGames";
import { enqueueGamePush } from "./games";

// Database helpers for the board games. The registered functions are in boardGames.ts and
// the pure rules are in boardGames.ts and boardGameRules.ts. This file imports both, so the
// rules files do not import it.

export type BoardGame = Doc<"board_games">;
export type BoardGameMark = Doc<"board_game_marks">;

/** The newest couple assets scanned for a Dots and Boxes photo. Older photos are never picked. */
const PHOTO_SCAN_LIMIT = 500;

/** The rules of a kind. The state type differs per game, and a caller that has only a kind does not need it. */
export function rulesFor(kind: BoardGameKind): BoardRules<any> {
  return BOARD_RULES[kind];
}

export async function getBoardGame(ctx: ReaderCtx, coupleId: string, kind: BoardGameKind): Promise<BoardGame | null> {
  return await ctx.db
    .query("board_games")
    .withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId).eq("kind", kind))
    .unique();
}

export async function getBoardGameMark(ctx: ReaderCtx, coupleId: string, userId: string): Promise<BoardGameMark | null> {
  return await ctx.db
    .query("board_game_marks")
    .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .unique();
}

/** Patches a game row, sets `updated_at`, and bumps `version`. */
export async function patchBoardGame(
  ctx: WriterCtx,
  game: BoardGame,
  patch: Partial<Omit<BoardGame, "_id" | "_creationTime">>,
): Promise<BoardGame> {
  await ctx.db.patch(game._id, { ...withUpdatedAt(patch), version: game.version + 1 });
  return (await ctx.db.get(game._id))!;
}

// --- Pushes -----------------------------------------------------------------

/**
 * `enqueueGamePush` has no payload field for more than a game id, so a board game push carries its
 * turn in `round_id` as "<game number>:<move count>". The drain re-check (`boardGameBackend`) reads it
 * back to see whether the pushed turn is still the current one. It names no move.
 */
export function boardGameTurnToken(game: Pick<BoardGame, "game_number" | "moves">): string {
  return `${game.game_number}:${game.moves.length}`;
}

/** The game number and move count in a push's `round_id`, or null when it is not a turn token. */
export function parseBoardGameTurnToken(token: unknown): { gameNumber: number; moveCount: number } | null {
  const match = typeof token === "string" ? /^(\d+):(\d+)$/.exec(token) : null;
  return match ? { gameNumber: Number(match[1]), moveCount: Number(match[2]) } : null;
}

/**
 * Tells `recipientUserId` about the game as it is now: `game_result` once it is finished,
 * otherwise `game_turn_ready`. The push is skipped while the recipient has the game open, and
 * the dedupe key is unique per game number and move.
 */
export async function enqueueBoardGamePush(ctx: WriterCtx, game: BoardGame, actorUserId: string, recipientUserId: string): Promise<void> {
  const finished = game.status === "finished";
  const token = boardGameTurnToken(game);
  await enqueueGamePush(ctx, {
    kind: finished ? "game_result" : "game_turn_ready",
    game_kind: game.kind,
    couple_id: game.couple_id,
    game_id: game.id,
    round_id: token,
    actor_user_id: actorUserId,
    recipient_user_id: recipientUserId,
    dedupe_key: finished ? `game_result:${game.id}:${game.game_number}` : `game_turn_ready:${game.id}:${token}`,
    skipIfPresent: true,
  });
}

/**
 * A random photo from the couple's Memories, as shown by `get_memories`: the memory and the link
 * are visible and not deleted, and the file is finished, visible and not queued for deletion.
 * Returns undefined when the couple has none.
 */
export async function pickBoardGamePhoto(ctx: ReaderCtx, userId: string, coupleId: string): Promise<string | undefined> {
  // Scans the newest assets only, so a couple with thousands of files stays cheap. An older photo is never picked.
  const assets = await ctx.db
    .query("media_assets")
    .withIndex("by_couple_id_created_at", (q) => q.eq("couple_id", coupleId))
    .order("desc")
    .take(PHOTO_SCAN_LIMIT);
  const candidates = assets.filter(
    (asset) => asset.upload_purpose === "memory_photo" && asset.media_type === "image" && asset.reserved_parent_kind === "memory_media",
  );
  // Pick a random candidate and check it. A candidate that fails the full check is dropped, so the pick stays uniform among the readable ones.
  while (candidates.length > 0) {
    const [asset] = candidates.splice(Math.floor(Math.random() * candidates.length), 1);
    if (await canReadMediaAsset(ctx, userId, asset)) return asset.id;
  }
  return undefined;
}

/** The photo id when the file can still be read through its memory, otherwise null. */
async function readablePhotoId(ctx: ReaderCtx, userId: string, coupleId: string, assetId: string | undefined): Promise<string | null> {
  const asset = await getByUuid(ctx, "media_assets", assetId);
  if (!asset || asset.couple_id !== coupleId) return null;
  return (await canReadMediaAsset(ctx, userId, asset)) ? asset.id : null;
}

/**
 * One game as the caller sees it. Absent values are null. The tallies are the caller's and the partner's.
 * The photo ids are null once the photo can no longer be read.
 */
export async function boardGameView(ctx: ReaderCtx, game: BoardGame, userId: string, partnerId: string | null) {
  const previous = game.previous;
  return {
    id: game.id,
    kind: game.kind,
    game_number: game.game_number,
    status: game.status,
    version: game.version,
    first_user_id: game.first_user_id,
    moves: game.moves,
    turn_user_id: orNull(game.turn_user_id),
    winner_user_id: orNull(game.winner_user_id),
    win_line: game.win_line,
    stake: orNull(game.stake),
    stake_by_user_id: orNull(game.stake_by_user_id),
    photo_media_asset_id: await readablePhotoId(ctx, userId, game.couple_id, game.photo_media_asset_id),
    my_wins: game.wins_by_user[userId] ?? 0,
    partner_wins: partnerId ? (game.wins_by_user[partnerId] ?? 0) : 0,
    draws: game.draws,
    games_finished: game.games_finished,
    previous: previous
      ? {
          game_number: previous.game_number,
          first_user_id: previous.first_user_id,
          moves: previous.moves,
          winner_user_id: orNull(previous.winner_user_id),
          win_line: previous.win_line,
          stake: orNull(previous.stake),
          photo_media_asset_id: await readablePhotoId(ctx, userId, game.couple_id, previous.photo_media_asset_id),
          finished_at: previous.finished_at,
        }
      : null,
    started_at: game.started_at,
    finished_at: orNull(game.finished_at),
    turn_started_at: game.turn_started_at,
    updated_at: game.updated_at,
  };
}
