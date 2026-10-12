import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import { DIFFICULTY_POINTS, normalizeCustomWord, normalizeWordText } from "./lib/gameWords";
import {
  beginTurn,
  drawWordChoices,
  enqueueGamePush,
  gameJson,
  GAME_RELAY_CHANNELS,
  getGame,
  getGameSettings,
  getMovesByGame,
  getPresence,
  INVITE_INTERVAL_MS,
  MAX_GUESS_LENGTH,
  patchGame,
  patchMove,
  PRESENCE_DELETE_AFTER_MS,
  requireGameSettings,
  requirePartnerId,
  roundJson,
  scoreSolve,
  settingsJson,
  SPEED_BONUS_POINTS,
  TURN_REMINDER_AFTER_MS,
  type Game,
  type GameMove,
} from "./lib/games";
import { newUuid, dateArg, uuidArg } from "./lib/ids";
import { signLiveTicket } from "./lib/liveTicket";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { applyCoupleActivity } from "./lib/streaks";
import { charLength } from "./lib/text";
import { addMs, nowIso } from "./lib/time";
import { gameLanguage, gamePlayStyle, literals } from "./lib/validators";
import { attachMemoryMediaAssets, insertMemory } from "./memories";

// Games. Draw & Guess is the only game so far. The rules and decisions are in
// docs/games-plan.md and docs/games/draw-and-guess.md. Helpers are in lib/games.ts.

const gameKind = v.literal("draw_and_guess");
const nullableString = v.optional(v.union(v.null(), v.string()));

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

// --- Settings ---------------------------------------------------------------

export const get_game_settings = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const settings = await getGameSettings(ctx, coupleId);
    return settings ? settingsJson(settings) : null;
  },
});

/** Sets the couple's play style and game language. Either partner may call it, and the last write wins. */
export const set_game_settings = mutation({
  args: { p_play_style: gamePlayStyle, p_language: gameLanguage },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const now = nowIso();
    const existing = await getGameSettings(ctx, coupleId);
    if (existing) {
      await ctx.db.patch(existing._id, {
        play_style: args.p_play_style,
        language: args.p_language,
        updated_by_user_id: userId,
        updated_at: now,
      });
      if (existing.language !== args.p_language) {
        // Words already offered for the open turn come from the old language.
        const game = await getGame(ctx, coupleId, "draw_and_guess");
        if (game?.state === "choosing_word") {
          await patchGame(ctx, game, { word_choices: await drawWordChoices(ctx, game, args.p_language) });
        }
      }
    } else {
      await ctx.db.insert("game_settings", {
        couple_id: coupleId,
        play_style: args.p_play_style,
        language: args.p_language,
        updated_by_user_id: userId,
        created_at: now,
        updated_at: now,
      });
    }
    return settingsJson((await getGameSettings(ctx, coupleId))!);
  },
});

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
 * `ensure_draw_and_guess_game`. It does not read the clock: `partner_last_seen_at` and
 * `last_invite_at` are timestamps, and the app decides what counts as recent.
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
    const mine = await getPresence(ctx, coupleId, "draw_and_guess", userId);
    const theirs = partnerId ? await getPresence(ctx, coupleId, "draw_and_guess", partnerId) : null;

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
      my_last_seen_at: orNull(mine?.last_seen_at),
      partner_last_seen_at: orNull(theirs?.last_seen_at),
      last_invite_at: orNull(invite?.sent_at),
    };
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

/** The longest solve time a phone may report: 30 days. */
const MAX_CLAIMED_SOLVE_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Stores one attempt. A correct guess solves the round: the points are added, the speed
 * bonus applies, and the next turn begins with the guesser as the drawer.
 *
 * The phone sends what the player saw: `p_speed_bonus` says whether the bonus was still on
 * screen when the guess was made, and `p_solve_ms` is the time since the player first saw the
 * drawing, both on the phone's clock. A guess can reach the server late (offline queue) or
 * before `mark_round_seen`, so the server clock alone would disagree with the screen. When the
 * phone sends a value, the server uses it. When it sends nothing, `scoreSolve` decides.
 */
export const submit_guess = mutation({
  args: {
    p_round_id: v.string(),
    p_guess: v.string(),
    p_speed_bonus: v.optional(v.union(v.null(), v.boolean())),
    p_solve_ms: v.optional(v.union(v.null(), v.number())),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    const guess = normalizeWordText(args.p_guess);
    if (guess === "" || charLength(guess) > MAX_GUESS_LENGTH) fail("23514", "guess must be 1 to 40 characters");
    const claimedBonus = args.p_speed_bonus ?? null;
    const claimedSolveMs = args.p_solve_ms ?? null;
    if (claimedSolveMs !== null && !(Number.isFinite(claimedSolveMs) && claimedSolveMs >= 0 && claimedSolveMs <= MAX_CLAIMED_SOLVE_MS)) {
      fail("23514", "solve time must be between 0 and 30 days");
    }

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, { kind: "submit_guess", scope: "games", request: ["submit_guess", roundId, guess, claimedBonus, claimedSolveMs] }),
      async () => {
        const { move, game } = await requireRound(ctx, userId, roundId);
        if (move.guesser_user_id !== userId) fail("42501", "only the guesser can guess");
        if (move.state !== "drawing" && move.state !== "guessing") fail("23514", "this round is already finished");

        const now = nowIso();
        const correct = guess === move.word;
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
          return { guess_id: guessId, correct, round_state: move.state, points: 0, speed_bonus: 0, solve_ms: null, created_at: now };
        }

        const scored = scoreSolve(move, now);
        const speedBonus = claimedBonus === null ? scored.speedBonus : claimedBonus ? SPEED_BONUS_POINTS : 0;
        const solveMs = claimedSolveMs === null ? scored.solveMs : Math.round(claimedSolveMs);
        await patchMove(ctx, move, { state: "solved", ended_at: now, solve_ms: solveMs, speed_bonus: speedBonus });
        // The shared total gets the word points. Each partner's total follows the "against each
        // other" rules, so switching the play style later loses nothing.
        const pointsByUser = { ...game.points_by_user };
        pointsByUser[move.drawer_user_id] = (pointsByUser[move.drawer_user_id] ?? 0) + move.points;
        pointsByUser[userId] = (pointsByUser[userId] ?? 0) + move.points + speedBonus;
        await beginTurn(ctx, game, userId, { shared_points: game.shared_points + move.points, points_by_user: pointsByUser });
        await enqueueGamePush(ctx, {
          kind: "game_guessed",
          game_kind: game.kind,
          couple_id: game.couple_id,
          game_id: game.id,
          round_id: move.id,
          actor_user_id: userId,
          recipient_user_id: move.drawer_user_id,
          dedupe_key: `game_guessed:${move.id}`,
          skipIfPresent: true,
        });
        return {
          guess_id: guessId,
          correct,
          round_state: "solved" as const,
          points: move.points,
          speed_bonus: speedBonus,
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

// --- Save to Memories -------------------------------------------------------

/** "Not now" for the caller only. The partner's prompt stays open. */
export const respond_save_prompt = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { move } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (move.state !== "solved" && move.state !== "missed") fail("23514", "the round is not finished yet");
    const existing = await ctx.db
      .query("game_save_responses")
      .withIndex("by_move_id_user_id", (q) => q.eq("move_id", move.id).eq("user_id", userId))
      .unique();
    if (!existing) {
      await ctx.db.insert("game_save_responses", {
        move_id: move.id,
        couple_id: move.couple_id,
        user_id: userId,
        response: "not_now",
        created_at: nowIso(),
      });
    }
    return null;
  },
});

/**
 * Saves a finished round as a memory titled with the word. The phone renders the drawing
 * to an image and uploads it first (purpose `memory_photo`, parent kind `memory_media`, parent
 * id = a new memory media id). A round is saved at most once: when both partners say yes at
 * the same time, the second call gets the first memory back and its image is queued for deletion.
 */
export const save_round_to_memories = mutation({
  args: {
    p_round_id: v.string(),
    p_memory_id: v.string(),
    p_media_asset_id: v.string(),
    p_memory_date: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const memoryId = uuidArg(args.p_memory_id);
    const assetId = uuidArg(args.p_media_asset_id);
    const memoryDate = dateArg(args.p_memory_date);
    const { move } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (move.state !== "solved" && move.state !== "missed") fail("23514", "the round is not finished yet");

    if (move.memory_id !== undefined) {
      const asset = await getByUuid(ctx, "media_assets", assetId);
      if (asset && asset.owner_user_id === userId && asset.couple_id === move.couple_id) {
        await queueOrphanedMediaAssetForDelete(ctx, assetId);
      }
      return { memory_id: move.memory_id, created: false };
    }

    const title = move.word.charAt(0).toLocaleUpperCase() + move.word.slice(1);
    await insertMemory(ctx, {
      id: memoryId,
      couple_id: move.couple_id,
      title,
      memory_date: memoryDate,
      created_by_user_id: userId,
      last_edited_by_user_id: userId,
    });
    await attachMemoryMediaAssets(ctx, userId, memoryId, [assetId]);
    await patchMove(ctx, move, { memory_id: memoryId, saved_by_user_id: userId });
    return { memory_id: memoryId, created: true };
  },
});

// --- Play together ----------------------------------------------------------

/** "Tell [Name] you want to play". One invite per sender per game every 15 minutes. */
export const send_game_invite = mutation({
  args: { p_kind: gameKind },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await requirePartnerId(ctx, coupleId, userId);
    const now = nowIso();
    const previous = await ctx.db
      .query("game_invites")
      .withIndex("by_couple_id_kind_sender_user_id", (q) =>
        q.eq("couple_id", coupleId).eq("kind", args.p_kind).eq("sender_user_id", userId),
      )
      .unique();
    if (previous && previous.sent_at > addMs(now, -INVITE_INTERVAL_MS)) {
      fail("53300", "you can send one invite every 15 minutes");
    }
    if (previous) {
      await ctx.db.patch(previous._id, { sent_at: now });
    } else {
      await ctx.db.insert("game_invites", { couple_id: coupleId, kind: args.p_kind, sender_user_id: userId, sent_at: now });
    }
    const game = await getGame(ctx, coupleId, args.p_kind);
    await enqueueGamePush(ctx, {
      kind: "game_invite",
      game_kind: args.p_kind,
      couple_id: coupleId,
      game_id: game?.id,
      actor_user_id: userId,
      recipient_user_id: partnerId,
      dedupe_key: `game_invite:${coupleId}:${userId}:${now}`,
    });
    return { sent_at: now };
  },
});

/**
 * The open game screen. The app sends `true` when the screen opens and every 30 seconds
 * after, and `false` when it closes. A row older than 60 seconds counts as gone.
 */
export const set_game_presence = mutation({
  args: { p_kind: gameKind, p_present: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getPresence(ctx, coupleId, args.p_kind, userId);
    if (!args.p_present) {
      if (existing) await ctx.db.delete(existing._id);
      return null;
    }
    const now = nowIso();
    if (existing) {
      await ctx.db.patch(existing._id, { last_seen_at: now });
    } else {
      await ctx.db.insert("game_presence", { couple_id: coupleId, kind: args.p_kind, user_id: userId, last_seen_at: now });
    }
    return null;
  },
});

/**
 * A 60-second ticket for the game's own relay room (`<couple>:draw_and_guess`), so game
 * sockets do not share the widget canvas room. Returns null while the relay is not configured.
 */
export const create_game_live_ticket = mutation({
  args: { p_kind: gameKind },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    return await signLiveTicket({ coupleId, userId, channel: GAME_RELAY_CHANNELS[args.p_kind] });
  },
});

// --- Cron jobs --------------------------------------------------------------

/** Deletes presence rows the app stopped refreshing, such as a phone that lost power. */
export const cleanup_stale_game_presence = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = addMs(nowIso(), -PRESENCE_DELETE_AFTER_MS);
    const stale = await ctx.db
      .query("game_presence")
      .withIndex("by_last_seen_at", (q) => q.lt("last_seen_at", cutoff))
      .take(200);
    for (const row of stale) await ctx.db.delete(row._id);
    return stale.length;
  },
});

/**
 * The single reminder for a turn that waited 72 hours. `turn_reminder_sent_at` is set before
 * anything else and cleared only when a new turn begins, so a move never gets two reminders.
 */
export const send_due_game_turn_reminders = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = nowIso();
    const due = await ctx.db
      .query("games")
      .withIndex("by_turn_reminder_sent_at_turn_started_at", (q) =>
        q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS)),
      )
      .take(100);
    let sent = 0;
    for (const game of due) {
      await ctx.db.patch(game._id, { turn_reminder_sent_at: now });
      if (!(await canAccessCoupleContent(ctx, game.turn_user_id, game.couple_id))) continue;
      const waiting = (await listActiveMembers(ctx, game.couple_id)).find((member) => member.user_id !== game.turn_user_id);
      sent += await enqueueGamePush(ctx, {
        kind: "game_turn_reminder",
        game_kind: game.kind,
        couple_id: game.couple_id,
        game_id: game.id,
        actor_user_id: waiting?.user_id ?? game.turn_user_id,
        recipient_user_id: game.turn_user_id,
        dedupe_key: `game_turn_reminder:${game.id}:${game.turn_started_at}`,
      });
    }
    return sent;
  },
});
