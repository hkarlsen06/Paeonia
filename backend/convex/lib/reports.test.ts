import { describe, expect, test } from "vitest";
import { createCouple, newTest } from "../test.setup";
import { newUuid } from "./ids";
import { tombstoneReportTargets } from "./reports";

describe("tombstoneReportTargets", () => {
  test("clears the live reference and stamps the deletion time once", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memoryId = newUuid();
    const otherMemoryId = newUuid();
    const reportId = newUuid();
    const otherReportId = newUuid();
    await t.run(async (ctx) => {
      const base = { target_kind: "memory" as const, created_at: "2026-10-10T10:00:00.000Z" };
      await ctx.db.insert("content_report_targets", { ...base, report_id: reportId, memory_id: memoryId });
      await ctx.db.insert("content_report_targets", { ...base, report_id: otherReportId, memory_id: otherMemoryId });
    });
    await t.run((ctx) => tombstoneReportTargets(ctx, "memory", memoryId));
    const rows = await t.run((ctx) => ctx.db.query("content_report_targets").collect());
    const cleared = rows.find((row) => row.report_id === reportId)!;
    const untouched = rows.find((row) => row.report_id === otherReportId)!;
    expect(cleared.memory_id).toBeUndefined();
    expect(cleared.live_target_deleted_at).toBeDefined();
    expect(untouched.memory_id).toBe(otherMemoryId);
    expect(untouched.live_target_deleted_at).toBeUndefined();
    expect(couple.coupleId).toBeDefined();
  });

  test("handles thread message media by message and asset", async () => {
    const t = newTest();
    const messageId = newUuid();
    const assetId = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("content_report_targets", {
        report_id: newUuid(),
        target_kind: "thread_message_media",
        message_media_message_id: messageId,
        message_media_asset_id: assetId,
        created_at: "2026-10-10T10:00:00.000Z",
      }),
    );
    await t.run((ctx) => tombstoneReportTargets(ctx, "thread_message_media", { message_id: messageId, media_asset_id: newUuid() }));
    expect((await t.run((ctx) => ctx.db.query("content_report_targets").first()))?.message_media_message_id).toBe(messageId);
    await t.run((ctx) => tombstoneReportTargets(ctx, "thread_message_media", { message_id: messageId, media_asset_id: assetId }));
    const row = await t.run((ctx) => ctx.db.query("content_report_targets").first());
    expect(row?.message_media_message_id).toBeUndefined();
    expect(row?.message_media_asset_id).toBeUndefined();
    expect(row?.live_target_deleted_at).toBeDefined();
  });

  test("profile targets use the user id", async () => {
    const t = newTest();
    const userId = newUuid();
    await t.run((ctx) =>
      ctx.db.insert("content_report_targets", {
        report_id: newUuid(),
        target_kind: "profile",
        profile_user_id: userId,
        created_at: "2026-10-10T10:00:00.000Z",
      }),
    );
    await t.run((ctx) => tombstoneReportTargets(ctx, "profile", userId));
    expect((await t.run((ctx) => ctx.db.query("content_report_targets").first()))?.profile_user_id).toBeUndefined();
  });
});
