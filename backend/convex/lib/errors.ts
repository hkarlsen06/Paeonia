import { ConvexError } from "convex/values";

/** Throws a ConvexError carrying a SQLSTATE-style code and the SQL error message. */
export function fail(code: string, message: string): never {
  throw new ConvexError({ code, message });
}

/** Mirrors the Postgres message for a violated CHECK constraint. */
export function checkViolation(table: string, constraint: string): never {
  return fail(
    "23514",
    `new row for relation "${table}" violates check constraint "${constraint}"`,
  );
}

/** Mirrors the Postgres message for a violated unique constraint. */
export function uniqueViolation(constraint: string): never {
  return fail(
    "23505",
    `duplicate key value violates unique constraint "${constraint}"`,
  );
}
