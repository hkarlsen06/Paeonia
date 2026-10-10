import type { DataModel, Doc, TableNames } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { NamedTableInfo } from "convex/server";
import { fail } from "./errors";
import { nowIso } from "./time";

export type ReaderCtx = QueryCtx;
export type WriterCtx = MutationCtx;

/** Tables that have a uuid `id` field and a `by_uuid` index. */
export type UuidTableName = {
  [T in TableNames]: "by_uuid" extends keyof NamedTableInfo<DataModel, T>["indexes"] ? T : never;
}[TableNames];

/** Looks a row up by its uuid `id`. Returns null when missing. Never scans. */
export async function getByUuid<T extends UuidTableName>(
  ctx: ReaderCtx,
  table: T,
  id: string | null | undefined,
): Promise<Doc<T> | null> {
  if (id === null || id === undefined) {
    return null;
  }
  // The index name and field are checked by UuidTableName; the query builder cannot see that through the generic.
  const query = ctx.db.query(table) as any;
  return (await query.withIndex("by_uuid", (q: any) => q.eq("id", id)).unique()) ?? null;
}

/** Like `getByUuid`, but fails with `P0002` (or the given error) when the row is missing. */
export async function requireByUuid<T extends UuidTableName>(
  ctx: ReaderCtx,
  table: T,
  id: string | null | undefined,
  error: { code: string; message: string } = { code: "P0002", message: `${table} row not found` },
): Promise<Doc<T>> {
  const row = await getByUuid(ctx, table, id);
  if (!row) {
    return fail(error.code, error.message);
  }
  return row;
}

/** Drops null and undefined fields. Nullable SQL columns are stored by omission. */
export function omitNulls<T extends Record<string, unknown>>(value: T): T {
  const result: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    if (item !== null && item !== undefined) {
      result[key] = item;
    }
  }
  return result as T;
}

/** `value ?? null`, for API output where missing columns are reported as null. */
export function orNull<T>(value: T | null | undefined): T | null {
  return value ?? null;
}

/**
 * Adds the `set_updated_at` trigger effect to a patch.
 * To clear a nullable column in a patch, set it to `undefined`.
 */
export function withUpdatedAt<T extends Record<string, unknown>>(patch: T): T & { updated_at: string } {
  return { ...patch, updated_at: nowIso() };
}

/** Adds the `touch_updated_at_and_revision` trigger effect: new `updated_at`, `revision + 1`. */
export function withTouch<T extends Record<string, unknown>>(
  row: { revision: number },
  patch: T,
): T & { updated_at: string; revision: number } {
  return { ...patch, updated_at: nowIso(), revision: row.revision + 1 };
}

/** Adds the `bump_revision` trigger effect: `revision + 1` without touching `updated_at`. */
export function withRevisionBump<T extends Record<string, unknown>>(
  row: { revision: number },
  patch: T,
): T & { revision: number } {
  return { ...patch, revision: row.revision + 1 };
}
