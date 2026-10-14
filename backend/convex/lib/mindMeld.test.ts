import { describe, expect, test } from "vitest";
import {
  levenshteinAtMostOne,
  matchKey,
  normalizeWord,
  roundOutcome,
  stemKey,
  validateWord,
  WORD_PROBLEM_MESSAGES,
} from "./mindMeld";

describe("normalizeWord", () => {
  test("trims and collapses whitespace to single spaces", () => {
    expect(normalizeWord("  ice   cream \n")).toBe("ice cream");
    expect(normalizeWord("New\tYork")).toBe("New York");
    expect(normalizeWord("a  b")).toBe("a b");
    expect(normalizeWord("   ")).toBe("");
  });

  test("keeps case and accents as typed", () => {
    expect(normalizeWord(" Blåbær ")).toBe("Blåbær");
  });
});

describe("validateWord", () => {
  test("accepts letters of any alphabet, digits, hyphens, apostrophes, and short phrases", () => {
    for (const word of ["ocean", "Ice cream", "New York City", "ice-cream", "rock'n'roll", "rock’n’roll", "дом", "寿司", "café", "R2D2", "a"]) {
      expect(validateWord(word)).toBeNull();
    }
  });

  test("refuses an empty word", () => {
    expect(validateWord("")).toBe("empty");
  });

  test("refuses more than 30 characters, counted as characters and not UTF-16 units", () => {
    expect(validateWord("a".repeat(30))).toBeNull();
    expect(validateWord("a".repeat(31))).toBe("too_long");
    expect(validateWord("😀".repeat(5))).toBe("bad_characters");
    expect(validateWord("é".repeat(30))).toBeNull();
  });

  test("refuses more than three words", () => {
    expect(validateWord("one two three")).toBeNull();
    expect(validateWord("one two three four")).toBe("too_many_words");
  });

  test("refuses a word without a letter", () => {
    expect(validateWord("123")).toBe("no_letters");
    expect(validateWord("-'-")).toBe("no_letters");
    // A letter that normalizes to nothing would give an empty key that matches any other empty key.
    expect(validateWord("\u037a")).toBe("no_letters");
  });

  test("refuses characters outside the allowed set", () => {
    for (const word of ["wow!", "a.b", "a_b", "a/b", "😀", "a,b", "<b>", "50%"]) {
      expect(validateWord(word)).toBe("bad_characters");
    }
  });

  test("every problem has a message", () => {
    expect(WORD_PROBLEM_MESSAGES.empty).toBe("word must be 1 to 30 characters in at most three words");
    expect(WORD_PROBLEM_MESSAGES.no_letters).toBe("word must contain a letter");
    expect(WORD_PROBLEM_MESSAGES.bad_characters).toBe("word has characters that are not allowed");
  });
});

describe("matchKey", () => {
  test("ignores case, spaces, hyphens, and punctuation", () => {
    expect(matchKey("Ice cream")).toBe("icecream");
    expect(matchKey("ice-cream")).toBe("icecream");
    expect(matchKey("is krem")).toBe("iskrem");
    expect(matchKey("rock'n’roll")).toBe("rocknroll");
  });

  test("spells the Nordic letters out", () => {
    expect(matchKey("Blåbær")).toBe("blaabaer");
    expect(matchKey("Ærlig")).toBe("aerlig");
    expect(matchKey("Ålesund")).toBe("aalesund");
    expect(matchKey("Øl")).toBe("oel");
    expect(matchKey("Käse")).toBe("kaese");
    expect(matchKey("Köln")).toBe("koeln");
  });

  test("spells the Nordic letters out when they carry a second accent", () => {
    expect(matchKey("ǻl")).toBe(matchKey("ål"));
    expect(matchKey("ǻl")).toBe("aal");
    expect(matchKey("ǟ")).toBe("ae");
    // A ring and a diaeresis on one a spell it out once, as the phone does.
    expect(matchKey("a\u030a\u0308l")).toBe("aal");
    expect(matchKey("ȫ")).toBe("oe");
    expect(matchKey("ǿ")).toBe("oe");
    expect(matchKey("ǽ")).toBe("ae");
    expect(matchKey("Å")).toBe("aa");
    // A plain a and o with another accent stay a and o.
    expect(matchKey("áéíóú")).toBe("aeiou");
    expect(matchKey("õ")).toBe("o");
  });

  test("strips accents, also from decomposed input", () => {
    expect(matchKey("café")).toBe("cafe");
    expect(matchKey("café")).toBe("cafe");
    expect(matchKey("Über")).toBe("uber");
    // a + combining ring above is å
    expect(matchKey("å")).toBe("aa");
  });

  test("folds compatibility forms", () => {
    expect(matchKey("ｆｉｓｈ")).toBe("fish");
    expect(matchKey("ﬁsh")).toBe("fish");
  });

  test("keeps digits and letters of other alphabets", () => {
    expect(matchKey("R2-D2")).toBe("r2d2");
    expect(matchKey("Дом")).toBe("дом");
    expect(matchKey("寿司")).toBe("寿司");
  });

  test("keys that match are the same for each spelling of a word", () => {
    expect(matchKey("Blåbær")).toBe(matchKey("blaabaer"));
    expect(matchKey("Ærlig")).toBe(matchKey("aerlig"));
    expect(matchKey("café")).toBe(matchKey("cafe"));
  });
});

describe("stemKey", () => {
  test("drops the first matching ending", () => {
    expect(stemKey("dogs")).toBe("dog");
    expect(stemKey("hunden")).toBe("hund");
    expect(stemKey("hestene")).toBe("hest");
    expect(stemKey("jentene")).toBe("jent");
    expect(stemKey("puppies")).toBe("puppy");
    expect(stemKey("boxes")).toBe("box");
    expect(stemKey("lamper")).toBe("lamp");
    expect(stemKey("huset")).toBe("hus");
    expect(stemKey("bluse")).toBe("blus");
    expect(stemKey("katta")).toBe("katt");
  });

  test("keeps at least 3 characters and moves on to a shorter ending", () => {
    expect(stemKey("pies")).toBe("pie");
    expect(stemKey("bus")).toBe("bus");
    expect(stemKey("as")).toBe("as");
    expect(stemKey("ene")).toBe("ene");
    expect(stemKey("ocean")).toBe("ocean");
  });

  test("counts characters, not UTF-16 units", () => {
    // Two letters outside the basic plane and an s are three characters, so the s stays.
    expect(stemKey("𐐨𐐩s")).toBe("𐐨𐐩s");
    expect(stemKey("𐐨𐐩𐐨s")).toBe("𐐨𐐩𐐨");
  });
});

describe("levenshteinAtMostOne", () => {
  test("accepts equal words and one added, removed, or changed letter", () => {
    expect(levenshteinAtMostOne("house", "house")).toBe(true);
    expect(levenshteinAtMostOne("house", "horse")).toBe(true);
    expect(levenshteinAtMostOne("ocean", "oceans")).toBe(true);
    expect(levenshteinAtMostOne("oceans", "ocean")).toBe(true);
    expect(levenshteinAtMostOne("ocan", "ocean")).toBe(true);
    expect(levenshteinAtMostOne("ocean", "ocea")).toBe(true);
    expect(levenshteinAtMostOne("", "a")).toBe(true);
  });

  test("refuses two edits", () => {
    expect(levenshteinAtMostOne("house", "mouse2")).toBe(false);
    expect(levenshteinAtMostOne("ocean", "oceanic")).toBe(false);
    expect(levenshteinAtMostOne("abcde", "abdce")).toBe(false);
    expect(levenshteinAtMostOne("abcde", "xbcdx")).toBe(false);
    expect(levenshteinAtMostOne("a", "abc")).toBe(false);
  });
});

describe("roundOutcome", () => {
  test("equal keys match", () => {
    expect(roundOutcome("Ice cream", "icecream")).toBe("match");
    expect(roundOutcome("is krem", "iskrem")).toBe("match");
    expect(roundOutcome("Blåbær", "blaabaer")).toBe("match");
    expect(roundOutcome("Ærlig", "aerlig")).toBe("match");
    expect(roundOutcome("café", "cafe")).toBe("match");
    expect(roundOutcome("FISH", "fish")).toBe("match");
  });

  test("the same stem is a near miss", () => {
    expect(roundOutcome("dog", "dogs")).toBe("near");
    expect(roundOutcome("hund", "hunden")).toBe("near");
    expect(roundOutcome("hest", "hestene")).toBe("near");
    expect(roundOutcome("puppies", "puppy")).toBe("near");
  });

  test("one letter apart is a near miss when both keys have 5 letters or more", () => {
    expect(roundOutcome("house", "horse")).toBe("near");
    expect(roundOutcome("ocean", "oceam")).toBe("near");
  });

  test("short words one letter apart are a miss", () => {
    expect(roundOutcome("cat", "car")).toBe("miss");
    expect(roundOutcome("dog", "dig")).toBe("miss");
    expect(roundOutcome("moon", "mood")).toBe("miss");
    expect(roundOutcome("house", "cat")).toBe("miss");
  });

  test("different words are a miss", () => {
    expect(roundOutcome("ocean", "sushi")).toBe("miss");
    expect(roundOutcome("salt", "fish")).toBe("miss");
  });

  test("words of another alphabet compare by their own letters", () => {
    expect(matchKey("дом")).not.toBe("");
    expect(matchKey("кот")).not.toBe("");
    expect(roundOutcome("дом", "кот")).toBe("miss");
    expect(roundOutcome("дом", "Дом")).toBe("match");
  });

  test("keys give the same answer as the words they come from", () => {
    expect(roundOutcome(matchKey("Blåbær"), matchKey("blaabaer"))).toBe("match");
    expect(roundOutcome(matchKey("hund"), matchKey("hunden"))).toBe("near");
    expect(roundOutcome(matchKey("ocean"), matchKey("sushi"))).toBe("miss");
  });
});
