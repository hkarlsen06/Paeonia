import { paginationOptsValidator } from "convex/server";
import { internalQuery } from "./_generated/server";

/**
 * Lists stored files for the nightly backup on one-s (`/srv/backup/paeonia-backup.sh`). Its
 * export leaves files out, and this list goes into the export as `_storage/documents.jsonl`, in the
 * shape a full export writes there. `internalId` is the id in the file's `/api/storage/` URL, which
 * the script downloads a file from the first time it sees its sha256.
 */
export const list_stored_files = internalQuery({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, { paginationOpts }) => {
    const result = await ctx.db.system.query("_storage").paginate(paginationOpts);
    const page = await Promise.all(
      result.page.map(async (file) => {
        const url = await ctx.storage.getUrl(file._id);
        if (url === null) throw new Error(`No URL for stored file ${file._id}`);
        return { ...file, internalId: new URL(url).pathname.split("/").pop() };
      }),
    );
    return { ...result, page };
  },
});
