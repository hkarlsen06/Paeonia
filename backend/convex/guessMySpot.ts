import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import { dataEpoch, enqueueGamePush, requirePartnerId } from "./lib/games";
import {
  coordinateArg,
  countryCodeArg,
  getCoupleGame,
  haversineMeters,
  isTakenOn,
  newestRounds,
  patchGame,
  PLACE_CITY_MAX,
  placeNameArg,
  pointsFor,
  RESULT_PUSH_DELAY_MS,
  sendDueGuessMySpotReminders,
  type Coordinate,
  type GuessMySpotGame,
  type GuessMySpotRound,
} from "./lib/guessMySpot";
import { roundWithPhoto } from "./lib/gameMediaReferences";
import { newUuid, uuidArg } from "./lib/ids";
import { queueOrphanedMediaAssetForDelete } from "./lib/mediaOrphans";
import { applyCoupleActivity } from "./lib/streaks";
import { addMs, nowIso } from "./lib/time";

// Guess my spot. The rules and decisions are in docs/games/guess-my-spot.md. The tables, the
// scoring, the input rules, and the hooks the shared games code calls are in lib/guessMySpot.ts.

/** The most guessed rounds the history returns. */
const MAX_HISTORY_ROUNDS = 500;

const nullableString = v.optional(v.union(v.null(), v.string()));

// --- Lookups ----------------------------------------------------------------

async function requireRound(ctx: ReaderCtx, userId: string, roundId: string): Promise<{ round: GuessMySpotRound; game: GuessMySpotGame }> {
  const round = await getByUuid(ctx, "guess_my_spot_rounds", roundId);
  const game = round ? await getByUuid(ctx, "guess_my_spot_games", round.game_id) : null;
  if (!round || !game || !(await canAccessCoupleContent(ctx, userId, round.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return { round, game };
}

function requireCoordinate(latitude: number, longitude: number): Coordinate {
  const coordinate = coordinateArg(latitude, longitude);
  if (coordinate === "latitude") return fail("23514", "latitude must be from -90 to 90");
  if (coordinate === "longitude") return fail("23514", "longitude must be from -180 to 180");
  return coordinate!;
}

// --- Reads ------------------------------------------------------------------

/** The real spot, the place name and the date go to the sender, and to the guesser only once the round has a guess. */
function roundJson(round: Omit<GuessMySpotRound, "_id" | "_creationTime">, userId: string) {
  const isSender = round.sender_user_id === userId;
  const shows = isSender || round.guess_latitude !== undefined;
  return {
    id: round.id,
    round_number: round.round_number,
    sender_user_id: round.sender_user_id,
    guesser_user_id: round.guesser_user_id,
    photo_media_asset_id: round.photo_media_asset_id,
    photo_width: orNull(round.photo_width),
    photo_height: orNull(round.photo_height),
    spot_latitude: shows ? round.spot_latitude : null,
    spot_longitude: shows ? round.spot_longitude : null,
    place_name: shows ? orNull(round.place_name) : null,
    place_city: shows ? orNull(round.place_city) : null,
    place_country_code: shows ? orNull(round.place_country_code) : null,
    taken_on: shows ? orNull(round.taken_on) : null,
    sent_at: round.sent_at,
    guess_latitude: orNull(round.guess_latitude),
    guess_longitude: orNull(round.guess_longitude),
    distance_m: orNull(round.distance_m),
    points: orNull(round.points),
    guessed_at: orNull(round.guessed_at),
    my_reveal_seen_at: orNull(isSender ? round.sender_reveal_seen_at : round.guesser_reveal_seen_at),
    /** The same rule `delete_guess_my_spot_round` enforces. */
    can_delete:
      isSender &&
      round.guess_latitude !== undefined &&
      round.deleted_at === undefined &&
      round.sender_reveal_seen_at !== undefined &&
      round.guesser_reveal_seen_at !== undefined,
  };
}

/**
 * Everything the Guess my spot screen shows, for the caller. Subscribe to it. It does not read the clock.
 *
 * Result: `{ user_id, partner_user_id, couple_id, data_epoch, game, current_round, previous_round }`.
 * `game` is null before the first game. `current_round` is the newest round and `previous_round`
 * the one before it, so the phone can show a reveal the caller has not seen while the next round
 * is already sent.
 */
export const get_guess_my_spot = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
    const game = await getCoupleGame(ctx, coupleId);
    const [current, previous] = game ? await newestRounds(ctx, game.id, 2) : [];
    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      data_epoch: dataEpoch(),
      game: game
        ? {
            id: game.id,
            turn_user_id: game.turn_user_id,
            turn_started_at: game.turn_started_at,
            shared_points: game.shared_points,
            my_points: game.points_by_user[userId] ?? 0,
            partner_points: partnerId ? (game.points_by_user[partnerId] ?? 0) : 0,
            round_count: game.round_count,
            version: game.version,
            created_by_user_id: game.created_by_user_id,
            created_at: game.created_at,
            updated_at: game.updated_at,
          }
        : null,
      current_round: current ? roundJson(current, userId) : null,
      previous_round: previous ? roundJson(previous, userId) : null,
    };
  },
});

/**
 * The couple's newest guessed rounds, newest first, for "Our places", and the records.
 *
 * Deleted rounds are left out of `rounds` but still count in the records.
 *
 * Result: `{ rounds, records }`. `records` is `{ shared_points, my_points, partner_points, mine, partner }`, each
 * `{ guesses, closest_m, average_m }` for that partner as the guesser, null before their first guess.
 * ponytail: returns at most 500 rounds with no paging, and the records read every round. A couple
 * plays a few rounds a day. Page by round number and keep running totals on the game row if needed.
 */
export const get_guess_my_spot_history = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const game = await getCoupleGame(ctx, coupleId);
    const none = { guesses: 0, closest_m: null, average_m: null };
    if (!game) {
      return { rounds: [], records: { shared_points: 0, my_points: 0, partner_points: 0, mine: none, partner: none } };
    }
    const all = await ctx.db
      .query("guess_my_spot_rounds")
      .withIndex("by_game_id_round_number", (q) => q.eq("game_id", game.id))
      .order("desc")
      .collect();
    const guessed = all.filter((round) => round.distance_m !== undefined);
    const records = (guesserId: string) => {
      const distances = guessed.filter((round) => round.guesser_user_id === guesserId).map((round) => round.distance_m!);
      if (distances.length === 0) return none;
      return {
        guesses: distances.length,
        closest_m: Math.min(...distances),
        average_m: Math.round(distances.reduce((sum, value) => sum + value, 0) / distances.length),
      };
    };
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? "";
    return {
      rounds: guessed
        .filter((round) => round.deleted_at === undefined)
        .slice(0, MAX_HISTORY_ROUNDS)
        .map((round) => roundJson(round, userId)),
      records: {
        shared_points: game.shared_points,
        my_points: game.points_by_user[userId] ?? 0,
        partner_points: game.points_by_user[partnerId] ?? 0,
        mine: records(userId),
        partner: records(partnerId),
      },
    };
  },
});

// --- The game ---------------------------------------------------------------

/** Makes the couple's game if there is none, with the caller sending first. Returns the game either way. */
export const ensure_guess_my_spot_game = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getCoupleGame(ctx, coupleId);
    if (existing) return { game_id: existing.id, created: false };

    await requirePartnerId(ctx, coupleId, userId);
    const id = newUuid();
    const now = nowIso();
    await ctx.db.insert("guess_my_spot_games", {
      id,
      couple_id: coupleId,
      turn_user_id: userId,
      turn_started_at: now,
      shared_points: 0,
      points_by_user: {},
      round_count: 0,
      version: 1,
      created_by_user_id: userId,
      created_at: now,
      updated_at: now,
    });
    return { game_id: id, created: true };
  },
});

/**
 * Sends the caller's photo as a new round. The photo is the caller's finalized
 * `guess_my_spot_photo` upload reserved for `p_round_id`. `p_round_number` is the round it makes,
 * and a send for a turn that already moved on is refused. The partner guesses next. Counts toward
 * the streak. Queues the turn push, or one push for the guess and this send when the caller
 * guessed the partner's photo less than a minute ago.
 *
 * Result: the new round as `get_guess_my_spot` shows it to the caller.
 */
export const send_guess_my_spot_photo = mutation({
  args: {
    p_round_id: v.string(),
    /** The round number this send makes, so one queued on another phone can't land in a later turn. */
    p_round_number: v.number(),
    p_media_asset_id: v.string(),
    p_latitude: v.number(),
    p_longitude: v.number(),
    p_place_name: nullableString,
    p_place_city: nullableString,
    /** ISO 3166-1 alpha-2, such as `NO`. */
    p_place_country_code: nullableString,
    /** The day the photo was taken, `YYYY-MM-DD`. */
    p_taken_on: nullableString,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    const assetId = uuidArg(args.p_media_asset_id);
    const spot = requireCoordinate(args.p_latitude, args.p_longitude);
    const placeName = placeNameArg(args.p_place_name);
    if (placeName === "invalid") fail("23514", "place name must be 1 to 120 plain characters");
    const placeCity = placeNameArg(args.p_place_city, PLACE_CITY_MAX);
    if (placeCity === "invalid") fail("23514", "place city must be 1 to 80 plain characters");
    const placeCountry = countryCodeArg(args.p_place_country_code);
    if (placeCountry === "invalid") fail("23514", "place country must be a two letter code");
    const takenOn = args.p_taken_on ?? undefined;
    if (takenOn !== undefined && !isTakenOn(takenOn, Date.now())) fail("23514", "taken on must be a date no later than tomorrow");
    // Before the replay check too, so a replay never answers someone who lost access.
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    // A replay answers from the stored round, so the round's own couple must be the caller's
    // current one. Someone who left and joined another couple gets nothing back.
    const existing = await getByUuid(ctx, "guess_my_spot_rounds", roundId);
    if (existing && existing.couple_id !== coupleId) fail("42501", "active entitled game access is required");

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "send_guess_my_spot_photo",
        scope: "games",
        request: [
          "send_guess_my_spot_photo",
          roundId,
          args.p_round_number,
          assetId,
          spot.latitude,
          spot.longitude,
          placeName ?? "",
          placeCity ?? "",
          placeCountry ?? "",
          takenOn ?? "",
        ],
      }),
      async () => {
        const game = await getCoupleGame(ctx, coupleId);
        if (!game) return fail("23514", "the game has not started");
        if (game.turn_user_id !== userId) fail("23514", "it isn't your turn");
        const [newest] = await newestRounds(ctx, game.id, 1);
        if (newest && newest.guess_latitude === undefined) fail("23514", "it isn't your turn");
        if (args.p_round_number !== game.round_count + 1) fail("23514", "this turn already moved on");
        if (await getByUuid(ctx, "guess_my_spot_rounds", roundId)) uniqueViolation("guess_my_spot_rounds_pkey");

        const asset = await getByUuid(ctx, "media_assets", assetId);
        if (!asset || asset.owner_user_id !== userId || asset.couple_id !== coupleId) {
          return fail("42501", "guess my spot photo is not available");
        }
        if (
          asset.upload_purpose !== "guess_my_spot_photo" ||
          asset.reserved_parent_kind !== "guess_my_spot_round" ||
          asset.reserved_parent_id !== roundId ||
          asset.media_type !== "image" ||
          asset.upload_status !== "finalized" ||
          asset.storage_delete_status !== "none" ||
          asset.moderation_status !== "visible" ||
          asset.deleted_at !== undefined
        ) {
          return fail("23514", "guess my spot photo is not usable");
        }
        if (await roundWithPhoto(ctx, assetId)) uniqueViolation("guess_my_spot_rounds_photo_media_asset_id_unique_idx");
        const partnerId = await requirePartnerId(ctx, coupleId, userId);

        const now = nowIso();
        const round = {
          id: roundId,
          game_id: game.id,
          couple_id: coupleId,
          round_number: game.round_count + 1,
          sender_user_id: userId,
          guesser_user_id: partnerId,
          photo_media_asset_id: assetId,
          ...(asset.width !== undefined ? { photo_width: asset.width } : {}),
          ...(asset.height !== undefined ? { photo_height: asset.height } : {}),
          spot_latitude: spot.latitude,
          spot_longitude: spot.longitude,
          ...(placeName !== undefined ? { place_name: placeName } : {}),
          ...(placeCity !== undefined ? { place_city: placeCity } : {}),
          ...(placeCountry !== undefined ? { place_country_code: placeCountry } : {}),
          ...(takenOn !== undefined ? { taken_on: takenOn } : {}),
          sent_at: now,
          created_at: now,
          updated_at: now,
        };
        await ctx.db.insert("guess_my_spot_rounds", round);
        await patchGame(ctx, game, {
          turn_user_id: partnerId,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
          round_count: round.round_number,
        });

        // The partner's round this caller guessed just now still waits on its delayed result push,
        // which drops once this round exists. Name both in this one push.
        const justGuessed =
          newest !== undefined &&
          newest.guessed_at !== undefined &&
          newest.sender_reveal_seen_at === undefined &&
          newest.guessed_at >= addMs(now, -RESULT_PUSH_DELAY_MS);
        await enqueueGamePush(ctx, {
          kind: "game_turn_ready",
          game_kind: "guess_my_spot",
          couple_id: coupleId,
          game_id: game.id,
          round_id: roundId,
          actor_user_id: userId,
          recipient_user_id: partnerId,
          dedupe_key: `game_turn_ready:${roundId}`,
          skipIfPresent: true,
          ...(justGuessed ? { step: "guessed" } : {}),
        });
        await applyCoupleActivity(ctx, {
          couple_id: coupleId,
          user_id: userId,
          couple_day_id: await getOrCreateCoupleDayAt(ctx, coupleId, now),
          activity_kind: "game_turn_completed",
          occurred_at: now,
          dedupe_key: `game_turn_completed:${roundId}:${userId}`,
          metadata: { game_id: game.id, round_id: roundId },
        });
        return roundJson(round, userId);
      },
    );
  },
});

/**
 * The caller's guess for a round that waits for it. Scores it by distance, adds the points to the
 * shared total and to the caller's own total, and starts the caller's turn to send. Queues the result push a minute ahead, so a
 * send in that time sends one push for both.
 *
 * Result: the guessed round with the real spot.
 */
export const submit_guess_my_spot_guess = mutation({
  args: { p_round_id: v.string(), p_latitude: v.number(), p_longitude: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    const guess = requireCoordinate(args.p_latitude, args.p_longitude);
    // Before the replay check too, so a replay never hands the spot to someone who lost access.
    await requireRound(ctx, userId, roundId);

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "submit_guess_my_spot_guess",
        scope: "games",
        request: ["submit_guess_my_spot_guess", roundId, guess.latitude, guess.longitude],
      }),
      async () => {
        const { round, game } = await requireRound(ctx, userId, roundId);
        if (round.guesser_user_id !== userId) fail("42501", "only the guesser can guess this round");
        if (round.guess_latitude !== undefined) fail("23514", "this round already has a guess");

        const now = nowIso();
        const distance = haversineMeters(guess, { latitude: round.spot_latitude, longitude: round.spot_longitude });
        const points = pointsFor(distance);
        const patch = {
          guess_latitude: guess.latitude,
          guess_longitude: guess.longitude,
          distance_m: distance,
          points,
          guessed_at: now,
        };
        await ctx.db.patch(round._id, withUpdatedAt(patch));
        await patchGame(ctx, game, {
          shared_points: game.shared_points + points,
          points_by_user: { ...game.points_by_user, [userId]: (game.points_by_user[userId] ?? 0) + points },
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
        });
        await enqueueGamePush(ctx, {
          kind: "game_result",
          game_kind: "guess_my_spot",
          couple_id: round.couple_id,
          game_id: game.id,
          round_id: round.id,
          actor_user_id: userId,
          recipient_user_id: round.sender_user_id,
          dedupe_key: `game_result:${round.id}`,
          skipIfPresent: true,
          delay_ms: RESULT_PUSH_DELAY_MS,
        });
        return roundJson({ ...round, ...patch }, userId);
      },
    );
  },
});

/** Keeps the first time the caller saw a guessed round's reveal. Safe to repeat. Result: `{ round_id, reveal_seen_at }`. */
export const mark_guess_my_spot_reveal_seen = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { round, game } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (round.guess_latitude === undefined) fail("23514", "the round has no guess yet");
    const field = round.sender_user_id === userId ? "sender_reveal_seen_at" : "guesser_reveal_seen_at";
    const seen = round[field];
    if (seen !== undefined) return { round_id: round.id, reveal_seen_at: seen };

    const now = nowIso();
    await ctx.db.patch(round._id, withUpdatedAt({ [field]: now }));
    await patchGame(ctx, game);
    return { round_id: round.id, reveal_seen_at: now };
  },
});

/**
 * The sender deletes a round from "Our places", for both partners. Only once both have seen its
 * reveal, so no turn or reveal still needs it. The photo is deleted, and the points stay. A repeat
 * returns the same answer.
 *
 * Result: `{ round_id, deleted_at }`.
 */
export const delete_guess_my_spot_round = mutation({
  args: { p_round_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    // Before the replay check too, so a replay never answers someone who lost access.
    await requireRound(ctx, userId, roundId);

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "delete_guess_my_spot_round",
        scope: "games",
        request: ["delete_guess_my_spot_round", roundId],
      }),
      async () => {
        await assertNoPendingAccountDeletion(ctx, userId);
        const { round, game } = await requireRound(ctx, userId, roundId);
        if (round.sender_user_id !== userId) fail("42501", "only the sender can delete this round");
        if (round.deleted_at !== undefined) return { round_id: round.id, deleted_at: round.deleted_at };
        if (round.sender_reveal_seen_at === undefined || round.guesser_reveal_seen_at === undefined) {
          fail("23514", "this round can't be deleted yet");
        }
        const now = nowIso();
        await ctx.db.patch(round._id, withUpdatedAt({ deleted_at: now }));
        await patchGame(ctx, game);
        // After the round's last write, so the sweep sees it deleted.
        await queueOrphanedMediaAssetForDelete(ctx, round.photo_media_asset_id);
        return { round_id: round.id, deleted_at: now };
      },
    );
  },
});

// --- Reminders --------------------------------------------------------------

/** The single reminder for a turn that waited 72 hours. `guessMySpotBackend.sendDueTurnReminders` runs the same code. */
export const send_due_guess_my_spot_reminders = internalMutation({
  args: {},
  handler: async (ctx) => await sendDueGuessMySpotReminders(ctx, nowIso()),
});
