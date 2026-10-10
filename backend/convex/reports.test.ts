import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { makeAsset, makeMemory, operation } from "./reports.fixtures";
import { createCouple, newTest } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

function reportArgs(overrides: Record<string, unknown> = {}) {
  return {
    p_reason: "harassment",
    p_note: "  they keep sending this  ",
    p_target_kind: "memory",
    p_target_id: newUuid(),
    p_target_aux_id: null,
    p_block_reported_user: false,
    ...operation(),
    ...overrides,
  };
}

describe("submit_content_report", () => {
  test("stores the report, target, snapshot, snapshot assets, and a pair warning", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const asset = await makeAsset(t, couple);
    const memory = await makeMemory(t, couple, [asset.id]);

    const reportId = await couple.second.as.mutation(
      api.reports.submit_content_report,
      reportArgs({ p_target_id: memory.id.toUpperCase(), p_reason: " Harassment " }),
    );
    expect(reportId).toMatch(/^[0-9a-f-]{36}$/);

    const state = await t.run(async (ctx) => ({
      reports: await ctx.db.query("content_reports").collect(),
      targets: await ctx.db.query("content_report_targets").collect(),
      snapshots: await ctx.db.query("report_snapshots").collect(),
      assets: await ctx.db.query("report_snapshot_assets").collect(),
      flags: await ctx.db.query("pair_safety_warning_flags").collect(),
    }));
    expect(state.reports).toHaveLength(1);
    expect(state.reports[0]).toMatchObject({
      id: reportId,
      reporter_user_id: couple.second.userId,
      reported_user_id: couple.first.userId,
      couple_id: couple.coupleId,
      pair_id: couple.pairId,
      reason: "harassment",
      note: "they keep sending this",
      status: "submitted",
      block_requested: false,
      leave_requested: false,
    });
    expect(state.targets[0]).toMatchObject({ report_id: reportId, target_kind: "memory", memory_id: memory.id });
    expect(state.snapshots[0].delete_after).toBeUndefined();
    expect(state.snapshots[0].snapshot).toMatchObject({
      schema_version: 1,
      report_id: reportId,
      reason: "harassment",
      note: "they keep sending this",
      target: { target_kind: "memory", memory_id: memory.id, title: "Our trip", media_asset_ids: [asset.id] },
    });
    expect(state.assets).toHaveLength(1);
    expect(state.assets[0]).toMatchObject({
      report_id: reportId,
      source_media_asset_id: asset.id,
      source_bucket: "couple-media",
      bucket: "report-snapshots",
      copy_status: "pending_copy",
      sha256: asset.sha,
    });
    expect(state.assets[0].storage_path).toBe(`${reportId}/${state.assets[0].id}.jpg`);
    expect(state.flags).toHaveLength(1);
    expect(state.flags[0]).toMatchObject({ pair_id: couple.pairId, source_report_id: reportId });

    // Reporting alone does not end the relationship.
    const couples = await t.run((ctx) => ctx.db.query("couples").collect());
    expect(couples[0].status).toBe("active");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("replays the same operation and rejects a changed request", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memory = await makeMemory(t, couple);
    const args = reportArgs({ p_target_id: memory.id });
    const first = await couple.second.as.mutation(api.reports.submit_content_report, args);
    expect(await couple.second.as.mutation(api.reports.submit_content_report, args)).toBe(first);
    expect(await t.run((ctx) => ctx.db.query("content_reports").collect())).toHaveLength(1);
    await expect(
      couple.second.as.mutation(api.reports.submit_content_report, { ...args, p_reason: "spam" }),
    ).rejects.toThrow(/23505.*client operation replay hash mismatch/);
  });

  test("reports the other partner's profile and conduct", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const profileReport = await couple.second.as.mutation(
      api.reports.submit_content_report,
      reportArgs({ p_target_kind: "profile", p_target_id: couple.first.userId }),
    );
    const conductReport = await couple.second.as.mutation(
      api.reports.submit_content_report,
      reportArgs({ p_target_kind: "conduct", p_target_id: couple.first.userId, p_reason: "threat" }),
    );
    const snapshots = await t.run((ctx) => ctx.db.query("report_snapshots").collect());
    const byReport = (id: string) => snapshots.find((row) => row.report_id === id)!.snapshot.target;
    expect(byReport(profileReport)).toMatchObject({
      target_kind: "profile",
      reported_user_id: couple.first.userId,
      profile_display_name: "First Partner",
      profile_moderation_status: "visible",
    });
    expect(byReport(conductReport).target_kind).toBe("conduct");
    const targets = await t.run((ctx) => ctx.db.query("content_report_targets").collect());
    expect(targets.find((row) => row.report_id === conductReport)?.conduct_user_id).toBe(couple.first.userId);
  });

  test("validates the request", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memory = await makeMemory(t, couple);
    const own = await makeMemory(t, couple);
    await t.run(async (ctx) => {
      const row = await ctx.db.query("memories").withIndex("by_uuid", (q) => q.eq("id", own.id)).unique();
      await ctx.db.patch(row!._id, { created_by_user_id: couple.second.userId, last_edited_by_user_id: couple.second.userId });
    });
    const call = (overrides: Record<string, unknown>, user = couple.second) =>
      user.as.mutation(api.reports.submit_content_report, reportArgs({ p_target_id: memory.id, ...overrides }));

    await expect(call({ p_reason: "boring" })).rejects.toThrow(/23514.*report reason is not supported/);
    await expect(call({ p_note: "x".repeat(4001) })).rejects.toThrow(/23514.*report note is too long/);
    await expect(call({ p_target_kind: "banana" })).rejects.toThrow(/23514.*report target kind is not supported/);
    await expect(call({ p_target_id: newUuid() })).rejects.toThrow(/22023.*report target was not found/);
    await expect(call({ p_target_kind: "thread_message_media", p_target_id: newUuid() })).rejects.toThrow(
      /23514.*thread message media reports require a media asset id/,
    );
    await expect(call({ p_target_id: own.id })).rejects.toThrow(/23514.*users cannot report themselves/);
    await expect(call({ p_target_id: "nope" })).rejects.toThrow(/22P02/);
    await expect(t.mutation(api.reports.submit_content_report, reportArgs())).rejects.toThrow(
      /42501.*authenticated user required/,
    );

    // A visible target in somebody else's couple is not reportable.
    const stranger = await createCouple(t);
    await expect(call({}, stranger.first)).rejects.toThrow(
      /42501.*report target is not connected to a reportable relationship/,
    );
    // Nothing was written by the failed attempts.
    expect(await t.run((ctx) => ctx.db.query("content_reports").collect())).toHaveLength(0);
  });
});

describe("submit_leave_and_report", () => {
  test("reports, then ends the relationship for both partners", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memory = await makeMemory(t, couple);
    const reportId = await couple.second.as.mutation(
      api.reports.submit_leave_and_report,
      reportArgs({ p_target_id: memory.id }),
    );
    const state = await t.run(async (ctx) => ({
      report: (await ctx.db.query("content_reports").collect())[0],
      couple: (await ctx.db.query("couples").collect())[0],
      members: await ctx.db.query("couple_members").collect(),
      blocks: await ctx.db.query("relationship_blocks").collect(),
      events: await ctx.db.query("relationship_sync_events").collect(),
    }));
    expect(state.report).toMatchObject({ id: reportId, leave_requested: true, block_requested: false });
    expect(state.couple.status).toBe("ended");
    const statusOf = (userId: string) => state.members.find((row) => row.user_id === userId)?.status;
    expect(statusOf(couple.second.userId)).toBe("left");
    expect(statusOf(couple.first.userId)).toBe("ended_notice_pending");
    expect(state.blocks).toHaveLength(0);
    expect(state.events).toHaveLength(2);
    expect(state.events[0]).toMatchObject({ event_kind: "relationship_ended", reason: "reported" });
  });

  test("blocks the reported partner when asked, and still lets the ended relationship be reported", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const memory = await makeMemory(t, couple);
    const reportId = await couple.second.as.mutation(
      api.reports.submit_leave_and_report,
      reportArgs({ p_target_id: memory.id, p_block_reported_user: true }),
    );
    const blocks = await t.run((ctx) => ctx.db.query("relationship_blocks").collect());
    expect(blocks).toHaveLength(1);
    expect(blocks[0]).toMatchObject({
      pair_id: couple.pairId,
      blocked_by_user_id: couple.second.userId,
      blocked_user_id: couple.first.userId,
      source_report_id: reportId,
    });
    const events = await t.run((ctx) => ctx.db.query("relationship_sync_events").collect());
    expect(events[0].reason).toBe("blocked");

    // The ended couple stays reportable until its retention window closes.
    const second = await couple.second.as.mutation(
      api.reports.submit_content_report,
      reportArgs({ p_target_kind: "conduct", p_target_id: couple.first.userId }),
    );
    expect(second).not.toBe(reportId);
  });
});
