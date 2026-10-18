import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import {
  catalogTopic,
  drawTopicChoices,
  getCoupleGame,
  isSpot,
  markTopicUsed,
  newestRounds,
  normalizeTopicText,
  OWN_TOPIC_MESSAGES,
  patchGame,
  pointsFor,
  RESULT_PUSH_DELAY_MS,
  sendDueConsensioReminders,
  SPOT_ON_DISTANCE,
  validateOwnTopic,
  type ConsensioGame,
  type ConsensioRound,
  type TopicChoice,
} from "./lib/consensio";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx } from "./lib/db";
import { getByUuid, orNull, withUpdatedAt } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import { dataEpoch, enqueueGamePush, requireGameSettings, requirePartnerId } from "./lib/games";
import { newUuid, uuidArg } from "./lib/ids";
import { applyCoupleActivity } from "./lib/streaks";
import { addMs, nowIso } from "./lib/time";
import { gameLanguage } from "./lib/validators";

// Consensio. The rules and decisions are in docs/games/consensio.md. The tables, the scoring, the
// topics, and the hooks the shared games code calls are in lib/consensio.ts.

/** The most rounds one history page returns. */
const MAX_HISTORY_PAGE = 50;

const nullableString = v.optional(v.union(v.null(), v.string()));

// --- Lookups ----------------------------------------------------------------

async function requireRound(ctx: ReaderCtx, userId: string, roundId: string): Promise<{ round: ConsensioRound; game: ConsensioGame }> {
  const round = await getByUuid(ctx, "consensio_rounds", roundId);
  const game = round ? await getByUuid(ctx, "consensio_games", round.game_id) : null;
  if (!round || !game || !(await canAccessCoupleContent(ctx, userId, round.couple_id))) {
    return fail("42501", "active entitled game access is required");
  }
  return { round, game };
}

// --- Reads ------------------------------------------------------------------

/** The real spot goes to the placer, and to the guesser only once the round has a guess. */
function roundJson(round: Omit<ConsensioRound, "_id" | "_creationTime">, userId: string) {
  const guessed = round.guess !== undefined;
  const isPlacer = round.placer_user_id === userId;
  return {
    id: round.id,
    round_number: round.round_number,
    placer_user_id: round.placer_user_id,
    guesser_user_id: round.guesser_user_id,
    topic_id: orNull(round.topic_id),
    language: orNull(round.language),
    subject: round.subject,
    left_end: round.left_end,
    right_end: round.right_end,
    spot: guessed || isPlacer ? round.spot : null,
    placed_at: round.placed_at,
    guess: orNull(round.guess),
    distance: orNull(round.distance),
    points: orNull(round.points),
    guessed_at: orNull(round.guessed_at),
    my_reveal_seen_at: orNull(isPlacer ? round.placer_reveal_seen_at : round.guesser_reveal_seen_at),
  };
}

/**
 * Everything the Consensio screen shows, for the caller. Subscribe to it. It does not read the clock.
 *
 * Result: `{ user_id, partner_user_id, couple_id, data_epoch, game, current_round, previous_round }`.
 * `game` is null before the first game. `choices` holds the next placer's three topics and is empty
 * for the other partner. `current_round` is the newest round and `previous_round` the one before it,
 * so the phone can show a reveal the caller has not seen while the next round is already placed.
 */
export const get_consensio = query({
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
            choices: game.turn_user_id === userId ? game.choices : [],
            shared_points: game.shared_points,
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
 * The couple's guessed rounds, newest first, and the records. `p_before_round_number` is the cursor,
 * and `next_before_round_number` is null on the last page. The limit is capped at 50.
 *
 * Result: `{ rounds, next_before_round_number, records }`. `records` is `{ shared_points, mine,
 * partner }`, each `{ guesses, spot_ons, average_distance }` for that partner as the guesser, with
 * the average rounded to a whole number and null before their first guess.
 * ponytail: the records read every round of the couple. A couple plays a few rounds a day, so a year
 * is about a thousand small rows. Keep running totals on the game row if this gets slow.
 */
export const get_consensio_history = query({
  args: { p_before_round_number: v.optional(v.union(v.null(), v.number())), p_limit: v.number() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    if (!Number.isFinite(args.p_limit) || args.p_limit < 1) fail("23514", "limit must be 1 or more");
    const before = args.p_before_round_number ?? Number.MAX_SAFE_INTEGER;
    if (Number.isNaN(before)) fail("23514", "round number cursor must be a number");
    const limit = Math.min(Math.floor(args.p_limit), MAX_HISTORY_PAGE);

    const game = await getCoupleGame(ctx, coupleId);
    if (!game) {
      const none = { guesses: 0, spot_ons: 0, average_distance: null };
      return { rounds: [], next_before_round_number: null, records: { shared_points: 0, mine: none, partner: none } };
    }
    const all = await ctx.db
      .query("consensio_rounds")
      .withIndex("by_game_id_round_number", (q) => q.eq("game_id", game.id))
      .order("desc")
      .collect();
    const guessed = all.filter((round) => round.guess !== undefined);
    const page = guessed.filter((round) => round.round_number < before);

    const records = (guesserId: string) => {
      const mine = guessed.filter((round) => round.guesser_user_id === guesserId);
      const total = mine.reduce((sum, round) => sum + (round.distance ?? 0), 0);
      return {
        guesses: mine.length,
        spot_ons: mine.filter((round) => (round.distance ?? Infinity) <= SPOT_ON_DISTANCE).length,
        average_distance: mine.length > 0 ? Math.round(total / mine.length) : null,
      };
    };
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? "";
    const rounds = page.slice(0, limit).map((round) => roundJson(round, userId));
    return {
      rounds,
      next_before_round_number: page.length > limit ? rounds[rounds.length - 1].round_number : null,
      records: { shared_points: game.shared_points, mine: records(userId), partner: records(partnerId) },
    };
  },
});

// --- The game ---------------------------------------------------------------

/** Makes the couple's game if there is none, with the caller placing first. Returns the game either way. */
export const ensure_consensio_game = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getCoupleGame(ctx, coupleId);
    if (existing) return { game_id: existing.id, created: false };

    await requirePartnerId(ctx, coupleId, userId);
    const settings = await requireGameSettings(ctx, coupleId);
    const id = newUuid();
    const now = nowIso();
    await ctx.db.insert("consensio_games", {
      id,
      couple_id: coupleId,
      turn_user_id: userId,
      turn_started_at: now,
      choices: await drawTopicChoices(ctx, coupleId, settings.language),
      shared_points: 0,
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
 * Places the caller's marker on a new round. The topic is a catalog topic (`p_topic_id` with
 * `p_topic_language`, any topic of that catalog) or the caller's own (`p_subject`, `p_left_end`,
 * `p_right_end`). `p_round_number` is the round it makes, and a placement for a turn that already
 * moved on is refused. The partner guesses next and gets three topics for their own next placement.
 * Counts toward the streak. Queues the turn push, or one push for the guess and this placement when
 * the caller guessed the partner's marker less than 5 minutes ago.
 *
 * Result: the new round as `get_consensio` shows it to the caller.
 */
export const place_consensio_spot = mutation({
  args: {
    p_round_id: v.string(),
    p_topic_id: nullableString,
    p_topic_language: v.optional(v.union(v.null(), gameLanguage)),
    p_subject: nullableString,
    p_left_end: nullableString,
    p_right_end: nullableString,
    p_spot: v.number(),
    /** The round number this placement makes, so one queued on another phone can't land in a later turn. */
    p_round_number: v.number(),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    if (!isSpot(args.p_spot)) fail("23514", "spot must be a whole number from 0 to 100");
    // Before the replay check too, so a replay never answers someone who lost access.
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    // The request names a catalog topic by id, so an edit of the catalog never changes a retry.
    const own = args.p_topic_id
      ? null
      : {
          subject: normalizeTopicText(args.p_subject ?? ""),
          left_end: normalizeTopicText(args.p_left_end ?? ""),
          right_end: normalizeTopicText(args.p_right_end ?? ""),
        };
    if (own) {
      const problem = validateOwnTopic(own.subject, own.left_end, own.right_end);
      if (problem) fail("23514", OWN_TOPIC_MESSAGES[problem]);
    }

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "place_consensio_spot",
        scope: "games",
        request: own
          ? ["place_consensio_spot", roundId, own.subject, own.left_end, own.right_end, args.p_spot, args.p_round_number]
          : ["place_consensio_spot", roundId, args.p_topic_id, args.p_topic_language ?? "", args.p_spot, args.p_round_number],
      }),
      async () => {
        let topic: TopicChoice | { subject: string; left_end: string; right_end: string };
        if (own) {
          topic = own;
        } else {
          const found = args.p_topic_language ? catalogTopic(args.p_topic_language, args.p_topic_id ?? "") : null;
          if (!found) return fail("23514", "topic is not available");
          topic = found;
        }
        const game = await getCoupleGame(ctx, coupleId);
        if (!game) return fail("23514", "the game has not started");
        if (game.turn_user_id !== userId) fail("23514", "it isn't your turn");
        const [newest] = await newestRounds(ctx, game.id, 1);
        if (newest && newest.guess === undefined) fail("23514", "it isn't your turn");
        if (args.p_round_number !== game.round_count + 1) fail("23514", "this turn already moved on");
        if (await getByUuid(ctx, "consensio_rounds", roundId)) uniqueViolation("consensio_rounds_pkey");
        const partnerId = await requirePartnerId(ctx, coupleId, userId);
        const settings = await requireGameSettings(ctx, coupleId);

        const now = nowIso();
        const round = {
          id: roundId,
          game_id: game.id,
          couple_id: coupleId,
          round_number: game.round_count + 1,
          placer_user_id: userId,
          guesser_user_id: partnerId,
          ...("topic_id" in topic ? { topic_id: topic.topic_id, language: topic.language } : {}),
          subject: topic.subject,
          left_end: topic.left_end,
          right_end: topic.right_end,
          spot: args.p_spot,
          placed_at: now,
          created_at: now,
          updated_at: now,
        };
        await ctx.db.insert("consensio_rounds", round);
        if ("topic_id" in topic) await markTopicUsed(ctx, coupleId, topic.language, topic.topic_id);
        await patchGame(ctx, game, {
          turn_user_id: partnerId,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
          choices: await drawTopicChoices(ctx, coupleId, settings.language),
          round_count: round.round_number,
        });

        // The partner's round this caller guessed just now still waits on its delayed result push,
        // which drops once this round exists. Name both in this one push.
        const justGuessed =
          newest !== undefined &&
          newest.guessed_at !== undefined &&
          newest.placer_reveal_seen_at === undefined &&
          newest.guessed_at >= addMs(now, -RESULT_PUSH_DELAY_MS);
        await enqueueGamePush(ctx, {
          kind: "game_turn_ready",
          game_kind: "consensio",
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
 * The caller's guess for a round that waits for it. Scores it, adds the points to the shared total,
 * and starts the caller's turn to place. Queues the result push 5 minutes ahead, so a placement in
 * that time sends one push for both.
 *
 * Result: the guessed round with the real spot.
 */
export const guess_consensio_spot = mutation({
  args: { p_round_id: v.string(), p_guess: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const roundId = uuidArg(args.p_round_id);
    if (!isSpot(args.p_guess)) fail("23514", "guess must be a whole number from 0 to 100");
    // Before the replay check too, so a replay never hands the spot to someone who lost access.
    await requireRound(ctx, userId, roundId);

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "guess_consensio_spot",
        scope: "games",
        request: ["guess_consensio_spot", roundId, args.p_guess],
      }),
      async () => {
        const { round, game } = await requireRound(ctx, userId, roundId);
        if (round.guesser_user_id !== userId) fail("42501", "only the guesser can guess this round");
        if (round.guess !== undefined) fail("23514", "this round already has a guess");

        const now = nowIso();
        const distance = Math.abs(args.p_guess - round.spot);
        const points = pointsFor(distance);
        const patch = { guess: args.p_guess, distance, points, guessed_at: now };
        await ctx.db.patch(round._id, withUpdatedAt(patch));
        await patchGame(ctx, game, {
          shared_points: game.shared_points + points,
          turn_started_at: now,
          turn_reminder_sent_at: undefined,
        });
        await enqueueGamePush(ctx, {
          kind: "game_result",
          game_kind: "consensio",
          couple_id: round.couple_id,
          game_id: game.id,
          round_id: round.id,
          actor_user_id: userId,
          recipient_user_id: round.placer_user_id,
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
export const mark_consensio_reveal_seen = mutation({
  args: { p_round_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const { round, game } = await requireRound(ctx, userId, uuidArg(args.p_round_id));
    if (round.guess === undefined) fail("23514", "the round has no guess yet");
    const field = round.placer_user_id === userId ? "placer_reveal_seen_at" : "guesser_reveal_seen_at";
    const seen = round[field];
    if (seen !== undefined) return { round_id: round.id, reveal_seen_at: seen };

    const now = nowIso();
    await ctx.db.patch(round._id, withUpdatedAt({ [field]: now }));
    await patchGame(ctx, game);
    return { round_id: round.id, reveal_seen_at: now };
  },
});

// --- Reminders --------------------------------------------------------------

/** The single reminder for a turn that waited 72 hours. `consensioBackend.sendDueTurnReminders` runs the same code. */
export const send_due_consensio_reminders = internalMutation({
  args: {},
  handler: async (ctx) => await sendDueConsensioReminders(ctx, nowIso()),
});
