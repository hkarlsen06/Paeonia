import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull } from "./db";
import { fail } from "./errors";
import { pickWordChoices, WORD_DIFFICULTIES, type GameLanguage, type WordChoice, type WordDifficulty } from "./gameWords";
import { enqueueNotificationForUser } from "./notifications";
import { charLength } from "./text";
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
/** A correct guess within `withinMs` of first seeing the drawing earns `points`. Checked in order. */
export const SPEED_BONUS_TIERS = [
  { withinMs: 15_000, points: 2 },
  { withinMs: 30_000, points: 1 },
] as const;
/** The guesser's bonus for a correct first attempt. */
export const FIRST_TRY_BONUS_POINTS = 1;
/** Solves slower than this stay out of the average solve time. */
export const AVERAGE_SOLVE_MAX_MS = 10 * 60_000;
/** The most rounds one history page returns. */
export const MAX_HISTORY_PAGE = 50;
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

/** The most attempts a round returns. Attempts are unlimited, so the oldest ones drop off. */
export const MAX_RETURNED_ATTEMPTS = 200;

/** Every move of a couple, oldest first by index order. Fine at this scale: one couple plays a few rounds a day. */
export async function getMovesByCouple(ctx: ReaderCtx, coupleId: string): Promise<GameMove[]> {
  return await ctx.db
    .query("game_moves")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .collect();
}

/** The newest attempts of a round, oldest first, and the exact number of attempts. */
export async function listGuesses(ctx: ReaderCtx, moveId: string): Promise<{ guesses: Doc<"game_guesses">[]; count: number }> {
  const byMove = () => ctx.db.query("game_guesses").withIndex("by_move_id_created_at", (q) => q.eq("move_id", moveId));
  const newest = await byMove().order("desc").take(MAX_RETURNED_ATTEMPTS + 1);
  // ponytail: counting past the cap reads every attempt of the round. Keep a counter on the round if that gets slow.
  const count = newest.length <= MAX_RETURNED_ATTEMPTS ? newest.length : (await byMove().collect()).length;
  return { guesses: newest.slice(0, MAX_RETURNED_ATTEMPTS).reverse(), count };
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

/** The speed bonus for a solve time: 2 within 15 seconds, 1 within 30, else 0. */
export function speedBonusForSolveMs(solveMs: number): number {
  return SPEED_BONUS_TIERS.find((tier) => solveMs <= tier.withinMs)?.points ?? 0;
}

/**
 * The server's own speed bonus and solve time for a correct guess, used when the phone sent no
 * claim. A guesser who watches live first sees the drawing at the drawer's first stroke, so the
 * clock runs while the partner draws.
 */
export function scoreSolve(
  move: Pick<GameMove, "guesser_first_seen_at">,
  solvedAt: string,
): { speedBonus: number; solveMs: number | undefined } {
  if (move.guesser_first_seen_at === undefined) return { speedBonus: 0, solveMs: undefined };
  const solveMs = Math.max(0, Date.parse(solvedAt) - Date.parse(move.guesser_first_seen_at));
  return { speedBonus: speedBonusForSolveMs(solveMs), solveMs };
}

/** Whether a solve with no hints beat every earlier hint-free solve by the same guesser. Needs at least one earlier one. */
export function isPersonalBest(
  moves: Pick<GameMove, "guesser_user_id" | "state" | "hints_used" | "solve_ms">[],
  guesserId: string,
  solveMs: number,
): boolean {
  const earlier = moves.filter(
    (move) =>
      move.guesser_user_id === guesserId &&
      move.state === "solved" &&
      (move.hints_used ?? 0) === 0 &&
      move.solve_ms !== undefined,
  );
  return earlier.length > 0 && earlier.every((move) => solveMs < move.solve_ms!);
}

/** One player's numbers across the couple's rounds. See `get_draw_and_guess_records`. */
export function playerRecords(moves: GameMove[], userId: string) {
  const solves = moves.filter((move) => move.guesser_user_id === userId && move.state === "solved");
  const timed = solves.filter((move) => (move.hints_used ?? 0) === 0 && move.solve_ms !== undefined);
  const average = timed.filter((move) => move.solve_ms! <= AVERAGE_SOLVE_MAX_MS);
  const fastest = timed.reduce<GameMove | null>((best, move) => (best === null || move.solve_ms! < best.solve_ms! ? move : best), null);
  return {
    user_id: userId,
    solves: solves.length,
    first_try_solves: solves.filter((move) => (move.first_try_bonus ?? 0) > 0).length,
    average_solve_ms: average.length === 0 ? null : Math.round(average.reduce((sum, move) => sum + move.solve_ms!, 0) / average.length),
    fastest_solve_ms: fastest?.solve_ms ?? null,
    fastest_solve_word: fastest?.word ?? null,
    drawings_solved: moves.filter((move) => move.drawer_user_id === userId && move.state === "solved").length,
  };
}

/** The letters of a word without spaces. A guesser can use at most this many minus 1 hints. */
export function wordLetterCount(word: string): number {
  return charLength(word.replaceAll(" ", ""));
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

/**
 * Whether a queued game push still has a reason to go out to `recipientUserId`, checked when the
 * push drain claims it. The recipient must still play in the couple. A turn push needs the round
 * to still wait for this guesser, a reminder needs the reminded turn to still be theirs, and a
 * guessed push needs the solved round to still exist.
 */
export async function gamePushStillWanted(
  ctx: ReaderCtx,
  kind: GamePushKind,
  payload: Record<string, unknown>,
  recipientUserId: string,
): Promise<{ wanted: true } | { wanted: false; reason: "ineligible" | "out_of_date" }> {
  const coupleId = typeof payload.couple_id === "string" ? payload.couple_id : null;
  if (!coupleId || !(await canAccessCoupleContent(ctx, recipientUserId, coupleId))) return { wanted: false, reason: "ineligible" };
  const roundId = typeof payload.round_id === "string" ? payload.round_id : null;
  const gameId = typeof payload.game_id === "string" ? payload.game_id : null;
  let current = true;
  if (kind === "game_turn_ready" || kind === "game_guessed") {
    const move = roundId ? await getByUuid(ctx, "game_moves", roundId) : null;
    current =
      move !== null &&
      (kind === "game_turn_ready"
        ? move.state === "guessing" && move.guesser_user_id === recipientUserId
        : move.state === "solved" && move.drawer_user_id === recipientUserId);
  } else if (kind === "game_turn_reminder") {
    const game = gameId ? await getByUuid(ctx, "games", gameId) : null;
    // A new turn clears turn_reminder_sent_at, so a set value means the reminded turn still waits.
    current = game !== null && game.turn_user_id === recipientUserId && game.turn_reminder_sent_at !== undefined;
  }
  return current ? { wanted: true } : { wanted: false, reason: "out_of_date" };
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

/** The fields of a finished round that history, records, and the result screens share. */
export function roundOutcomeJson(move: GameMove) {
  return {
    solve_ms: orNull(move.solve_ms),
    speed_bonus: move.speed_bonus,
    first_try_bonus: move.first_try_bonus ?? 0,
    hints_used: move.hints_used ?? 0,
    personal_best: move.personal_best ?? false,
    guesser_reaction: orNull(move.guesser_reaction),
  };
}

/** One round with its attempts. `starred_by_me` is the caller's private star. */
export async function roundJson(ctx: ReaderCtx, move: GameMove, userId: string) {
  const { guesses, count } = await listGuesses(ctx, move.id);
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
    ...roundOutcomeJson(move),
    starred_by_me: (await getRoundStar(ctx, move.id, userId)) !== null,
    /** When each partner dismissed the result. The app reads the field for its own role. */
    drawer_result_seen_at: orNull(move.drawer_result_seen_at),
    guesser_result_seen_at: orNull(move.guesser_result_seen_at),
    /** Every attempt of the round. `attempts` holds the newest 200, oldest first. */
    attempt_count: count,
    attempts: guesses.map((guess) => ({
      id: guess.id,
      user_id: guess.user_id,
      text: guess.text,
      correct: guess.correct,
      created_at: guess.created_at,
    })),
  };
}

/** The user's star on a round, if any. */
export async function getRoundStar(ctx: ReaderCtx, moveId: string, userId: string): Promise<Doc<"game_round_stars"> | null> {
  return await ctx.db
    .query("game_round_stars")
    .withIndex("by_move_id_user_id", (q) => q.eq("move_id", moveId).eq("user_id", userId))
    .unique();
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
 * Deletes every game row of a couple: settings, games, rounds, guesses, stars, used
 * words, presence, and invites. Drawing media is queued for deletion by the couple media
 * sweep in `cleanupCoupleContent`.
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
  for (const row of await ctx.db.query("game_round_stars").withIndex("by_couple_id_user_id_round_number", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_used_words").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_presence").withIndex("by_couple_id_kind_user_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  for (const row of await ctx.db.query("game_invites").withIndex("by_couple_id_kind_sender_user_id", (q) => q.eq("couple_id", coupleId)).collect()) await remove(row);
  return deleted;
}
