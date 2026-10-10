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
