import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, TableNames } from "./_generated/dataModel";
import { httpAction, internalMutation, internalQuery, mutation, type MutationCtx } from "./_generated/server";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { hmacSha256Hex, timingSafeEqual } from "./lib/crypto";
import { EXPORT_VALID_DAYS, TABLE_EXPORTS, isExportableMedia, mediaFilePath, shapeRow } from "./lib/dataExportRegistry";
import { expireDataExport, removeExportChunks, removeExportParts } from "./lib/dataExportFiles";
import { getByUuid, withUpdatedAt, type ReaderCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { newUuid, uuidArg } from "./lib/ids";
import { enqueueNotificationForUser, notificationLocaleLanguage } from "./lib/notifications";
import { consumeRateLimit } from "./lib/rateLimits";
import { exportRow, latestExport } from "./dataExportStatus";
import { addDaysToInstant, addMs, nowIso } from "./lib/time";

// "Download my data" (GDPR Art. 15 and 20). What the export holds is decided in one place,
// lib/dataExportRegistry.ts. This module has the person-facing functions, the paged reads the
// build action uses (dataExportBuild.ts), and the signed download link. docs/privacy-and-data-export.md
// explains the design.

const PAGE_SIZE = 200;
/** Children of one parent row. A parent with more than this fails the export loudly. */
const CHILD_MAX = 50;
const CHILD_BATCH_MAX = 100;
const MEDIA_PAGE_SIZE = 200;
/** A build that has not finished after this long is given up on. */
const STALE_BUILD_MS = 2 * 3_600_000;
const LINK_VALID_SECONDS = 3600;
const KEEP_ENDED_ROWS_DAYS = 30;

type Row = Record<string, unknown>;

const cursorArg = v.union(v.null(), v.string());

/**
 * Starts a download of everything Paeonia holds about the signed-in person. A download that is still
 * being built is returned as it is. A finished one is replaced. Anyone signed in can ask, with or
 * without a subscription. Limited to a few a day.
 */
export const request_data_export = mutation({
  args: { p_include_files: v.boolean(), p_language: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const latest = await latestExport(ctx, userId);
    if (latest?.status === "preparing") return exportRow(latest);

    await consumeRateLimit(ctx, "dataExportRequest", userId);
    if (latest?.status === "ready") await expireDataExport(ctx, latest);

    const now = nowIso();
    const id = newUuid();
    await ctx.db.insert("data_exports", {
      id,
      user_id: userId,
      status: "preparing",
      locale: notificationLocaleLanguage(args.p_language),
      include_files: args.p_include_files,
      progress: 0,
      row_count: 0,
      file_count: 0,
      skipped_file_count: 0,
      part_count: 0,
      byte_size: 0,
      created_at: now,
      updated_at: now,
    });
    await ctx.scheduler.runAfter(0, internal.dataExportBuild.collect_data, { export_id: id, table_index: 0 });
    return exportRow((await getByUuid(ctx, "data_exports", id))!);
  },
});

/** Deletes a finished download from our servers before it expires. */
export const delete_data_export = mutation({
  args: { p_export_id: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    const userId = await requireUserId(ctx);
    const row = await getByUuid(ctx, "data_exports", uuidArg(args.p_export_id));
    if (!row || row.user_id !== userId) return false;
    if (row.status === "preparing" || row.status === "ready") await expireDataExport(ctx, row);
    return true;
  },
});

// ---- download link ----

function signingSecret(): string {
  const secret = process.env.PAEONIA_MEDIA_URL_SECRET;
  if (!secret) throw new Error("PAEONIA_MEDIA_URL_SECRET is not set");
  return secret;
}

const signedMessage = (partId: string, expiresAtSeconds: number | string) => `data-export.${partId}.${expiresAtSeconds}`;

/**
 * One signed `GET /data-export` link for each zip file of a finished download. A link works for an
 * hour without an auth header, so the phone can hand it to a background download.
 */
export const create_data_export_download_links = mutation({
  args: { p_export_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const row = await getByUuid(ctx, "data_exports", uuidArg(args.p_export_id));
    if (!row || row.user_id !== userId || row.status !== "ready" || (row.expires_at ?? "") <= nowIso()) {
      return fail("42501", "data export is not available");
    }
    const site = process.env.CONVEX_SITE_URL;
    if (!site) throw new Error("CONVEX_SITE_URL is not set");
    const expiresAtSeconds = Math.floor(Date.now() / 1000) + LINK_VALID_SECONDS;
    const parts = await ctx.db
      .query("data_export_parts")
      .withIndex("by_export_id_part_number", (q) => q.eq("export_id", row.id))
      .collect();
    const links = [];
    for (const part of parts) {
      if (!part.storage_id) return fail("42501", "data export is not available");
      const sig = await hmacSha256Hex(signingSecret(), signedMessage(part.id, expiresAtSeconds));
      links.push({
        part_number: part.part_number,
        file_name: part.file_name,
        byte_size: part.byte_size ?? 0,
        url: `${site.replace(/\/+$/, "")}/data-export?part=${part.id}&exp=${expiresAtSeconds}&sig=${sig}`,
        expires_at: new Date(expiresAtSeconds * 1000).toISOString(),
      });
    }
    return links;
  },
});

/** What `GET /data-export` needs to serve a zip file, or null when it cannot be served. */
export const get_part_for_serve = internalQuery({
  args: { part_id: v.string() },
  handler: async (ctx, args) => {
    const part = await getByUuid(ctx, "data_export_parts", args.part_id);
    const row = part ? await getByUuid(ctx, "data_exports", part.export_id) : null;
    if (!part?.storage_id || !row || row.status !== "ready" || (row.expires_at ?? "") <= nowIso()) return null;
    const stored = await ctx.db.system.get(part.storage_id);
    return { storage_id: part.storage_id, file_name: part.file_name, byte_size: stored?.size ?? part.byte_size ?? null };
  },
});

/** `GET /data-export?part=&exp=&sig=`. The signature from `create_data_export_download_links` is the only credential. */
export const serve_data_export = httpAction(async (ctx, request) => {
  const params = new URL(request.url).searchParams;
  const part = params.get("part") ?? "";
  const exp = params.get("exp") ?? "";
  const sig = params.get("sig") ?? "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(part) || !/^\d{1,12}$/.test(exp)) {
    return new Response("invalid download link", { status: 400 });
  }
  const secret = process.env.PAEONIA_MEDIA_URL_SECRET;
  if (!secret) return new Response("downloads are not configured", { status: 500 });
  const expected = await hmacSha256Hex(secret, signedMessage(part, exp));
  if (!timingSafeEqual(expected, sig.toLowerCase())) return new Response("invalid download link", { status: 403 });
  if (Number(exp) * 1000 < Date.now()) return new Response("download link expired", { status: 403 });

  const target = await ctx.runQuery(internal.dataExport.get_part_for_serve, { part_id: part });
  const blob = target ? await ctx.storage.get(target.storage_id) : null;
  if (!target || !blob) return new Response("not found", { status: 404 });
  return new Response(blob.stream(), {
    status: 200,
    headers: {
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="${target.file_name}"`,
      ...(target.byte_size === null ? {} : { "Content-Length": String(target.byte_size) }),
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
});

// ---- reads for the build action ----
// These are internal. The action passes the user id of the export job, and every read below
// takes its scope from the registry and the user's own memberships, never from the arguments.

/** The couples the person is or was in: `all`, and the ones they are in now: `active`. */
export async function exportCoupleScope(ctx: ReaderCtx, userId: string): Promise<{ all: string[]; active: string[] }> {
  const memberships = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId))
    .collect();
  const all: string[] = [];
  const active: string[] = [];
  for (const member of memberships) {
    const couple = await getByUuid(ctx, "couples", member.couple_id);
    if (!couple) continue;
    all.push(couple.id);
    if (member.status === "active" && couple.status === "active") active.push(couple.id);
  }
  return { all, active };
}

export const export_scope = internalQuery({
  args: { user_id: v.string() },
  handler: async (ctx, args) => await exportCoupleScope(ctx, args.user_id),
});

/** One page of an `own` or `couple` table. `scope_value` is the couple id for a couple table. */
export const export_rows = internalQuery({
  args: { user_id: v.string(), table: v.string(), scope_value: v.optional(v.string()), cursor: cursorArg },
  handler: async (ctx, args): Promise<{ rows: Row[]; cursor: string | null }> => {
    const spec = TABLE_EXPORTS[args.table as TableNames];
    if (!spec || spec.kind === "excluded" || spec.kind === "child") return fail("22023", "table is not exported by page");
    let field: string;
    let value: string;
    if (spec.kind === "own") {
      field = spec.field;
      value = args.user_id;
    } else {
      const scope = await exportCoupleScope(ctx, args.user_id);
      value = args.scope_value ?? "";
      if (!(spec.author ? scope.all : scope.active).includes(value)) return fail("42501", "couple is not part of this export");
      field = "couple_id";
    }
    const page = await (ctx.db.query(args.table as never) as any)
      .withIndex(spec.index, (q: any) => q.eq(field, value))
      .paginate({ numItems: PAGE_SIZE, cursor: args.cursor });
    const rows: Row[] = [];
    for (const doc of page.page as Row[]) {
      if (spec.kind === "couple" && spec.author && doc[spec.author] !== args.user_id) continue;
      const shaped = shapeRow(spec, doc, args.user_id);
      if (shaped) rows.push(shaped);
    }
    return { rows, cursor: page.isDone ? null : page.continueCursor };
  },
});

/** The rows of a `child` table that hang off the given parent keys. */
export const export_children = internalQuery({
  args: { user_id: v.string(), table: v.string(), keys: v.array(v.string()) },
  handler: async (ctx, args): Promise<Row[]> => {
    const spec = TABLE_EXPORTS[args.table as TableNames];
    if (!spec || spec.kind !== "child") return fail("22023", "table is not exported through a parent");
    if (args.keys.length > CHILD_BATCH_MAX) return fail("22023", "too many parent keys");
    const rows: Row[] = [];
    for (const key of args.keys) {
      const docs = (await (ctx.db.query(args.table as never) as any)
        .withIndex(spec.index, (q: any) => q.eq(spec.field, key))
        .take(CHILD_MAX + 1)) as Row[];
      if (docs.length > CHILD_MAX) return fail("54000", `${args.table} has too many rows for one parent`);
      for (const doc of docs) {
        const shaped = shapeRow(spec, doc, args.user_id);
        if (shaped) rows.push(shaped);
      }
    }
    return rows;
  },
});

/**
 * The rows that `spec.referencedBy` adds: rows of the person's couples that the person's own rows
 * point to, and that the author filter left out. A row is returned only if the person has a row
 * pointing to it, so the ids in the arguments cannot reach anything else.
 */
export const export_referenced_rows = internalQuery({
  args: { user_id: v.string(), table: v.string(), ids: v.array(v.string()) },
  handler: async (ctx, args): Promise<Row[]> => {
    const spec = TABLE_EXPORTS[args.table as TableNames];
    if (!spec || spec.kind !== "couple" || !spec.referencedBy) return fail("22023", "table has no referenced rows");
    if (args.ids.length > CHILD_BATCH_MAX) return fail("22023", "too many ids");
    const { referencedBy } = spec;
    const scope = await exportCoupleScope(ctx, args.user_id);
    const rows: Row[] = [];
    for (const id of args.ids) {
      const doc = (await getByUuid(ctx, args.table as never, id)) as Row | null;
      if (!doc || typeof doc.couple_id !== "string" || !scope.all.includes(doc.couple_id)) continue;
      const mine = await (ctx.db.query(referencedBy.table as never) as any)
        .withIndex(referencedBy.index, (q: any) => q.eq(referencedBy.field, id).eq("user_id", args.user_id))
        .first();
      if (!mine) continue;
      const shaped = shapeRow(spec, doc, args.user_id);
      if (shaped) rows.push(shaped);
    }
    return rows;
  },
});

/** The archive path of each of the person's files that the export includes, for the `file` field of `media_assets` rows. */
export const export_media_paths = internalQuery({
  args: { user_id: v.string(), asset_ids: v.array(v.string()) },
  handler: async (ctx, args): Promise<{ id: string; path: string }[]> => {
    if (args.asset_ids.length > MEDIA_PAGE_SIZE) return fail("22023", "too many ids");
    const found = [];
    for (const id of args.asset_ids) {
      const asset = await getByUuid(ctx, "media_assets", id);
      if (!asset || asset.owner_user_id !== args.user_id || !isExportableMedia(asset) || !asset.storage_id) continue;
      if (await ctx.db.system.get(asset.storage_id)) found.push({ id, path: mediaFilePath(asset) });
    }
    return found;
  },
});

export type MediaPlanEntry = { id: string; path: string; size: number };

/**
 * One page of the files the person uploaded: the ones the export can include, with their path in the
 * archive and their stored size, and how many finished uploads it has to leave out.
 */
export const export_media_page = internalQuery({
  args: { user_id: v.string(), cursor: cursorArg },
  handler: async (ctx, args): Promise<{ files: MediaPlanEntry[]; skipped: number; cursor: string | null }> => {
    const page = await ctx.db
      .query("media_assets")
      .withIndex("by_owner_user_id_created_at", (q) => q.eq("owner_user_id", args.user_id))
      .paginate({ numItems: MEDIA_PAGE_SIZE, cursor: args.cursor });
    const files: MediaPlanEntry[] = [];
    let skipped = 0;
    for (const asset of page.page) {
      if (asset.upload_status !== "finalized" || asset.bucket === "report-snapshots") continue;
      const stored = isExportableMedia(asset) && asset.storage_id ? await ctx.db.system.get(asset.storage_id) : null;
      if (stored) files.push({ id: asset.id, path: mediaFilePath(asset), size: stored.size });
      else skipped += 1;
    }
    return { files, skipped, cursor: page.isDone ? null : page.continueCursor };
  },
});

/** The files of one zip part, read again by id so the part never trusts the plan's paths. */
export const export_assets = internalQuery({
  args: { user_id: v.string(), asset_ids: v.array(v.string()) },
  handler: async (ctx, args) => {
    const found = [];
    for (const id of args.asset_ids) {
      const asset = await getByUuid(ctx, "media_assets", id);
      if (asset?.owner_user_id === args.user_id && isExportableMedia(asset) && asset.storage_id) {
        found.push({ id: asset.id, path: mediaFilePath(asset), storage_id: asset.storage_id });
      }
    }
    return found;
  },
});

// ---- the job ----

export const get_export_job = internalQuery({
  args: { export_id: v.string() },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    return row ? { ...exportRow(row), user_id: row.user_id, locale: row.locale } : null;
  },
});

export const get_export_part = internalQuery({
  args: { export_id: v.string(), part_number: v.number() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("data_export_parts")
      .withIndex("by_export_id_part_number", (q) => q.eq("export_id", args.export_id).eq("part_number", args.part_number))
      .unique(),
});

export const list_export_parts = internalQuery({
  args: { export_id: v.string() },
  handler: async (ctx, args) =>
    (
      await ctx.db
        .query("data_export_parts")
        .withIndex("by_export_id_part_number", (q) => q.eq("export_id", args.export_id))
        .collect()
    ).map((part) => ({ part_number: part.part_number, file_name: part.file_name, stored: part.storage_id !== undefined })),
});

/** Stores one JSON data file the build wrote. Returns false (and deletes the file) when the download no longer wants it. */
export const record_export_chunk = internalMutation({
  args: {
    export_id: v.string(),
    source_table: v.string(),
    group: v.string(),
    chunk_index: v.number(),
    row_count: v.number(),
    size: v.number(),
    crc: v.number(),
    byte_size: v.number(),
    storage_id: v.id("_storage"),
  },
  handler: async (ctx, args): Promise<boolean> => {
    const { export_id, ...chunk } = args;
    const row = await getByUuid(ctx, "data_exports", export_id);
    if (!row || row.status !== "preparing") {
      await ctx.storage.delete(args.storage_id);
      return false;
    }
    await ctx.db.insert("data_export_chunks", { id: newUuid(), export_id: row.id, ...chunk, created_at: nowIso() });
    return true;
  },
});

const chunkView = (chunk: Doc<"data_export_chunks">) => ({
  id: chunk.id,
  source_table: chunk.source_table,
  group: chunk.group,
  chunk_index: chunk.chunk_index,
  row_count: chunk.row_count,
  size: chunk.size,
  crc: chunk.crc,
  byte_size: chunk.byte_size,
  storage_id: chunk.storage_id,
  path: chunk.path ?? null,
  part_number: chunk.part_number ?? null,
});

/** The data files of an export in the order they were written: all of them, or those planned into one part. */
export const list_export_chunks = internalQuery({
  args: { export_id: v.string(), part_number: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const chunks = await ctx.db
      .query("data_export_chunks")
      .withIndex("by_export_id_part_number", (q) =>
        args.part_number === undefined
          ? q.eq("export_id", args.export_id)
          : q.eq("export_id", args.export_id).eq("part_number", args.part_number),
      )
      .collect();
    return chunks.sort((a, b) => a._creationTime - b._creationTime).map(chunkView);
  },
});

/** Records the zip files the build plans, with the media files and data files each one holds. */
export const add_export_parts = internalMutation({
  args: {
    export_id: v.string(),
    parts: v.array(v.object({ part_number: v.number(), file_name: v.string(), asset_ids: v.array(v.string()) })),
    chunks: v.array(v.object({ chunk_id: v.string(), path: v.string(), part_number: v.number() })),
    file_count: v.number(),
    skipped_file_count: v.number(),
    row_count: v.number(),
  },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    if (!row || row.status !== "preparing") return false;
    const now = nowIso();
    for (const part of args.parts) {
      await ctx.db.insert("data_export_parts", { id: newUuid(), export_id: row.id, ...part, created_at: now });
    }
    for (const placed of args.chunks) {
      const chunk = await getByUuid(ctx, "data_export_chunks", placed.chunk_id);
      if (!chunk || chunk.export_id !== row.id) return fail("22023", "data file is not part of this export");
      await ctx.db.patch(chunk._id, { path: placed.path, part_number: placed.part_number });
    }
    await ctx.db.patch(
      row._id,
      withUpdatedAt({
        part_count: args.parts.length,
        file_count: args.file_count,
        skipped_file_count: args.skipped_file_count,
        row_count: args.row_count,
      }),
    );
    return true;
  },
});

/** Deletes the data files of one part once its zip file is stored. */
export const drop_part_chunks = internalMutation({
  args: { export_id: v.string(), part_number: v.number() },
  handler: async (ctx, args) => {
    await removeExportChunks(ctx, args.export_id, args.part_number);
  },
});

/** Moves the progress bar forward. It never moves back. */
export const set_export_progress = internalMutation({
  args: { export_id: v.string(), progress: v.number() },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    if (!row || row.status !== "preparing" || args.progress <= row.progress) return;
    await ctx.db.patch(row._id, withUpdatedAt({ progress: Math.min(args.progress, 0.99) }));
  },
});

/** Stores one finished zip file against its part. Returns false when the download no longer wants it. */
export const record_export_part = internalMutation({
  args: { export_id: v.string(), part_number: v.number(), storage_id: v.id("_storage"), byte_size: v.number() },
  handler: async (ctx, args): Promise<boolean> => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    const part = await ctx.db
      .query("data_export_parts")
      .withIndex("by_export_id_part_number", (q) => q.eq("export_id", args.export_id).eq("part_number", args.part_number))
      .unique();
    if (!row || row.status !== "preparing" || !part) {
      await ctx.storage.delete(args.storage_id);
      return false;
    }
    await ctx.db.patch(part._id, { storage_id: args.storage_id, byte_size: args.byte_size });
    return true;
  },
});

/** Counts files that were stored when planned but gone when the part was built. */
export const add_skipped_files = internalMutation({
  args: { export_id: v.string(), count: v.number() },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    if (row && row.status === "preparing" && args.count > 0) {
      await ctx.db.patch(
        row._id,
        withUpdatedAt({ skipped_file_count: row.skipped_file_count + args.count, file_count: Math.max(0, row.file_count - args.count) }),
      );
    }
  },
});

/** Marks the download ready for three days, and tells the person with a push. */
export const finish_export = internalMutation({
  args: { export_id: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    if (!row || row.status !== "preparing") return false;
    const parts = await ctx.db
      .query("data_export_parts")
      .withIndex("by_export_id_part_number", (q) => q.eq("export_id", row.id))
      .collect();
    if (parts.length === 0 || parts.some((part) => !part.storage_id)) return fail("P0001", "data export has missing parts");
    const now = nowIso();
    await ctx.db.patch(
      row._id,
      withUpdatedAt({
        status: "ready" as const,
        progress: 1,
        ready_at: now,
        expires_at: addDaysToInstant(now, EXPORT_VALID_DAYS),
        byte_size: parts.reduce((sum, part) => sum + (part.byte_size ?? 0), 0),
        error_code: undefined,
      }),
    );
    await enqueueNotificationForUser(ctx, {
      recipient_user_id: row.user_id,
      kind: "data_export_ready",
      payload: {
        type: "data_export_ready",
        route: "data_export",
        deeplink: "paeonia://settings/data-export",
        export_id: row.id,
      },
      dedupe_key: `data_export_ready:${row.id}`,
      redaction_level: "private",
      apns_push_type: "alert",
      apns_collapse_id: `data-export:${row.id}`,
      scheduled_for: now,
    });
    return true;
  },
});

/** Gives up on a download. Its files are deleted and the person can ask again. */
export const fail_export = internalMutation({
  args: { export_id: v.string(), error_code: v.string() },
  handler: async (ctx, args) => {
    const row = await getByUuid(ctx, "data_exports", args.export_id);
    if (!row || row.status !== "preparing") return;
    await failExport(ctx, row, args.error_code);
  },
});

async function failExport(ctx: MutationCtx, row: Doc<"data_exports">, errorCode: string): Promise<void> {
  await removeExportParts(ctx, row.id);
  await ctx.db.patch(row._id, withUpdatedAt({ status: "failed" as const, error_code: errorCode }));
}

/**
 * The hourly job. Deletes the files of downloads that ran out their days, gives up on builds that
 * never finished, and forgets old ended downloads. Runs again right away while more are due.
 */
export const expire_data_exports = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = nowIso();
    const BATCH = 25;
    const due = await ctx.db
      .query("data_exports")
      .withIndex("by_status_expires_at", (q) => q.eq("status", "ready").lte("expires_at", now))
      .take(BATCH);
    for (const row of due) await expireDataExport(ctx, row);

    const stuck = await ctx.db
      .query("data_exports")
      .withIndex("by_status_expires_at", (q) => q.eq("status", "preparing"))
      .take(BATCH);
    const staleBefore = addMs(now, -STALE_BUILD_MS);
    let failed = 0;
    for (const row of stuck) {
      if (row.created_at >= staleBefore) continue;
      await failExport(ctx, row, "export_timed_out");
      failed += 1;
    }

    const forgetBefore = addDaysToInstant(now, -KEEP_ENDED_ROWS_DAYS);
    let forgotten = 0;
    for (const status of ["expired", "failed"] as const) {
      const old = await ctx.db
        .query("data_exports")
        .withIndex("by_status_expires_at", (q) => q.eq("status", status))
        .take(BATCH);
      for (const row of old) {
        if (row.updated_at >= forgetBefore) continue;
        await ctx.db.delete(row._id);
        forgotten += 1;
      }
    }
    if (due.length === BATCH || failed === BATCH || forgotten >= BATCH) {
      await ctx.scheduler.runAfter(0, internal.dataExport.expire_data_exports, {});
    }
  },
});
