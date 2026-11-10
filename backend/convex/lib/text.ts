import { fail } from "./errors";

/**
 * Postgres `btrim(text)`. It strips spaces only, not tabs or newlines, so a
 * body of "\n" stays non-empty. Use it wherever the SQL called `btrim`.
 */
export function btrim(value: string | null | undefined): string {
  return (value ?? "").replace(/^ +| +$/g, "");
}

/** Postgres `char_length`: counts code points, not UTF-16 units. */
export function charLength(value: string): number {
  let count = 0;
  for (const _ of value) count += 1;
  return count;
}

/** `nullif(btrim(value), '')`. */
export function btrimToNull(value: string | null | undefined): string | null {
  const trimmed = btrim(value);
  return trimmed === "" ? null : trimmed;
}

/**
 * `value` trimmed of white space, or a `23514` failure unless it has 1 to `maxCodePoints` code
 * points. The app trims and counts a title the same way, so it never queues one this refuses.
 */
export function requireTitle(value: string, maxCodePoints: number, label: string): string {
  const title = value.trim();
  if (title.length === 0 || charLength(title) > maxCodePoints) {
    fail("23514", `${label} must be 1 to ${maxCodePoints} characters`);
  }
  return title;
}
