import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { addDaysToInstant, nowIso } from "./lib/time";
import { makeMemory, operation } from "./reports.fixtures";
import { createCouple, newTest, type TestConvex, type TestCouple } from "./test.setup";

afterEach(() => {
  vi.useRealTimers();
});

test("prune_expired_rows deletes client operations and outbox rows older than 30 days", async () => {
  const t = newTest();
  const now = nowIso();
  const old = addDaysToInstant(now, -31);
  const recent = addDaysToInstant(now, -29);
  await t.run(async (ctx) => {
    for (const created_at of [old, recent]) {
      await ctx.db.insert("client_operations", {
        id: newUuid(),
        user_id: newUuid(),
        client_operation_id: newUuid(),
        client_id: newUuid(),
        client_sequence: 1,
        local_created_at: created_at,
        operation_kind: "test",
        idempotency_scope: "test",
        request_hash: "x",
        status: "succeeded",
        attempt_count: 1,
        last_attempt_at: created_at,
        created_at,
        updated_at: created_at,
      });
      await ctx.db.insert("widget_push_outbox", {
        id: newUuid(),
        recipient_user_id: newUuid(),
        target_widget_device_id: newUuid(),
        widget_push_token_hash: "x",
        apns_environment: "production",
        kind: "widget_updated",
        payload: {},
        scheduled_for: created_at,
        sent_at: created_at,
        created_at,
      });
    }
  });

  await t.mutation(internal.retention.prune_expired_rows, {});

  const left = await t.run(async (ctx) => ({
    operations: (await ctx.db.query("client_operations").collect()).map((row) => row.created_at),
    widgetPushes: (await ctx.db.query("widget_push_outbox").collect()).map((row) => row.created_at),
  }));
  expect(left).toEqual({ operations: [recent], widgetPushes: [recent] });
});

describe("prune_kept_records", () => {
  // The job runs in pages a second apart, and a report queues work on a pool that waits on timers.
  async function prune(t: TestConvex, now: string) {
    await t.mutation(internal.retention.prune_kept_records, { p_now: now });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  }

  test("deletes a report and what hangs on it three years after it closed, and keeps an open one", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
    const t = newTest();
    const report = async (block: boolean) => {
      const couple = await createCouple(t);
      const memory = await makeMemory(t, couple);
      return await couple.second.as.mutation(api.reports.submit_leave_and_report, {
        p_reason: "harassment",
        p_note: null,
        p_target_kind: "memory",
        p_target_id: memory.id,
        p_target_aux_id: null,
        p_block_reported_user: block,
        ...operation(),
      });
    };
    const closed = await report(true);
    const open = await report(false);
    await t.mutation(internal.moderation.apply_report_moderation_action, {
      p_report_id: closed,
      p_action_kind: "hide",
      p_operator_identifier: "ops",
    });
    const left = () =>
      t.run(async (ctx) => ({
        reports: (await ctx.db.query("content_reports").collect()).map((row) => row.id),
        targets: (await ctx.db.query("content_report_targets").collect()).map((row) => row.report_id),
        snapshots: (await ctx.db.query("report_snapshots").collect()).map((row) => row.report_id),
        actions: (await ctx.db.query("moderation_actions").collect()).map((row) => row.report_id),
        warnings: (await ctx.db.query("pair_safety_warning_flags").collect()).map((row) => row.source_report_id),
        blocks: (await ctx.db.query("relationship_blocks").collect()).map((row) => row.source_report_id ?? null),
      }));

    await prune(t, "2029-10-10T11:59:59.000Z");
    expect(await left()).toEqual({
      reports: [closed, open],
      targets: [closed, open],
      snapshots: [closed, open],
      actions: [closed],
      warnings: [closed, open],
      blocks: [closed],
    });

    // Three years to the second after the moderation action. The open report stays however old it is.
    await prune(t, "2029-10-10T12:00:01.000Z");
    await prune(t, "2040-01-01T00:00:00.000Z");
    expect(await left()).toEqual({
      reports: [open],
      targets: [open],
      snapshots: [open],
      actions: [],
      warnings: [open],
      // The block outlives the report that led to it.
      blocks: [null],
    });
  });

  test("deletes a closed privacy request after three years, a finished account deletion with what the account left", async () => {
    vi.useFakeTimers();
    const t = newTest();
    const closedAt = "2026-10-10T12:00:00.000Z";
    const request = (kind: "deletion" | "correction", status: "completed" | "cancelled" | "submitted") => ({
      id: newUuid(),
      user_id: newUuid(),
      request_kind: kind,
      status,
      requested_at: closedAt,
      revision: 1,
      created_at: closedAt,
      updated_at: closedAt,
    });
    const corrected = request("correction", "completed");
    const withdrawn = request("correction", "cancelled");
    const waiting = request("correction", "submitted");
    const deletedAccount = request("deletion", "completed");
    // The Clerk delete of this one never went through, so its account is not gone.
    const stuckDeletion = { ...request("deletion", "completed"), status: "processing" as const };
    const job = (row: { id: string; user_id: string }, status: "completed" | "attention_required") => ({
      id: newUuid(),
      request_id: row.id,
      user_id: row.user_id,
      auth_provider: "apple" as const,
      status,
      provider_revocation_status: "succeeded" as const,
      created_at: closedAt,
      updated_at: closedAt,
    });
    await t.run(async (ctx) => {
      for (const row of [corrected, withdrawn, waiting, deletedAccount, stuckDeletion]) {
        await ctx.db.insert("privacy_requests", row);
        await ctx.db.insert("privacy_request_events", {
          id: newUuid(),
          request_id: row.id,
          event_kind: "submitted",
          metadata: {},
          created_at: closedAt,
        });
      }
      await ctx.db.insert("account_deletion_jobs", { ...job(deletedAccount, "completed"), completed_at: closedAt });
      await ctx.db.insert("account_deletion_jobs", job(stuckDeletion, "attention_required"));
      for (const row of [deletedAccount, stuckDeletion]) {
        await ctx.db.insert("users", {
          id: row.user_id,
          clerk_user_id: `user_${row.user_id}`,
          auth_provider: "apple",
          created_at: closedAt,
        });
      }
    });
    const left = () =>
      t.run(async (ctx) => ({
        requests: (await ctx.db.query("privacy_requests").collect()).map((row) => row.id),
        events: (await ctx.db.query("privacy_request_events").collect()).map((row) => row.request_id),
        jobs: (await ctx.db.query("account_deletion_jobs").collect()).map((row) => row.request_id),
        users: (await ctx.db.query("users").collect()).map((row) => row.id),
      }));
    const all = [corrected, withdrawn, waiting, deletedAccount, stuckDeletion].map((row) => row.id);
    const deletions = [deletedAccount, stuckDeletion];

    await prune(t, "2029-10-10T11:59:59.000Z");
    expect(await left()).toEqual({
      requests: all,
      events: all,
      jobs: deletions.map((row) => row.id),
      users: deletions.map((row) => row.user_id),
    });

    await prune(t, "2029-10-10T12:00:01.000Z");
    await prune(t, "2040-01-01T00:00:00.000Z");
    const kept = [waiting.id, stuckDeletion.id];
    expect(await left()).toEqual({ requests: kept, events: kept, jobs: [stuckDeletion.id], users: [stuckDeletion.user_id] });
  });

  test("deletes the admin log after three years and an ended grant after one, and keeps a live grant", async () => {
    vi.useFakeTimers();
    const t = newTest();
    const at = "2026-10-10T12:00:00.000Z";
    const grant = (status: "active" | "expired" | "revoked", ended: { expires_at?: string; revoked_at?: string }) => ({
      id: newUuid(),
      user_id: newUuid(),
      grant_kind: "test" as const,
      status,
      scope: "user" as const,
      reason: "test",
      granted_by: "test",
      granted_at: "2026-01-01T00:00:00.000Z",
      created_at: "2026-01-01T00:00:00.000Z",
      updated_at: at,
      ...ended,
    });
    const lifetime = { ...grant("active", {}), grant_kind: "lifetime" as const };
    const ranOut = grant("expired", { expires_at: at });
    // Taken back long after it was due to end, so the year counts from the day it was taken back.
    const takenBack = grant("revoked", { expires_at: "2026-02-01T00:00:00.000Z", revoked_at: at });
    await t.run(async (ctx) => {
      for (const row of [lifetime, ranOut, takenBack]) await ctx.db.insert("entitlement_grants", row);
      await ctx.db.insert("admin_audit_log", { id: newUuid(), action: "user_banned", target_user_id: newUuid(), created_at: at });
    });
    const left = () =>
      t.run(async (ctx) => ({
        grants: (await ctx.db.query("entitlement_grants").collect()).map((row) => row.id),
        log: (await ctx.db.query("admin_audit_log").collect()).length,
      }));

    await prune(t, "2027-10-10T11:59:59.000Z");
    expect(await left()).toEqual({ grants: [lifetime.id, ranOut.id, takenBack.id], log: 1 });
    await prune(t, "2027-10-10T12:00:01.000Z");
    expect(await left()).toEqual({ grants: [lifetime.id], log: 1 });
    await prune(t, "2029-10-10T11:59:59.000Z");
    expect(await left()).toEqual({ grants: [lifetime.id], log: 1 });
    await prune(t, "2029-10-10T12:00:01.000Z");
    expect(await left()).toEqual({ grants: [lifetime.id], log: 0 });
  });

  test("deletes a used, replaced or expired invite 30 days after its expiry time, with its code", async () => {
    vi.useFakeTimers();
    const t = newTest();
    const expiresAt = "2026-10-10T12:00:00.000Z";
    const invite = (status: "pending" | "accepted" | "revoked" | "expired") => ({
      id: newUuid(),
      created_by_user_id: newUuid(),
      status,
      expires_at: expiresAt,
      created_at: "2026-09-10T12:00:00.000Z",
      updated_at: "2026-09-10T12:00:00.000Z",
    });
    const invites = (["pending", "accepted", "revoked", "expired"] as const).map(invite);
    await t.run(async (ctx) => {
      for (const row of invites) {
        await ctx.db.insert("pairing_invites", row);
        await ctx.db.insert("pairing_invite_secrets", { invite_id: row.id, code_hash: row.id, created_at: row.created_at });
      }
    });
    const left = () =>
      t.run(async (ctx) => ({
        invites: (await ctx.db.query("pairing_invites").collect()).map((row) => row.status),
        codes: (await ctx.db.query("pairing_invite_secrets").collect()).map((row) => row.invite_id),
      }));

    await prune(t, "2026-11-09T11:59:59.000Z");
    expect(await left()).toEqual({ invites: ["pending", "accepted", "revoked", "expired"], codes: invites.map((row) => row.id) });
    // The hourly cron marks a pending invite expired, so this job leaves a pending one alone.
    await prune(t, "2026-11-09T12:00:01.000Z");
    expect(await left()).toEqual({ invites: ["pending"], codes: [invites[0].id] });
  });

  test("deletes a purged couple's rows and its pair once no block or report holds the pair", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
    const t = newTest();
    const purged = await createCouple(t);
    const blocked = await createCouple(t);
    const reported = await createCouple(t);
    const ended = await createCouple(t);
    const active = await createCouple(t);
    const memory = await makeMemory(t, reported);
    const reportId = await reported.second.as.mutation(api.reports.submit_leave_and_report, {
      p_reason: "harassment",
      p_note: null,
      p_target_kind: "memory",
      p_target_id: memory.id,
      p_target_aux_id: null,
      p_block_reported_user: false,
      ...operation(),
    });
    await t.run(async (ctx) => {
      const at = "2026-10-10T12:00:00.000Z";
      for (const couple of [purged, blocked, reported, ended]) {
        const row = (await ctx.db.query("couples").withIndex("by_uuid", (q) => q.eq("id", couple.coupleId)).unique())!;
        await ctx.db.patch(
          row._id,
          couple === ended
            ? { status: "ended", ended_at: at, delete_after: "2026-11-09T12:00:00.000Z" }
            : { status: "deleted", ended_at: at, delete_after: at, purged_at: at },
        );
        await ctx.db.insert("relationship_sync_events", {
          id: newUuid(),
          user_id: couple.first.userId,
          couple_id: couple.coupleId,
          event_kind: "content_purged",
          occurred_at: at,
          relationship_status: "deleted",
          member_status: "left",
          local_purge_scope: {},
          created_at: at,
          updated_at: at,
        });
        const inviteId = newUuid();
        await ctx.db.insert("pairing_invites", {
          id: inviteId,
          created_by_user_id: couple.first.userId,
          status: "accepted",
          // Far enough ahead that only the couple's own cleanup can take it.
          expires_at: "2099-01-01T00:00:00.000Z",
          couple_id: couple.coupleId,
          created_at: at,
          updated_at: at,
        });
        await ctx.db.insert("pairing_invite_secrets", { invite_id: inviteId, code_hash: inviteId, created_at: at });
      }
      await ctx.db.insert("relationship_blocks", {
        id: newUuid(),
        pair_id: blocked.pairId,
        blocked_by_user_id: blocked.first.userId,
        blocked_user_id: blocked.second.userId,
        created_at: at,
      });
    });
    const left = () =>
      t.run(async (ctx) => {
        const of = (rows: { couple_id?: string }[]) => [...new Set(rows.map((row) => row.couple_id))].sort();
        const invites = await ctx.db.query("pairing_invites").collect();
        return {
          pairs: (await ctx.db.query("relationship_pairs").collect()).map((row) => row.id).sort(),
          couples: (await ctx.db.query("couples").collect()).map((row) => row.id).sort(),
          members: of(await ctx.db.query("couple_members").collect()),
          events: of(await ctx.db.query("relationship_sync_events").collect()),
          invites: of(invites),
          codes: (await ctx.db.query("pairing_invite_secrets").collect()).length,
        };
      });
    const ids = (couples: TestCouple[], key: "coupleId" | "pairId" = "coupleId") => couples.map((couple) => couple[key]).sort();
    const kept = async (couples: TestCouple[]) => {
      const rows = await left();
      expect(rows.pairs).toEqual(ids(couples, "pairId"));
      expect(rows.couples).toEqual(ids(couples));
      expect(rows.members).toEqual(ids(couples));
      // The active couple was given no event or invite above.
      const ended = couples.filter((couple) => couple !== active);
      expect(rows.events).toEqual(expect.arrayContaining(ids(ended)));
      expect(rows.events).not.toContain(purged.coupleId);
      expect(rows.invites).toEqual(ids(ended));
      expect(rows.codes).toBe(ended.length);
    };

    // The purged couple with nothing on its pair goes. A block and a report each hold theirs, and
    // a couple that is not purged yet, or still active, is never touched.
    await prune(t, "2026-10-11T03:40:00.000Z");
    await kept([blocked, reported, ended, active]);

    // The block is taken back. The report closes and still holds its pair for three years.
    await t.run(async (ctx) => {
      for (const block of await ctx.db.query("relationship_blocks").collect()) await ctx.db.delete(block._id);
    });
    await t.mutation(internal.moderation.apply_report_moderation_action, {
      p_report_id: reportId,
      p_action_kind: "hide",
      p_operator_identifier: "ops",
    });
    await prune(t, "2026-10-12T03:40:00.000Z");
    await kept([reported, ended, active]);
    await prune(t, "2029-10-11T03:40:00.000Z");
    await kept([ended, active]);
  });

  test("deletes purchase records five years after the end of the Norwegian year of the purchase", async () => {
    vi.useFakeTimers();
    const t = newTest();
    // The last second of 2026 in Norway, and the first of 2027.
    const in2026 = "2026-12-31T22:59:59.000Z";
    const in2027 = "2026-12-31T23:00:00.000Z";
    const payload = (createdAt: string) => ({
      id: newUuid(),
      payload_kind: "transaction" as const,
      environment: "production" as const,
      received_at: createdAt,
      created_at: createdAt,
    });
    const purchase = (purchasedAt: string, rawPayloadId: string) => ({
      id: newUuid(),
      user_id: newUuid(),
      product_id: newUuid(),
      environment: "production" as const,
      original_transaction_id: newUuid(),
      transaction_id: newUuid(),
      status: "expired" as const,
      purchased_at: purchasedAt,
      raw_payload_id: rawPayloadId,
      created_at: purchasedAt,
      updated_at: purchasedAt,
    });
    const oldPayload = payload(in2026);
    // Apple signed the 2027 purchase a moment before it started, so its data is older than it.
    const earlyPayload = payload(in2026);
    const noticePayload = payload(in2026);
    const restorePayload = payload(in2026);
    const old = purchase(in2026, oldPayload.id);
    const newer = purchase(in2027, earlyPayload.id);
    await t.run(async (ctx) => {
      for (const row of [oldPayload, earlyPayload, noticePayload, restorePayload]) await ctx.db.insert("storekit_payloads", row);
      for (const row of [old, newer]) await ctx.db.insert("storekit_transactions", row);
      await ctx.db.insert("storekit_notification_events", {
        id: newUuid(),
        notification_uuid: newUuid(),
        notification_type: "DID_RENEW",
        environment: "production",
        raw_payload_id: noticePayload.id,
        received_at: in2026,
        created_at: in2026,
      });
      await ctx.db.insert("streak_restorations", {
        id: newUuid(),
        couple_id: newUuid(),
        purchaser_user_id: newUuid(),
        product_id: newUuid(),
        environment: "production",
        transaction_id: newUuid(),
        restored_count: 3,
        purchased_at: in2026,
        restored_at: in2026,
        raw_payload_id: restorePayload.id,
        status: "applied",
        created_at: in2026,
      });
    });
    const left = () =>
      t.run(async (ctx) => ({
        purchases: (await ctx.db.query("storekit_transactions").collect()).map((row) => row.id),
        payloads: (await ctx.db.query("storekit_payloads").collect()).map((row) => row.id),
        notices: (await ctx.db.query("storekit_notification_events").collect()).length,
        restores: (await ctx.db.query("streak_restorations").collect()).length,
      }));

    // The last minute of 2031 in Norway: five years after the end of 2026 have not passed yet.
    await prune(t, "2031-12-31T22:59:00.000Z");
    expect(await left()).toEqual({
      purchases: [old.id, newer.id],
      payloads: [oldPayload.id, earlyPayload.id, noticePayload.id, restorePayload.id],
      notices: 1,
      restores: 1,
    });

    // New Year 2032 in Norway. The 2027 purchase keeps its signed data for another year.
    await prune(t, "2031-12-31T23:00:00.000Z");
    expect(await left()).toEqual({ purchases: [newer.id], payloads: [earlyPayload.id], notices: 0, restores: 0 });
  });
});
