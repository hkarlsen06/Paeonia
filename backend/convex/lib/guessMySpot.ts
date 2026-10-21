import { defineTable } from "convex/server";
import { v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import { roundWithPhoto } from "./gameMediaReferences";
import type { GameBackend } from "./gameRegistry";
import { enqueueGamePush, isGamePresent, TURN_REMINDER_AFTER_MS, type GamePushKind } from "./games";
import { charLength } from "./text";
import { addMs } from "./time";

// Guess my spot: the tables, the scoring, the input rules, and the hooks the shared games code
// calls (`guessMySpotBackend` at the end). The registered functions are in convex/guessMySpot.ts.
// The rules and decisions are in docs/games/guess-my-spot.md.

export const MAX_POINTS = 5000;
/** Every this many kilometres halves the points. */
export const HALVING_KM = 1500;
export const EARTH_RADIUS_KM = 6371.0088;
/** The verdicts, by the most metres each allows. Further than `CLOSE_METERS` is "now you know where". */
export const SPOT_ON_METERS = 1000;
export const SO_CLOSE_METERS = 25_000;
export const CLOSE_METERS = 300_000;
export const PLACE_NAME_MAX = 120;
export const PLACE_CITY_MAX = 80;
/** The guesser of a round gets one push for a guess and a send made within this long of each other. */
export const RESULT_PUSH_DELAY_MS = 60_000;

// --- Tables -----------------------------------------------------------------

/** Spread into `defineSchema` in schema.ts. */
export const guessMySpotTables = {
  // FK: couple_id -> couples cascade. couple_id is unique. The game never ends.
  guess_my_spot_games: defineTable({
    id: v.string(),
    couple_id: v.string(),
    /** Who acts next: the guesser while the newest round has no guess, the next sender after that. */
    turn_user_id: v.string(),
    turn_started_at: v.string(),
    turn_reminder_sent_at: v.optional(v.string()),
    shared_points: v.number(),
    /** Each partner's points as the guesser, for "against each other". The sender scores nothing. */
    points_by_user: v.record(v.string(), v.number()),
    round_count: v.number(),
    /** Goes up with every change to the game or its rounds, seen marks included. The phone never takes an older one. */
    version: v.number(),
    created_by_user_id: v.string(),
    created_at: v.string(),
    updated_at: v.string(),
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id", ["couple_id"])
    .index("by_turn_reminder_sent_at_turn_started_at", ["turn_reminder_sent_at", "turn_started_at"]),

  // FK: game_id -> guess_my_spot_games cascade; photo_media_asset_id -> media_assets. (game_id, round_number)
  // and photo_media_asset_id are unique. The client makes `id`. The guesser never reads the spot,
  // the place name or the date before `guess_latitude` is set.
  guess_my_spot_rounds: defineTable({
    id: v.string(),
    game_id: v.string(),
    couple_id: v.string(),
    round_number: v.number(),
    sender_user_id: v.string(),
    guesser_user_id: v.string(),
    photo_media_asset_id: v.string(),
    photo_width: v.optional(v.number()),
    photo_height: v.optional(v.number()),
    spot_latitude: v.number(),
    spot_longitude: v.number(),
    place_name: v.optional(v.string()),
    place_city: v.optional(v.string()),
    /** ISO 3166-1 alpha-2, such as `NO`. */
    place_country_code: v.optional(v.string()),
    /** The day the photo was taken, `YYYY-MM-DD`. */
    taken_on: v.optional(v.string()),
    sent_at: v.string(),
    guess_latitude: v.optional(v.number()),
    guess_longitude: v.optional(v.number()),
    distance_m: v.optional(v.number()),
    points: v.optional(v.number()),
    guessed_at: v.optional(v.string()),
    sender_reveal_seen_at: v.optional(v.string()),
    guesser_reveal_seen_at: v.optional(v.string()),
    /** The sender deleted it from "Our places". Its photo is gone, its points stay. */
    deleted_at: v.optional(v.string()),
    created_at: v.string(),
    updated_at: v.string(),
  })
    .index("by_uuid", ["id"])
    .index("by_game_id_round_number", ["game_id", "round_number"])
    .index("by_couple_id", ["couple_id"])
    .index("by_photo_media_asset_id", ["photo_media_asset_id"]),
};

export type GuessMySpotGame = Doc<"guess_my_spot_games">;
export type GuessMySpotRound = Doc<"guess_my_spot_rounds">;
export type Coordinate = { latitude: number; longitude: number };

// --- Scoring ----------------------------------------------------------------

/** The great-circle distance in whole metres (haversine on a sphere). */
export function haversineMeters(a: Coordinate, b: Coordinate): number {
  const rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad;
  const dLng = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * EARTH_RADIUS_KM * 1000 * Math.asin(Math.min(1, Math.sqrt(h))));
}

/** Up to 5000, halving every 1,500 km. */
export function pointsFor(distanceM: number): number {
  return Math.round(MAX_POINTS * 0.5 ** (distanceM / 1000 / HALVING_KM));
}

// --- Input rules ------------------------------------------------------------

/** The coordinate rounded to 6 decimals (about 10 cm), or null when it is out of range. */
export function coordinateArg(latitude: number, longitude: number): Coordinate | null | "latitude" | "longitude" {
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) return "latitude";
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) return "longitude";
  const round = (value: number) => Math.round(value * 1e6) / 1e6;
  return { latitude: round(latitude), longitude: round(longitude) };
}

/** Trimmed with every run of whitespace as one space. Undefined when nothing is left. */
export function placeNameArg(raw: string | null | undefined, max = PLACE_NAME_MAX): string | undefined | "invalid" {
  const name = (raw ?? "").trim().replace(/\s+/g, " ");
  if (name === "") return undefined;
  if (charLength(name) > max || /[\p{Cc}\p{Co}\p{Cn}]/u.test(name)) return "invalid";
  return name;
}

/** Two ASCII capital letters, or undefined for none. */
export function countryCodeArg(raw: string | null | undefined): string | undefined | "invalid" {
  if (raw === null || raw === undefined || raw === "") return undefined;
  return /^[A-Z]{2}$/.test(raw) ? raw : "invalid";
}

/** A real calendar date, `YYYY-MM-DD`, no later than tomorrow in UTC. */
export function isTakenOn(value: string, nowMs: number): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const ms = Date.parse(`${value}T00:00:00.000Z`);
  if (Number.isNaN(ms) || new Date(ms).toISOString().slice(0, 10) !== value) return false;
  return ms <= nowMs + 24 * 3_600_000;
}

// --- Lookups both files share -----------------------------------------------

export async function getCoupleGame(ctx: ReaderCtx, coupleId: string): Promise<GuessMySpotGame | null> {
  return await ctx.db
    .query("guess_my_spot_games")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

/** The newest rounds of a game, newest first. */
export async function newestRounds(ctx: ReaderCtx, gameId: string, count: number): Promise<GuessMySpotRound[]> {
  return await ctx.db
    .query("guess_my_spot_rounds")
    .withIndex("by_game_id_round_number", (q) => q.eq("game_id", gameId))
    .order("desc")
    .take(count);
}

/** Patches a game and bumps its version. */
export async function patchGame(ctx: WriterCtx, game: GuessMySpotGame, patch: Partial<GuessMySpotGame> = {}): Promise<void> {
  await ctx.db.patch(game._id, withUpdatedAt({ ...patch, version: game.version + 1 }));
}

/** A partner reads a round's photo while they can reach the couple's content. */
export async function canReadGuessMySpotPhoto(ctx: ReaderCtx, userId: string, asset: Doc<"media_assets">): Promise<boolean> {
  const round = await roundWithPhoto(ctx, asset.id);
  return (
    round !== null &&
    round.id === asset.reserved_parent_id &&
    round.couple_id === asset.couple_id &&
    (await canAccessCoupleContent(ctx, userId, round.couple_id))
  );
}

// --- Hooks for the shared games code ------------------------------------------

/**
 * A turn push needs its round to still wait for the recipient's guess. A result push needs the
 * sender to not have seen the reveal, to not have the game open, and no next round yet: a send
 * within the delay sent one push for both. A reminder needs the turn it was sent for, which ends
 * when `turn_reminder_sent_at` is cleared.
 */
export async function guessMySpotPushStillWanted(
  ctx: ReaderCtx,
  push: GamePushKind,
  payload: Record<string, unknown>,
  recipientUserId: string,
): Promise<boolean> {
  const round = await getByUuid(ctx, "guess_my_spot_rounds", typeof payload.round_id === "string" ? payload.round_id : null);
  switch (push) {
    case "game_turn_ready":
      if (!round || round.guesser_user_id !== recipientUserId || round.guess_latitude !== undefined) return false;
      // The partner may have opened the game between the send and the delivery.
      return !(await isGamePresent(ctx, round.couple_id, "guess_my_spot", recipientUserId));
    case "game_result": {
      if (!round || round.sender_user_id !== recipientUserId || round.sender_reveal_seen_at !== undefined) return false;
      // The push waited a minute, so the sender may have opened the game since.
      if (await isGamePresent(ctx, round.couple_id, "guess_my_spot", recipientUserId)) return false;
      const next = await ctx.db
        .query("guess_my_spot_rounds")
        .withIndex("by_game_id_round_number", (q) => q.eq("game_id", round.game_id).eq("round_number", round.round_number + 1))
        .first();
      return next === null;
    }
    case "game_turn_reminder": {
      const game = await getByUuid(ctx, "guess_my_spot_games", typeof payload.game_id === "string" ? payload.game_id : null);
      return game !== null && game.turn_user_id === recipientUserId && game.turn_reminder_sent_at !== undefined;
    }
    case "game_invite":
      return true;
  }
}

/**
 * The couple's one game, when it is the user's turn or one of the two newest guessed rounds has a
 * reveal they have not seen. A round its sender deleted has nothing left to see.
 */
export async function guessMySpotWaitingFor(ctx: ReaderCtx, coupleId: string, userId: string): Promise<number> {
  const game = await getCoupleGame(ctx, coupleId);
  if (!game) return 0;
  if (game.turn_user_id === userId) return 1;
  const unseen = (await newestRounds(ctx, game.id, 2)).some(
    (round) =>
      round.guess_latitude !== undefined &&
      round.deleted_at === undefined &&
      ((round.sender_user_id === userId && round.sender_reveal_seen_at === undefined) ||
        (round.guesser_user_id === userId && round.guesser_reveal_seen_at === undefined)),
  );
  return unseen ? 1 : 0;
}

/**
 * Deletes the couple's rows in both tables and returns how many. The photos go with the couple
 * media sweep (lib/relationshipCleanup.ts).
 * ponytail: runs in one mutation like the other couple cleanup. Upgrade path: delete in chunks.
 */
export async function deleteCoupleGuessMySpotRows(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = [
    ...(await ctx.db.query("guess_my_spot_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("guess_my_spot_rounds").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}

/**
 * The single reminder for a turn that waited 72 hours, a guess or a send. `turn_reminder_sent_at`
 * is set before anything else, so a turn never gets two. Returns the pushes queued.
 */
export async function sendDueGuessMySpotReminders(ctx: WriterCtx, now: string): Promise<number> {
  const due = await ctx.db
    .query("guess_my_spot_games")
    .withIndex("by_turn_reminder_sent_at_turn_started_at", (q) =>
      q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS)),
    )
    .take(100);
  let sent = 0;
  for (const game of due) {
    await patchGame(ctx, game, { turn_reminder_sent_at: now });
    if (!(await canAccessCoupleContent(ctx, game.turn_user_id, game.couple_id))) continue;
    const [newest] = await newestRounds(ctx, game.id, 1);
    // The turn is always the newest round's guesser's (to guess it, then to send the next), so the
    // partner who acted last is its sender. Before the first round, it is the other member.
    const actor =
      newest?.sender_user_id ??
      (await listActiveMembers(ctx, game.couple_id)).find((member) => member.user_id !== game.turn_user_id)?.user_id;
    if (!actor) continue;
    sent += await enqueueGamePush(ctx, {
      kind: "game_turn_reminder",
      game_kind: "guess_my_spot",
      couple_id: game.couple_id,
      game_id: game.id,
      ...(newest ? { round_id: newest.id } : {}),
      actor_user_id: actor,
      recipient_user_id: game.turn_user_id,
      dedupe_key: `game_turn_reminder:${game.id}:${game.turn_started_at}`,
    });
  }
  return sent;
}

/** What the shared games code asks of Guess my spot. Registered in `GAME_BACKENDS` (gameRegistry.ts). */
export const guessMySpotBackend: GameBackend = {
  pushStillWanted: guessMySpotPushStillWanted,
  waitingFor: guessMySpotWaitingFor,
  deleteCoupleRows: deleteCoupleGuessMySpotRows,
  sendDueTurnReminders: sendDueGuessMySpotReminders,
};
