import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { withUpdatedAt } from "./db";

/** The two calls of file storage that `storeAndRecord` needs. An action's `ctx.storage` has them. */
export type BlobStorage = {
  store(blob: Blob): Promise<Id<"_storage">>;
  delete(storageId: Id<"_storage">): Promise<void>;
};

/**
 * Stores a blob and runs `record`, which saves its storage id. When `record` fails, nothing knows the
 * blob yet, so a later cleanup of the export cannot find it. This deletes it before it rethrows.
 */
export async function storeAndRecord<T>(
  storage: BlobStorage,
  blob: Blob,
  record: (storageId: Id<"_storage">) => Promise<T>,
): Promise<T> {
  const storageId = await storage.store(blob);
  try {
    return await record(storageId);
  } catch (error) {
    await storage.delete(storageId).catch(() => undefined);
    throw error;
  }
}

/** Deletes the data files that wait for a zip file (all of them, or those of one part), and their rows. */
export async function removeExportChunks(ctx: MutationCtx, exportId: string, partNumber?: number): Promise<void> {
  const chunks = await ctx.db
    .query("data_export_chunks")
    .withIndex("by_export_id_part_number", (q) =>
      partNumber === undefined ? q.eq("export_id", exportId) : q.eq("export_id", exportId).eq("part_number", partNumber),
    )
    .collect();
  for (const chunk of chunks) {
    await ctx.storage.delete(chunk.storage_id);
    await ctx.db.delete(chunk._id);
  }
}

/** Deletes the zip files of an export from storage, and their rows. */
export async function removeExportParts(ctx: MutationCtx, exportId: string): Promise<void> {
  await removeExportChunks(ctx, exportId);
  const parts = await ctx.db
    .query("data_export_parts")
    .withIndex("by_export_id_part_number", (q) => q.eq("export_id", exportId))
    .collect();
  for (const part of parts) {
    if (part.storage_id) await ctx.storage.delete(part.storage_id);
    await ctx.db.delete(part._id);
  }
}

/** Ends a download: its files are deleted at once and the row stays as a record that it was made. */
export async function expireDataExport(ctx: MutationCtx, row: Doc<"data_exports">): Promise<void> {
  await removeExportParts(ctx, row.id);
  await ctx.db.patch(row._id, withUpdatedAt({ status: "expired" as const }));
}

/** Account deletion: removes every download of the person, files and rows. */
export async function deleteUserDataExports(ctx: MutationCtx, userId: string): Promise<void> {
  const rows = await ctx.db
    .query("data_exports")
    .withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId))
    .collect();
  for (const row of rows) {
    await removeExportParts(ctx, row.id);
    await ctx.db.delete(row._id);
  }
}
