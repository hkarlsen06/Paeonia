import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { cleanupCoupleContent, purgeCoupleContent } from "./lib/relationshipCleanup";
import { createCouple, createSignedInUser, newTest, relationshipStateOf, type TestConvex, type TestCouple } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
});
afterEach(() => {
  vi.useRealTimers();
});

async function expectFail(promise: Promise<unknown>, code: string, message?: string) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  expect(error?.data?.code).toBe(code);
  if (message) expect(error?.data?.message).toContain(message);
}

let sequence = 0;
const operation = (clientId = newUuid(), clientSequence = ++sequence) => ({
  p_client_operation_id: newUuid(),
  p_client_id: clientId,
  p_client_sequence: clientSequence,
  p_local_created_at: NOW,
});

const events = (t: TestConvex, coupleId: string) =>
  t.run(async (ctx) =>
    (await ctx.db.query("relationship_sync_events").collect()).filter((event) => event.couple_id === coupleId),
  );

describe("set_couple_started_on", () => {
  async function startedOnCouple() {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Pacific/Kiritimati", "America/Los_Angeles"] });
    return { t, ...couple };
  }
  const startedOn = (t: TestConvex, coupleId: string) =>
    t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((couple) => couple.id === coupleId)?.started_on);

  test("an entitled partner sets their local today and both partners get a refresh event", async () => {
    const { t, coupleId, first } = await startedOnCouple();
    // 12:00 UTC is already 2026-10-11 in Kiritimati.
    expect(await first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2026-10-11", ...operation() })).toBe("2026-10-11");
    expect(await startedOn(t, coupleId)).toBe("2026-10-11");
    const refresh = (await events(t, coupleId)).filter((event) => event.event_kind === "relationship_updated");
    expect(refresh).toHaveLength(2);
    expect(refresh[0]).toMatchObject({
      reason: "relationship_start_date_changed",
      initiated_by_user_id: first.userId,
      local_purge_scope: { relationship: "refresh" },
    });
  });

  test("the partner covered by the couple entitlement can edit the date", async () => {
    const { t, coupleId, second } = await startedOnCouple();
    expect(await second.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-02-29", ...operation() })).toBe("2020-02-29");
    expect(await startedOn(t, coupleId)).toBe("2020-02-29");
  });

  test("a date after the caller's local today is rejected", async () => {
    const { second } = await startedOnCouple();
    // Los Angeles is still on 2026-10-10.
    await expectFail(second.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2026-10-11", ...operation() }), "23514");
    await expectFail(second.as.mutation(api.relationship.set_couple_started_on, { p_started_on: null, ...operation() }), "23514");
    await expectFail(second.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2026-02-30", ...operation() }), "22007");
  });

  test("a delayed lower-sequence retry cannot overwrite a newer edit from the same client", async () => {
    const { t, coupleId, second } = await startedOnCouple();
    const clientId = newUuid();
    expect(await second.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2021-01-01", ...operation(clientId, 3) })).toBe("2021-01-01");
    expect(await second.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2019-01-01", ...operation(clientId, 2) })).toBe("2021-01-01");
    expect(await startedOn(t, coupleId)).toBe("2021-01-01");
    // Each non-superseded edit fans out to both partners.
    expect((await events(t, coupleId)).filter((event) => event.event_kind === "relationship_updated")).toHaveLength(2);
  });

  test("a replay returns the stored date and a different request with the same operation id is refused", async () => {
    const { t, coupleId, first } = await startedOnCouple();
    const op = operation();
    await first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-01-01", ...op });
    expect(await first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-01-01", ...op })).toBe("2020-01-01");
    expect((await events(t, coupleId)).filter((event) => event.event_kind === "relationship_updated")).toHaveLength(2);
    await expectFail(
      first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-01-02", ...op }),
      "23505",
      "client operation replay hash mismatch",
    );
  });

  test("a user outside an active entitled couple cannot change a relationship date", async () => {
    const { t } = await startedOnCouple();
    const outsider = await createSignedInUser(t, { timeZone: "Not/A_Time_Zone" });
    await expectFail(
      outsider.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-01-01", ...operation() }),
      "42501",
    );
    await expectFail(
      t.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-01-01", ...operation() }),
      "42501",
      "authenticated user required",
    );
  });

  test("an unentitled couple cannot change the date", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    await expectFail(
      couple.first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: "2020-01-01", ...operation() }),
      "42501",
    );
  });
});

describe("leaving and blocking", () => {
  test("leave_relationship ends the couple, and a replay returns the stored answer", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const op = operation();
    expect(await couple.first.as.mutation(api.relationship.leave_relationship, op)).toBe(true);
    expect(await couple.first.as.mutation(api.relationship.leave_relationship, op)).toBe(true);
    const rows = await t.run(async (ctx) => ({
      couples: await ctx.db.query("couples").collect(),
      members: await ctx.db.query("couple_members").collect(),
    }));
    expect(rows.couples[0]).toMatchObject({ status: "ended" });
    expect(Object.fromEntries(rows.members.map((member) => [member.user_id, member.status]))).toEqual({
      [couple.first.userId]: "left",
      [couple.second.userId]: "ended_notice_pending",
    });
    expect((await events(t, couple.coupleId)).filter((event) => event.reason === "user_left")).toHaveLength(2);
    // Nothing left to leave.
    expect(await couple.first.as.mutation(api.relationship.leave_relationship, operation())).toBe(false);
  });

  test("a signed out caller and a stranger leave nothing", async () => {
    const t = newTest();
    await createCouple(t);
    await expectFail(t.mutation(api.relationship.leave_relationship, operation()), "42501", "authenticated user required");
    const stranger = await createSignedInUser(t, {});
    expect(await stranger.as.mutation(api.relationship.leave_relationship, operation())).toBe(false);
    const couples = await t.run((ctx) => ctx.db.query("couples").collect());
    expect(couples[0].status).toBe("active");
  });

  test("mark_relationship_ended_notice_seen only works for the member with a pending notice", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.relationship.leave_relationship, operation());
    const stranger = await createSignedInUser(t, {});
    expect(await stranger.as.mutation(api.relationship.mark_relationship_ended_notice_seen, { p_couple_id: couple.coupleId })).toBe(false);
    expect(await couple.first.as.mutation(api.relationship.mark_relationship_ended_notice_seen, { p_couple_id: couple.coupleId })).toBe(false);
    expect(await couple.second.as.mutation(api.relationship.mark_relationship_ended_notice_seen, { p_couple_id: couple.coupleId })).toBe(true);
    expect(await couple.second.as.mutation(api.relationship.mark_relationship_ended_notice_seen, { p_couple_id: couple.coupleId })).toBe(false);
    const state = await relationshipStateOf(couple.second);
    expect(state).toMatchObject({ member_status: "ended_notice_seen", ended_notice_seen_at: NOW });
  });
});

describe("relationship_state in get_access_snapshot", () => {
  test("projects the partner for an active couple and an ended one, and nothing otherwise", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      const couplesRow = (await ctx.db.query("couples").first())!;
      await ctx.db.patch(couplesRow._id, { started_on: "2024-05-01" });
    });
    const active = await relationshipStateOf(couple.first);
    expect(active).toEqual({
      couple_id: couple.coupleId,
      pair_id: couple.pairId,
      relationship_status: "active",
      member_status: "active",
      accepted_invite: false,
      partner_user_id: couple.second.userId,
      partner_display_name: "Second Partner",
      partner_profile_photo_asset_id: null,
      started_on: "2024-05-01",
      ended_at: null,
      delete_after: null,
      ended_notice_seen_at: null,
    });

    await couple.first.as.mutation(api.relationship.leave_relationship, operation());
    const ended = await relationshipStateOf(couple.second);
    expect(ended).toMatchObject({ relationship_status: "ended", member_status: "ended_notice_pending", ended_at: NOW });
    const leaver = await relationshipStateOf(couple.first);
    expect(leaver).toMatchObject({ relationship_status: "ended", member_status: "left" });

    const stranger = await createSignedInUser(t, {});
    expect(await relationshipStateOf(stranger)).toBeNull();
  });

  test("hides a partner profile that is not visible", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId))
        .unique();
      await ctx.db.patch(profile!._id, { moderation_status: "hidden" });
    });
    const state = await relationshipStateOf(couple.first);
    expect(state).toMatchObject({ partner_user_id: couple.second.userId, partner_display_name: null });
  });
});

describe("get_relationship_sync_events", () => {
  test("returns only the caller's events in order, strictly after the cursor", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    for (const [time, value] of [
      ["2026-10-10T12:00:00.000Z", "2024-01-01"],
      ["2026-10-10T12:00:01.000Z", "2024-01-02"],
      ["2026-10-10T12:00:02.000Z", "2024-01-03"],
    ] as const) {
      vi.setSystemTime(new Date(time));
      await couple.first.as.mutation(api.relationship.set_couple_started_on, { p_started_on: value, ...operation() });
    }
    const all = await couple.first.as.query(api.relationship.get_relationship_sync_events, { p_limit: 100 });
    expect(all).toHaveLength(3);
    expect(all.map((event) => event.created_at)).toEqual([...all.map((event) => event.created_at)].sort());
    expect(all.every((event) => event.user_id === couple.first.userId)).toBe(true);
    expect(all[0]).toMatchObject({ event_kind: "relationship_updated", reason: "relationship_start_date_changed", ended_at: null });

    const page = await couple.first.as.query(api.relationship.get_relationship_sync_events, { p_limit: 2 });
    expect(page.map((event) => event.id)).toEqual(all.slice(0, 2).map((event) => event.id));
    const next = await couple.first.as.query(api.relationship.get_relationship_sync_events, {
      p_after_created_at: page[1].created_at,
      p_after_id: page[1].id.toUpperCase(),
      p_limit: 2,
    });
    expect(next.map((event) => event.id)).toEqual([all[2].id]);
    expect(
      await couple.first.as.query(api.relationship.get_relationship_sync_events, {
        p_after_created_at: all[2].created_at,
        p_after_id: all[2].id,
        p_limit: 10,
      }),
    ).toEqual([]);
    await expectFail(couple.first.as.query(api.relationship.get_relationship_sync_events, { p_limit: 0 }), "23514");
    const stranger = await createSignedInUser(t, {});
    expect(await stranger.as.query(api.relationship.get_relationship_sync_events, { p_limit: 10 })).toEqual([]);
  });

  test("the partner gets a relationship_ended event with the purge scope", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.relationship.leave_relationship, operation());
    const second = await couple.second.as.query(api.relationship.get_relationship_sync_events, { p_limit: 10 });
    expect(second).toHaveLength(1);
    expect(second[0]).toMatchObject({ event_kind: "relationship_ended", member_status: "ended_notice_pending", relationship_status: "ended" });
    expect(second[0].local_purge_scope).toEqual({
      relationship_content: "hide",
      location: "purge",
      widget_cache: "purge",
      pending_uploads: "review",
    });
  });
});

// ---- cleanup and purge ----

async function endedCoupleWithContent(t: TestConvex): Promise<TestCouple & { assetId: string; memoryId: string }> {
  const couple = await createCouple(t);
  await couple.first.as.mutation(api.relationship.leave_relationship, operation());
  const assetId = newUuid();
  const memoryId = newUuid();
  const threadId = newUuid();
  const dayId = newUuid();
  const instanceId = newUuid();
  const answerId = newUuid();
  await t.run(async (ctx) => {
    const row = (await ctx.db.query("couples").first())!;
    await ctx.db.patch(row._id, { delete_after: "2026-10-09T00:00:00.000Z" });
    const moderation = { moderation_status: "visible" as const };
    const times = { created_at: NOW, updated_at: NOW };
    await ctx.db.insert("media_assets", {
      id: assetId,
      owner_user_id: couple.first.userId,
      couple_id: couple.coupleId,
      reserved_parent_kind: "memory_media",
      reserved_parent_id: memoryId,
      reserved_by_client_operation_id: newUuid(),
      bucket: "couple-media",
      storage_path: `${couple.coupleId}/photo.jpg`,
      media_type: "image",
      upload_purpose: "memory_photo",
      expected_media_type: "image",
      expected_bucket: "couple-media",
      upload_status: "finalized",
      upload_expires_at: NOW,
      upload_finalized_at: NOW,
      storage_delete_status: "none",
      storage_delete_attempts: 0,
      ...moderation,
      ...times,
    });
    await ctx.db.insert("memories", {
      id: memoryId,
      couple_id: couple.coupleId,
      title: "Trip",
      memory_date: "2026-01-01",
      created_by_user_id: couple.first.userId,
      last_edited_by_user_id: couple.first.userId,
      revision: 1,
      ...moderation,
      ...times,
    });
    await ctx.db.insert("memory_notes", {
      id: newUuid(),
      memory_id: memoryId,
      user_id: couple.first.userId,
      body: "note",
      revision: 1,
      ...moderation,
      ...times,
    });
    await ctx.db.insert("memory_media", {
      id: newUuid(),
      memory_id: memoryId,
      media_asset_id: assetId,
      owner_user_id: couple.first.userId,
      sort_order: 0,
      ...moderation,
      ...times,
    });
    await ctx.db.insert("conversation_threads", {
      id: threadId,
      couple_id: couple.coupleId,
      kind: "memory",
      created_by_user_id: couple.first.userId,
      ...moderation,
      ...times,
    });
    await ctx.db.insert("thread_messages", {
      id: newUuid(),
      thread_id: threadId,
      sender_user_id: couple.first.userId,
      body: "hi",
      ...moderation,
      ...times,
    });
    await ctx.db.insert("couple_days", {
      id: dayId,
      couple_id: couple.coupleId,
      local_date: "2026-10-09",
      anchor_time_zone_id: "UTC",
      starts_at: "2026-10-09T00:00:00.000Z",
      ends_at: "2026-10-10T00:00:00.000Z",
      created_at: NOW,
    });
    await ctx.db.insert("daily_question_instances", {
      id: instanceId,
      couple_day_id: dayId,
      couple_id: couple.coupleId,
      question_id: newUuid(),
      question_version_id: newUuid(),
      seeded_for_user_id: couple.first.userId,
      slot_number: 1,
      status: "answered",
      created_at: NOW,
    });
    await ctx.db.insert("daily_question_answers", {
      id: answerId,
      instance_id: instanceId,
      user_id: couple.first.userId,
      ...moderation,
      ...times,
    });
    await ctx.db.insert("daily_answer_text", { answer_id: answerId, body: "answer" });
    await ctx.db.insert("content_report_targets", {
      report_id: newUuid(),
      target_kind: "memory",
      memory_id: memoryId,
      created_at: NOW,
    });
  });
  return { ...couple, assetId, memoryId };
}

describe("relationship content cleanup", () => {
  test("hides content, queues media, marks the couple deleted, and tells both members", async () => {
    const t = newTest();
    const couple = await endedCoupleWithContent(t);
    const result = await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, {});
    expect(result).toEqual([{ couple_id: couple.coupleId, queued_media_count: 1, sync_event_count: 2 }]);

    const state = await t.run(async (ctx) => ({
      couple: await ctx.db.query("couples").first(),
      memory: await ctx.db.query("memories").first(),
      note: await ctx.db.query("memory_notes").first(),
      message: await ctx.db.query("thread_messages").first(),
      answer: await ctx.db.query("daily_question_answers").first(),
      asset: await ctx.db.query("media_assets").first(),
    }));
    expect(state.couple?.status).toBe("deleted");
    for (const row of [state.memory, state.note, state.message, state.answer]) {
      expect(row).toMatchObject({ deleted_at: NOW, moderation_status: "hidden" });
    }
    expect(state.memory?.revision).toBe(2);
    expect(state.asset).toMatchObject({ storage_delete_status: "pending", deleted_at: NOW });
    const purged = (await events(t, couple.coupleId)).filter((event) => event.event_kind === "content_purged");
    expect(purged).toHaveLength(2);
    expect(purged[0]).toMatchObject({ reason: "relationship_cleanup", relationship_status: "deleted" });

    // The couple is not ended anymore, so a second run finds nothing.
    expect(await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, {})).toEqual([]);
  });

  test("leaves couples inside their retention window alone", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.relationship.leave_relationship, operation());
    expect(await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, {})).toEqual([]);
    expect(
      await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, { p_now: "2026-12-01T00:00:00.000Z" }),
    ).toHaveLength(1);
  });

  test("a couple bigger than one chunk finishes over several, and each chunk leaves the done rows alone", async () => {
    const t = newTest();
    const couple = await endedCoupleWithContent(t);
    const chunks: boolean[] = [];
    for (let i = 0; i < 30 && chunks.at(-1) !== true; i += 1) {
      chunks.push(
        await t.run(async (ctx) => {
          const row = (await ctx.db.query("couples").first())!;
          return (await cleanupCoupleContent(ctx, row, NOW, { left: 2 })).done;
        }),
      );
    }
    expect(chunks.length).toBeGreaterThan(2);
    const state = await t.run(async (ctx) => ({
      couple: await ctx.db.query("couples").first(),
      memory: await ctx.db.query("memories").first(),
      note: await ctx.db.query("memory_notes").first(),
      asset: await ctx.db.query("media_assets").first(),
    }));
    expect(state.couple?.status).toBe("deleted");
    expect(state.memory?.revision).toBe(2);
    expect(state.note?.revision).toBe(2);
    expect(state.asset).toMatchObject({ storage_delete_status: "pending" });
    // The members hear about it once, in the last chunk.
    expect((await events(t, couple.coupleId)).filter((event) => event.reason === "relationship_cleanup")).toHaveLength(2);
  });
});

describe("relationship content purge", () => {
  test("waits for the stored files to be deleted, then removes the rows and keeps report snapshots", async () => {
    const t = newTest();
    const couple = await endedCoupleWithContent(t);
    await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, {});

    // The media asset is still pending storage deletion.
    expect(await t.mutation(internal.relationshipJobs.purge_deleted_relationship_content, {})).toEqual([]);
    await t.run(async (ctx) => {
      const asset = (await ctx.db.query("media_assets").first())!;
      await ctx.db.patch(asset._id, { storage_delete_status: "deleted", storage_deleted_at: NOW });
    });

    const result = await t.mutation(internal.relationshipJobs.purge_deleted_relationship_content, {});
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({ couple_id: couple.coupleId, media_rows_deleted: 1, sync_event_count: 2 });
    expect(result[0].content_rows_deleted).toBeGreaterThanOrEqual(8);

    const remaining = await t.run(async (ctx) => ({
      memories: await ctx.db.query("memories").collect(),
      notes: await ctx.db.query("memory_notes").collect(),
      media: await ctx.db.query("memory_media").collect(),
      threads: await ctx.db.query("conversation_threads").collect(),
      messages: await ctx.db.query("thread_messages").collect(),
      days: await ctx.db.query("couple_days").collect(),
      instances: await ctx.db.query("daily_question_instances").collect(),
      answers: await ctx.db.query("daily_question_answers").collect(),
      texts: await ctx.db.query("daily_answer_text").collect(),
      assets: await ctx.db.query("media_assets").collect(),
      target: await ctx.db.query("content_report_targets").first(),
      couple: await ctx.db.query("couples").first(),
    }));
    for (const rows of [
      remaining.memories,
      remaining.notes,
      remaining.media,
      remaining.threads,
      remaining.messages,
      remaining.days,
      remaining.instances,
      remaining.answers,
      remaining.texts,
      remaining.assets,
    ]) {
      expect(rows).toHaveLength(0);
    }
    expect(remaining.target?.memory_id).toBeUndefined();
    expect(remaining.target?.live_target_deleted_at).toBe(NOW);
    expect(remaining.couple?.status).toBe("deleted");
    const hardPurge = (await events(t, couple.coupleId)).filter((event) => event.reason === "relationship_hard_purge");
    expect(hardPurge).toHaveLength(2);
    expect(hardPurge[0]).toMatchObject({ event_kind: "content_purged", relationship_status: "deleted" });

    // A purged couple is out of the purge range, so it is not purged twice.
    expect(remaining.couple?.purged_at).toBeDefined();
    expect(await t.mutation(internal.relationshipJobs.purge_deleted_relationship_content, {})).toEqual([]);
  });

  test("a couple bigger than one chunk is purged over several", async () => {
    const t = newTest();
    const couple = await endedCoupleWithContent(t);
    await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, {});
    await t.run(async (ctx) => {
      const asset = (await ctx.db.query("media_assets").first())!;
      await ctx.db.patch(asset._id, { storage_delete_status: "deleted", storage_deleted_at: NOW });
    });
    const chunks: boolean[] = [];
    for (let i = 0; i < 40 && chunks.at(-1) !== true; i += 1) {
      chunks.push(
        await t.run(async (ctx) => {
          const row = (await ctx.db.query("couples").first())!;
          return (await purgeCoupleContent(ctx, row, { left: 2 })).done;
        }),
      );
    }
    expect(chunks.length).toBeGreaterThan(2);
    const left = await t.run(async (ctx) => ({
      memories: await ctx.db.query("memories").collect(),
      messages: await ctx.db.query("thread_messages").collect(),
      answers: await ctx.db.query("daily_question_answers").collect(),
      days: await ctx.db.query("couple_days").collect(),
      assets: await ctx.db.query("media_assets").collect(),
      couple: await ctx.db.query("couples").first(),
    }));
    expect([left.memories, left.messages, left.answers, left.days, left.assets].every((rows) => rows.length === 0)).toBe(true);
    expect(left.couple?.purged_at).toBeDefined();
    expect((await events(t, couple.coupleId)).filter((event) => event.reason === "relationship_hard_purge")).toHaveLength(2);
  });

  test("keeps the couple's report snapshot assets", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.relationship.leave_relationship, operation());
    await t.run(async (ctx) => {
      const row = (await ctx.db.query("couples").first())!;
      await ctx.db.patch(row._id, { delete_after: "2026-10-09T00:00:00.000Z" });
      await ctx.db.insert("media_assets", {
        id: newUuid(),
        owner_user_id: couple.first.userId,
        couple_id: couple.coupleId,
        reserved_parent_kind: "report_snapshot",
        reserved_parent_id: newUuid(),
        reserved_by_client_operation_id: newUuid(),
        bucket: "report-snapshots",
        storage_path: "snap/1.jpg",
        media_type: "report_snapshot",
        upload_purpose: "report_snapshot",
        expected_media_type: "report_snapshot",
        expected_bucket: "report-snapshots",
        upload_status: "finalized",
        upload_expires_at: NOW,
        moderation_status: "visible",
        storage_delete_status: "none",
        storage_delete_attempts: 0,
        created_at: NOW,
        updated_at: NOW,
      });
    });
    await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, {});
    // The snapshot never counts against the purge and is never queued for deletion.
    const asset = await t.run((ctx) => ctx.db.query("media_assets").first());
    expect(asset?.storage_delete_status).toBe("none");
    const result = await t.mutation(internal.relationshipJobs.purge_deleted_relationship_content, {});
    expect(result[0]).toMatchObject({ media_rows_deleted: 0 });
    expect(await t.run((ctx) => ctx.db.query("media_assets").collect())).toHaveLength(1);
  });
});
