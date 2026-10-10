import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { createCouple, newTest } from "../test.setup";
import { newUuid } from "./ids";
import { endRelationshipForPair } from "./relationshipEnd";
import { createRelationshipSyncEvent } from "./syncEvents";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

describe("endRelationshipForPair", () => {
  test("ends the couple, updates both members, writes sync events, and removes locations", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run((ctx) =>
      ctx.db.insert("latest_partner_locations", {
        couple_id: couple.coupleId,
        user_id: couple.first.userId,
        latitude: 59.9,
        longitude: 10.7,
        captured_at: "2026-10-10T11:59:00.000Z",
        received_at: "2026-10-10T11:59:00.000Z",
        updated_at: "2026-10-10T11:59:00.000Z",
        source: "manual_refresh",
        client_operation_id: newUuid(),
        client_id: newUuid(),
        client_sequence: 1,
      }),
    );
    expect(await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.first.userId, "user_left"))).toBe(true);
    const state = await t.run(async (ctx) => ({
      couple: await ctx.db.query("couples").first(),
      members: await ctx.db.query("couple_members").collect(),
      events: await ctx.db.query("relationship_sync_events").collect(),
      locations: await ctx.db.query("latest_partner_locations").collect(),
    }));
    expect(state.couple).toMatchObject({
      status: "ended",
      ended_at: "2026-10-10T12:00:00.000Z",
      delete_after: "2026-11-09T12:00:00.000Z",
    });
    const byUser = Object.fromEntries(state.members.map((member) => [member.user_id, member.status]));
    expect(byUser).toEqual({ [couple.first.userId]: "left", [couple.second.userId]: "ended_notice_pending" });
    expect(state.events).toHaveLength(2);
    expect(state.events[0]).toMatchObject({
      event_kind: "relationship_ended",
      reason: "user_left",
      relationship_status: "ended",
      initiated_by_user_id: couple.first.userId,
      local_purge_scope: { relationship_content: "hide", location: "purge", widget_cache: "purge", pending_uploads: "review" },
    });
    expect(state.events.map((event) => event.member_status).sort()).toEqual(["ended_notice_pending", "left"]);
    expect(state.locations).toHaveLength(0);
  });

  test("returns false when the pair has no active couple, and fails for a non-member initiator", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await expect(t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, newUuid(), "user_left"))).rejects.toThrow(
      /42501.*initiating user is not an active member of the relationship/,
    );
    await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.first.userId, "user_left"));
    expect(await t.run((ctx) => endRelationshipForPair(ctx, couple.pairId, couple.first.userId, "user_left"))).toBe(false);
  });
});

describe("createRelationshipSyncEvent", () => {
  test("rejects an oversize purge scope and an empty reason", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const base = {
      user_id: couple.first.userId,
      couple_id: couple.coupleId,
      event_kind: "relationship_updated" as const,
      relationship_status: "active" as const,
      member_status: "active" as const,
    };
    await expect(
      t.run((ctx) => createRelationshipSyncEvent(ctx, { ...base, local_purge_scope: { big: "x".repeat(5000) } })),
    ).rejects.toThrow(/relationship_sync_events_local_purge_scope_check/);
    await expect(t.run((ctx) => createRelationshipSyncEvent(ctx, { ...base, reason: "" }))).rejects.toThrow(
      /relationship_sync_events_reason_check/,
    );
    const id = await t.run((ctx) => createRelationshipSyncEvent(ctx, base));
    expect((await t.run((ctx) => ctx.db.query("relationship_sync_events").first()))?.id).toBe(id);
  });
});
