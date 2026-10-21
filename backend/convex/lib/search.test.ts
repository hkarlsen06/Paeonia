import { describe, expect, test } from "vitest";
import { containsEveryToken, matchesWordPrefixes, searchTokens, snippetOf } from "./search";

describe("searchTokens", () => {
  test("lowercases, drops punctuation and repeats, and keeps Norwegian letters", () => {
    expect(searchTokens("  Sommer, sommer! Ålesund ")).toEqual(["sommer", "ålesund"]);
  });

  test("returns nothing for text shorter than two letters", () => {
    expect(searchTokens("a")).toEqual([]);
    expect(searchTokens("?!")).toEqual([]);
    expect(searchTokens("ab")).toEqual(["ab"]);
  });

  test("keeps at most six words", () => {
    expect(searchTokens("one two three four five six seven eight")).toHaveLength(6);
  });
});

describe("matching", () => {
  test("every token must start a word", () => {
    expect(matchesWordPrefixes("A walk on the beach", ["wal", "bea"])).toBe(true);
    expect(matchesWordPrefixes("A walk on the beach", ["walk", "mountain"])).toBe(false);
    expect(matchesWordPrefixes("sunset", ["set"])).toBe(false);
  });

  test("a scan also finds a token inside a word", () => {
    expect(containsEveryToken("Sommerferie i Hvaler", ["ferie", "hval"])).toBe(true);
    expect(containsEveryToken("Sommerferie", ["vinter"])).toBe(false);
  });
});

describe("snippetOf", () => {
  test("returns short text whole, with whitespace collapsed", () => {
    expect(snippetOf("a  b\n c", ["b"])).toBe("a b c");
  });

  test("cuts long text around the first match and marks both ends", () => {
    const text = `${"lorem ipsum ".repeat(30)}TARGET ${"dolor sit ".repeat(30)}`;
    const snippet = snippetOf(text, ["target"]);
    expect(snippet.startsWith("…")).toBe(true);
    expect(snippet.endsWith("…")).toBe(true);
    expect(snippet.toLowerCase()).toContain("target");
    expect(snippet.length).toBeLessThanOrEqual(165);
  });

  test("starts at the beginning when the match is near it", () => {
    const text = `needle ${"filler ".repeat(60)}`;
    const snippet = snippetOf(text, ["needle"]);
    expect(snippet.startsWith("needle")).toBe(true);
    expect(snippet.endsWith("…")).toBe(true);
  });
});
