import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation } from "./_generated/server";
import { canAccessCoupleContent, getCurrentEntitledCoupleId, isActiveCoupleMember } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { getByUuid, orNull, withTouch, withUpdatedAt } from "./lib/db";
import { checkViolation, fail, uniqueViolation } from "./lib/errors";
import { dateArg, newUuid, optionalTimestampArg, optionalUuidArg, uuidArg } from "./lib/ids";
import { queueMemoryMediaAssetsIfOrphaned, queueThreadMediaAssetsIfOrphaned } from "./lib/mediaOrphans";
import { enqueueMemoryCreatedNotification } from "./lib/notifications";
import { btrimToNull, charLength } from "./lib/text";
import { nowIso } from "./lib/time";

const nullableUuidArray = v.optional(v.union(v.null(), v.array(v.string())));

/** Port of `internal.normalize_memory_title`. */
export function normalizeMemoryTitle(title: string | null | undefined): string {
  const normalized = btrimToNull(title);
  if (normalized === null) return fail("23514", "memory title is required");
  if (charLength(normalized) > 160) return fail("23514", "memory title is too long");
  return normalized;
}

/** Port of `internal.normalize_memory_note_body`. */
export function normalizeMemoryNoteBody(body: string | null | undefined): string {
  const normalized = btrimToNull(body);
  if (normalized === null) return fail("23514", "memory note body is required");
  if (charLength(normalized) > 4000) return fail("23514", "memory note body is too long");
  return normalized;
}

/** Port of `assert_memory_member_allowed`. */
export async function assertMemoryMemberAllowed(
  ctx: ReaderCtx,
  coupleId: string,
  createdByUserId: string,
  lastEditedByUserId: string,
): Promise<void> {
  if (
    !(await isActiveCoupleMember(ctx, createdByUserId, coupleId)) ||
    !(await isActiveCoupleMember(ctx, lastEditedByUserId, coupleId))
  ) {
    fail("23514", "memory users must be active couple members");
  }
}

/** Port of `assert_memory_note_allowed`. */
export async function assertMemoryNoteAllowed(ctx: ReaderCtx, memoryId: string, userId: string): Promise<void> {
  const memory = await getByUuid(ctx, "memories", memoryId);
  if (
    !memory ||
    memory.deleted_at !== undefined ||
    memory.moderation_status !== "visible" ||
    !(await isActiveCoupleMember(ctx, userId, memory.couple_id))
  ) {
    fail("23514", "memory note user must be an active memory couple member");
  }
}

/** Port of `assert_memory_media_allowed`. */
export async function assertMemoryMediaAllowed(
  ctx: ReaderCtx,
  row: { id: string; memory_id: string; media_asset_id: string; owner_user_id: string },
): Promise<void> {
  const memory = await getByUuid(ctx, "memories", row.memory_id);
  if (!memory || memory.deleted_at !== undefined || memory.moderation_status !== "visible") {
    fail("23503", "visible memory was not found for media attachment");
  }
  const asset = await getByUuid(ctx, "media_assets", row.media_asset_id);
  if (
    !asset ||
    asset.owner_user_id !== row.owner_user_id ||
    asset.couple_id !== memory.couple_id ||
    asset.reserved_parent_kind !== "memory_media" ||
    asset.reserved_parent_id !== row.id ||
    !["memory_photo", "voice_note"].includes(asset.upload_purpose) ||
    !["image", "voice"].includes(asset.media_type) ||
    asset.upload_status !== "finalized" ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    fail("23514", "memory media asset is not usable");
  }
}

/**
 * Inserts a memories row. Runs `assert_memory_member_allowed` first and the
 * `enqueue_memory_created_notification` trigger after.
 */
export async function insertMemory(
  ctx: WriterCtx,
  row: {
    id: string;
    couple_id: string;
    title: string;
    memory_date: string;
    created_by_user_id: string;
    last_edited_by_user_id: string;
  },
): Promise<Doc<"memories">> {
  await assertMemoryMemberAllowed(ctx, row.couple_id, row.created_by_user_id, row.last_edited_by_user_id);
  if (await getByUuid(ctx, "memories", row.id)) uniqueViolation("memories_pkey");
  const now = nowIso();
  const docId = await ctx.db.insert("memories", {
    ...row,
    revision: 1,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  const memory = (await ctx.db.get(docId))!;
  await enqueueMemoryCreatedNotification(ctx, memory);
  return memory;
}

/**
 * Patches a memory: the `touch_updated_at_and_revision` trigger plus the
 * `assert_memory_member_allowed` check on the editor. Returns the patched row.
 */
export async function patchMemory(
  ctx: WriterCtx,
  memory: Doc<"memories">,
  patch: { title?: string; memory_date?: string; last_edited_by_user_id: string; deleted_at?: string },
): Promise<Doc<"memories">> {
  await assertMemoryMemberAllowed(ctx, memory.couple_id, memory.created_by_user_id, patch.last_edited_by_user_id);
  await ctx.db.patch(memory._id, withTouch(memory, patch));
  return (await ctx.db.get(memory._id))!;
}

async function insertMemoryNote(
  ctx: WriterCtx,
  row: { memory_id: string; user_id: string; body: string },
): Promise<Doc<"memory_notes">> {
  await assertMemoryNoteAllowed(ctx, row.memory_id, row.user_id);
  const existing = await ctx.db
    .query("memory_notes")
    .withIndex("by_memory_id_user_id", (q) => q.eq("memory_id", row.memory_id).eq("user_id", row.user_id))
    .first();
  if (existing) uniqueViolation("memory_notes_memory_user_unique");
  const now = nowIso();
  const docId = await ctx.db.insert("memory_notes", {
    id: newUuid(),
    ...row,
    revision: 1,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
  return (await ctx.db.get(docId))!;
}

async function insertMemoryMedia(
  ctx: WriterCtx,
  row: { id: string; memory_id: string; media_asset_id: string; owner_user_id: string; sort_order: number },
): Promise<void> {
  await assertMemoryMediaAllowed(ctx, row);
  if (row.sort_order < 1 || row.sort_order > 20) {
    checkViolation("memory_media", "memory_media_sort_order_check");
  }
  if (await getByUuid(ctx, "memory_media", row.id)) uniqueViolation("memory_media_pkey");
  const sameAsset = await ctx.db
    .query("memory_media")
    .withIndex("by_memory_id_media_asset_id", (q) =>
      q.eq("memory_id", row.memory_id).eq("media_asset_id", row.media_asset_id),
    )
    .first();
  if (sameAsset) uniqueViolation("memory_media_memory_asset_unique");
  const sameSlot = await ctx.db
    .query("memory_media")
    .withIndex("by_memory_id_owner_user_id_sort_order", (q) =>
      q.eq("memory_id", row.memory_id).eq("owner_user_id", row.owner_user_id).eq("sort_order", row.sort_order),
    )
    .collect();
  if (sameSlot.some((link) => link.deleted_at === undefined)) {
    uniqueViolation("memory_media_active_owner_sort_order_idx");
  }
  const now = nowIso();
  await ctx.db.insert("memory_media", {
    ...row,
    moderation_status: "visible",
    created_at: now,
    updated_at: now,
  });
}

/** The memory, if the caller may write to it. Fails with 42501 otherwise. */
async function requireWritableMemory(ctx: ReaderCtx, userId: string, memoryId: string): Promise<Doc<"memories">> {
  const memory = await getByUuid(ctx, "memories", memoryId);
  if (
    !memory ||
    memory.deleted_at !== undefined ||
    memory.moderation_status !== "visible" ||
    !(await canAccessCoupleContent(ctx, userId, memory.couple_id))
  ) {
    return fail("42501", "active entitled memory access is required");
  }
  return memory;
}

/** Port of `internal.attach_memory_media_assets`. Returns the new memory_media ids. */
export async function attachMemoryMediaAssets(
  ctx: WriterCtx,
  userId: string,
  memoryId: string,
  mediaAssetIds: string[],
): Promise<string[]> {
  const mediaIds = mediaAssetIds.map(uuidArg);
  if (mediaIds.length === 0) return [];
  if (mediaIds.length > 10) fail("23514", "a memory can attach at most 10 media assets at once");
  if (new Set(mediaIds).size !== mediaIds.length) fail("23514", "memory media asset ids must be unique");

  const memory = await requireWritableMemory(ctx, userId, memoryId);

  const mine = await ctx.db
    .query("memory_media")
    .withIndex("by_memory_id_owner_user_id_sort_order", (q) => q.eq("memory_id", memory.id).eq("owner_user_id", userId))
    .collect();
  let activeImageCount = 0;
  let maxSortOrder = 0;
  for (const link of mine) {
    if (link.deleted_at !== undefined) continue;
    maxSortOrder = Math.max(maxSortOrder, link.sort_order);
    if (link.moderation_status !== "visible") continue;
    const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
    if (asset && asset.media_type === "image" && asset.deleted_at === undefined && asset.moderation_status === "visible") {
      activeImageCount += 1;
    }
  }

  const inserted: string[] = [];
  for (const [index, assetId] of mediaIds.entries()) {
    const asset = await getByUuid(ctx, "media_assets", assetId);
    if (
      !asset ||
      asset.owner_user_id !== userId ||
      asset.couple_id !== memory.couple_id ||
      asset.reserved_parent_kind !== "memory_media" ||
      !["memory_photo", "voice_note"].includes(asset.upload_purpose) ||
      !["image", "voice"].includes(asset.media_type) ||
      asset.upload_status !== "finalized" ||
      asset.storage_delete_status !== "none" ||
      asset.moderation_status !== "visible" ||
      asset.deleted_at !== undefined
    ) {
      return fail("23514", "memory media asset is not usable");
    }
    if (asset.media_type === "image") {
      activeImageCount += 1;
      if (activeImageCount > 5) fail("23514", "each partner can add at most 5 photos to a memory");
    }
    await insertMemoryMedia(ctx, {
      id: asset.reserved_parent_id,
      memory_id: memory.id,
      media_asset_id: asset.id,
      owner_user_id: userId,
      sort_order: maxSortOrder + 1 + index,
    });
    inserted.push(asset.reserved_parent_id);
  }
  return inserted;
}

export const create_memory = mutation({
  args: {
    p_memory_id: v.string(),
    p_title: v.string(),
    p_memory_date: v.string(),
    p_note_body: v.optional(v.union(v.null(), v.string())),
    p_media_asset_ids: nullableUuidArray,
    ...clientOperationArgs,
  },
  handler: async (ctx, args): Promise<string> => {
    const userId = await requireUserId(ctx);
    const title = normalizeMemoryTitle(args.p_title);
    const memoryId = uuidArg(args.p_memory_id);
    const memoryDate = dateArg(args.p_memory_date);
    const noteBody = btrimToNull(args.p_note_body);
    if (noteBody !== null && charLength(noteBody) > 4000) fail("23514", "memory note body is too long");
    const mediaIds = (args.p_media_asset_ids ?? []).map(uuidArg);
    if (noteBody === null && mediaIds.length === 0) fail("23514", "memory must include a note or media");

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "create_memory",
        scope: "memories",
        request: ["create_memory", memoryId, title, memoryDate, noteBody ?? "", mediaIds],
      }),
      async () => {
        const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
        await insertMemory(ctx, {
          id: memoryId,
          couple_id: coupleId,
          title,
          memory_date: memoryDate,
          created_by_user_id: userId,
          last_edited_by_user_id: userId,
        });
        if (noteBody !== null) {
          await insertMemoryNote(ctx, { memory_id: memoryId, user_id: userId, body: noteBody });
        }
        await attachMemoryMediaAssets(ctx, userId, memoryId, mediaIds);
        return { memory_id: memoryId };
      },
    );
    return stored.memory_id;
  },
});

export const update_memory = mutation({
  args: {
    p_memory_id: v.string(),
    p_expected_revision: v.number(),
    p_title: v.string(),
    p_memory_date: v.string(),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (!(args.p_expected_revision >= 1)) fail("23514", "expected memory revision is required");
    const title = normalizeMemoryTitle(args.p_title);
    const memoryDate = dateArg(args.p_memory_date);
    const memoryId = uuidArg(args.p_memory_id);

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "update_memory",
        scope: "memories",
        request: ["update_memory", memoryId, args.p_expected_revision, title, memoryDate],
      }),
      async () => {
        const memory = await requireWritableMemory(ctx, userId, memoryId);
        if (memory.revision !== args.p_expected_revision) fail("40001", "memory revision conflict");
        const updated = await patchMemory(ctx, memory, {
          title,
          memory_date: memoryDate,
          last_edited_by_user_id: userId,
        });
        return { memory_id: updated.id, revision: updated.revision, updated_at: updated.updated_at };
      },
    );
    return [stored];
  },
});

export const hide_memory = mutation({
  args: {
    p_memory_id: v.string(),
    p_expected_revision: v.number(),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (!(args.p_expected_revision >= 1)) fail("23514", "expected memory revision is required");
    const memoryId = uuidArg(args.p_memory_id);

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "hide_memory",
        scope: "memories",
        request: ["hide_memory", memoryId, args.p_expected_revision],
      }),
      async () => {
        const memory = await requireWritableMemory(ctx, userId, memoryId);
        if (memory.revision !== args.p_expected_revision) fail("40001", "memory revision conflict");
        const now = nowIso();
        const hidden = await patchMemory(ctx, memory, { deleted_at: now, last_edited_by_user_id: userId });

        const threadLinks = await ctx.db
          .query("memory_threads")
          .withIndex("by_memory_id", (q) => q.eq("memory_id", memory.id))
          .collect();
        for (const link of threadLinks) {
          const thread = await getByUuid(ctx, "conversation_threads", link.thread_id);
          if (thread && thread.deleted_at === undefined) {
            await ctx.db.patch(thread._id, withUpdatedAt({ deleted_at: now }));
          }
        }

        // Postgres ran these as deferred triggers, after every write above.
        await queueMemoryMediaAssetsIfOrphaned(ctx, memory.id);
        for (const link of threadLinks) await queueThreadMediaAssetsIfOrphaned(ctx, link.thread_id);
        return { memory_id: hidden.id, revision: hidden.revision, updated_at: hidden.updated_at };
      },
    );
    return [stored];
  },
});

export const upsert_memory_note = mutation({
  args: {
    p_memory_id: v.string(),
    p_expected_revision: v.optional(v.union(v.null(), v.number())),
    p_body: v.string(),
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const body = normalizeMemoryNoteBody(args.p_body);
    const memoryId = uuidArg(args.p_memory_id);
    const expected = args.p_expected_revision ?? null;

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "upsert_memory_note",
        scope: "memories",
        request: ["upsert_memory_note", memoryId, expected === null ? "" : expected, body],
      }),
      async () => {
        const memory = await requireWritableMemory(ctx, userId, memoryId);
        const note = await ctx.db
          .query("memory_notes")
          .withIndex("by_memory_id_user_id", (q) => q.eq("memory_id", memory.id).eq("user_id", userId))
          .unique();
        let result: Doc<"memory_notes">;
        if (note) {
          if (note.deleted_at !== undefined || note.moderation_status !== "visible") {
            fail("42501", "memory note is not editable");
          }
          if (expected === null || note.revision !== expected) fail("40001", "memory note revision conflict");
          await ctx.db.patch(note._id, withTouch(note, { body }));
          result = (await ctx.db.get(note._id))!;
        } else {
          if (expected !== null && expected !== 0) fail("40001", "memory note revision conflict");
          result = await insertMemoryNote(ctx, { memory_id: memory.id, user_id: userId, body });
        }
        return { note_id: result.id, revision: result.revision, updated_at: result.updated_at };
      },
    );
    return [stored];
  },
});

export const attach_memory_media = mutation({
  args: {
    p_memory_id: v.string(),
    p_media_asset_ids: nullableUuidArray,
    ...clientOperationArgs,
  },
  handler: async (ctx, args): Promise<string[]> => {
    const userId = await requireUserId(ctx);
    const mediaIds = (args.p_media_asset_ids ?? []).map(uuidArg);
    if (mediaIds.length === 0) fail("23514", "memory media asset ids are required");
    const memoryId = uuidArg(args.p_memory_id);

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "attach_memory_media",
        scope: "memories",
        request: ["attach_memory_media", memoryId, mediaIds],
      }),
      async () => ({ memory_media_ids: await attachMemoryMediaAssets(ctx, userId, memoryId, mediaIds) }),
    );
    return stored.memory_media_ids;
  },
});

export const remove_memory_media = mutation({
  args: {
    p_memory_media_id: v.string(),
    ...clientOperationArgs,
  },
  handler: async (ctx, args): Promise<string> => {
    const userId = await requireUserId(ctx);
    const memoryMediaId = uuidArg(args.p_memory_media_id);

    const stored = await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "remove_memory_media",
        scope: "memories",
        request: ["remove_memory_media", memoryMediaId],
      }),
      async () => {
        const link = await getByUuid(ctx, "memory_media", memoryMediaId);
        if (
          !link ||
          link.deleted_at !== undefined ||
          link.moderation_status !== "visible" ||
          link.owner_user_id !== userId
        ) {
          fail("42501", "memory media is not removable");
        }
        await requireWritableMemory(ctx, userId, link.memory_id);

        const now = nowIso();
        await ctx.db.patch(link._id, withUpdatedAt({ deleted_at: now }));
        const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
        if (asset && asset.owner_user_id === userId && asset.storage_delete_status !== "deleted") {
          await ctx.db.patch(
            asset._id,
            withUpdatedAt({
              storage_delete_status: asset.storage_delete_status === "none" ? ("pending" as const) : asset.storage_delete_status,
              deleted_at: asset.deleted_at ?? now,
            }),
          );
        }
        return { memory_media_id: link.id };
      },
    );
    return stored.memory_media_id;
  },
});

export const get_memories = mutation({
  args: {
    p_updated_after: v.optional(v.union(v.null(), v.string())),
    p_cursor_memory_id: v.optional(v.union(v.null(), v.string())),
    p_limit: v.optional(v.union(v.null(), v.number())),
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const limit = args.p_limit ?? 100;
    if (!Number.isInteger(limit) || limit < 1 || limit > 200) fail("23514", "memory read limit is out of range");
    const updatedAfter = optionalTimestampArg(args.p_updated_after);
    const cursorId = optionalUuidArg(args.p_cursor_memory_id) ?? "00000000-0000-0000-0000-000000000000";
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    // ponytail: reads every memory of the couple, then pages in memory. Add a sync index if couples reach thousands.
    const memories = await ctx.db
      .query("memories")
      .withIndex("by_couple_id_updated_at_id", (q) => q.eq("couple_id", coupleId))
      .collect();
    const rows = [];
    for (const memory of memories) {
      rows.push(await buildMemoryRow(ctx, userId, memory));
    }
    return rows
      .filter(
        (row) =>
          updatedAfter === undefined ||
          row.sync_updated_at > updatedAfter ||
          (row.sync_updated_at === updatedAfter && row.memory_id > cursorId),
      )
      .sort((a, b) =>
        a.sync_updated_at !== b.sync_updated_at
          ? a.sync_updated_at < b.sync_updated_at
            ? -1
            : 1
          : a.memory_id < b.memory_id
            ? -1
            : 1,
      )
      .slice(0, limit);
  },
});

async function buildMemoryRow(ctx: ReaderCtx, userId: string, memory: Doc<"memories">) {
  const visibleMemory = memory.deleted_at === undefined && memory.moderation_status === "visible";
  const notes = await ctx.db
    .query("memory_notes")
    .withIndex("by_memory_id_updated_at", (q) => q.eq("memory_id", memory.id))
    .collect();
  const ownNote = notes.find((note) => note.user_id === userId) ?? null;
  const partnerNote = notes.filter((note) => note.user_id !== userId).at(-1) ?? null;
  const noteBody = (note: Doc<"memory_notes"> | null) =>
    note && visibleMemory && note.deleted_at === undefined && note.moderation_status === "visible" ? note.body : null;

  const links = await ctx.db
    .query("memory_media")
    .withIndex("by_memory_id_owner_user_id_sort_order", (q) => q.eq("memory_id", memory.id))
    .collect();
  const memoryMediaIds: string[] = [];
  const mediaAssetIds: string[] = [];
  const states = [];
  let mediaUpdatedAt: string | null = null;
  for (const link of links) {
    const asset = await getByUuid(ctx, "media_assets", link.media_asset_id);
    if (!asset) continue;
    const updatedAt = link.updated_at > asset.updated_at ? link.updated_at : asset.updated_at;
    if (mediaUpdatedAt === null || updatedAt > mediaUpdatedAt) mediaUpdatedAt = updatedAt;
    if (
      visibleMemory &&
      link.deleted_at === undefined &&
      link.moderation_status === "visible" &&
      asset.reserved_parent_kind === "memory_media" &&
      asset.reserved_parent_id === link.id &&
      asset.upload_status === "finalized" &&
      asset.storage_delete_status === "none" &&
      asset.moderation_status === "visible" &&
      asset.deleted_at === undefined
    ) {
      memoryMediaIds.push(link.id);
      mediaAssetIds.push(link.media_asset_id);
    }
    states.push({
      memory_media_id: link.id,
      media_asset_id: link.media_asset_id,
      owner_user_id: link.owner_user_id,
      sort_order: link.sort_order,
      deleted_at: orNull(link.deleted_at),
      moderation_status: link.moderation_status,
      asset_deleted_at: orNull(asset.deleted_at),
      asset_moderation_status: asset.moderation_status,
      asset_storage_delete_status: asset.storage_delete_status,
      updated_at: updatedAt,
    });
  }
  const thread = await ctx.db
    .query("memory_threads")
    .withIndex("by_memory_id", (q) => q.eq("memory_id", memory.id))
    .unique();

  const syncUpdatedAt = [memory.updated_at, ownNote?.updated_at, partnerNote?.updated_at, mediaUpdatedAt].reduce<string>(
    (best, value) => (value && value > best ? value : best),
    "",
  );
  return {
    memory_id: memory.id,
    couple_id: memory.couple_id,
    title: visibleMemory ? memory.title : null,
    memory_date: memory.memory_date,
    created_by_user_id: memory.created_by_user_id,
    last_edited_by_user_id: memory.last_edited_by_user_id,
    revision: memory.revision,
    moderation_status: memory.moderation_status,
    deleted_at: orNull(memory.deleted_at),
    created_at: memory.created_at,
    updated_at: memory.updated_at,
    sync_updated_at: syncUpdatedAt,
    own_note_id: orNull(ownNote?.id),
    own_note_body: noteBody(ownNote),
    own_note_revision: orNull(ownNote?.revision),
    own_note_updated_at: orNull(ownNote?.updated_at),
    own_note_deleted_at: orNull(ownNote?.deleted_at),
    own_note_moderation_status: orNull(ownNote?.moderation_status),
    partner_note_id: orNull(partnerNote?.id),
    partner_note_user_id: orNull(partnerNote?.user_id),
    partner_note_body: noteBody(partnerNote),
    partner_note_revision: orNull(partnerNote?.revision),
    partner_note_updated_at: orNull(partnerNote?.updated_at),
    partner_note_deleted_at: orNull(partnerNote?.deleted_at),
    partner_note_moderation_status: orNull(partnerNote?.moderation_status),
    memory_media_ids: memoryMediaIds,
    media_asset_ids: mediaAssetIds,
    memory_media_states: states,
    thread_id: orNull(thread?.thread_id),
  };
}
