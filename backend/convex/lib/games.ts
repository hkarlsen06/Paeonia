import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { orNull } from "./db";
import { fail } from "./errors";
import { pickWordChoices, WORD_DIFFICULTIES, type GameLanguage, type WordChoice, type WordDifficulty } from "./gameWords";
import { enqueueNotificationForUser } from "./notifications";
import { addMs, nowIso } from "./time";

// Shared engine helpers for the games tables. The registered functions are in games.ts.

export type GameKind = "draw_and_guess";
export type Game = Doc<"games">;
export type GameMove = Doc<"game_moves">;
export type GameSettings = Doc<"game_settings">;

/** A presence row refreshed within this long counts as "the game screen is open". */
export const PRESENCE_FRESH_MS = 60_000;
/** The cleanup cron deletes presence rows older than this. */
export const PRESENCE_DELETE_AFTER_MS = 2 * 60_000;
/** A correct guess this soon after the guesser first saw the drawing earns the speed bonus. */
export const SPEED_BONUS_WINDOW_MS = 30_000;
export const SPEED_BONUS_POINTS = 1;
export const INVITE_INTERVAL_MS = 15 * 60_000;
export const TURN_REMINDER_AFTER_MS = 72 * 3_600_000;
export const MAX_GUESS_LENGTH = 40;
/** The relay room name suffix for a game. The relay's allowlist must contain it. */
export const GAME_RELAY_CHANNELS: Record<GameKind, string> = { draw_and_guess: "draw_and_guess" };

const DEEP_LINKS: Record<GameKind, string> = { draw_and_guess: "paeonia://games/draw-and-guess" };

// --- Lookups ----------------------------------------------------------------

export async function getGameSettings(ctx: ReaderCtx, coupleId: string): Promise<GameSettings | null> {
  return await ctx.db
    .query("game_settings")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

export async function requireGameSettings(ctx: ReaderCtx, coupleId: string): Promise<GameSettings> {
  const settings = await getGameSettings(ctx, coupleId);
  if (!settings) return fail("23514", "game settings are required");
  return settings;
}

export async function getGame(ctx: ReaderCtx, coupleId: string, kind: GameKind): Promise<Game | null> {
  return await ctx.db
    .query("games")
    .withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId).eq("kind", kind))
    .unique();
}

/** Fails with 42501 unless `userId` is an active, entitled member of the couple. */
export async function requireCoupleAccess(ctx: ReaderCtx, userId: string, coupleId: string): Promise<void> {
  if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
    fail("42501", "active entitled couple access is required");
  }
}

/** The active partner of `userId`. Fails with 23514 when there is none. */
export async function requirePartnerId(ctx: ReaderCtx, coupleId: string, userId: string): Promise<string> {
  const partner = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId);
  if (!partner) return fail("23514", "a game needs two active partners");
  return partner.user_id;
}

export async function getMovesByGame(ctx: ReaderCtx, gameId: string, take: number): Promise<GameMove[]> {
  return await ctx.db
    .query("game_moves")
    .withIndex("by_game_id_round_number", (q) => q.eq("game_id", gameId))
    .order("desc")
    .take(take);
}

export async function listGuesses(ctx: ReaderCtx, moveId: string): Promise<Doc<"game_guesses">[]> {
  return await ctx.db
    .query("game_guesses")
    .withIndex("by_move_id_created_at", (q) => q.eq("move_id", moveId))
    .take(200);
}

// --- Presence ---------------------------------------------------------------

export async function getPresence(
  ctx: ReaderCtx,
  coupleId: string,
  kind: GameKind,
  userId: string,
): Promise<Doc<"game_presence"> | null> {
  return await ctx.db
    .query("game_presence")
    .withIndex("by_couple_id_kind_user_id", (q) => q.eq("couple_id", coupleId).eq("kind", kind).eq("user_id", userId))
    .unique();
}

/** True when the user's game screen refreshed its presence row within `PRESENCE_FRESH_MS`. */
export async function isGamePresent(ctx: ReaderCtx, coupleId: string, kind: GameKind, userId: string): Promise<boolean> {
  const row = await getPresence(ctx, coupleId, kind, userId);
  return row !== null && row.last_seen_at >= addMs(nowIso(), -PRESENCE_FRESH_MS);
}

// --- Words ------------------------------------------------------------------

/**
 * Picks the three words for a turn and marks them as seen. A difficulty whose words
 * were all seen starts over: its used rows are deleted first.
 */
export async function drawWordChoices(
  ctx: WriterCtx,
  game: Pick<Game, "id" | "couple_id">,
  language: GameLanguage,
): Promise<WordChoice[]> {
  const rows = {} as Record<WordDifficulty, Doc<"game_used_words">[]>;
  const used = {} as Record<WordDifficulty, Set<string>>;
  for (const difficulty of WORD_DIFFICULTIES) {
    rows[difficulty] = await ctx.db
      .query("game_used_words")
      .withIndex("by_game_id_language_difficulty", (q) =>
        q.eq("game_id", game.id).eq("language", language).eq("difficulty", difficulty),
      )
      .collect();
    used[difficulty] = new Set(rows[difficulty].map((row) => row.word_id));
  }
  const { choices, reset } = pickWordChoices(language, used);
  for (const difficulty of reset) {
    for (const row of rows[difficulty]) await ctx.db.delete(row._id);
  }
  const now = nowIso();
  for (const choice of choices) {
    await ctx.db.insert("game_used_words", {
      game_id: game.id,
      couple_id: game.couple_id,
      language,
      difficulty: choice.difficulty,
      word_id: choice.word_id,
      created_at: now,
    });
  }
  return choices;
}

// --- Writes -----------------------------------------------------------------

/** Patches a game row and bumps `version`. */
export async function patchGame(ctx: WriterCtx, game: Game, patch: Partial<Omit<Game, "_id" | "_creationTime">>): Promise<Game> {
  const next = { ...patch, version: game.version + 1, updated_at: nowIso() };
  await ctx.db.patch(game._id, next);
  return (await ctx.db.get(game._id))!;
}

export async function patchMove(ctx: WriterCtx, move: GameMove, patch: Partial<Omit<GameMove, "_id" | "_creationTime">>): Promise<GameMove> {
  await ctx.db.patch(move._id, { ...patch, updated_at: nowIso() });
  return (await ctx.db.get(move._id))!;
}

/** Starts a turn for `drawerUserId`: new choices, fresh reminder clock. */
export async function beginTurn(
  ctx: WriterCtx,
  game: Game,
  drawerUserId: string,
  extra: Partial<Omit<Game, "_id" | "_creationTime">> = {},
): Promise<Game> {
  const settings = await requireGameSettings(ctx, game.couple_id);
  return await patchGame(ctx, game, {
    ...extra,
    state: "choosing_word",
    turn_user_id: drawerUserId,
    turn_number: game.turn_number + 1,
    word_choices: await drawWordChoices(ctx, game, settings.language),
    turn_started_at: nowIso(),
    turn_reminder_sent_at: undefined,
  });
}

/**
 * Points for a correct guess. `shared` always gets the word points. The guesser also gets the
 * speed bonus when the guess comes while the partner is still drawing (a live round), or within
 * 30 seconds of first seeing the finished drawing. A guesser who watched live saw the finished
 * drawing when it was sent, so the window starts at the later of the two times.
 */
export function scoreSolve(
  move: Pick<GameMove, "points" | "state" | "guesser_first_seen_at" | "drawing_submitted_at">,
  solvedAt: string,
): { speedBonus: number; solveMs: number | undefined } {
  if (move.guesser_first_seen_at === undefined) {
    return { speedBonus: move.state === "drawing" ? SPEED_BONUS_POINTS : 0, solveMs: undefined };
  }
  const solveMs = Math.max(0, Date.parse(solvedAt) - Date.parse(move.guesser_first_seen_at));
  if (move.state === "drawing") return { speedBonus: SPEED_BONUS_POINTS, solveMs };
  const finishedSeenAt = Math.max(
    Date.parse(move.guesser_first_seen_at),
    move.drawing_submitted_at === undefined ? 0 : Date.parse(move.drawing_submitted_at),
  );
  const sinceFinished = Date.parse(solvedAt) - finishedSeenAt;
  return { speedBonus: sinceFinished <= SPEED_BONUS_WINDOW_MS ? SPEED_BONUS_POINTS : 0, solveMs };
}

// --- Notifications ----------------------------------------------------------

export type GamePushKind = "game_turn_ready" | "game_guessed" | "game_invite" | "game_turn_reminder";

/**
 * Queues one lock-screen-safe push. The payload names the game and the people, never the
 * word or the drawing. `skipIfPresent` drops the push when the recipient has the game open.
 * Returns the number of rows queued.
 */
export async function enqueueGamePush(
  ctx: WriterCtx,
  args: {
    kind: GamePushKind;
    game_kind: GameKind;
    couple_id: string;
    game_id?: string;
    round_id?: string;
    actor_user_id: string;
    recipient_user_id: string;
    dedupe_key: string;
    skipIfPresent?: boolean;
  },
): Promise<number> {
  if (args.skipIfPresent && (await isGamePresent(ctx, args.couple_id, args.game_kind, args.recipient_user_id))) {
    return 0;
  }
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: args.recipient_user_id,
    kind: args.kind,
    payload: {
      type: args.kind,
      game_kind: args.game_kind,
      couple_id: args.couple_id,
      ...(args.game_id ? { game_id: args.game_id } : {}),
      ...(args.round_id ? { round_id: args.round_id } : {}),
      actor_user_id: args.actor_user_id,
      route: "games",
      deeplink: DEEP_LINKS[args.game_kind],
    },
    dedupe_key: args.dedupe_key,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `${args.kind}:${args.couple_id}`,
    scheduled_for: nowIso(),
  });
}

// --- Reads ------------------------------------------------------------------

export function settingsJson(settings: GameSettings) {
  return {
    couple_id: settings.couple_id,
    play_style: settings.play_style,
    language: settings.language,
    updated_by_user_id: settings.updated_by_user_id,
    created_at: settings.created_at,
    updated_at: settings.updated_at,
  };
}

export function gameJson(game: Game, userId: string, partnerId: string | null) {
  return {
    id: game.id,
    kind: game.kind,
    state: game.state,
    turn_user_id: game.turn_user_id,
    turn_number: game.turn_number,
    current_round_id: orNull(game.current_round_id),
    shared_points: game.shared_points,
    my_points: game.points_by_user[userId] ?? 0,
    partner_points: partnerId ? (game.points_by_user[partnerId] ?? 0) : 0,
    turn_started_at: game.turn_started_at,
    version: game.version,
    created_at: game.created_at,
    updated_at: game.updated_at,
  };
}

/** One round with its attempts and the save-prompt state for `userId`. */
export async function roundJson(ctx: ReaderCtx, move: GameMove, userId: string) {
  const guesses = await listGuesses(ctx, move.id);
  const responses = await ctx.db
    .query("game_save_responses")
    .withIndex("by_move_id_user_id", (q) => q.eq("move_id", move.id))
    .collect();
  return {
    id: move.id,
    round_number: move.round_number,
    drawer_user_id: move.drawer_user_id,
    guesser_user_id: move.guesser_user_id,
    state: move.state,
    difficulty: move.difficulty,
    word: move.word,
    points: move.points,
    drawing_media_asset_id: orNull(move.drawing_media_asset_id),
    drawing_submitted_at: orNull(move.drawing_submitted_at),
    started_at: move.started_at,
    guesser_first_seen_at: orNull(move.guesser_first_seen_at),
    ended_at: orNull(move.ended_at),
    solve_ms: orNull(move.solve_ms),
    speed_bonus: move.speed_bonus,
    memory_id: orNull(move.memory_id),
    saved_by_user_id: orNull(move.saved_by_user_id),
    my_save_response: responses.find((row) => row.user_id === userId)?.response ?? null,
    partner_save_response: responses.find((row) => row.user_id !== userId)?.response ?? null,
    attempts: guesses.map((guess) => ({
      id: guess.id,
      user_id: guess.user_id,
      text: guess.text,
      correct: guess.correct,
      created_at: guess.created_at,
    })),
  };
}

// --- Cleanup ----------------------------------------------------------------

/** Deletes the presence rows of a couple. Call when the couple stops being active. */
export async function deleteGamePresenceForCouple(ctx: WriterCtx, coupleId: string): Promise<void> {
  for (const kind of ["draw_and_guess"] as const) {
    const rows = await ctx.db
      .query("game_presence")
      .withIndex("by_couple_id_kind_user_id", (q) => q.eq("couple_id", coupleId).eq("kind", kind))
      .collect();
    for (const row of rows) await ctx.db.delete(row._id);
  }
}

// ponytail: like the rest of the couple cleanup, this runs in one mutation, so a couple with more
// than about 8000 game rows (guesses count) will not finish. Upgrade path: delete in chunks and reschedule.
/**
 * Deletes every game row of a couple: settings, games, rounds, guesses, save answers, used
 * words, presence, and invites. Drawing media is queued for deletion by the couple media
 * sweep in `cleanupCoupleContent`. Memories saved from a game stay ordinary memories.
 */
export async function deleteCoupleGameRows(ctx: WriterCtx, coupleId: string): Promise<number> {
  let deleted = 0;
  const remove = async (row: { _id: Parameters<WriterCtx["db"]["delete"]>[0] }) => {
    await ctx.db.delete(row._id);
    deleted += 1;
  };
  for (const row of await ctx.db.query("game_settings").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("games").withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_moves").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_guesses").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_save_responses").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_used_words").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_presence").withIndex("by_couple_id_kind_user_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_invites").withIndex("by_couple_id_kind_sender_user_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  return deleted;
}
