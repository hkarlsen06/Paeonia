import type { Doc } from "./_generated/dataModel";
import { query } from "./_generated/server";
import { requireUserId } from "./lib/auth";
import { orNull, type ReaderCtx } from "./lib/db";

// The live status of "Download my data". It has its own small module, because the app subscribes to
// it while Privacy and safety is open and Convex loads every import of a module on each run.
// dataExport.ts has the rest.

export function exportRow(row: Doc<"data_exports">) {
  return {
    id: row.id,
    status: row.status,
    progress: row.progress,
    include_files: row.include_files,
    created_at: row.created_at,
    ready_at: orNull(row.ready_at),
    expires_at: orNull(row.expires_at),
    part_count: row.part_count,
    byte_size: row.byte_size,
    row_count: row.row_count,
    file_count: row.file_count,
    skipped_file_count: row.skipped_file_count,
    error_code: orNull(row.error_code),
  };
}

export async function latestExport(ctx: ReaderCtx, userId: string): Promise<Doc<"data_exports"> | null> {
  return await ctx.db
    .query("data_exports")
    .withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId))
    .order("desc")
    .first();
}

/** The person's newest download, or null when they never asked. The app subscribes to this. */
export const get_data_export = query({
  args: {},
  handler: async (ctx) => {
    const row = await latestExport(ctx, await requireUserId(ctx));
    return row ? exportRow(row) : null;
  },
});
