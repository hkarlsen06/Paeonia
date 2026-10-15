import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { createCouple, newTest, type TestConvex } from "../test.setup";
import { newUuid } from "./ids";
import {
  mediaAssetHasLiveReference,
  queueMemoryMediaAssetsIfOrphaned,
  queueOldMediaAssetIfOrphaned,
  queueOrphanedMediaAssetForDelete,
  queueOrphanedMediaAssetsForDelete,
} from "./mediaOrphans";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

async function insertAsset(
  t: TestConvex,
  ownerUserId: string,
  coupleId: string,
  overrides: Record<string, unknown> = {},
) {
  const id = newUuid();
  await t.run((ctx) =>
    ctx.db.insert("media_assets", {
      id,
      owner_user_id: ownerUserId,
      couple_id: coupleId,
      reserved_parent_kind: "memory_media",
      reserved_parent_id: newUuid(),
      reserved_by_client_operation_id: newUuid(),
      bucket: "couple-media",
      storage_path: `couple/${id}.jpg`,
      media_type: "image",
      upload_purpose: "memory_photo",
      expected_media_type: "image",
      expected_bucket: "couple-media",
      mime_type: "image/jpeg",
      byte_size: 10,
      sha256: "a".repeat(64),
      upload_status: "finalized",
      upload_expires_at: "2026-10-10T13:00:00.000Z",
      upload_finalized_at: "2026-10-10T11:00:00.000Z",
      moderation_status: "visible",
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      created_at: "2026-10-10T11:00:00.000Z",
      updated_at: "2026-10-10T11:00:00.000Z",
      ...overrides,
    } as never),
  );
  return id;
}

async function insertMemoryWithMedia(t: TestConvex, couple: { coupleId: string; first: { userId: string } }, assetId: string) {
  const memoryId = newUuid();
  await t.run(async (ctx) => {
    const now = "2026-10-10T11:00:00.000Z";
    await ctx.db.insert("memories", {
      id: memoryId, couple_id: couple.coupleId, title: "Trip", memory_date: "2026-10-01",
      created_by_user_id: couple.first.userId, last_edited_by_user_id: couple.first.userId,
      revision: 1, moderation_status: "visible", created_at: now, updated_at: now,
    });
    await ctx.db.insert("memory_media", {
      id: newUuid(), memory_id: memoryId, media_asset_id: assetId, owner_user_id: couple.first.userId,
      sort_order: 1, moderation_status: "visible", created_at: now, updated_at: now,
    });
  });
  return memoryId;
}

async function asset(t: TestConvex, id: string) {
  return await t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", id)).unique());
}

describe("media orphan queueing", () => {
  test("an asset linked to a live memory is not an orphan", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const assetId = await insertAsset(t, couple.first.userId, couple.coupleId);
    await insertMemoryWithMedia(t, couple, assetId);
    expect(await t.run((ctx) => mediaAssetHasLiveReference(ctx, assetId))).toBe(true);
    expect(await t.run((ctx) => queueOrphanedMediaAssetForDelete(ctx, assetId))).toBe(false);
    expect((await asset(t, assetId))?.storage_delete_status).toBe("none");
  });

  test("deleting the memory orphans its media, which is queued for storage deletion", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const assetId = await insertAsset(t, couple.first.userId, couple.coupleId, { last_storage_delete_error: "old" });
    const memoryId = await insertMemoryWithMedia(t, couple, assetId);
    await t.run(async (ctx) => {
      const memory = await ctx.db.query("memories").withIndex("by_uuid", (q) => q.eq("id", memoryId)).unique();
      await ctx.db.patch(memory!._id, { deleted_at: "2026-10-10T12:00:00.000Z" });
    });
    await t.run((ctx) => queueMemoryMediaAssetsIfOrphaned(ctx, memoryId));
    const row = await asset(t, assetId);
    expect(row).toMatchObject({ storage_delete_status: "pending", deleted_at: "2026-10-10T12:00:00.000Z" });
    expect(row?.last_storage_delete_error).toBeUndefined();
    expect(row?.updated_at).toBe("2026-10-10T12:00:00.000Z");
  });

  test("shared assets stay live while another live row references them", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const assetId = await insertAsset(t, couple.first.userId, couple.coupleId);
    const first = await insertMemoryWithMedia(t, couple, assetId);
    await insertMemoryWithMedia(t, couple, assetId);
    await t.run(async (ctx) => {
      const memory = await ctx.db.query("memories").withIndex("by_uuid", (q) => q.eq("id", first)).unique();
      await ctx.db.patch(memory!._id, { deleted_at: "2026-10-10T12:00:00.000Z" });
    });
    await t.run((ctx) => queueOldMediaAssetIfOrphaned(ctx, assetId));
    expect((await asset(t, assetId))?.storage_delete_status).toBe("none");
  });

  test("pending uploads, report snapshots, and already queued assets are left alone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const pending = await insertAsset(t, couple.first.userId, couple.coupleId, {
      upload_status: "pending",
      upload_finalized_at: undefined,
      mime_type: undefined,
      byte_size: undefined,
      sha256: undefined,
    });
    const snapshot = await insertAsset(t, couple.first.userId, couple.coupleId, {
      bucket: "report-snapshots",
      expected_bucket: "report-snapshots",
      media_type: "report_snapshot",
      expected_media_type: "report_snapshot",
      upload_purpose: "report_snapshot",
      reserved_parent_kind: "report_snapshot",
    });
    const queued = await insertAsset(t, couple.first.userId, couple.coupleId, { storage_delete_status: "retrying" });
    const results = await t.run(async (ctx) => [
      await queueOrphanedMediaAssetForDelete(ctx, pending),
      await queueOrphanedMediaAssetForDelete(ctx, snapshot),
      await queueOrphanedMediaAssetForDelete(ctx, queued),
      await queueOrphanedMediaAssetForDelete(ctx, null),
      await queueOrphanedMediaAssetForDelete(ctx, newUuid()),
    ]);
    expect(results).toEqual([false, false, false, false, false]);
  });

  test("a failed deletion is retried by requeueing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const assetId = await insertAsset(t, couple.first.userId, couple.coupleId, { storage_delete_status: "failed" });
    expect(await t.run((ctx) => queueOrphanedMediaAssetForDelete(ctx, assetId))).toBe(true);
    expect((await asset(t, assetId))?.storage_delete_status).toBe("pending");
  });

  test("the sweep queues only unreferenced finalized assets and honors the limit", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const linked = await insertAsset(t, couple.first.userId, couple.coupleId);
    await insertMemoryWithMedia(t, couple, linked);
    const orphanA = await insertAsset(t, couple.first.userId, couple.coupleId, { updated_at: "2026-10-10T10:00:00.000Z" });
    const orphanB = await insertAsset(t, couple.first.userId, couple.coupleId, { updated_at: "2026-10-10T10:30:00.000Z" });
    // Fresh uploads may still be waiting for an offline write to attach them.
    expect(await t.run((ctx) => queueOrphanedMediaAssetsForDelete(ctx))).toMatchObject({ queued: 0 });
    vi.setSystemTime(new Date("2026-10-17T12:00:01.000Z"));
    expect(await t.run((ctx) => queueOrphanedMediaAssetsForDelete(ctx, 1))).toMatchObject({ queued: 1 });
    expect((await asset(t, orphanA))?.storage_delete_status).toBe("pending");
    expect((await asset(t, orphanB))?.storage_delete_status).toBe("none");
    expect(await t.run((ctx) => queueOrphanedMediaAssetsForDelete(ctx))).toMatchObject({ queued: 1 });
    expect((await asset(t, linked))?.storage_delete_status).toBe("none");
    await expect(t.run((ctx) => queueOrphanedMediaAssetsForDelete(ctx, 0))).rejects.toThrow(
      /23514.*orphaned media queue limit is out of range/,
    );
  });
});
