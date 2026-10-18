import { defineTable } from "convex/server";
import { v } from "convex/values";
import enTopics from "../../games/consensio/en.json";
import nbTopics from "../../games/consensio/nb.json";
import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import type { GameBackend } from "./gameRegistry";
import type { GameLanguage } from "./gameWords";
import { enqueueGamePush, isGamePresent, TURN_REMINDER_AFTER_MS, type GamePushKind } from "./games";
import { charLength } from "./text";
import { addMs, nowIso } from "./time";
import { gameLanguage } from "./validators";

// Consensio: the tables, the scoring, the topics, and the hooks the shared games code calls
// (`consensioBackend` at the end). The registered functions are in convex/consensio.ts.
// The rules and decisions are in docs/games/consensio.md.

export const MAX_SPOT = 100;
export const SUBJECT_LENGTH = { min: 2, max: 60 } as const;
export const END_LENGTH = { min: 1, max: 24 } as const;
/** A guess this close to the spot is spot on. */
export const SPOT_ON_DISTANCE = 3;
/** The placer gets one push for a guess and a placement made within this long of each other. */
export const RESULT_PUSH_DELAY_MS = 5 * 60_000;
export const CHOICE_COUNT = 3;

// --- Tables -----------------------------------------------------------------

const topicChoice = v.object({
  topic_id: v.string(),
  language: gameLanguage,
  subject: v.string(),
  left_end: v.string(),
  right_end: v.string(),
});

/** Spread into `defineSchema` in schema.ts. */
export const consensioTables = {
  // FK: couple_id -> couples cascade. couple_id is unique. The game never ends.
  consensio_games: defineTable({
    id: v.string(),
    couple_id: v.string(),
    /** Who acts next: the guesser while the newest round has no guess, the next placer after that. */
    turn_user_id: v.string(),
    turn_started_at: v.string(),
    turn_reminder_sent_at: v.optional(v.string()),
    /** The next placer's three topics. Only `turn_user_id` reads them. */
    choices: v.array(topicChoice),
    shared_points: v.number(),
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

  // FK: game_id -> consensio_games cascade. (game_id, round_number) is unique. The client makes `id`.
  // The guesser never reads `spot` before `guess` is set.
  consensio_rounds: defineTable({
    id: v.string(),
    game_id: v.string(),
    couple_id: v.string(),
    round_number: v.number(),
    placer_user_id: v.string(),
    guesser_user_id: v.string(),
    /** The catalog topic, or none for a topic the placer wrote. The text is stored, so a catalog edit never changes a round. */
    topic_id: v.optional(v.string()),
    language: v.optional(gameLanguage),
    subject: v.string(),
    left_end: v.string(),
    right_end: v.string(),
    spot: v.number(),
    placed_at: v.string(),
    guess: v.optional(v.number()),
    distance: v.optional(v.number()),
    points: v.optional(v.number()),
    guessed_at: v.optional(v.string()),
    placer_reveal_seen_at: v.optional(v.string()),
    guesser_reveal_seen_at: v.optional(v.string()),
    created_at: v.string(),
    updated_at: v.string(),
  })
    .index("by_uuid", ["id"])
    .index("by_game_id_round_number", ["game_id", "round_number"])
    .index("by_couple_id", ["couple_id"]),

  // The catalog topics a couple has placed, per language. A language starts over when all were used.
  consensio_used_topics: defineTable({
    couple_id: v.string(),
    language: gameLanguage,
    topic_id: v.string(),
    created_at: v.string(),
  }).index("by_couple_id_language", ["couple_id", "language"]),
};

export type ConsensioGame = Doc<"consensio_games">;
export type ConsensioRound = Doc<"consensio_rounds">;
export type TopicChoice = { topic_id: string; language: GameLanguage; subject: string; left_end: string; right_end: string };

// --- Scoring ----------------------------------------------------------------

/** One point less for every 4 positions off: 5 for 0 to 3 off, 0 from 20 off. */
export function pointsFor(distance: number): number {
  return Math.max(0, 5 - Math.floor(distance / 4));
}

/** True for a whole number from 0 to 100. */
export function isSpot(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= MAX_SPOT;
}

// --- Topics -----------------------------------------------------------------

export type CatalogTopic = { id: string; subject: string; left: string; right: string };
type TopicCatalog = { language: GameLanguage; topics: CatalogTopic[] };

/** Source files: `backend/games/consensio/<language>.json`. */
export const TOPIC_CATALOGS: Record<GameLanguage, TopicCatalog> = {
  en: enTopics as TopicCatalog,
  nb: nbTopics as TopicCatalog,
};

export function catalogTopic(language: GameLanguage, topicId: string): TopicChoice | null {
  const topic = TOPIC_CATALOGS[language].topics.find((item) => item.id === topicId);
  return topic ? { topic_id: topic.id, language, subject: topic.subject, left_end: topic.left, right_end: topic.right } : null;
}

/**
 * Three topics of `language` the couple has not placed, in random order. When fewer than three are
 * left, the language starts over and `reset` is true.
 */
export function pickTopics(
  language: GameLanguage,
  used: ReadonlySet<string>,
  random: () => number = Math.random,
): { choices: TopicChoice[]; reset: boolean } {
  const all = TOPIC_CATALOGS[language].topics;
  let pool = all.filter((topic) => !used.has(topic.id));
  const reset = pool.length < CHOICE_COUNT;
  if (reset) pool = [...all];
  const choices: TopicChoice[] = [];
  while (choices.length < CHOICE_COUNT && pool.length > 0) {
    const [topic] = pool.splice(Math.floor(random() * pool.length), 1);
    choices.push({ topic_id: topic.id, language, subject: topic.subject, left_end: topic.left, right_end: topic.right });
  }
  return { choices, reset };
}

/** Draws the next placer's three topics. Clears the language's used topics when it starts over. */
export async function drawTopicChoices(ctx: WriterCtx, coupleId: string, language: GameLanguage): Promise<TopicChoice[]> {
  const rows = await ctx.db
    .query("consensio_used_topics")
    .withIndex("by_couple_id_language", (q) => q.eq("couple_id", coupleId).eq("language", language))
    .collect();
  const { choices, reset } = pickTopics(language, new Set(rows.map((row) => row.topic_id)));
  if (reset) for (const row of rows) await ctx.db.delete(row._id);
  return choices;
}

export async function markTopicUsed(ctx: WriterCtx, coupleId: string, language: GameLanguage, topicId: string): Promise<void> {
  await ctx.db.insert("consensio_used_topics", { couple_id: coupleId, language, topic_id: topicId, created_at: nowIso() });
}

/** Trims and collapses every run of whitespace, line breaks included, to one space. */
export function normalizeTopicText(raw: string): string {
  return raw.trim().replace(/\s+/g, " ");
}

export type OwnTopicProblem = "subject" | "end" | "same_ends" | "characters";

export const OWN_TOPIC_MESSAGES: Record<OwnTopicProblem, string> = {
  subject: "topic must have a subject of 2 to 60 characters",
  end: "each end must be 1 to 24 characters",
  same_ends: "the two ends must be different",
  characters: "topic has characters that are not allowed",
};

/** The first problem with a normalized own topic, or null when it can be placed. */
export function validateOwnTopic(subject: string, left: string, right: string): OwnTopicProblem | null {
  const subjectLength = charLength(subject);
  if (subjectLength < SUBJECT_LENGTH.min || subjectLength > SUBJECT_LENGTH.max) return "subject";
  for (const end of [left, right]) {
    const length = charLength(end);
    if (length < END_LENGTH.min || length > END_LENGTH.max) return "end";
  }
  if (left.toLocaleLowerCase() === right.toLocaleLowerCase()) return "same_ends";
  // Control, private-use and unassigned code points. Emoji and their joiners are fine.
  if ([subject, left, right].some((text) => /[\p{Cc}\p{Co}\p{Cn}]/u.test(text))) return "characters";
  return null;
}

// --- Lookups both files share -----------------------------------------------

export async function getCoupleGame(ctx: ReaderCtx, coupleId: string): Promise<ConsensioGame | null> {
  return await ctx.db
    .query("consensio_games")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

/** The newest rounds of a game, newest first. */
export async function newestRounds(ctx: ReaderCtx, gameId: string, count: number): Promise<ConsensioRound[]> {
  return await ctx.db
    .query("consensio_rounds")
    .withIndex("by_game_id_round_number", (q) => q.eq("game_id", gameId))
    .order("desc")
    .take(count);
}

/** Patches a game and bumps its version. */
export async function patchGame(ctx: WriterCtx, game: ConsensioGame, patch: Partial<ConsensioGame> = {}): Promise<void> {
  await ctx.db.patch(game._id, withUpdatedAt({ ...patch, version: game.version + 1 }));
}

// --- Hooks for the shared games code ------------------------------------------

/**
 * A turn push needs its round to still wait for the recipient's guess. A result push needs the
 * placer to not have seen the reveal, to not have the game open, and no next round yet: a placement
 * within the delay sent one push for both. A reminder needs the turn it was sent for, which ends when `turn_reminder_sent_at`
 * is cleared.
 */
export async function consensioPushStillWanted(
  ctx: ReaderCtx,
  push: GamePushKind,
  payload: Record<string, unknown>,
  recipientUserId: string,
): Promise<boolean> {
  const roundId = typeof payload.round_id === "string" ? payload.round_id : null;
  const round = await getByUuid(ctx, "consensio_rounds", roundId);
  switch (push) {
    case "game_turn_ready":
      return round !== null && round.guesser_user_id === recipientUserId && round.guess === undefined;
    case "game_result": {
      if (!round || round.placer_user_id !== recipientUserId || round.placer_reveal_seen_at !== undefined) return false;
      // The push waited 5 minutes, so the placer may have opened the game since.
      if (await isGamePresent(ctx, round.couple_id, "consensio", recipientUserId)) return false;
      const next = await ctx.db
        .query("consensio_rounds")
        .withIndex("by_game_id_round_number", (q) => q.eq("game_id", round.game_id).eq("round_number", round.round_number + 1))
        .first();
      return next === null;
    }
    case "game_turn_reminder": {
      const game = await getByUuid(ctx, "consensio_games", typeof payload.game_id === "string" ? payload.game_id : null);
      return game !== null && game.turn_user_id === recipientUserId && game.turn_reminder_sent_at !== undefined;
    }
    case "game_invite":
      return true;
  }
}

/**
 * Deletes the couple's rows in the three Consensio tables and returns how many.
 * ponytail: runs in one mutation like the other couple cleanup. A couple with thousands of rounds may
 * exceed the write limit. Upgrade path: delete in chunks and reschedule.
 */
export async function deleteCoupleConsensioRows(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = [
    ...(await ctx.db.query("consensio_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("consensio_rounds").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("consensio_used_topics").withIndex("by_couple_id_language", (q) => q.eq("couple_id", coupleId)).collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}

/**
 * The single reminder for a turn that waited 72 hours, a guess or a placement. `turn_reminder_sent_at`
 * is set before anything else, so a turn never gets two. Returns the pushes queued.
 */
export async function sendDueConsensioReminders(ctx: WriterCtx, now: string): Promise<number> {
  const due = await ctx.db
    .query("consensio_games")
    .withIndex("by_turn_reminder_sent_at_turn_started_at", (q) =>
      q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS)),
    )
    .take(100);
  let sent = 0;
  for (const game of due) {
    await patchGame(ctx, game, { turn_reminder_sent_at: now });
    if (!(await canAccessCoupleContent(ctx, game.turn_user_id, game.couple_id))) continue;
    const [newest] = await newestRounds(ctx, game.id, 1);
    // The turn is always the newest round's guesser's (to guess it, then to place the next), so the
    // partner who acted last is its placer. Before the first round, it is the other member.
    const actor =
      newest?.placer_user_id ??
      (await listActiveMembers(ctx, game.couple_id)).find((member) => member.user_id !== game.turn_user_id)?.user_id;
    if (!actor) continue;
    sent += await enqueueGamePush(ctx, {
      kind: "game_turn_reminder",
      game_kind: "consensio",
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

/** What the shared games code asks of Consensio. Registered in `GAME_BACKENDS` (gameRegistry.ts). */
export const consensioBackend: GameBackend = {
  pushStillWanted: consensioPushStillWanted,
  deleteCoupleRows: deleteCoupleConsensioRows,
  sendDueTurnReminders: sendDueConsensioReminders,

  /** The next placer's topics came from the old language. A placement queued with one still works. */
  async onLanguageChanged(ctx, coupleId, language) {
    const game = await getCoupleGame(ctx, coupleId);
    if (game) await patchGame(ctx, game, { choices: await drawTopicChoices(ctx, coupleId, language) });
  },
};
