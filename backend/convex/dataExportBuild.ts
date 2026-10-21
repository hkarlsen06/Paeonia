"use node";

import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalAction, type ActionCtx } from "./_generated/server";
import { renderReadme, type ReadmeFile } from "./lib/dataExportReadme";
import {
  FIRST_PART_RESERVE_BYTES,
  JsonChunker,
  dataFilePath,
  exportChunkBytes,
  exportCollectBudgetMs,
  exportPartLimitBytes,
  partFileName,
  planParts,
  type PlannedFile,
} from "./lib/dataExportPlan";
import {
  EXPORT_GROUPS,
  TABLE_EXPORTS,
  exportedTablesInOrder,
  type ExportedTable,
  type ExportGroup,
} from "./lib/dataExportRegistry";
import { storeAndRecord } from "./lib/dataExportFiles";
import { crc32, deflateRaw, ZipBuilder } from "./lib/zip";

// Builds the zip files of a "Download my data" export in three steps, so no action holds more than
// a bounded amount and none runs for long.
//
// 1. `collect_data` reads the tables in registry order. It cuts each table into JSON files of about
//    4 MiB, deflates them and stores each one in file storage (`data_export_chunks`). It stops
//    between tables when its time budget is used and schedules itself to go on.
// 2. When every table is collected, the same action plans the zip parts: the data files first, then the
//    media files, each part up to the part limit.
// 3. `build_part` builds one zip part at a time and schedules the next. Part 1 also gets the README and
//    the manifest. The last part marks the export ready.

type Row = Record<string, unknown>;
type Scope = { all: string[]; active: string[] };

const CHILD_BATCH = 100;
const ASSET_BATCH = 50;
const MEDIA_PATH_BATCH = 100;

/** Reports progress when it moved by at least two percent, so a large export is not a storm of writes. */
function progressReporter(ctx: ActionCtx, exportId: string) {
  let reported = 0;
  return async (progress: number) => {
    if (progress - reported < 0.02) return;
    reported = progress;
    await ctx.runMutation(internal.dataExport.set_export_progress, { export_id: exportId, progress });
  };
}

/** Thrown when the download was deleted or given up on while the build ran. The build just stops. */
class ExportGone extends Error {}

type Reader = {
  ctx: ActionCtx;
  userId: string;
  scope: Scope;
  /** Values of a field for each table collected so far, as `table.field`. */
  cache: Map<string, string[]>;
  /** Values of `key` in the rows of `table`, for the children and `referencedBy` rows that read them. */
  keys: (table: string, key: string) => Promise<string[]>;
};

async function pagesOf(
  ctx: ActionCtx,
  userId: string,
  table: string,
  scopeValue: string | undefined,
  onRows: (rows: Row[]) => Promise<void>,
): Promise<void> {
  let cursor: string | null = null;
  do {
    const page: { rows: Row[]; cursor: string | null } = await ctx.runQuery(internal.dataExport.export_rows, {
      user_id: userId,
      table,
      scope_value: scopeValue,
      cursor,
    });
    if (page.rows.length > 0) await onRows(page.rows);
    cursor = page.cursor;
  } while (cursor !== null);
}

/** Reads the rows of one exported table in batches. */
async function forEachBatch(
  reader: Reader,
  table: string,
  spec: ExportedTable,
  onRows: (rows: Row[]) => Promise<void>,
): Promise<void> {
  const { ctx, userId, scope } = reader;
  if (spec.kind === "own") return await pagesOf(ctx, userId, table, undefined, onRows);

  if (spec.kind === "couple") {
    const seen = new Set<string>();
    const remember = async (rows: Row[]) => {
      for (const row of rows) if (typeof row.id === "string") seen.add(row.id);
      await onRows(rows);
    };
    for (const coupleId of spec.author ? scope.all : scope.active) {
      await pagesOf(ctx, userId, table, coupleId, remember);
    }
    if (spec.referencedBy) {
      const wanted = (await reader.keys(spec.referencedBy.table, spec.referencedBy.field)).filter((id) => !seen.has(id));
      for (let start = 0; start < wanted.length; start += CHILD_BATCH) {
        const rows: Row[] = await ctx.runQuery(internal.dataExport.export_referenced_rows, {
          user_id: userId,
          table,
          ids: wanted.slice(start, start + CHILD_BATCH),
        });
        if (rows.length > 0) await onRows(rows);
      }
    }
    return;
  }

  const keys = await reader.keys(spec.parent, spec.parentKey);
  for (let start = 0; start < keys.length; start += CHILD_BATCH) {
    const rows: Row[] = await ctx.runQuery(internal.dataExport.export_children, {
      user_id: userId,
      table,
      keys: keys.slice(start, start + CHILD_BATCH),
    });
    if (rows.length > 0) await onRows(rows);
  }
}

/** For each table, the fields that another table reads from its rows. */
function neededKeys(tables: [string, ExportedTable][]): Map<string, Set<string>> {
  const needed = new Map<string, Set<string>>();
  const need = (table: string, key: string) => {
    if (!needed.has(table)) needed.set(table, new Set());
    needed.get(table)!.add(key);
  };
  for (const [, spec] of tables) {
    if (spec.kind === "child") need(spec.parent, spec.parentKey);
    if (spec.kind === "couple" && spec.referencedBy) need(spec.referencedBy.table, spec.referencedBy.field);
  }
  return needed;
}

function makeReader(ctx: ActionCtx, userId: string, scope: Scope): Reader {
  const reader: Reader = {
    ctx,
    userId,
    scope,
    cache: new Map(),
    // A table collected in this invocation has its keys cached. After the action went on in a new
    // invocation, the keys are read from the table again.
    keys: async (table, key) => {
      const cacheKey = `${table}.${key}`;
      const cached = reader.cache.get(cacheKey);
      if (cached) return cached;
      const spec = TABLE_EXPORTS[table as keyof typeof TABLE_EXPORTS];
      if (spec.kind === "excluded") throw new Error(`${table} is not exported`);
      const found = new Set<string>();
      await forEachBatch(reader, table, spec, async (rows) => {
        for (const row of rows) if (typeof row[key] === "string") found.add(row[key] as string);
      });
      const list = [...found];
      reader.cache.set(cacheKey, list);
      return list;
    },
  };
  return reader;
}

const encoder = new TextEncoder();

async function storeChunk(
  ctx: ActionCtx,
  exportId: string,
  table: string,
  group: ExportGroup,
  chunkIndex: number,
  chunk: { text: string; rows: number },
): Promise<void> {
  const bytes = encoder.encode(chunk.text);
  const deflated = await deflateRaw(bytes);
  // A blob without a type uploads with an empty Content-Type, which the self-hosted backend refuses.
  const blob = new Blob([deflated as BlobPart], { type: "application/octet-stream" });
  const recorded = await storeAndRecord(ctx.storage, blob, (storageId) =>
    ctx.runMutation(internal.dataExport.record_export_chunk, {
      export_id: exportId,
      source_table: table,
      group,
      chunk_index: chunkIndex,
      row_count: chunk.rows,
      size: bytes.length,
      crc: crc32(bytes),
      byte_size: deflated.length,
      storage_id: storageId,
    }),
  );
  if (!recorded) throw new ExportGone();
}

/** Collects one table into JSON files in storage. */
async function collectTable(
  reader: Reader,
  exportId: string,
  table: string,
  spec: ExportedTable,
  includeFiles: boolean,
  wantedKeys: Set<string> | undefined,
): Promise<void> {
  const chunker = new JsonChunker(exportChunkBytes());
  const kept = new Map<string, Set<string>>([...(wantedKeys ?? [])].map((key) => [key, new Set<string>()]));
  let chunkIndex = 0;

  await forEachBatch(reader, table, spec, async (rows) => {
    if (table === "media_assets") await addFilePaths(reader, rows, includeFiles);
    for (const row of rows) {
      for (const [key, found] of kept) if (typeof row[key] === "string") found.add(row[key] as string);
      const done = chunker.add(row);
      if (done) await storeChunk(reader.ctx, exportId, table, spec.group, chunkIndex++, done);
    }
  });
  const last = chunker.finish();
  if (last) await storeChunk(reader.ctx, exportId, table, spec.group, chunkIndex++, last);
  for (const [key, found] of kept) reader.cache.set(`${table}.${key}`, [...found]);
}

/** Sets `file` on `media_assets` rows: where the file sits in the archive, or null when it is not included. */
async function addFilePaths(reader: Reader, rows: Row[], includeFiles: boolean): Promise<void> {
  const pathById = new Map<string, string>();
  if (includeFiles) {
    const ids = rows.map((row) => row.id).filter((id): id is string => typeof id === "string");
    for (let start = 0; start < ids.length; start += MEDIA_PATH_BATCH) {
      const found = await reader.ctx.runQuery(internal.dataExport.export_media_paths, {
        user_id: reader.userId,
        asset_ids: ids.slice(start, start + MEDIA_PATH_BATCH),
      });
      for (const entry of found) pathById.set(entry.id, entry.path);
    }
  }
  for (const row of rows) row.file = pathById.get(row.id as string) ?? null;
}

/** Collects the person's data table by table. Goes on in a new action when the time budget is used. */
export const collect_data = internalAction({
  args: { export_id: v.string(), table_index: v.number() },
  handler: async (ctx, args): Promise<null> => {
    try {
      const job = await ctx.runQuery(internal.dataExport.get_export_job, { export_id: args.export_id });
      if (!job || job.status !== "preparing") return null;
      const started = Date.now();
      const report = progressReporter(ctx, args.export_id);
      const scope = await ctx.runQuery(internal.dataExport.export_scope, { user_id: job.user_id });
      const tables = exportedTablesInOrder();
      const needed = neededKeys(tables);
      const reader = makeReader(ctx, job.user_id, scope);

      for (let index = args.table_index; index < tables.length; index += 1) {
        if (index > args.table_index && Date.now() - started >= exportCollectBudgetMs()) {
          await ctx.scheduler.runAfter(0, internal.dataExportBuild.collect_data, {
            export_id: args.export_id,
            table_index: index,
          });
          return null;
        }
        const [table, spec] = tables[index]!;
        await collectTable(reader, args.export_id, table, spec, job.include_files, needed.get(table));
        await report(0.05 + 0.4 * ((index + 1) / tables.length));
      }
      await planExport(ctx, args.export_id, job);
    } catch (error) {
      await giveUp(ctx, args.export_id, error);
    }
    return null;
  },
});

/** Plans the zip parts from the data files and the media files, and starts building them. */
async function planExport(
  ctx: ActionCtx,
  exportId: string,
  job: { user_id: string; include_files: boolean },
): Promise<void> {
  const media: (PlannedFile & { path: string })[] = [];
  let skipped = 0;
  if (job.include_files) {
    let cursor: string | null = null;
    do {
      const page: Awaited<ReturnType<typeof readMediaPage>> = await readMediaPage(ctx, job.user_id, cursor);
      media.push(...page.files);
      skipped += page.skipped;
      cursor = page.cursor;
    } while (cursor !== null);
  }

  const chunks = await ctx.runQuery(internal.dataExport.list_export_chunks, { export_id: exportId });
  const countByTable = new Map<string, number>();
  for (const chunk of chunks) countByTable.set(chunk.source_table, (countByTable.get(chunk.source_table) ?? 0) + 1);
  const pathOf = (chunk: (typeof chunks)[number]) =>
    dataFilePath(
      EXPORT_GROUPS[chunk.group as ExportGroup].folder,
      chunk.source_table,
      chunk.chunk_index,
      countByTable.get(chunk.source_table)!,
    );

  const parts = planParts(
    [...chunks.map((chunk) => ({ id: chunk.id, size: chunk.byte_size })), ...media],
    FIRST_PART_RESERVE_BYTES,
    exportPartLimitBytes(),
  );
  const chunkIds = new Set(chunks.map((chunk) => chunk.id));
  const partOfChunk = new Map<string, number>();
  parts.forEach((ids, index) => ids.forEach((id) => partOfChunk.set(id, index + 1)));
  const date = new Date().toISOString().slice(0, 10);

  await ctx.runMutation(internal.dataExport.add_export_parts, {
    export_id: exportId,
    parts: parts.map((ids, index) => ({
      part_number: index + 1,
      file_name: partFileName(date, index + 1, parts.length),
      asset_ids: ids.filter((id) => !chunkIds.has(id)),
    })),
    chunks: chunks.map((chunk) => ({ chunk_id: chunk.id, path: pathOf(chunk), part_number: partOfChunk.get(chunk.id)! })),
    file_count: media.length,
    skipped_file_count: skipped,
    row_count: chunks.reduce((sum, chunk) => sum + chunk.row_count, 0),
  });
  await ctx.scheduler.runAfter(0, internal.dataExportBuild.build_part, { export_id: exportId, part_number: 1 });
}

async function readMediaPage(ctx: ActionCtx, userId: string, cursor: string | null) {
  return await ctx.runQuery(internal.dataExport.export_media_page, { user_id: userId, cursor });
}

/** Adds the media files of one part to `builder`. Returns how many files were gone from storage. */
async function addMediaFiles(
  ctx: ActionCtx,
  builder: ZipBuilder,
  userId: string,
  assetIds: readonly string[],
): Promise<number> {
  let missing = 0;
  for (let start = 0; start < assetIds.length; start += ASSET_BATCH) {
    const wanted = assetIds.slice(start, start + ASSET_BATCH);
    const assets = await ctx.runQuery(internal.dataExport.export_assets, { user_id: userId, asset_ids: wanted });
    missing += wanted.length - assets.length;
    for (const asset of assets) {
      const blob = await ctx.storage.get(asset.storage_id);
      if (!blob) {
        missing += 1;
        continue;
      }
      builder.addStoredBlob(asset.path, blob, crc32(new Uint8Array(await blob.arrayBuffer())));
    }
  }
  return missing;
}

/** Stores a finished zip file against its part. Returns false when the download no longer wants it. */
async function storePart(ctx: ActionCtx, exportId: string, partNumber: number, builder: ZipBuilder): Promise<boolean> {
  const blob = builder.toBlob();
  return await storeAndRecord(ctx.storage, blob, (storageId) =>
    ctx.runMutation(internal.dataExport.record_export_part, {
      export_id: exportId,
      part_number: partNumber,
      storage_id: storageId,
      byte_size: blob.size,
    }),
  );
}

async function giveUp(ctx: ActionCtx, exportId: string, error: unknown): Promise<void> {
  if (error instanceof ExportGone) return;
  console.error("[data-export] build failed", error instanceof Error ? error.message : error);
  await ctx.runMutation(internal.dataExport.fail_export, { export_id: exportId, error_code: "export_failed" });
}

/** The README and the manifest, for part 1. */
async function addReadmeAndManifest(
  ctx: ActionCtx,
  builder: ZipBuilder,
  exportId: string,
  job: { user_id: string; locale: "en" | "nb"; include_files: boolean; file_count: number; skipped_file_count: number; created_at: string },
): Promise<void> {
  const chunks = await ctx.runQuery(internal.dataExport.list_export_chunks, { export_id: exportId });
  const parts = await ctx.runQuery(internal.dataExport.list_export_parts, { export_id: exportId });
  const partNames = parts.map((part) => part.file_name);
  const generatedAt = new Date().toISOString();
  const specOf = (table: string) => TABLE_EXPORTS[table as keyof typeof TABLE_EXPORTS] as ExportedTable;

  const readmeFiles: ReadmeFile[] = chunks.map((chunk) => ({
    path: chunk.path!,
    group: chunk.group as ExportGroup,
    rows: chunk.row_count,
    about: specOf(chunk.source_table).about[job.locale],
  }));
  const manifest = {
    format: "paeonia-data-export",
    format_version: 2,
    generated_at: generatedAt,
    user_id: job.user_id,
    language: job.locale,
    includes_files: job.include_files,
    zip_files: partNames,
    files: chunks.map((chunk) => ({
      path: chunk.path,
      zip_file: partNames[chunk.part_number! - 1],
      table: chunk.source_table,
      group: chunk.group,
      entries: chunk.row_count,
      about: specOf(chunk.source_table).about,
    })),
    media_files: { included: job.file_count, left_out: job.skipped_file_count },
    not_included: Object.entries(TABLE_EXPORTS)
      .filter(([, spec]) => spec.kind === "excluded")
      .map(([table, spec]) => ({ table, reason: spec.kind === "excluded" ? spec.reason : "" })),
  };
  const readme = renderReadme({
    locale: job.locale,
    generatedAt,
    userId: job.user_id,
    includeFiles: job.include_files,
    partNames,
    files: readmeFiles,
    mediaCount: job.file_count,
    mediaSkippedCount: job.skipped_file_count,
  });
  await builder.addFile("README.md", encoder.encode(readme), { compress: true });
  await builder.addFile("manifest.json", encoder.encode(JSON.stringify(manifest, null, 2)), { compress: true });
}

/** Builds one zip file, stores it, and schedules the next one. The last one marks the export ready. */
export const build_part = internalAction({
  args: { export_id: v.string(), part_number: v.number() },
  handler: async (ctx, args): Promise<null> => {
    try {
      const job = await ctx.runQuery(internal.dataExport.get_export_job, { export_id: args.export_id });
      const part = await ctx.runQuery(internal.dataExport.get_export_part, {
        export_id: args.export_id,
        part_number: args.part_number,
      });
      if (!job || job.status !== "preparing" || !part) return null;
      const parts = await ctx.runQuery(internal.dataExport.list_export_parts, { export_id: args.export_id });

      const builder = new ZipBuilder();
      if (args.part_number === 1) await addReadmeAndManifest(ctx, builder, args.export_id, job);
      const chunks = await ctx.runQuery(internal.dataExport.list_export_chunks, {
        export_id: args.export_id,
        part_number: args.part_number,
      });
      for (const chunk of chunks) {
        const blob = await ctx.storage.get(chunk.storage_id);
        if (!blob) throw new Error(`data file ${chunk.path} is gone from storage`);
        builder.addDeflatedBlob(chunk.path!, blob, chunk.crc, chunk.size);
      }
      const missing = await addMediaFiles(ctx, builder, job.user_id, part.asset_ids);
      if (missing > 0) await ctx.runMutation(internal.dataExport.add_skipped_files, { export_id: args.export_id, count: missing });

      if (!(await storePart(ctx, args.export_id, args.part_number, builder))) return null;
      await ctx.runMutation(internal.dataExport.drop_part_chunks, { export_id: args.export_id, part_number: args.part_number });
      await finishOrContinue(ctx, args.export_id, args.part_number, parts.length);
    } catch (error) {
      await giveUp(ctx, args.export_id, error);
    }
    return null;
  },
});

async function finishOrContinue(ctx: ActionCtx, exportId: string, partNumber: number, partCount: number): Promise<void> {
  if (partNumber < partCount) {
    await ctx.runMutation(internal.dataExport.set_export_progress, {
      export_id: exportId,
      progress: 0.5 + 0.49 * (partNumber / partCount),
    });
    await ctx.scheduler.runAfter(0, internal.dataExportBuild.build_part, {
      export_id: exportId,
      part_number: partNumber + 1,
    });
    return;
  }
  await ctx.runMutation(internal.dataExport.finish_export, { export_id: exportId });
}
