import type { ConvexError } from "convex/values";
import { describe, expect, test } from "vitest";
import {
  canEndAt,
  CHOICE_COUNT,
  END_FROM_LINE,
  lineUsesDare,
  MAX_DARE_LENGTH,
  MAX_LINE_LENGTH,
  MAX_LINES,
  MAX_TITLE_LENGTH,
  MIN_DARE_LENGTH,
  MIN_LINE_LENGTH,
  mustEndAt,
  normalizeDareWord,
  normalizeStoryText,
  pickChoices,
  requireStoryLine,
  requireStoryTitle,
  seededRandom,
  STORY_OPENINGS,
  STORY_WORDS,
} from "./storyChain";
import type { GameLanguage } from "./gameWords";

const LANGUAGES = ["en", "nb"] as const satisfies readonly GameLanguage[];

/** Whole-word pronoun matchers. `\b` only knows ASCII letters, so Norwegian uses lookarounds. */
const FORBIDDEN_PRONOUNS: Record<GameLanguage, RegExp> = {
  en: /(?<![\p{L}])(?:i|me|my|mine|we|us|our|ours|you|your|yours)(?![\p{L}])/iu,
  nb: /(?<![\p{L}])(?:jeg|meg|min|mitt|mine|vi|oss|vår|vårt|våre|du|deg|din|ditt|dine|dere)(?![\p{L}])/iu,
};

const WORD_LETTERS: Record<GameLanguage, RegExp> = { en: /^[a-z]+$/, nb: /^[a-zæøå]+$/ };

/** English nouns whose plural changes the stem, plus compounds that end in a changing noun. */
const BLOCKED_EN = [
  "knife", "leaf", "wolf", "mouse", "goose", "tooth", "story", "city", "butterfly", "party", "cherry",
  "snowman", "firefly", "cactus", "bakery", "shelf", "scarf", "bookshelf", "fairy", "baby", "puppy",
  "family", "berry", "daisy", "foot", "woman", "child",
];

/** Norwegian nouns with a vowel change or a dropped e in the plural or definite form. */
const BLOCKED_NB = [
  "bok", "bøker", "mann", "menn", "hånd", "hender", "fot", "føtter", "tann", "tenner", "natt", "netter",
  "bror", "brødre", "datter", "døtre", "sykkel", "nøkkel", "himmel", "vinter", "sommer", "finger",
  "helikopter", "anker", "strand", "gulrot", "badeand", "fiskestang", "museum", "teater", "støvel", "vaffel",
];
const BLOCKED_NB_ENDINGS = ["bok", "mann", "hånd", "fot", "tann", "natt", "bror", "datter", "stang", "rot", "and", "tå"];

function failure(fn: () => unknown): ConvexError<{ code: string; message: string }> {
  try {
    fn();
  } catch (error) {
    return error as ConvexError<{ code: string; message: string }>;
  }
  throw new Error("expected the call to throw");
}

const codePoints = (text: string) => [...text].length;

describe.each(LANGUAGES)("openings %s", (language) => {
  const openings = STORY_OPENINGS[language];

  test("has unique snake_case ascii ids and unique texts", () => {
    const ids = openings.map((opening) => opening.id);
    const texts = openings.map((opening) => opening.text);
    expect(ids.filter((id) => !/^[a-z0-9]+(?:_[a-z0-9]+)*$/.test(id))).toEqual([]);
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([]);
    expect(texts.filter((text, index) => texts.indexOf(text) !== index)).toEqual([]);
  });

  test("is one sentence of at most 120 characters that starts with a capital and ends with a period", () => {
    const bad = openings.filter(
      (opening) =>
        codePoints(opening.text) > 120 ||
        !opening.text.endsWith(".") ||
        /[.!?]/.test(opening.text.slice(0, -1)) ||
        !/^\p{Lu}/u.test(opening.text) ||
        opening.text !== normalizeStoryText(opening.text),
    );
    expect(bad).toEqual([]);
  });

  test("avoids dashes and curly quotes", () => {
    expect(openings.filter((opening) => /[–—‘’“”]/.test(opening.text))).toEqual([]);
  });

  test("never speaks as or to a person", () => {
    expect(openings.filter((opening) => FORBIDDEN_PRONOUNS[language].test(opening.text))).toEqual([]);
  });
});

describe.each(LANGUAGES)("dare words %s", (language) => {
  const words = STORY_WORDS[language];

  test("has 120 words", () => {
    expect(words).toHaveLength(120);
  });

  test("has unique ascii ids that follow the word", () => {
    const ids = words.map((word) => word.id);
    expect(ids.filter((id) => !/^[a-z]+$/.test(id))).toEqual([]);
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([]);
    const idOf = (text: string) => text.replace(/æ/g, "ae").replace(/ø/g, "o").replace(/å/g, "aa");
    expect(words.filter((word) => word.id !== idOf(word.text))).toEqual([]);
  });

  test("does not repeat a word", () => {
    const texts = words.map((word) => word.text);
    expect(texts.filter((text, index) => texts.indexOf(text) !== index)).toEqual([]);
  });

  test("has lowercase single words of 4 to 14 letters", () => {
    const bad = words.filter(
      (word) => !WORD_LETTERS[language].test(word.text) || codePoints(word.text) < 4 || codePoints(word.text) > 14,
    );
    expect(bad).toEqual([]);
  });

  test("is accepted by the dare word rules", () => {
    expect(words.filter((word) => normalizeDareWord(word.text) !== word.text)).toEqual([]);
  });
});

describe("dare words whose forms keep the stem", () => {
  const texts = (language: GameLanguage) => STORY_WORDS[language].map((word) => word.text);

  test("English avoids irregular plurals", () => {
    const words = texts("en");
    expect(words.filter((word) => BLOCKED_EN.includes(word))).toEqual([]);
    expect(words.filter((word) => /[^aeiou]y$/.test(word))).toEqual([]);
    expect(words.filter((word) => /(?:[^f]f|fe)$/.test(word) && word !== "giraffe")).toEqual([]);
    expect(words.filter((word) => /(?:man|tooth|foot|mouse|goose)$/.test(word))).toEqual([]);
  });

  test("Norwegian avoids vowel changes and dropped e", () => {
    const words = texts("nb");
    expect(words.filter((word) => BLOCKED_NB.includes(word))).toEqual([]);
    expect(words.filter((word) => BLOCKED_NB_ENDINGS.some((ending) => word.endsWith(ending)))).toEqual([]);
    expect(words.filter((word) => /(?:el|er|en|e)$/.test(word))).toEqual([]);
  });
});

describe("constants", () => {
  test("match the design", () => {
    expect([MIN_LINE_LENGTH, MAX_LINE_LENGTH, END_FROM_LINE, MAX_LINES]).toEqual([2, 240, 8, 20]);
    expect([MAX_TITLE_LENGTH, MIN_DARE_LENGTH, MAX_DARE_LENGTH, CHOICE_COUNT]).toEqual([40, 2, 20, 3]);
  });
});

describe("normalizeStoryText", () => {
  test.each([
    ["  hello  ", "hello"],
    ["a   b", "a b"],
    ["a\n\nb", "a b"],
    ["  one\ttwo \r\n three\n", "one two three"],
    ["a  b", "a b"],
    ["", ""],
    [" \n\t ", ""],
  ])("%j", (input, expected) => {
    expect(normalizeStoryText(input)).toBe(expected);
  });
});

describe("requireStoryLine", () => {
  const message = "story line must be 2 to 240 characters";

  test("returns the normalized text", () => {
    expect(requireStoryLine("  Hunden   løp\nhjem. ")).toBe("Hunden løp hjem.");
    expect(requireStoryLine("ok")).toBe("ok");
  });

  test.each([["", "empty"], ["a", "one character"], ["  a \n ", "one character with spaces"]])(
    "rejects %j (%s)",
    (input) => {
      expect(failure(() => requireStoryLine(input)).data).toEqual({ code: "23514", message });
    },
  );

  test("accepts 240 characters and rejects 241", () => {
    expect(requireStoryLine("a".repeat(240))).toBe("a".repeat(240));
    expect(failure(() => requireStoryLine("a".repeat(241))).data).toEqual({ code: "23514", message });
  });

  test("counts emoji as one character each", () => {
    const emoji240 = "😀".repeat(240);
    expect(emoji240.length).toBe(480);
    expect(requireStoryLine(emoji240)).toBe(emoji240);
    expect(failure(() => requireStoryLine("😀".repeat(241))).data).toEqual({ code: "23514", message });
    expect(failure(() => requireStoryLine("😀")).data).toEqual({ code: "23514", message });
    expect(requireStoryLine("😀😀")).toBe("😀😀");
  });

  test("counts the length after whitespace collapses", () => {
    const line = `${"a".repeat(120)}\n\n\n\n${"b".repeat(119)}`;
    expect(requireStoryLine(line)).toBe(`${"a".repeat(120)} ${"b".repeat(119)}`);
    expect(failure(() => requireStoryLine(`${"a".repeat(120)} ${"b".repeat(120)}`)).data).toEqual({
      code: "23514",
      message,
    });
  });
});

describe("requireStoryTitle", () => {
  const message = "story title must be 1 to 40 characters";

  test("returns the normalized title", () => {
    expect(requireStoryTitle("  The  goat\nand the bus ")).toBe("The goat and the bus");
    expect(requireStoryTitle("Å")).toBe("Å");
  });

  test.each([[""], ["   "], ["\n\t"]])("rejects %j", (input) => {
    expect(failure(() => requireStoryTitle(input)).data).toEqual({ code: "23514", message });
  });

  test("accepts 40 characters and rejects 41", () => {
    expect(requireStoryTitle("a".repeat(40))).toBe("a".repeat(40));
    expect(failure(() => requireStoryTitle("a".repeat(41))).data).toEqual({ code: "23514", message });
  });

  test("counts emoji as one character each", () => {
    expect(requireStoryTitle("😀".repeat(40))).toBe("😀".repeat(40));
    expect(failure(() => requireStoryTitle("😀".repeat(41))).data).toEqual({ code: "23514", message });
  });
});

describe("normalizeDareWord", () => {
  const message = "dare word must be one word of 2 to 20 letters";

  test.each([
    ["Hund", "hund"],
    ["  Café ", "café"],
    ["Café", "café"],
    ["smørbrød", "smørbrød"],
    ["ÆØÅ", "æøå"],
    ["LIGHTHOUSE", "lighthouse"],
    ["ab", "ab"],
    ["a".repeat(20), "a".repeat(20)],
    ["é".repeat(20), "é".repeat(20)],
    ["日本語", "日本語"],
  ])("accepts %j", (input, expected) => {
    expect(normalizeDareWord(input)).toBe(expected);
  });

  test.each([
    [""],
    ["   "],
    ["a"],
    ["a".repeat(21)],
    ["é".repeat(21)],
    ["two words"],
    ["hund1"],
    ["hund!"],
    ["don't"],
    ["well-known"],
    ["😀😀"],
  ])("rejects %j", (input) => {
    expect(failure(() => normalizeDareWord(input)).data).toEqual({ code: "23514", message });
  });
});

describe("lineUsesDare", () => {
  test.each([
    ["Hunden løp over jordet.", "hund", true],
    ["Fra gårdshunden kom det en lyd.", "hund", true],
    ["Hun løp hjem.", "hund", false],
    ["They climbed the LIGHTHOUSE stairs.", "lighthouse", true],
    ["They climbed the lighthouses.", "Lighthouse", true],
    ["They climbed the stairs.", "lighthouse", false],
    ["Ære være brunosten.", "ÆRE", true],
    ["Smørbrødene var borte.", "smørbrød", true],
  ])("%j with %j is %s", (line, word, expected) => {
    expect(lineUsesDare(line, word)).toBe(expected);
  });

  test("treats composed and decomposed accents as the same", () => {
    const composed = "Café";
    const decomposed = "Café";
    expect(composed).not.toBe(decomposed);
    expect(lineUsesDare(`They met at the ${decomposed} door.`, composed)).toBe(true);
    expect(lineUsesDare(`They met at the ${composed} door.`, decomposed)).toBe(true);
    expect(lineUsesDare(`They met at the ${decomposed.toUpperCase()} door.`, "café")).toBe(true);
  });

  test("accepts what normalizeDareWord returns", () => {
    expect(lineUsesDare("Hunden løp.", normalizeDareWord("  HUND "))).toBe(true);
  });
});

describe("canEndAt and mustEndAt", () => {
  test("a line may end the story from line 8", () => {
    expect(canEndAt(1)).toBe(false);
    expect(canEndAt(7)).toBe(false);
    expect(canEndAt(8)).toBe(true);
    expect(canEndAt(19)).toBe(true);
    expect(canEndAt(20)).toBe(true);
  });

  test("line 20 must end the story", () => {
    expect(mustEndAt(8)).toBe(false);
    expect(mustEndAt(19)).toBe(false);
    expect(mustEndAt(20)).toBe(true);
    expect(mustEndAt(21)).toBe(true);
  });
});

describe("seededRandom", () => {
  const take = (seed: string, count = 8) => {
    const random = seededRandom(seed);
    return Array.from({ length: count }, () => random());
  };

  test("repeats the same sequence for the same seed", () => {
    expect(take("game-1:4")).toEqual(take("game-1:4"));
  });

  test("gives other sequences for other seeds", () => {
    expect(take("game-1:4")).not.toEqual(take("game-1:5"));
    expect(take("game-1:4")).not.toEqual(take("game-2:4"));
    expect(take("")).not.toEqual(take("a"));
  });

  test("stays in [0, 1) and is not constant", () => {
    const values = take("range", 500);
    expect(values.every((value) => value >= 0 && value < 1)).toBe(true);
    expect(new Set(values).size).toBeGreaterThan(450);
  });
});

describe("pickChoices", () => {
  const pool = "abcdefghij".split("").map((id) => ({ id, text: id.toUpperCase() }));
  const ids = (entries: readonly { id: string }[]) => entries.map((entry) => entry.id);

  test("picks distinct entries from the pool", () => {
    const { choices, reset } = pickChoices(pool, new Set(), CHOICE_COUNT, "game:1");
    expect(choices).toHaveLength(3);
    expect(new Set(ids(choices)).size).toBe(3);
    for (const choice of choices) expect(pool).toContainEqual(choice);
    expect(reset).toBe(false);
  });

  test("gives the same picks for the same inputs", () => {
    const used = new Set(["a", "b"]);
    expect(pickChoices(pool, used, 3, "game:1")).toEqual(pickChoices(pool, new Set(["b", "a"]), 3, "game:1"));
  });

  test("changes the picks with the seed", () => {
    const picks = new Set(
      Array.from({ length: 30 }, (_, turn) => ids(pickChoices(pool, new Set(), 3, `game:${turn}`).choices).join()),
    );
    expect(picks.size).toBeGreaterThan(10);
  });

  test("skips used entries", () => {
    const used = new Set(["a", "b", "c", "d", "e", "f", "g"]);
    for (let turn = 0; turn < 20; turn += 1) {
      const { choices, reset } = pickChoices(pool, used, 3, `game:${turn}`);
      expect(ids(choices).sort()).toEqual(["h", "i", "j"]);
      expect(reset).toBe(false);
    }
  });

  test("starts over with the whole pool when fewer than 3 are unused", () => {
    const used = new Set(["a", "b", "c", "d", "e", "f", "g", "h"]);
    const { choices, reset } = pickChoices(pool, used, 3, "game:1");
    expect(reset).toBe(true);
    expect(choices).toHaveLength(3);
    expect(new Set(ids(choices)).size).toBe(3);
    const seen = new Set<string>();
    for (let turn = 0; turn < 40; turn += 1) {
      for (const id of ids(pickChoices(pool, used, 3, `game:${turn}`).choices)) seen.add(id);
    }
    expect([...seen].some((id) => used.has(id))).toBe(true);
  });

  test("starts over when every entry is used", () => {
    const used = new Set(ids(pool));
    const { choices, reset } = pickChoices(pool, used, 3, "game:1");
    expect(reset).toBe(true);
    expect(choices).toHaveLength(3);
  });

  test("ignores used ids that are not in the pool", () => {
    const used = new Set(["x", "y", "z"]);
    expect(pickChoices(pool, used, 3, "game:1")).toEqual(pickChoices(pool, new Set(), 3, "game:1"));
  });

  test("does not change the pool", () => {
    const before = ids(pool);
    pickChoices(pool, new Set(["a"]), 3, "game:1");
    pickChoices(pool, new Set(ids(pool)), 3, "game:1");
    expect(ids(pool)).toEqual(before);
  });

  test("keeps the same picks across deploys", () => {
    expect(ids(pickChoices(pool, new Set(), 3, "game:1").choices)).toMatchInlineSnapshot(`
      [
        "e",
        "b",
        "i",
      ]
    `);
  });

  test("works on the real catalogs", () => {
    for (const language of LANGUAGES) {
      const openings = pickChoices(STORY_OPENINGS[language], new Set(), CHOICE_COUNT, "game:7");
      const words = pickChoices(STORY_WORDS[language], new Set(), CHOICE_COUNT, "game:7");
      expect(openings.choices).toHaveLength(3);
      expect(words.choices).toHaveLength(3);
      for (const choice of openings.choices) expect(STORY_OPENINGS[language]).toContainEqual(choice);
      for (const choice of words.choices) expect(STORY_WORDS[language]).toContainEqual(choice);
    }
  });
});
