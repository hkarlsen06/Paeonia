import enOpenings from "../../games/story-chain/openings/en.json";
import nbOpenings from "../../games/story-chain/openings/nb.json";
import enWords from "../../games/story-chain/words/en.json";
import nbWords from "../../games/story-chain/words/nb.json";
import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { getByUuid, orNull } from "./db";
import { fail } from "./errors";
import type { GameBackend } from "./gameRegistry";
import { enqueueGamePush, TURN_REMINDER_AFTER_MS } from "./games";
import type { GameLanguage } from "./gameWords";
import { charLength } from "./text";
import { addMs, nowIso } from "./time";

export type StoryOpening = { id: string; text: string };
export type StoryWord = { id: string; text: string };

/** A line is 2 to 240 characters after normalizing. Characters are code points. */
export const MIN_LINE_LENGTH = 2;
export const MAX_LINE_LENGTH = 240;
/** The writer may end the story from this line number on. */
export const END_FROM_LINE = 8;
/** The story always ends with this line number. */
export const MAX_LINES = 20;
export const MAX_TITLE_LENGTH = 40;
/** A dare word is one word of 2 to 20 letters. */
export const MIN_DARE_LENGTH = 2;
export const MAX_DARE_LENGTH = 20;
/** How many openings or dare words Paeonia suggests at once. */
export const CHOICE_COUNT = 3;

/** Source files: `backend/games/story-chain/openings/<language>.json`. */
export const STORY_OPENINGS: Record<GameLanguage, readonly StoryOpening[]> = {
  en: enOpenings.openings,
  nb: nbOpenings.openings,
};

/** Source files: `backend/games/story-chain/words/<language>.json`. */
export const STORY_WORDS: Record<GameLanguage, readonly StoryWord[]> = {
  en: enWords.words,
  nb: nbWords.words,
};

/** Trims and collapses every run of whitespace, line breaks included, to one space. */
export function normalizeStoryText(input: string): string {
  return input.trim().replace(/\s+/g, " ");
}

/** Normalizes a story line and checks its length (2 to 240 code points). Returns the normalized text. */
export function requireStoryLine(input: string): string {
  const text = normalizeStoryText(input);
  const length = charLength(text);
  if (length < MIN_LINE_LENGTH || length > MAX_LINE_LENGTH) {
    fail("23514", "story line must be 2 to 240 characters");
  }
  return text;
}

/** Normalizes a story title and checks its length (1 to 40 code points). Returns the normalized text. */
export function requireStoryTitle(input: string): string {
  const title = normalizeStoryText(input);
  const length = charLength(title);
  if (length < 1 || length > MAX_TITLE_LENGTH) {
    fail("23514", "story title must be 1 to 40 characters");
  }
  return title;
}

/**
 * Validates a dare word the writer typed: one word of 2 to 20 letters in any script.
 * Returns it in NFC and lowercase.
 */
export function normalizeDareWord(input: string): string {
  const word = input.normalize("NFC").trim().toLowerCase().normalize("NFC");
  if (!/^\p{L}{2,20}$/u.test(word)) {
    fail("23514", "dare word must be one word of 2 to 20 letters");
  }
  return word;
}

function normalizeForMatch(value: string): string {
  return value.normalize("NFC").toLowerCase();
}

/**
 * True when the line contains the dare word, ignoring case. "hunden" and "gårdshund"
 * both use "hund". The phone runs the same check.
 */
export function lineUsesDare(line: string, word: string): boolean {
  return normalizeForMatch(line).includes(normalizeForMatch(word));
}

/** From this line number on, the writer may make the line the last one. */
export function canEndAt(lineNumber: number): boolean {
  return lineNumber >= END_FROM_LINE;
}

/** The last line is forced at this line number. */
export function mustEndAt(lineNumber: number): boolean {
  return lineNumber >= MAX_LINES;
}

/** A deterministic random generator in [0, 1): an xmur3-style string hash feeding mulberry32. */
export function seededRandom(seed: string): () => number {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i += 1) {
    h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  let state = (h ^ (h >>> 16)) >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Picks `count` distinct entries from `pool`, skipping ids the couple already used. Fewer than
 * `count` unused entries means the list starts over: the whole pool is eligible and `reset` is
 * true. The same pool, used set, count, and seed always give the same choices.
 */
export function pickChoices<T extends { id: string }>(
  pool: readonly T[],
  used: ReadonlySet<string>,
  count: number,
  seed: string,
): { choices: T[]; reset: boolean } {
  const unused = pool.filter((entry) => !used.has(entry.id));
  const reset = unused.length < count;
  const candidates = reset ? [...pool] : unused;
  const random = seededRandom(seed);
  for (let i = candidates.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
  }
  return { choices: candidates.slice(0, count), reset };
}

// --- Tables -----------------------------------------------------------------

export type StoryChainGame = Doc<"story_chain_games">;
export type Story = Doc<"story_chain_stories">;
export type ContentKind = Doc<"story_chain_used">["kind"];

/** The most stories one history page returns. */
export const MAX_HISTORY_PAGE = 50;

export async function getStoryChainGame(ctx: ReaderCtx, coupleId: string): Promise<StoryChainGame | null> {
  return await ctx.db
    .query("story_chain_games")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

/** Every change to the game goes through here, so `version` always moves forward. */
export async function patchStoryChainGame(
  ctx: WriterCtx,
  game: StoryChainGame,
  patch: Partial<Omit<StoryChainGame, "_id" | "_creationTime" | "id" | "version">>,
): Promise<void> {
  await ctx.db.patch(game._id, { ...patch, version: game.version + 1, updated_at: nowIso() });
}

export async function patchStory(
  ctx: WriterCtx,
  story: Story,
  patch: Partial<Omit<Story, "_id" | "_creationTime" | "id">>,
): Promise<void> {
  await ctx.db.patch(story._id, { ...patch, updated_at: nowIso() });
}

export async function getStoryStar(ctx: ReaderCtx, storyId: string, userId: string): Promise<Doc<"story_chain_stars"> | null> {
  return await ctx.db
    .query("story_chain_stars")
    .withIndex("by_story_id_user_id", (q) => q.eq("story_id", storyId).eq("user_id", userId))
    .unique();
}

/** A story as the app reads it. Only the caller's own star and seen mark leave the server. */
export async function storyJson(ctx: ReaderCtx, story: Story, userId: string) {
  return {
    id: story.id,
    story_number: story.story_number,
    starter_user_id: story.starter_user_id,
    opening_id: orNull(story.opening_id),
    opening_text: orNull(story.opening_text),
    state: story.state,
    lines: story.lines.map((line) => ({
      id: line.id,
      number: line.number,
      author_user_id: line.author_user_id,
      text: line.text,
      dare_word: orNull(line.dare_word),
      created_at: line.created_at,
    })),
    last_line_user_id: orNull(story.last_line_user_id),
    title: orNull(story.title),
    titled_by_user_id: orNull(story.titled_by_user_id),
    finished_at: orNull(story.finished_at),
    seen_by_me: story.seen_by.includes(userId),
    starred_by_me: story.state === "finished" && (await getStoryStar(ctx, story.id, userId)) !== null,
    created_at: story.created_at,
    updated_at: story.updated_at,
  };
}

// --- Openings and dare words --------------------------------------------------

type LocatedEntry = { id: string; text: string; language: GameLanguage };

/**
 * An opening by id, from the couple's language first and then the other one, so a pick made
 * before a language change still counts.
 */
export function findOpening(id: string, language: GameLanguage): LocatedEntry | null {
  return findIn(STORY_OPENINGS, id, language);
}

/** A dare word by id, from the couple's language first. Some words, such as "popcorn", are in both lists. */
export function findWord(id: string, language: GameLanguage): LocatedEntry | null {
  return findIn(STORY_WORDS, id, language);
}

function findIn(
  catalogs: Record<GameLanguage, readonly { id: string; text: string }[]>,
  id: string,
  preferred: GameLanguage,
): LocatedEntry | null {
  const languages: GameLanguage[] = preferred === "en" ? ["en", "nb"] : ["nb", "en"];
  for (const language of languages) {
    const entry = catalogs[language].find((item) => item.id === id);
    if (entry) return { ...entry, language };
  }
  return null;
}

async function usedIds(ctx: ReaderCtx, gameId: string, kind: ContentKind, language: GameLanguage): Promise<Set<string>> {
  const rows = await ctx.db
    .query("story_chain_used")
    .withIndex("by_game_id_language_kind", (q) => q.eq("game_id", gameId).eq("language", language).eq("kind", kind))
    .collect();
  return new Set(rows.map((row) => row.content_id));
}

/** The three openings of the turn: a pick from the unused ones, seeded by the game and the turn. */
export async function openingChoices(ctx: ReaderCtx, game: StoryChainGame, language: GameLanguage) {
  const pool = STORY_OPENINGS[language];
  const used = await usedIds(ctx, game.id, "opening", language);
  const { choices } = pickChoices(pool, used, CHOICE_COUNT, `${game.id}:opening:${game.turn_number}`);
  return choices.map((entry) => ({ opening_id: entry.id, text: entry.text }));
}

/** The three dare words of the turn: a pick from the unused ones, seeded by the game and the turn. */
export async function wordChoices(ctx: ReaderCtx, game: StoryChainGame, language: GameLanguage) {
  const pool = STORY_WORDS[language];
  const used = await usedIds(ctx, game.id, "word", language);
  const { choices } = pickChoices(pool, used, CHOICE_COUNT, `${game.id}:word:${game.turn_number}`);
  return choices.map((entry) => ({ word_id: entry.id, word: entry.text }));
}

/**
 * Records that the couple used an opening or a word. When fewer than three unused entries were
 * left, the choices had started over, so the old rows go first.
 */
export async function markContentUsed(
  ctx: WriterCtx,
  game: StoryChainGame,
  kind: ContentKind,
  language: GameLanguage,
  contentId: string,
): Promise<void> {
  const rows = await ctx.db
    .query("story_chain_used")
    .withIndex("by_game_id_language_kind", (q) => q.eq("game_id", game.id).eq("language", language).eq("kind", kind))
    .collect();
  const poolSize = (kind === "opening" ? STORY_OPENINGS : STORY_WORDS)[language].length;
  if (poolSize - rows.length < CHOICE_COUNT) {
    for (const row of rows) await ctx.db.delete(row._id);
  } else if (rows.some((row) => row.content_id === contentId)) {
    return;
  }
  await ctx.db.insert("story_chain_used", {
    game_id: game.id,
    couple_id: game.couple_id,
    language,
    kind,
    content_id: contentId,
    created_at: nowIso(),
  });
}

// --- Hooks for the shared games code ----------------------------------------------

export const storyChainBackend: GameBackend = {
  /**
   * A turn push names the line that passed the turn (`round_id`), and it stays wanted while that
   * line is still the newest of the current story and the turn is still the recipient's. A result
   * push names the story (the story was named) and needs it finished and not yet seen by its
   * last writer.
   */
  async pushStillWanted(ctx, push, payload, recipientUserId) {
    const gameId = typeof payload.game_id === "string" ? payload.game_id : null;
    const roundId = typeof payload.round_id === "string" ? payload.round_id : null;
    const game = gameId ? await getByUuid(ctx, "story_chain_games", gameId) : null;
    switch (push) {
      case "game_turn_ready": {
        if (game === null || game.turn_user_id !== recipientUserId || !game.current_story_id) return false;
        const story = await getByUuid(ctx, "story_chain_stories", game.current_story_id);
        return (
          story !== null &&
          story.lines.at(-1)?.id === roundId &&
          game.state === (payload.step === "last_line" ? "titling" : "writing")
        );
      }
      case "game_result": {
        const story = roundId ? await getByUuid(ctx, "story_chain_stories", roundId) : null;
        return story !== null && story.state === "finished" && !story.seen_by.includes(recipientUserId);
      }
      case "game_turn_reminder":
        // A new turn clears turn_reminder_sent_at, so a set value means the reminded turn still waits.
        return game !== null && game.turn_user_id === recipientUserId && game.turn_reminder_sent_at !== undefined;
      case "game_invite":
        return true;
    }
  },

  /** The couple's one game, when it is the user's turn or the newest finished story is unseen by them. */
  async waitingFor(ctx, coupleId, userId) {
    const game = await getStoryChainGame(ctx, coupleId);
    if (!game) return 0;
    if (game.turn_user_id === userId) return 1;
    const finished = await ctx.db
      .query("story_chain_stories")
      .withIndex("by_game_id_story_number", (q) => q.eq("game_id", game.id))
      .order("desc")
      .filter((q) => q.eq(q.field("state"), "finished"))
      .first();
    return finished !== null && !finished.seen_by.includes(userId) ? 1 : 0;
  },

  // ponytail: one mutation for the whole couple. A couple writes a few stories a week, so this stays
  // far below the transaction limits. Delete in chunks if that ever changes.
  async deleteCoupleRows(ctx, coupleId) {
    const rows = [
      ...(await ctx.db.query("story_chain_games").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
      ...(await ctx.db.query("story_chain_stories").withIndex("by_couple_id_story_number", (q) => q.eq("couple_id", coupleId)).collect()),
      ...(await ctx.db.query("story_chain_stars").withIndex("by_couple_id_user_id_story_number", (q) => q.eq("couple_id", coupleId)).collect()),
      ...(await ctx.db.query("story_chain_used").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ];
    for (const row of rows) await ctx.db.delete(row._id);
    return rows.length;
  },

  /**
   * The single reminder for a turn that waited 72 hours. `turn_reminder_sent_at` is set first and
   * cleared only when a new turn begins, so a turn never gets two reminders.
   */
  async sendDueTurnReminders(ctx, now) {
    const due = await ctx.db
      .query("story_chain_games")
      .withIndex("by_turn_reminder_sent_at_turn_started_at", (q) =>
        q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS)),
      )
      .take(100);
    let sent = 0;
    for (const game of due) {
      await ctx.db.patch(game._id, { turn_reminder_sent_at: now });
      if (!(await canAccessCoupleContent(ctx, game.turn_user_id, game.couple_id))) continue;
      const partner = (await listActiveMembers(ctx, game.couple_id)).find((member) => member.user_id !== game.turn_user_id);
      if (!partner) continue;
      sent += await enqueueGamePush(ctx, {
        kind: "game_turn_reminder",
        game_kind: "story_chain",
        couple_id: game.couple_id,
        game_id: game.id,
        actor_user_id: partner.user_id,
        recipient_user_id: game.turn_user_id,
        dedupe_key: `game_turn_reminder:story_chain:${game.id}:${game.turn_started_at}`,
      });
    }
    return sent;
  },
};
