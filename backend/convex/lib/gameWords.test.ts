import { describe, expect, test } from "vitest";
import {
  normalizeCustomWord,
  normalizeWordText,
  pickWordChoices,
  WORD_CATALOGS,
  WORD_DIFFICULTIES,
  type GameLanguage,
  type WordDifficulty,
} from "./gameWords";

const ALPHABETS: Record<GameLanguage, RegExp> = { en: /^[a-z]+$/, nb: /^[a-zæøå]+$/ };

describe.each(["en", "nb"] as const)("word list %s", (language) => {
  const catalog = WORD_CATALOGS[language];

  test("names its language", () => {
    expect(catalog.language).toBe(language);
  });

  test("has at least 90 words per difficulty", () => {
    for (const difficulty of WORD_DIFFICULTIES) {
      expect(catalog.words.filter((word) => word.difficulty === difficulty).length).toBeGreaterThanOrEqual(90);
    }
  });

  test("has unique lowercase ascii slug ids", () => {
    const ids = catalog.words.map((word) => word.id);
    expect(ids.filter((id) => !/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/.test(id))).toEqual([]);
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([]);
  });

  test("has lowercase words of 3 to 14 letters in at most two words", () => {
    const bad = catalog.words.filter((word) => {
      const parts = word.text.split(" ");
      const letters = word.text.replace(/ /g, "");
      return (
        word.text !== word.text.toLowerCase() ||
        parts.length > 2 ||
        parts.some((part) => !ALPHABETS[language].test(part)) ||
        [...letters].length < 3 ||
        [...letters].length > 14 ||
        !WORD_DIFFICULTIES.includes(word.difficulty)
      );
    });
    expect(bad).toEqual([]);
  });

  test("does not repeat a word", () => {
    const texts = catalog.words.map((word) => word.text);
    expect(texts.filter((text, index) => texts.indexOf(text) !== index)).toEqual([]);
  });
});

describe("normalizeCustomWord", () => {
  test.each([
    ["Cat", "cat"],
    ["  the   dog  ", "the dog"],
    ["the dog at mom", null],
    ["brunost", "brunost"],
    ["Æsel", "æsel"],
    ["ØL på båt", "øl på båt"],
    ["ab", "ab"],
    ["a", null],
    ["", null],
    ["a".repeat(21), null],
    ["a".repeat(20), "a".repeat(20)],
    ["one two three", "one two three"],
    ["one two three four", null],
    ["cat5", null],
    ["cat!", null],
    ["café", null],
    ["a b", "a b"],
  ] as const)("%j", (input, expected) => {
    if (expected === null) {
      expect(() => normalizeCustomWord(input)).toThrow(/custom word must be 2 to 20 letters/);
    } else {
      expect(normalizeCustomWord(input)).toBe(expected);
    }
  });
});

test("normalizeWordText trims, collapses spaces, and lowercases", () => {
  expect(normalizeWordText("  Hot   DOG ")).toBe("hot dog");
});

describe("pickWordChoices", () => {
  const none = (): Record<WordDifficulty, Set<string>> => ({ easy: new Set(), medium: new Set(), hard: new Set() });

  test("returns one word per difficulty from the language", () => {
    const { choices, reset } = pickWordChoices("nb", none());
    expect(choices.map((choice) => choice.difficulty)).toEqual(["easy", "medium", "hard"]);
    for (const choice of choices) {
      const entry = WORD_CATALOGS.nb.words.find((word) => word.id === choice.word_id);
      expect(entry).toMatchObject({ text: choice.word, difficulty: choice.difficulty });
    }
    expect(reset).toEqual([]);
  });

  test("skips used words and starts a difficulty over when it runs out", () => {
    const used = none();
    const easy = WORD_CATALOGS.en.words.filter((word) => word.difficulty === "easy").map((word) => word.id);
    for (const id of easy.slice(1)) used.easy.add(id);
    const first = pickWordChoices("en", used);
    expect(first.choices[0].word_id).toBe(easy[0]);
    expect(first.reset).toEqual([]);

    used.easy.add(easy[0]);
    const second = pickWordChoices("en", used);
    expect(second.reset).toEqual(["easy"]);
    expect(easy).toContain(second.choices[0].word_id);
  });
});
