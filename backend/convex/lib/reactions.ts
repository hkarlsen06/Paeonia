import { fail } from "./errors";

/**
 * Emoji reactions in the question chat. Each person has at most one reaction on each
 * answer and each message, kept in `daily_answer_reactions` and `thread_message_reactions`.
 */

/** Longest reaction accepted, in UTF-16 units. A family or flag emoji fits. */
const MAX_REACTION_LENGTH = 32;

/** One emoji, such as ❤️, 👍🏽 or 🇳🇴. Letters, digits and words are refused. */
export function isReactionEmoji(value: string): boolean {
  if (value.length === 0 || value.length > MAX_REACTION_LENGTH) return false;
  if (!/^[\p{Extended_Pictographic}\p{Emoji_Component}\u200d\ufe0f\u20e3]+$/u.test(value)) return false;
  if (!/[\p{Extended_Pictographic}\p{Regional_Indicator}]/u.test(value)) return false;
  // Two emoji side by side pass the checks above. A runtime without Segmenter allows them.
  if (typeof Intl.Segmenter !== "function") return true;
  return [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(value)].length === 1;
}

/** The reaction a caller asked for, trimmed, or null to take it back. Fails on anything but one emoji. */
export function reactionArg(value: string | null): string | null {
  if (value === null) return null;
  const emoji = value.trim();
  if (!isReactionEmoji(emoji)) fail("23514", "reaction must be one emoji");
  return emoji;
}
