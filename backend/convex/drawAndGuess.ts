import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull } from "./lib/db";
import {
  beginTurn,
  drawWordChoices,
  FIRST_TRY_BONUS_POINTS,
  gameJson,
  getGame,
  getMovesByCouple,
  getMovesByGame,
  getRoundStar,
  isPersonalBest,
  listGuesses,
  MAX_GUESS_LENGTH,
  MAX_HISTORY_PAGE,
  patchGame,
  patchMove,
  playerRecords,
  roundJson,
  roundOutcomeJson,
  scoreSolve,
  wordLetterCount,
  type Game,
  type GameMove,
} from "./lib/drawAndGuess";
import { fail, uniqueViolation } from "./lib/errors";
import { DIFFICULTY_POINTS, normalizeCustomWord, normalizeWordText } from "./lib/gameWords";
import { enqueueGamePush, getGameSettings, requireGameSettings, requirePartnerId, settingsJson } from "./lib/games";
import { newUuid, uuidArg } from "./lib/ids";
import { gameRoom, onlineUserIds } from "./lib/presence";
import { applyCoupleActivity } from "./lib/streaks";
import { charLength } from "./lib/text";
import { nowIso } from "./lib/time";
import { literals } from "./lib/validators";

// Draw & Guess functions. The rules and decisions are in docs/games-plan.md and
// docs/games/draw-and-guess.md. Helpers are in lib/drawAndGuess.ts. Settings, invites, presence,
// and the relay ticket are shared by all games and live in games.ts.

const nullableString = v.optional(v.union(v.null(), v.string()));
/** The speed bonus tiers a phone can claim. */
const SPEED_BONUS_CLAIMS: readonly number[] = [0, 1, 2];

// --- Shared lookups ---------------------------------------------------------

/** The round and its game, for a caller who may access the couple. Fails with 42501 otherwise. */
async function requireRound(
  ctx: ReaderCtx,
  userId: string,
  roundId: string,
): Promise<{ move: GameMove; game: Game }> {
  const move = await getByUuid(ctx, "game_moves", roundId);
  const game = move ? await getByUuid(ctx, "games", move.game_id) : null;
  if (!move || !game || !(await canAccessCoupleContent(ctx, userId, move.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return { move, game };
}

async function requireGameById(ctx: ReaderCtx, userId: string, gameId: string): Promise<Game> {
  const game = await getByUuid(ctx, "games", gameId);
  if (!game || !(await canAccessCoupleContent(ctx, userId, game.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return game;
}

// --- Draw & Guess: the game and its screen -----------------------------------

/**
 * Gets or creates the couple's Draw & Guess game. The caller draws first. Needs the game
 * settings, so the app runs setup before this.
 */
export const ensure_draw_and_guess_game = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getGame(ctx, coupleId, "draw_and_guess");
    if (existing) return { game_id: existing.id, created: false };

    await requirePartnerId(ctx, coupleId, userId);
    const settings = await requireGameSettings(ctx, coupleId);
    const id = newUuid();
    const now = nowIso();
    await ctx.db.insert("games", {
      id,
      couple_id: coupleId,
      kind: "draw_and_guess",
      state: "choosing_word",
      turn_user_id: userId,
      turn_number: 1,
      word_choices: await drawWordChoices(ctx, { id, couple_id: coupleId }, settings.language),
      shared_points: 0,
      points_by_user: {},
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
 * Everything the Draw & Guess screen shows, for the caller. Subscribe to it after
 * `ensure_draw_and_guess_game`. It does not read the clock: the presence component marks a
 * closed screen offline, and the app decides what counts as a recent `last_invite_at`.
 */
export const get_draw_and_guess = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const settings = await getGameSettings(ctx, coupleId);
    const game = await getGame(ctx, coupleId, "draw_and_guess");
    const partner = (
      await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
        .collect()
    ).find((member) => member.user_id !== userId);
    const partnerId = partner?.user_id ?? null;

    const invite = await ctx.db
      .query("game_invites")
      .withIndex("by_couple_id_kind_sender_user_id", (q) =>
        q.eq("couple_id", coupleId).eq("kind", "draw_and_guess").eq("sender_user_id", userId),
      )
      .unique();
    const online = await onlineUserIds(ctx, gameRoom(coupleId, "draw_and_guess"));

    // The latest round first. It is the current round, whatever its state.
    const moves = game ? await getMovesByGame(ctx, game.id, 21) : [];
    const rounds = [];
    for (const move of moves) rounds.push(await roundJson(ctx, move, userId));

    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      settings: settings ? settingsJson(settings) : null,
      game: game ? gameJson(game, userId, partnerId) : null,
      current_round: rounds[0] ?? null,
      recent_rounds: rounds.slice(1),
      // Only the drawer whose turn it is may see the three choices.
      choices:
        game?.state === "choosing_word" && game.turn_user_id === userId
          ? (game.word_choices ?? []).map((choice) => ({
              difficulty: choice.difficulty,
              word_id: choice.word_id,
              word: choice.word,
              points: DIFFICULTY_POINTS[choice.difficulty],
            }))
          : null,
      my_present: online.includes(userId),
      partner_present: partnerId !== null && online.includes(partnerId),
      last_invite_at: orNull(invite?.sent_at),
    };
  },
});

/**
 * One round by id, in the same shape as the rounds of `get_draw_and_guess`. The phone uses it
 * to find a round that is no longer among the recent rounds. Null when the couple has no such round.
 */
export const get_draw_and_guess_round = query({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const move = await getByUuid(ctx, "game_moves", uuidArg(args.p_round_id));
    if (!move || move.couple_id !== coupleId) return null;
    return await roundJson(ctx, move, userId);
  },
});

// --- Draw & Guess: the turn --------------------------------------------------

/** Picks the word and starts the round. The round exists from this moment, so the partner can start guessing. */
export const pick_draw_word = mutation({
  args: {
    p_game_id: v.string(),
    p_round_id: v.string(),
    p_choice: literals("easy", "medium", "hard", "custom"),
    p_custom_word: nullableString,
    /** The `word_id` of the offered choice the drawer saw. Required unless the choice is custom. */
    p_word_id: nullableString,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const gameId = uuidArg(args.p_game_id);
    const roundId = uuidArg(args.p_round_id);
    const customWord = args.p_choice === "custom" ? normalizeCustomWord(args.p_custom_word ?? "") : null;
    const seenWordId = args.p_choice === "custom" ? "" : (args.p_word_id ?? "");

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "pick_draw_word",
        scope: "games",
        request: ["pick_draw_word", gameId, roundId, args.p_choice, customWord ?? "", seenWordId],
      }),
      async () => {
        const game = await requireGameById(ctx, userId, gameId);
        if (game.turn_user_id !== userId) fail("42501", "it is not your turn");
        if (game.state !== "choosing_word") fail("23514", "a word was already chosen for this turn");
        if (await getByUuid(ctx, "game_moves", roundId)) uniqueViolation("game_moves_pkey");
        const guesserId = await requirePartnerId(ctx, game.couple_id, userId);

        let word: string;
        let wordId: string | undefined;
        if (customWord !== null) {
          word = customWord;
        } else {
          const choice = game.word_choices?.find((item) => item.difficulty === args.p_choice);
          if (!choice) return fail("23514", "word choice is not available");
          // The choices change when the partner switches the game language. Never start a
          // round with a word the drawer didn't see.
          if (choice.word_id !== seenWordId) return fail("23514", "word choice is out of date");
          word = choice.word;
          wordId = choice.word_id;
        }
        const points = DIFFICULTY_POINTS[args.p_choice];
        const now = nowIso();
        await ctx.db.insert("game_moves", {
          id: roundId,
          game_id: game.id,
          couple_id: game.couple_id,
          round_number: game.turn_number,
          drawer_user_id: userId,
          guesser_user_id: guesserId,
          state: "drawing",
          difficulty: args.p_choice,
          word_id: wordId,
          word,
          points,
          started_at: now,
          speed_bonus: 0,
          created_at: now,
          updated_at: now,
        });
        await patchGame(ctx, game, { state: "drawing", current_round_id: roundId, word_choices: undefined });
        return { round_id: roundId, round_number: game.turn_number, difficulty: args.p_choice, word, points };
      },
    );
  },
});

/** The finished drawing as a usable `game-drawings` asset of this round, owned by the caller. */
async function assertDrawingAssetUsable(
  ctx: ReaderCtx,
  userId: string,
  move: GameMove,
  assetId: string,
): Promise<void> {
  const asset = await getByUuid(ctx, "media_assets", assetId);
  if (
    !asset ||
    asset.owner_user_id !== userId ||
    asset.couple_id !== move.couple_id ||
    asset.bucket !== "game-drawings" ||
    asset.expected_bucket !== "game-drawings" ||
    asset.reserved_parent_kind !== "game_move" ||
    asset.reserved_parent_id !== move.id ||
    asset.upload_purpose !== "game_drawing_payload" ||
    asset.media_type !== "drawing_payload" ||
    asset.expected_media_type !== "drawing_payload" ||
    !asset.storage_path.startsWith(`${move.couple_id}/${move.game_id}/rounds/${move.id}/`) ||
    asset.upload_status !== "finalized" ||
    asset.upload_finalized_at === undefined ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", "game drawing asset is not usable");
  }
  const taken = await ctx.db
    .query("game_moves")
    .withIndex("by_drawing_media_asset_id", (q) => q.eq("drawing_media_asset_id", assetId))
    .first();
  if (taken) uniqueViolation("game_moves_drawing_media_asset_id_unique_idx");
}

/**
 * Sends the drawing. A round in `drawing` moves to `guessing`, the partner's turn starts, and
 * the partner gets a push unless the game is open on their phone. A round the partner already
 * solved live only gets its drawing attached. Both count as the streak activity.
 */
export const submit_drawing = mutation({
  args: { p_round_id: v.string(), p_media_asset_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    const assetId = uuidArg(args.p_media_asset_id);

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "submit_drawing",
        scope: "games",
        request: ["submit_drawing", roundId, assetId],
      }),
      async () => {
        const { move, game } = await requireRound(ctx, userId, roundId);
        if (move.drawer_user_id !== userId) fail("42501", "only the drawer can send the drawing");
        if (move.drawing_media_asset_id !== undefined) fail("23505", "the drawing for this round was already sent");
        await assertDrawingAssetUsable(ctx, userId, move, assetId);

        const now = nowIso();
        const sent = await patchMove(ctx, move, {
          drawing_media_asset_id: assetId,
          drawing_submitted_at: now,
          ...(move.state === "drawing" ? { state: "guessing" as const } : {}),
        });
        if (move.state === "drawing") {
          await patchGame(ctx, game, {
            state: "guessing",
            turn_user_id: move.guesser_user_id,
            turn_started_at: now,
            turn_reminder_sent_at: undefined,
          });
          await enqueueGamePush(ctx, {
            kind: "game_turn_ready",
            game_kind: game.kind,
            couple_id: game.couple_id,
            game_id: game.id,
            round_id: move.id,
            actor_user_id: userId,
            recipient_user_id: move.guesser_user_id,
            dedupe_key: `game_turn_ready:${move.id}`,
            skipIfPresent: true,
          });
        }
        await applyCoupleActivity(ctx, {
          couple_id: game.couple_id,
          user_id: userId,
          couple_day_id: await getOrCreateCoupleDayAt(ctx, game.couple_id, now),
          activity_kind: "game_turn_completed",
          occurred_at: now,
          dedupe_key: `game_turn_completed:${move.id}`,
          metadata: { game_id: game.id, round_id: move.id },
        });
        return { round_id: move.id, round_state: sent.state, drawing_submitted_at: now };
      },
    );
  },
});

/** Records when the guesser first saw the drawing. The first call wins. The speed bonus counts from it. */
export const mark_round_seen = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { move } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (move.guesser_user_id !== userId) fail("42501", "only the guesser can see this drawing");
    if (move.state !== "drawing" && move.state !== "guessing") return { guesser_first_seen_at: orNull(move.guesser_first_seen_at) };
    if (move.guesser_first_seen_at !== undefined) return { guesser_first_seen_at: move.guesser_first_seen_at };
    const now = nowIso();
    await patchMove(ctx, move, { guesser_first_seen_at: now });
    return { guesser_first_seen_at: now };
  },
});

/** The longest solve time the server stores: 30 days. A longer claim is capped, never refused. */
const MAX_STORED_SOLVE_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Stores one attempt. A correct guess solves the round: the points are added, the bonuses
 * apply, and the next turn begins with the guesser as the drawer.
 *
 * The phone sends what the player saw. `p_speed_bonus` is the tier on screen when the guess was
 * made (0, 1, or 2), and `p_solve_ms` is the time since the player first saw the drawing, both on
 * the phone's clock. A guess can reach the server late (offline queue) or before `mark_round_seen`,
 * so the server clock alone would disagree with the screen. When the phone sends a value, the
 * server uses it. When it sends nothing, `scoreSolve` decides.
 *
 * `p_hints_used` counts the letters the phone's hints showed. The phone picks the letters. A
 * correct guess stores the count, and any hint zeroes the speed bonus and the first-try bonus.
 * A wrong guess ignores `p_hints_used`. The first-try bonus is +1 for a correct first attempt.
 *
 * Result: `{ guess_id, correct, round_state, points, speed_bonus, first_try_bonus, hints_used,
 * personal_best, solve_ms, created_at }`. A wrong guess returns zeros, `false`, and a null solve time.
 */
export const submit_guess = mutation({
  args: {
    p_round_id: v.string(),
    p_guess: v.string(),
    p_speed_bonus: v.optional(v.union(v.null(), v.number())),
    p_solve_ms: v.optional(v.union(v.null(), v.number())),
    p_hints_used: v.optional(v.union(v.null(), v.number())),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    const guess = normalizeWordText(args.p_guess);
    if (guess === "" || charLength(guess) > MAX_GUESS_LENGTH) fail("23514", "guess must be 1 to 40 characters");
    const claimedBonus = args.p_speed_bonus ?? null;
    const claimedSolveMs = args.p_solve_ms ?? null;
    const claimedHints = args.p_hints_used ?? null;
    if (claimedBonus !== null && !SPEED_BONUS_CLAIMS.includes(claimedBonus)) {
      fail("23514", "speed bonus must be 0, 1, or 2");
    }
    // A game waits as long as it needs, so a guess after a month away still counts. Only a
    // value that is not a time is refused.
    if (claimedSolveMs !== null && !(Number.isFinite(claimedSolveMs) && claimedSolveMs >= 0)) {
      fail("23514", "solve time must be a number of milliseconds from 0 up");
    }
    if (claimedHints !== null && !(Number.isInteger(claimedHints) && claimedHints >= 0)) {
      fail("23514", "hints used must be a whole number from 0 up");
    }

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "submit_guess",
        scope: "games",
        request: ["submit_guess", roundId, guess, claimedBonus, claimedSolveMs, claimedHints],
      }),
      async () => {
        const { move, game } = await requireRound(ctx, userId, roundId);
        if (move.guesser_user_id !== userId) fail("42501", "only the guesser can guess");
        if (move.state !== "drawing" && move.state !== "guessing") fail("23514", "this round is already finished");

        const now = nowIso();
        const correct = guess === move.word;
        // A hint can reveal at most all letters but one, or the hints would give the word away.
        if (correct && claimedHints !== null && claimedHints > wordLetterCount(move.word) - 1) {
          fail("23514", "hints used is more than the word allows");
        }
        const firstAttempt =
          (await ctx.db.query("game_guesses").withIndex("by_move_id_created_at", (q) => q.eq("move_id", move.id)).first()) === null;
        const guessId = newUuid();
        await ctx.db.insert("game_guesses", {
          id: guessId,
          move_id: move.id,
          couple_id: move.couple_id,
          user_id: userId,
          text: guess,
          correct,
          created_at: now,
        });
        if (!correct) {
          return {
            guess_id: guessId,
            correct,
            round_state: move.state,
            points: 0,
            speed_bonus: 0,
            first_try_bonus: 0,
            hints_used: 0,
            personal_best: false,
            solve_ms: null,
            created_at: now,
          };
        }

        const hintsUsed = claimedHints ?? 0;
        const scored = scoreSolve(move, now);
        const solveMs = claimedSolveMs === null ? scored.solveMs : Math.min(Math.round(claimedSolveMs), MAX_STORED_SOLVE_MS);
        const speedBonus = hintsUsed > 0 ? 0 : (claimedBonus ?? scored.speedBonus);
        const firstTryBonus = hintsUsed === 0 && firstAttempt ? FIRST_TRY_BONUS_POINTS : 0;
        const personalBest =
          hintsUsed === 0 && solveMs !== undefined && isPersonalBest(await getMovesByCouple(ctx, move.couple_id), userId, solveMs);
        await patchMove(ctx, move, {
          state: "solved",
          ended_at: now,
          solve_ms: solveMs,
          speed_bonus: speedBonus,
          first_try_bonus: firstTryBonus,
          hints_used: hintsUsed,
          personal_best: personalBest,
        });
        // The shared total gets the word points. Each partner's total follows the "against each
        // other" rules, so switching the play style later loses nothing.
        const pointsByUser = { ...game.points_by_user };
        pointsByUser[move.drawer_user_id] = (pointsByUser[move.drawer_user_id] ?? 0) + move.points;
        pointsByUser[userId] = (pointsByUser[userId] ?? 0) + move.points + speedBonus + firstTryBonus;
        await beginTurn(ctx, game, userId, { shared_points: game.shared_points + move.points, points_by_user: pointsByUser });
        await enqueueGamePush(ctx, {
          kind: "game_result",
          game_kind: game.kind,
          couple_id: game.couple_id,
          game_id: game.id,
          round_id: move.id,
          actor_user_id: userId,
          recipient_user_id: move.drawer_user_id,
          dedupe_key: `game_result:${move.id}`,
          skipIfPresent: true,
        });
        return {
          guess_id: guessId,
          correct,
          round_state: "solved" as const,
          points: move.points,
          speed_bonus: speedBonus,
          first_try_bonus: firstTryBonus,
          hints_used: hintsUsed,
          personal_best: personalBest,
          solve_ms: solveMs ?? null,
          created_at: now,
        };
      },
    );
  },
});

/** "Show me": the guesser gives up. The round counts as missed, scores nothing, and the guesser draws next. */
export const give_up_round = mutation({
  args: { p_round_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, { kind: "give_up_round", scope: "games", request: ["give_up_round", roundId] }),
      async () => {
        const { move, game } = await requireRound(ctx, userId, roundId);
        if (move.guesser_user_id !== userId) fail("42501", "only the guesser can give up");
        if (move.state !== "drawing" && move.state !== "guessing") fail("23514", "this round is already finished");
        await patchMove(ctx, move, { state: "missed", ended_at: nowIso() });
        await beginTurn(ctx, game, userId);
        return { round_id: move.id, round_state: "missed" as const };
      },
    );
  },
});

// --- After the round: result, reaction, stars -------------------------------

/** A round that ended. Reactions, stars, and the result screen only apply to these. */
function assertFinished(move: GameMove): void {
  if (move.state !== "solved" && move.state !== "missed") fail("23514", "the round is not finished yet");
}

/**
 * Records that the caller dismissed the finished round's result. The caller must be the drawer
 * or the guesser. It sets the caller's own field once and keeps the first time, so a second
 * device or a retry changes nothing. Result: `{ round_id, result_seen_at }`.
 */
export const mark_round_result_seen = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { move } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    assertFinished(move);
    const field =
      move.drawer_user_id === userId ? "drawer_result_seen_at" : move.guesser_user_id === userId ? "guesser_result_seen_at" : null;
    if (field === null) return fail("42501", "only the drawer or the guesser can see this result");
    const seenAt = move[field] ?? nowIso();
    if (move[field] === undefined) await patchMove(ctx, move, { [field]: seenAt });
    return { round_id: move.id, result_seen_at: seenAt };
  },
});

/**
 * The guesser's reaction to a finished round: `love`, `laugh`, `wow`, or null to clear it. The
 * last write wins, setting the same value again changes nothing, and nobody gets a push.
 * Result: `{ round_id, guesser_reaction }`.
 */
export const set_round_reaction = mutation({
  args: { p_round_id: v.string(), p_reaction: v.optional(v.union(v.null(), literals("love", "laugh", "wow"))) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { move } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (move.guesser_user_id !== userId) fail("42501", "only the guesser can react");
    assertFinished(move);
    const reaction = args.p_reaction ?? undefined;
    if (move.guesser_reaction !== reaction) await patchMove(ctx, move, { guesser_reaction: reaction });
    return { round_id: move.id, guesser_reaction: orNull(reaction) };
  },
});

/**
 * Stars or unstars a finished round for the caller. Stars are private: the partner is not told.
 * Setting the current value again changes nothing. Result: `{ round_id, starred }`.
 */
export const set_round_star = mutation({
  args: { p_round_id: v.string(), p_starred: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { move } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    assertFinished(move);
    const existing = await getRoundStar(ctx, move.id, userId);
    if (args.p_starred && !existing) {
      await ctx.db.insert("game_round_stars", {
        couple_id: move.couple_id,
        move_id: move.id,
        user_id: userId,
        round_number: move.round_number,
        created_at: nowIso(),
      });
    } else if (!args.p_starred && existing) {
      await ctx.db.delete(existing._id);
    }
    return { round_id: move.id, starred: args.p_starred };
  },
});

// --- History and records ----------------------------------------------------

/**
 * The couple's finished rounds that hold a drawing, newest first by round number and strictly
 * before `p_before_round_number`. `p_limit` is capped at 50. With `p_starred_only` it returns
 * only the rounds the caller starred. It does not read the clock.
 *
 * Result: `{ rounds, next_before_round_number }`. Pass `next_before_round_number` as the next
 * `p_before_round_number`; it is null when there are no more rounds. Each round has `id`,
 * `round_number`, `drawer_user_id`, `guesser_user_id`, `word`, `difficulty`, `points`, `state`,
 * `drawing_media_asset_id`, `solve_ms`, `speed_bonus`, `first_try_bonus`, `hints_used`,
 * `attempt_count`, `guesser_reaction`, `personal_best`, `starred_by_me`,
 * `started_at`, and `ended_at`.
 */
export const get_draw_and_guess_history = query({
  args: {
    p_starred_only: v.boolean(),
    p_before_round_number: v.optional(v.union(v.null(), v.number())),
    p_limit: v.number(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    if (!Number.isFinite(args.p_limit) || args.p_limit < 1) fail("23514", "limit must be 1 or more");
    const before = args.p_before_round_number ?? Number.MAX_SAFE_INTEGER;
    if (Number.isNaN(before)) fail("23514", "round number cursor must be a number");
    const limit = Math.min(Math.floor(args.p_limit), MAX_HISTORY_PAGE);

    const found: GameMove[] = [];
    let more = false;
    // Takes one round more than the limit to learn whether another page exists.
    const take = (move: GameMove | null): boolean => {
      if (!move || (move.state !== "solved" && move.state !== "missed") || move.drawing_media_asset_id === undefined) return false;
      if (found.length === limit) {
        more = true;
        return true;
      }
      found.push(move);
      return false;
    };
    if (args.p_starred_only) {
      const stars = ctx.db
        .query("game_round_stars")
        .withIndex("by_couple_id_user_id_round_number", (q) =>
          q.eq("couple_id", coupleId).eq("user_id", userId).lt("round_number", before),
        )
        .order("desc");
      for await (const star of stars) {
        if (take(await getByUuid(ctx, "game_moves", star.move_id))) break;
      }
    } else {
      const game = await getGame(ctx, coupleId, "draw_and_guess");
      const moves = game
        ? ctx.db
            .query("game_moves")
            .withIndex("by_game_id_round_number", (q) => q.eq("game_id", game.id).lt("round_number", before))
            .order("desc")
        : null;
      if (moves) {
        for await (const move of moves) {
          if (take(move)) break;
        }
      }
    }

    const rounds = [];
    for (const move of found) {
      rounds.push({
        id: move.id,
        round_number: move.round_number,
        drawer_user_id: move.drawer_user_id,
        guesser_user_id: move.guesser_user_id,
        word: move.word,
        difficulty: move.difficulty,
        points: move.points,
        state: move.state,
        drawing_media_asset_id: move.drawing_media_asset_id!,
        ...roundOutcomeJson(move),
        attempt_count: (await listGuesses(ctx, move.id)).count,
        starred_by_me: (await getRoundStar(ctx, move.id, userId)) !== null,
        started_at: move.started_at,
        ended_at: orNull(move.ended_at),
      });
    }
    return { rounds, next_before_round_number: more ? found[found.length - 1].round_number : null };
  },
});

/**
 * Each partner's numbers, the caller first. It scans the couple's rounds, which is fine for one
 * couple. `solves` counts rounds they solved as the guesser. `first_try_solves` counts the solves
 * that earned the first-try bonus. `average_solve_ms` covers hint-free solves of 10 minutes or
 * less, and `fastest_solve_ms` with `fastest_solve_word` covers every hint-free solve. Both are
 * null with none. `drawings_solved` counts rounds they drew that the partner solved.
 *
 * Result: `{ partners: [{ user_id, solves, first_try_solves, average_solve_ms, fastest_solve_ms,
 * fastest_solve_word, drawings_solved }] }`.
 */
export const get_draw_and_guess_records = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const members = await listActiveMembers(ctx, coupleId);
    const ids = [userId, ...members.map((member) => member.user_id).filter((id) => id !== userId)];
    const moves = await getMovesByCouple(ctx, coupleId);
    return { partners: ids.map((id) => playerRecords(moves, id)) };
  },
});
