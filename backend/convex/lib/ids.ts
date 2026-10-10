import { fail } from "./errors";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** A fresh lowercase uuid for client-less inserts. */
export function newUuid(): string {
  return crypto.randomUUID();
}

/**
 * Normalizes a uuid argument to lowercase hyphenated form. iOS sends uppercase
 * strings and Convex compares strings exactly, so every uuid argument must pass
 * through here. Accepts the same shapes Postgres does: hyphenated, plain 32 hex
 * digits, and a surrounding pair of braces.
 */
export function uuidArg(value: unknown): string {
  if (typeof value === "string") {
    let text = value.trim().toLowerCase();
    if (text.startsWith("{") && text.endsWith("}")) {
      text = text.slice(1, -1);
    }
    if (/^[0-9a-f]{32}$/.test(text)) {
      text = `${text.slice(0, 8)}-${text.slice(8, 12)}-${text.slice(12, 16)}-${text.slice(16, 20)}-${text.slice(20)}`;
    }
    if (UUID_PATTERN.test(text)) {
      return text;
    }
  }
  return fail("22P02", `invalid input syntax for type uuid: "${String(value)}"`);
}

/** Like `uuidArg`, but null and undefined become undefined. */
export function optionalUuidArg(value: string | null | undefined): string | undefined {
  return value === null || value === undefined ? undefined : uuidArg(value);
}

/**
 * Normalizes a timestamp argument to `toISOString()` form so string comparison
 * between stored timestamps stays valid. Fails with 22007 on invalid input.
 */
export function timestampArg(value: unknown): string {
  if (typeof value === "string") {
    const ms = Date.parse(value);
    if (!Number.isNaN(ms)) {
      return new Date(ms).toISOString();
    }
  }
  return fail(
    "22007",
    `invalid input syntax for type timestamp with time zone: "${String(value)}"`,
  );
}

export function optionalTimestampArg(value: string | null | undefined): string | undefined {
  return value === null || value === undefined ? undefined : timestampArg(value);
}

/** Validates a YYYY-MM-DD calendar date. Fails with 22007 on invalid input. */
export function dateArg(value: unknown): string {
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const parsed = new Date(`${value}T00:00:00.000Z`);
    if (!Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value) {
      return value;
    }
  }
  return fail("22007", `invalid input syntax for type date: "${String(value)}"`);
}

export function optionalDateArg(value: string | null | undefined): string | undefined {
  return value === null || value === undefined ? undefined : dateArg(value);
}
