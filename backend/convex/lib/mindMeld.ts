import { defineTable } from "convex/server";
import { v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, withUpdatedAt } from "./db";
import type { GameBackend } from "./gameRegistry";
import { enqueueGamePush, TURN_REMINDER_AFTER_MS, type GamePushKind, type GameWait } from "./games";
import { charLength } from "./text";
import { addMs } from "./time";
import { literals } from "./validators";

// Mind Meld: the word rules, the tables, and the hooks the shared games code calls
// (`mindMeldBackend` at the end). The registered functions are in convex/mindMeld.ts.
// The rules and decisions are in docs/games/mind-meld.md.

export const MAX_ROUNDS = 10;
export const MAX_WORD_LENGTH = 30;
export const MAX_WORD_COUNT = 3;

// --- Tables -----------------------------------------------------------------

/** Spread into `defineSchema` in schema.ts. */
export const mindMeldTables = {
  // FK: couple_id -> couples cascade. (couple_id, game_number) is unique. Only the newest game can be playing.
  mind_meld_games: defineTable({
    id: v.string(),
    couple_id: v.string(),
    game_number: v.number(),
    state: literals("playing", "melded", "ended"),
    end_reason: v.optional(literals("rounds", "restart")),
    ended_by_user_id: v.optional(v.string()),
    ended_at: v.optional(v.string()),
    /** How many rounds a melded game took, set when it melds. Records and stats read it, so they never read rounds. */
    rounds_taken: v.optional(v.number()),
    /** User id to the time that person first saw the ending. */
    end_seen_by_user: v.record(v.string(), v.string()),
    /** Goes up with every change to the game, its rounds, or its words. The phone never takes an older one. */
    version: v.number(),
    created_by_user_id: v.string(),
    created_at: v.string(),
    updated_at: v.string(),
  })
    .index("by_uuid", ["id"])
    .index("by_couple_id_game_number", ["couple_id", "game_number"]),

  // FK: game_id -> mind_meld_games cascade. (game_id, round_number) is unique.
  mind_meld_rounds: defineTable({
    id: v.string(),
    game_id: v.string(),
    couple_id: v.string(),
    round_number: v.number(),
    state: literals("open", "revealed"),
    outcome: v.optional(literals("match", "near", "miss")),
    /** Set when a partner counted a near miss as a match. */
    counted_by_user_id: v.optional(v.string()),
    /** Set while exactly one partner has locked in. */
    waiting_since: v.optional(v.string()),
    reminder_sent_at: v.optional(v.string()),
    revealed_at: v.optional(v.string()),
    created_at: v.string(),
    updated_at: v.string(),
  })
    .index("by_uuid", ["id"])
    .index("by_game_id_round_number", ["game_id", "round_number"])
    .index("by_couple_id", ["couple_id"])
    .index("by_reminder_sent_at_waiting_since", ["reminder_sent_at", "waiting_since"]),

  // FK: round_id -> mind_meld_rounds cascade. (round_id, user_id) is unique. The partner never reads `word` before the round is revealed.
  mind_meld_words: defineTable({
    round_id: v.string(),
    game_id: v.string(),
    couple_id: v.string(),
    user_id: v.string(),
    /** As typed, with single spaces. */
    word: v.string(),
    match_key: v.string(),
    locked_at: v.string(),
    /** The first time this person saw the revealed round. */
    reveal_seen_at: v.optional(v.string()),
  })
    .index("by_round_id_user_id", ["round_id", "user_id"])
    .index("by_game_id", ["game_id"])
    .index("by_couple_id", ["couple_id"]),
};

// --- Word rules -------------------------------------------------------------

export type WordProblem = "empty" | "too_long" | "too_many_words" | "no_letters" | "bad_characters";

/** The 23514 message for each problem. */
export const WORD_PROBLEM_MESSAGES: Record<WordProblem, string> = {
  empty: "word must be 1 to 30 characters in at most three words",
  too_long: "word must be 1 to 30 characters in at most three words",
  too_many_words: "word must be 1 to 30 characters in at most three words",
  no_letters: "word must contain a letter",
  bad_characters: "word has characters that are not allowed",
};

/** Trims and collapses every run of whitespace to one space. */
export function normalizeWord(raw: string): string {
  return raw.trim().replace(/\s+/g, " ");
}

/** The first problem with a normalized word, or null when it can be locked in. */
export function validateWord(word: string): WordProblem | null {
  if (word === "") return "empty";
  if (charLength(word) > MAX_WORD_LENGTH) return "too_long";
  if (word.split(" ").length > MAX_WORD_COUNT) return "too_many_words";
  if (!/^[\p{L}\p{M}\p{N} '’-]+$/u.test(word)) return "bad_characters";
  // A few letters, such as the Greek ypogegrammeni, are accents once normalized and leave an empty key.
  if (!/\p{L}/u.test(word) || matchKey(word) === "") return "no_letters";
  return null;
}

/**
 * The key two words are compared by: case, spaces, punctuation, and accents are gone, and the
 * Nordic letters are spelled out so "Blåbær" and "blaabaer" match. Letters of other alphabets stay.
 * The spelling out runs before the accent strip, which would turn å into a. After the decomposition
 * å is a with a ring above and ä is a with a diaeresis, so the marks are looked for behind the
 * letter. That also catches ǻ and ǟ, which carry a second accent.
 */
export function matchKey(word: string): string {
  return word
    .normalize("NFKC")
    .toLowerCase()
    .normalize("NFD")
    .replace(/æ/g, "ae")
    .replace(/ø/g, "oe")
    // Each a or o is spelled out once, so a ring and a diaeresis on one letter give "aa", as on the phone.
    .replace(/([ao])(\p{M}*)/gu, (_, letter: string, marks: string) => {
      if (letter === "a" && marks.includes("\u030a")) return `aa${marks}`;
      return marks.includes("\u0308") ? `${letter}e${marks}` : letter + marks;
    })
    .replace(/\p{M}/gu, "")
    .replace(/[^\p{L}\p{N}]/gu, "");
}

const STEM_ENDINGS: readonly (readonly [string, string])[] = [
  ["ingen", ""],
  ["inger", ""],
  ["ings", ""],
  ["ing", ""],
  ["ende", ""],
  ["ene", ""],
  ["ane", ""],
  ["ers", ""],
  ["ies", "y"],
  ["es", ""],
  ["er", ""],
  ["en", ""],
  ["et", ""],
  ["ed", ""],
  ["s", ""],
  ["a", ""],
  ["e", ""],
];

/**
 * Drops the first matching ending that leaves at least 3 characters, then one letter of a doubled
 * last letter, so "dogs" and "dog" share a stem, and so do "kidnapper", "kidnapping" and "kidnap".
 */
export function stemKey(key: string): string {
  const ending = STEM_ENDINGS.find(([end]) => key.endsWith(end) && charLength(key) - end.length >= 3);
  const stem = ending ? key.slice(0, key.length - ending[0].length) + ending[1] : key;
  const letters = Array.from(stem);
  const last = letters.length - 1;
  return letters.length > 3 && letters[last] === letters[last - 1] ? letters.slice(0, last).join("") : stem;
}

/** True when `a` and `b` are equal or differ by one added, removed, or changed character. */
export function levenshteinAtMostOne(a: string, b: string): boolean {
  const x = Array.from(a);
  const y = Array.from(b);
  const [short, long] = x.length <= y.length ? [x, y] : [y, x];
  if (long.length - short.length > 1) return false;
  let i = 0;
  while (i < short.length && short[i] === long[i]) i += 1;
  const sameLength = short.length === long.length;
  return short.slice(sameLength ? i + 1 : i).join("") === long.slice(i + 1).join("");
}

export type RoundOutcome = "match" | "near" | "miss";

/** Takes words or match keys. A near miss shows "So close!" and either partner may count it. */
export function roundOutcome(wordA: string, wordB: string): RoundOutcome {
  const a = matchKey(wordA);
  const b = matchKey(wordB);
  if (a === b) return "match";
  if (stemKey(a) === stemKey(b)) return "near";
  if (charLength(a) >= 5 && charLength(b) >= 5 && levenshteinAtMostOne(a, b)) return "near";
  return "miss";
}

// --- Writes both files share ------------------------------------------------

export type MindMeldGame = Doc<"mind_meld_games">;

/** The couple's newest game, in any state. */
export async function newestGame(ctx: ReaderCtx, coupleId: string): Promise<MindMeldGame | null> {
  return await ctx.db
    .query("mind_meld_games")
    .withIndex("by_couple_id_game_number", (q) => q.eq("couple_id", coupleId))
    .order("desc")
    .first();
}

/**
 * Patches a game and bumps its version. Bumps the couple's newest game too when that is another
 * game, because the phone compares the newest game's version and a change to an older game (such as
 * a seen mark on `previous`) must not look like old data. Call it once per game per mutation.
 */
export async function patchGame(ctx: WriterCtx, game: MindMeldGame, patch: Partial<MindMeldGame> = {}): Promise<void> {
  await ctx.db.patch(game._id, withUpdatedAt({ ...patch, version: game.version + 1 }));
  const newest = await newestGame(ctx, game.couple_id);
  if (newest && newest._id !== game._id) {
    await ctx.db.patch(newest._id, withUpdatedAt({ version: newest.version + 1 }));
  }
}

// --- Hooks for the shared games code ------------------------------------------

/**
 * A turn push needs the round to be open in a game in play and still waiting for this recipient.
 * A reminder also needs its round to have been reminded. A result push needs the recipient to not
 * have seen the revealed round yet. A restart leaves its open round open, so the game state counts.
 */
export async function mindMeldPushStillWanted(
  ctx: ReaderCtx,
  push: GamePushKind,
  payload: Record<string, unknown>,
  recipientUserId: string,
): Promise<boolean> {
  const round = await getByUuid(ctx, "mind_meld_rounds", typeof payload.round_id === "string" ? payload.round_id : null);
  if (!round) return false;
  const mine = await ctx.db
    .query("mind_meld_words")
    .withIndex("by_round_id_user_id", (q) => q.eq("round_id", round.id).eq("user_id", recipientUserId))
    .unique();
  switch (push) {
    case "game_result":
      return mine !== null && mine.reveal_seen_at === undefined;
    case "game_turn_ready":
    case "game_turn_reminder": {
      if (round.state !== "open" || mine !== null) return false;
      if (push === "game_turn_reminder" && round.reminder_sent_at === undefined) return false;
      return (await getByUuid(ctx, "mind_meld_games", round.game_id))?.state === "playing";
    }
    case "game_invite":
      return true;
  }
}

/**
 * The couple's two newest games, the ones the app shows. A game in play counts when the partner
 * locked in and the user has not, or when one of its two newest rounds is revealed and the user has
 * not seen it. A finished game counts until the user has seen how it ended.
 */
export async function mindMeldWaitingFor(ctx: ReaderCtx, coupleId: string, userId: string): Promise<GameWait[]> {
  const games = await ctx.db
    .query("mind_meld_games")
    .withIndex("by_couple_id_game_number", (q) => q.eq("couple_id", coupleId))
    .order("desc")
    .take(2);
  const waits: GameWait[] = [];
  for (const game of games) {
    if (game.state !== "playing") {
      if (game.end_seen_by_user[userId] === undefined) waits.push({ kind: "mind_meld", key: `end:${game.id}` });
      continue;
    }
    const rounds = await ctx.db
      .query("mind_meld_rounds")
      .withIndex("by_game_id_round_number", (q) => q.eq("game_id", game.id))
      .order("desc")
      .take(2);
    for (const round of rounds) {
      const mine = await ctx.db
        .query("mind_meld_words")
        .withIndex("by_round_id_user_id", (q) => q.eq("round_id", round.id).eq("user_id", userId))
        .unique();
      const myTurn = round.state === "open" && round.waiting_since !== undefined && mine === null;
      const unseenReveal = round.state === "revealed" && mine !== null && mine.reveal_seen_at === undefined;
      if (myTurn || unseenReveal) {
        waits.push({ kind: "mind_meld", key: `${myTurn ? "turn" : "result"}:${round.id}` });
        break;
      }
    }
  }
  return waits;
}

/**
 * Deletes the couple's rows in the three Mind Meld tables and returns how many.
 * ponytail: runs in one mutation like the other couple cleanup. A couple with a few hundred finished
 * games may exceed the write limit. Upgrade path: delete in chunks and reschedule.
 */
export async function deleteCoupleMindMeldRows(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = [
    ...(await ctx.db.query("mind_meld_games").withIndex("by_couple_id_game_number", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("mind_meld_rounds").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("mind_meld_words").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}

/**
 * The single reminder for a round that waited 72 hours for the partner who has not locked in.
 * `reminder_sent_at` is set before anything else, so a round never gets two. Returns the pushes queued.
 */
export async function sendDueMindMeldReminders(ctx: WriterCtx, now: string): Promise<number> {
  const due = await ctx.db
    .query("mind_meld_rounds")
    .withIndex("by_reminder_sent_at_waiting_since", (q) =>
      q.eq("reminder_sent_at", undefined).gt("waiting_since", "").lte("waiting_since", addMs(now, -TURN_REMINDER_AFTER_MS)),
    )
    .take(100);
  let sent = 0;
  for (const round of due) {
    const game = await getByUuid(ctx, "mind_meld_games", round.game_id);
    await ctx.db.patch(round._id, withUpdatedAt({ reminder_sent_at: now }));
    if (game) await patchGame(ctx, game);
    const words = await ctx.db
      .query("mind_meld_words")
      .withIndex("by_round_id_user_id", (q) => q.eq("round_id", round.id))
      .collect();
    if (game?.state !== "playing" || words.length !== 1) continue;
    const waitingUserId = words[0].user_id;
    if (!(await canAccessCoupleContent(ctx, waitingUserId, round.couple_id))) continue;
    const partner = (await listActiveMembers(ctx, round.couple_id)).find((member) => member.user_id !== waitingUserId);
    if (!partner) continue;
    sent += await enqueueGamePush(ctx, {
      kind: "game_turn_reminder",
      game_kind: "mind_meld",
      couple_id: round.couple_id,
      game_id: round.game_id,
      round_id: round.id,
      actor_user_id: waitingUserId,
      recipient_user_id: partner.user_id,
      dedupe_key: `game_turn_reminder:${round.id}`,
    });
  }
  return sent;
}

/** What the shared games code asks of Mind Meld. Registered in `GAME_BACKENDS` (gameRegistry.ts). */
export const mindMeldBackend: GameBackend = {
  pushStillWanted: mindMeldPushStillWanted,
  waitingFor: mindMeldWaitingFor,
  deleteCoupleRows: deleteCoupleMindMeldRows,
  sendDueTurnReminders: sendDueMindMeldReminders,
};
