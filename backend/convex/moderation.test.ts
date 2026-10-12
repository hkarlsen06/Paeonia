import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { tombstoneReportTargets } from "./lib/reports";
import { makeAsset, makeMemory, operation } from "./reports.fixtures";
import { createCouple, newTest, type TestConvex, type TestCouple } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

async function report(t: TestConvex, couple: TestCouple, kind: string, targetId: string, extra: Record<string, unknown> = {}) {
  return await couple.second.as.mutation(api.reports.submit_leave_and_report, {
    p_reason: "privacy",
    p_note: null,
    p_target_kind: kind,
    p_target_id: targetId,
    p_target_aux_id: null,
    p_block_reported_user: false,
    ...operation(),
    ...extra,
  });
}

const act = (t: TestConvex, reportId: string, action: string, extra: Record<string, unknown> = {}) =>
  t.mutation(internal.moderation.apply_report_moderation_action, {
    p_report_id: reportId,
    p_action_kind: action,
    p_operator_identifier: "ops@paeonia.no",
    ...extra,
  });

async function memorySetup() {
  const t = newTest();
  const couple = await createCouple(t);
  const asset = await makeAsset(t, couple);
  const memory = await makeMemory(t, couple, [asset.id]);
  const reportId = await report(t, couple, "memory", memory.id);
  // Submitting a report schedules the snapshot copy. Let it finish so tests start from a known state.
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const memoryRow = () =>
    t.run((ctx) => ctx.db.query("memories").withIndex("by_uuid", (q) => q.eq("id", memory.id)).unique());
  const assetRow = () =>
    t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", asset.id)).unique());
  return { t, couple, asset, memory, reportId, memoryRow, assetRow };
}

/** Puts the snapshot asset back to the state it has right after the report, before any copy. */
async function resetCopy(t: TestConvex) {
  await t.run(async (ctx) => {
    for (const row of await ctx.db.query("report_snapshot_assets").collect()) {
      await ctx.db.patch(row._id, {
        copy_status: "pending_copy",
        copy_attempts: 0,
        copy_claimed_at: undefined,
        copy_completed_at: undefined,
        storage_id: undefined,
      });
    }
  });
}

describe("apply_report_moderation_action", () => {
  test("hide and restore change the memory and close the report", async () => {
    const { t, reportId, memory, memoryRow } = await memorySetup();
    const actionId = await act(t, reportId, "hide", { p_reason: "privacy", p_notes: "checked" });

    const hidden = (await memoryRow())!;
    expect(hidden).toMatchObject({ moderation_status: "hidden", moderation_report_id: reportId, revision: 2 });
    const actions = await t.run((ctx) => ctx.db.query("moderation_actions").collect());
    expect(actions).toHaveLength(1);
    expect(actions[0]).toMatchObject({
      id: actionId,
      report_id: reportId,
      action_kind: "hide",
      status: "applied",
      target_kind: "memory",
      target_id: memory.id,
      previous_moderation_status: "visible",
      new_moderation_status: "hidden",
      storage_action: "none",
      operator_kind: "operator",
      operator_identifier: "ops@paeonia.no",
      reason: "privacy",
      notes: "checked",
    });
    const state = await t.run(async (ctx) => ({
      report: (await ctx.db.query("content_reports").collect())[0],
      snapshot: (await ctx.db.query("report_snapshots").collect())[0],
      assets: await ctx.db.query("report_snapshot_assets").collect(),
    }));
    expect(state.report).toMatchObject({ status: "action_taken", resolved_at: "2026-10-10T12:00:00.000Z" });
    expect(state.snapshot.delete_after).toBe("2027-04-08T12:00:00.000Z");
    expect(state.assets[0].delete_after).toBe("2027-04-08T12:00:00.000Z");

    vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
    await act(t, reportId, "restore");
    const visible = (await memoryRow())!;
    expect(visible).toMatchObject({ moderation_status: "visible", revision: 3 });
    expect(visible.moderation_report_id).toBeUndefined();
    const restored = await t.run(async (ctx) => ({
      report: (await ctx.db.query("content_reports").collect())[0],
      snapshot: (await ctx.db.query("report_snapshots").collect())[0],
    }));
    expect(restored.report).toMatchObject({ status: "closed", resolved_at: "2026-10-10T12:00:00.000Z" });
    // The retention clock starts once.
    expect(restored.snapshot.delete_after).toBe("2027-04-08T12:00:00.000Z");
  });

  test("remove queues the media for storage deletion and blocks a restore", async () => {
    const { t, reportId, assetRow, memoryRow } = await memorySetup();
    await act(t, reportId, "remove");
    expect(await memoryRow()).toMatchObject({ moderation_status: "removed" });
    expect(await assetRow()).toMatchObject({
      deleted_at: "2026-10-10T12:00:00.000Z",
      storage_delete_status: "pending",
    });
    const [action] = await t.run((ctx) => ctx.db.query("moderation_actions").collect());
    expect(action.storage_action).toBe("queued_delete");
    await expect(act(t, reportId, "restore")).rejects.toThrow(
      /23514.*cannot restore content with media queued for storage deletion/,
    );
  });

  test("restore is refused for content moderated by a different report", async () => {
    const { t, couple, reportId, memory } = await memorySetup();
    const other = await report(t, couple, "memory", memory.id);
    await act(t, other, "hide");
    await expect(act(t, reportId, "restore")).rejects.toThrow(
      /23514.*cannot restore content moderated by a different report/,
    );
  });

  test("delete_storage needs assets, and reject_upload marks a reported media asset", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memory = await makeMemory(t, couple);
    const bare = await report(t, couple, "memory", memory.id);
    await expect(act(t, bare, "delete_storage")).rejects.toThrow(
      /23514.*delete_storage found no storage assets for this target/,
    );

    const asset = await makeAsset(t, couple);
    const mediaReport = await report(t, couple, "media_asset", asset.id);
    await act(t, mediaReport, "reject_upload");
    const row = await t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", asset.id)).unique());
    expect(row).toMatchObject({ moderation_status: "rejected", moderation_report_id: mediaReport });
    await act(t, mediaReport, "delete_storage");
    const deleted = await t.run((ctx) => ctx.db.query("media_assets").withIndex("by_uuid", (q) => q.eq("id", asset.id)).unique());
    expect(deleted).toMatchObject({ moderation_status: "removed", storage_delete_status: "pending" });
  });

  test("validates the operator input and the target", async () => {
    const { t, couple, reportId } = await memorySetup();
    await expect(act(t, newUuid(), "hide")).rejects.toThrow(/22023.*content report was not found/);
    await expect(act(t, reportId, "explode")).rejects.toThrow(/23514.*moderation action is not supported/);
    await expect(act(t, reportId, "hide", { p_operator_identifier: "   " })).rejects.toThrow(
      /moderation operator identifier is required/,
    );
    const conduct = await report(t, couple, "conduct", couple.first.userId);
    await expect(act(t, conduct, "hide")).rejects.toThrow(/23514.*moderation action cannot change this target kind/);
    // Pair level actions do not need a target to change.
    await act(t, conduct, "create_pair_warning");
  });

  test("a deleted target cannot be moderated", async () => {
    const { t, reportId, memory, memoryRow } = await memorySetup();
    const row = (await memoryRow())!;
    await t.run(async (ctx) => {
      await tombstoneReportTargets(ctx, "memory", memory.id);
      await ctx.db.delete(row._id);
    });
    await expect(act(t, reportId, "hide")).rejects.toThrow(/22023.*moderation target was not found/);
    const [target] = await t.run((ctx) => ctx.db.query("content_report_targets").collect());
    expect(target.live_target_deleted_at).toBeDefined();
  });

  test("pair warnings and blocks", async () => {
    const { t, couple, reportId } = await memorySetup();
    // The report already raised a warning. Creating it again changes nothing.
    await act(t, reportId, "create_pair_warning");
    expect(await t.run((ctx) => ctx.db.query("pair_safety_warning_flags").collect())).toHaveLength(1);
    await act(t, reportId, "clear_pair_warning");
    expect(await t.run((ctx) => ctx.db.query("pair_safety_warning_flags").collect())).toHaveLength(0);

    // Submitting the report ended the relationship. Reopen it so the block has one to end.
    await t.run(async (ctx) => {
      for (const couple of await ctx.db.query("couples").collect()) await ctx.db.patch(couple._id, { status: "active" });
      for (const member of await ctx.db.query("couple_members").collect()) await ctx.db.patch(member._id, { status: "active" });
      for (const event of await ctx.db.query("relationship_sync_events").collect()) await ctx.db.delete(event._id);
    });
    await act(t, reportId, "block_pair");
    const blocks = await t.run((ctx) => ctx.db.query("relationship_blocks").collect());
    expect(blocks[0]).toMatchObject({
      blocked_by_user_id: couple.second.userId,
      blocked_user_id: couple.first.userId,
      source_report_id: reportId,
    });
    const events = await t.run((ctx) => ctx.db.query("relationship_sync_events").collect());
    expect(events[0].reason).toBe("moderation_block");

    await act(t, reportId, "unblock_pair");
    const revoked = (await t.run((ctx) => ctx.db.query("relationship_blocks").collect()))[0];
    expect(revoked).toMatchObject({ revoked_by_user_id: couple.second.userId, revoke_reason: "admin_correction" });
    expect(revoked.revoked_at).toBeDefined();
  });

  test("infer_report_target_for_moderation resolves the target ids", async () => {
    const { t, reportId, memory } = await memorySetup();
    const rows = await t.query(internal.moderation.infer_report_target_for_moderation, { p_report_id: reportId });
    expect(rows).toEqual([{ target_kind: "memory", target_id: memory.id, target_aux_id: null }]);
    expect(await t.query(internal.moderation.infer_report_target_for_moderation, { p_report_id: newUuid() })).toEqual([]);
  });
});

describe("report snapshot assets", () => {
  async function snapshotAssetRow(t: TestConvex) {
    return (await t.run((ctx) => ctx.db.query("report_snapshot_assets").collect()))[0];
  }

  test("the copy action stores a second blob with the same bytes", async () => {
    const { t, asset } = await memorySetup();
    await resetCopy(t);
    const result = await t.action(internal.moderation.copy_report_snapshot_assets, {});
    expect(result).toEqual({ claimed: 1, copied: 1, failed: 0 });
    const row = await snapshotAssetRow(t);
    expect(row).toMatchObject({ copy_status: "copied", copy_attempts: 1, copy_completed_at: "2026-10-10T12:00:00.000Z" });
    expect(row.storage_id).toBeDefined();
    expect(row.storage_id).not.toBe(asset.storageId);
    const copy = await t.run(async (ctx) => await (await ctx.storage.get(row.storage_id!))!.text());
    expect(copy).toBe("photo-bytes");
    expect(await t.action(internal.moderation.copy_report_snapshot_assets, {})).toEqual({ claimed: 0, copied: 0, failed: 0 });
  });

  test("a changed source is retried, then failed for good after five attempts", async () => {
    const { t } = await memorySetup();
    await resetCopy(t);
    // The source file no longer matches the checksum recorded at report time.
    await t.run(async (ctx) => {
      const copy = (await ctx.db.query("report_snapshot_assets").collect())[0];
      await ctx.db.patch(copy._id, { sha256: "f".repeat(64) });
    });
    await t.action(internal.moderation.copy_report_snapshot_assets, {});
    let row = await snapshotAssetRow(t);
    expect(row).toMatchObject({ copy_status: "pending_copy", copy_attempts: 1, last_copy_error: "source file checksum changed" });
    for (let attempt = 2; attempt <= 5; attempt += 1) {
      await t.action(internal.moderation.copy_report_snapshot_assets, {});
    }
    row = await snapshotAssetRow(t);
    expect(row).toMatchObject({ copy_status: "copy_failed", copy_attempts: 5 });
    expect(await t.action(internal.moderation.copy_report_snapshot_assets, {})).toEqual({ claimed: 0, copied: 0, failed: 0 });
  });

  test("a copy stuck in copying is claimed again after 15 minutes", async () => {
    const { t } = await memorySetup();
    await resetCopy(t);
    const first = await t.mutation(internal.moderation.claim_report_snapshot_asset_copies, {});
    expect(first).toHaveLength(1);
    expect(first[0]).toMatchObject({ copy_attempts: 1, destination_bucket: "report-snapshots" });
    expect(await t.mutation(internal.moderation.claim_report_snapshot_asset_copies, {})).toHaveLength(0);
    vi.setSystemTime(new Date("2026-10-10T12:16:00.000Z"));
    const again = await t.mutation(internal.moderation.claim_report_snapshot_asset_copies, {});
    expect(again[0].copy_attempts).toBe(2);
    await expect(t.mutation(internal.moderation.claim_report_snapshot_asset_copies, { p_limit: 0 })).rejects.toThrow(
      /23514.*report snapshot copy claim limit is out of range/,
    );
  });

  test("expired copies are deleted from storage and then purged with their snapshot", async () => {
    const { t, reportId } = await memorySetup();
    const copied = await snapshotAssetRow(t);
    expect(copied.copy_status).toBe("copied");

    // Nothing expires before the first moderation action sets delete_after.
    expect(await t.mutation(internal.moderation.cleanup_report_snapshots, {})).toMatchObject({
      storage: { deleted: 0 },
      purged: { snapshot_asset_rows_deleted: 0, snapshot_rows_deleted: 0 },
    });
    await act(t, reportId, "hide");
    vi.setSystemTime(new Date("2027-04-09T12:00:00.000Z"));

    const result = await t.mutation(internal.moderation.cleanup_report_snapshots, {});
    expect(result).toMatchObject({
      storage: { claimed: 1, deleted: 1, failed: 0 },
      purged: { snapshot_asset_rows_deleted: 1, snapshot_rows_deleted: 1 },
    });
    expect(await t.run(async (ctx) => (await ctx.storage.get(copied.storage_id!)) === null)).toBe(true);
    expect(await t.run((ctx) => ctx.db.query("report_snapshot_assets").collect())).toHaveLength(0);
    expect(await t.run((ctx) => ctx.db.query("report_snapshots").collect())).toHaveLength(0);
  });

  test("purge also drops uncopied rows whose retention ended", async () => {
    const { t, reportId } = await memorySetup();
    await resetCopy(t);
    await act(t, reportId, "hide");
    vi.setSystemTime(new Date("2027-04-09T12:00:00.000Z"));
    expect(await t.mutation(internal.moderation.purge_deleted_report_snapshots, {})).toEqual({
      snapshot_asset_rows_deleted: 1,
      snapshot_rows_deleted: 1,
    });
    await expect(t.mutation(internal.moderation.purge_deleted_report_snapshots, { p_limit: 5000 })).rejects.toThrow(
      /23514.*report snapshot purge limit is out of range/,
    );
  });
});
