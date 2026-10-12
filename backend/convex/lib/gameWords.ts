import enWords from "../../games/words/en.json";
import nbWords from "../../games/words/nb.json";
import { fail } from "./errors";

export type GameLanguage = "en" | "nb";
export type WordDifficulty = "easy" | "medium" | "hard";
export type WordEntry = { id: string; text: string; difficulty: WordDifficulty };
export type WordCatalog = { language: GameLanguage; words: WordEntry[] };
export type WordChoice = { difficulty: WordDifficulty; word_id: string; word: string };

export const WORD_DIFFICULTIES: readonly WordDifficulty[] = ["easy", "medium", "hard"];

/** Points a correct guess is worth. A custom word counts as medium. */
export const DIFFICULTY_POINTS = { easy: 1, medium: 2, hard: 3, custom: 2 } as const;

/** Source files: `backend/games/words/<language>.json`. */
export const WORD_CATALOGS: Record<GameLanguage, WordCatalog> = {
  en: enWords as WordCatalog,
  nb: nbWords as WordCatalog,
};

const CUSTOM_WORD_PATTERN = /^[a-zæøå]+$/;

/** Trims, collapses runs of whitespace to one space, and lowercases. Guesses and custom words use it. */
export function normalizeWordText(input: string): string {
  return input.trim().replace(/\s+/g, " ").toLowerCase();
}

/**
 * Validates a custom word: 2 to 20 letters, at most three words, letters A-Z plus
 * ÆØÅ in either case. Returns the normalized word.
 */
export function normalizeCustomWord(input: string): string {
  const word = normalizeWordText(input);
  const parts = word.split(" ");
  const letters = word.replace(/ /g, "");
  if (
    parts.length > 3 ||
    parts.some((part) => !CUSTOM_WORD_PATTERN.test(part)) ||
    [...letters].length < 2 ||
    [...letters].length > 20
  ) {
    fail("23514", "custom word must be 2 to 20 letters in at most three words");
  }
  return word;
}

/**
 * One word per difficulty from the language catalog, skipping words the couple already saw.
 * A difficulty whose words are all used starts over and is listed in `reset`.
 */
export function pickWordChoices(
  language: GameLanguage,
  used: Record<WordDifficulty, ReadonlySet<string>>,
  random: () => number = Math.random,
): { choices: WordChoice[]; reset: WordDifficulty[] } {
  const choices: WordChoice[] = [];
  const reset: WordDifficulty[] = [];
  for (const difficulty of WORD_DIFFICULTIES) {
    const pool = WORD_CATALOGS[language].words.filter((entry) => entry.difficulty === difficulty);
    let available = pool.filter((entry) => !used[difficulty].has(entry.id));
    if (available.length === 0) {
      reset.push(difficulty);
      available = pool;
    }
    const entry = available[Math.min(available.length - 1, Math.floor(random() * available.length))];
    choices.push({ difficulty, word_id: entry.id, word: entry.text });
  }
  return { choices, reset };
}
