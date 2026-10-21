import type { Doc } from "../_generated/dataModel";
import { getEntitledCoupleIdForUser, listActiveMembers } from "./access";
import { findCoupleDayAt, resolveCoupleDayAnchorAt, userLocalDate } from "./coupleDays";
import { instancesOfDay, isLive, visibleAnswersOf } from "./dailyQuestions";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { newestGame as newestMindMeldGame } from "./mindMeld";
import { isSharingNow } from "./locationPause";
import { findProfile } from "./profiles";
import { getCoupleStreakParticipationForDay, readCoupleStreak } from "./streaks";
import { addDaysToDate } from "./time";

// Everything the Lock Screen widgets show, in one read. It carries no question text, answer text,
// message text, or coordinates, because a widget can sit on a locked phone.

const MAX_COUNTDOWNS = 3;
const EARTH_RADIUS_METERS = 6_371_000;

type Coordinates = { latitude: number; longitude: number };

/** Great-circle distance between two coordinates in whole meters (haversine). */
export function distanceMeters(a: Coordinates, b: Coordinates): number {
  const rad = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * rad;
  const dLon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) ** 2;
  return Math.round(2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(h))));
}

async function upcomingCountdowns(ctx: ReaderCtx, coupleId: string, userId: string, now: string) {
  // The phone drops past countdowns by its own clock, so keep yesterday for phones that are behind.
  const earliest = addDaysToDate(await userLocalDate(ctx, userId, now), -1);
  const rows = await ctx.db
    .query("countdowns")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .collect();
  const sorted = rows
    .filter((row) => row.target_date >= earliest)
    .sort((a, b) => (a.target_date !== b.target_date ? (a.target_date < b.target_date ? -1 : 1) : a.id < b.id ? -1 : 1));
  // Yesterday's rows get their own limit, so they never crowd out the upcoming ones.
  const yesterday = sorted.filter((row) => row.target_date === earliest).slice(0, MAX_COUNTDOWNS);
  const upcoming = sorted.filter((row) => row.target_date > earliest).slice(0, MAX_COUNTDOWNS);
  return [...yesterday, ...upcoming]
    .map((row) => ({ id: row.id, title: row.title, target_date: row.target_date, created_at: row.created_at }));
}

/** The distance between the partners, only while both share their location and both have a stored fix. */
async function distanceBetween(ctx: ReaderCtx, coupleId: string, userId: string, partnerId: string) {
  const locations: Doc<"latest_partner_locations">[] = [];
  for (const id of [userId, partnerId]) {
    const preference = await ctx.db
      .query("location_sharing_preferences")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", id))
      .unique();
    if (!isSharingNow(preference)) return null;
    const location = await ctx.db
      .query("latest_partner_locations")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", coupleId).eq("user_id", id))
      .unique();
    if (!location) return null;
    locations.push(location);
  }
  const [mine, theirs] = locations;
  return {
    meters: distanceMeters(mine, theirs),
    as_of: mine.captured_at < theirs.captured_at ? mine.captured_at : theirs.captured_at,
  };
}

/**
 * Whether each partner finished their own daily questions on the day. A partner is done when every
 * live question seeded for them has a visible answer from them. Null when the day has no live question.
 */
async function dailyQuestionState(ctx: ReaderCtx, coupleDayId: string, userId: string, partnerId: string | null) {
  const live = (await instancesOfDay(ctx, coupleDayId)).filter(isLive);
  if (live.length === 0) return null;
  const answered = new Set<string>();
  for (const instance of live) {
    const answers = await visibleAnswersOf(ctx, instance.id);
    if (answers.some((answer) => answer.user_id === instance.seeded_for_user_id)) answered.add(instance.id);
  }
  const done = (id: string | null) => {
    if (id === null) return false;
    const own = live.filter((instance) => instance.seeded_for_user_id === id);
    return own.length > 0 && own.every((instance) => answered.has(instance.id));
  };
  return { me_answered: done(userId), partner_answered: done(partnerId) };
}

type Turn = { kind: string; updated_at: string };

/**
 * The games where the caller is the one to act. Draw & Guess, Story Chain, Exquisite Corpse, Consensio,
 * Guess my spot and the board games store `turn_user_id`. Mind Meld has no turns, so it counts when the partner locked in a
 * word for the open round and the caller has not.
 */
async function myTurnGames(ctx: ReaderCtx, coupleId: string, userId: string): Promise<Turn[]> {
  const turns: Turn[] = [];
  const draw = await ctx.db
    .query("games")
    .withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId).eq("kind", "draw_and_guess"))
    .first();
  if (draw?.turn_user_id === userId) turns.push({ kind: draw.kind, updated_at: draw.updated_at });

  const story = await ctx.db.query("story_chain_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).first();
  if (story?.turn_user_id === userId) turns.push({ kind: "story_chain", updated_at: story.updated_at });

  const corpse = await ctx.db.query("exquisite_corpse_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).first();
  if (corpse?.turn_user_id === userId) turns.push({ kind: "exquisite_corpse", updated_at: corpse.updated_at });

  const consensio = await ctx.db.query("consensio_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).first();
  if (consensio?.turn_user_id === userId) turns.push({ kind: "consensio", updated_at: consensio.updated_at });

  const spot = await ctx.db.query("guess_my_spot_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).first();
  if (spot?.turn_user_id === userId) turns.push({ kind: "guess_my_spot", updated_at: spot.updated_at });

  const boards = await ctx.db.query("board_games").withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId)).collect();
  for (const board of boards) {
    if (board.status === "playing" && board.turn_user_id === userId) turns.push({ kind: board.kind, updated_at: board.updated_at });
  }

  const meld = await newestMindMeldGame(ctx, coupleId);
  if (meld?.state === "playing") {
    const round = await ctx.db
      .query("mind_meld_rounds")
      .withIndex("by_game_id_round_number", (q) => q.eq("game_id", meld.id))
      .order("desc")
      .first();
    if (round?.state === "open") {
      const words = await ctx.db
        .query("mind_meld_words")
        .withIndex("by_round_id_user_id", (q) => q.eq("round_id", round.id))
        .collect();
      if (words.length === 1 && words[0].user_id !== userId) turns.push({ kind: "mind_meld", updated_at: round.updated_at });
    }
  }
  return turns;
}

/** The Lock Screen widget state for `userId` at `now`, or null when they have no active entitled couple. */
export async function readLockScreenState(ctx: ReaderCtx, userId: string, now: string) {
  const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
  if (!coupleId) return null;
  const couple = await getByUuid(ctx, "couples", coupleId);
  const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
  const partnerProfile = partnerId === null ? null : await findProfile(ctx, partnerId);

  // The day row appears with the first activity of the day. Before that, the anchor gives the same window.
  const existingDay = await findCoupleDayAt(ctx, coupleId, now);
  const window = existingDay ?? (await resolveCoupleDayAnchorAt(ctx, coupleId, now));
  const participation = existingDay
    ? await getCoupleStreakParticipationForDay(ctx, coupleId, userId, existingDay.id)
    : { current_user_contributed_today: false, partner_contributed_today: false };
  const streak = await readCoupleStreak(ctx, coupleId, now);

  const turns = (await myTurnGames(ctx, coupleId, userId)).sort((a, b) =>
    a.updated_at < b.updated_at ? 1 : a.updated_at > b.updated_at ? -1 : 0,
  );

  return {
    generated_at: now,
    partner: partnerProfile
      ? { display_name: partnerProfile.display_name ?? null, time_zone_id: partnerProfile.time_zone_id ?? null }
      : null,
    started_on: couple?.started_on ?? null,
    upcoming_countdowns: await upcomingCountdowns(ctx, coupleId, userId, now),
    distance: partnerId === null ? null : await distanceBetween(ctx, coupleId, userId, partnerId),
    couple_day: { local_date: window.local_date, starts_at: window.starts_at, ends_at: window.ends_at },
    streak: {
      current_count: streak.current_count,
      me_active_today: participation.current_user_contributed_today,
      partner_active_today: participation.partner_contributed_today,
    },
    daily_question: existingDay ? await dailyQuestionState(ctx, existingDay.id, userId, partnerId) : null,
    games: { my_turn_count: turns.length, first_my_turn_kind: turns[0]?.kind ?? null },
  };
}
