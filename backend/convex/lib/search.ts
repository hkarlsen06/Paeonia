/**
 * Text rules for the content search (`search.ts`). A search index finds candidates by word
 * prefix. These helpers decide which candidates really match, so the answer does not depend on
 * how the index engine treats several words, and they cut the snippet that the app shows.
 */

export const MIN_SEARCH_LENGTH = 2;
const MAX_SEARCH_LENGTH = 100;
const MAX_SEARCH_TOKENS = 6;
export const SNIPPET_LENGTH = 160;

/** Lowercased words made of letters and digits, in order. */
export function wordsOf(text: string): string[] {
  return text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
}

/**
 * The words to look for, or an empty list when the text is too short to search. The text is
 * cut at `MAX_SEARCH_LENGTH` characters and keeps at most `MAX_SEARCH_TOKENS` different words.
 */
export function searchTokens(raw: string): string[] {
  const trimmed = raw.trim().slice(0, MAX_SEARCH_LENGTH);
  const tokens = [...new Set(wordsOf(trimmed))].slice(0, MAX_SEARCH_TOKENS);
  const length = tokens.reduce((total, token) => total + token.length, 0);
  return length < MIN_SEARCH_LENGTH ? [] : tokens;
}

/** The query text for the search index: the words, so punctuation never reaches the engine. */
export function searchQueryText(tokens: string[]): string {
  return tokens.join(" ");
}

/** Every token starts a word of the text. The match the search indexes can find. */
export function matchesWordPrefixes(text: string, tokens: string[]): boolean {
  const words = wordsOf(text);
  return tokens.every((token) => words.some((word) => word.startsWith(token)));
}

/** Every token appears somewhere in the text, also inside a word. For scans over a small set of rows. */
export function containsEveryToken(text: string, tokens: string[]): boolean {
  const lower = text.toLowerCase();
  return tokens.every((token) => lower.includes(token));
}

/**
 * A short piece of `text` around the first token that appears in it, with "…" where it was cut.
 * Whitespace is collapsed to single spaces. Text that fits is returned whole.
 */
export function snippetOf(text: string, tokens: string[], maxLength = SNIPPET_LENGTH): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (flat.length <= maxLength) return flat;
  const lower = flat.toLowerCase();
  const hits = tokens.map((token) => lower.indexOf(token)).filter((index) => index >= 0);
  const first = hits.length > 0 ? Math.min(...hits) : 0;
  // Leave a little lead-in before the match, then start on a word.
  let start = Math.max(0, first - Math.floor(maxLength / 4));
  if (start > 0) {
    const space = flat.indexOf(" ", start);
    if (space >= 0 && space < first) start = space + 1;
  }
  let end = Math.min(flat.length, start + maxLength);
  if (end < flat.length) {
    const space = flat.lastIndexOf(" ", end);
    if (space > first) end = space;
  }
  return `${start > 0 ? "…" : ""}${flat.slice(start, end)}${end < flat.length ? "…" : ""}`;
}
