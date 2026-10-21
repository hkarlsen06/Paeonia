import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { getOrCreateTodayCoupleDay } from "./lib/coupleDays";
import { newUuid } from "./lib/ids";
import { seedProducts } from "./storekit.testHelpers";
import { createCouple, createSignedInUser, newTest, type TestConvex } from "./test.setup";

const NOW = new Date("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});
afterEach(() => {
  vi.useRealTimers();
});

async function demoSetup(t: TestConvex, options: { maxRedemptions?: number } = {}) {
  await seedProducts(t);
  const partner = await createSignedInUser(t, { name: "demo-partner" });
  const reviewer = await createSignedInUser(t, { name: "reviewer" });
  await t.mutation(internal.review.register_review_demo_partner, {
    p_slot: 1,
    p_user_id: partner.userId,
    p_display_name: "Alex",
  });
  const codeId = await t.mutation(internal.review.issue_review_access_code, {
    p_code: "ABC123",
    p_seeded_partner_user_id: partner.userId,
    ...(options.maxRedemptions ? { p_max_redemptions: options.maxRedemptions } : {}),
  });
  return { partner, reviewer, codeId };
}

const redeem = (t: TestConvex, codeId: string, reviewerId: string) =>
  t.mutation(internal.review.redeem_review_access, { p_code_id: codeId, p_reviewer_user_id: reviewerId });

describe("redeem_review_access", () => {
  test("seeds a paired, paywalled demo couple", async () => {
    const t = newTest();
    const { partner, reviewer, codeId } = await demoSetup(t);
    const coupleId = await redeem(t, codeId, reviewer.userId);

    const state = await t.run(async (ctx) => ({
      members: await ctx.db.query("couple_members").collect(),
      couple: await ctx.db.query("couples").first(),
      streak: await ctx.db.query("streak_states").first(),
      locations: await ctx.db.query("latest_partner_locations").collect(),
      sharing: await ctx.db.query("location_sharing_preferences").collect(),
      sessions: await ctx.db.query("review_access_sessions").collect(),
      code: await ctx.db.query("review_access_codes").first(),
      events: await ctx.db.query("relationship_sync_events").collect(),
      transactions: await ctx.db.query("storekit_transactions").collect(),
    }));

    expect(state.members.filter((member) => member.status === "active")).toHaveLength(2);
    expect(state.members.find((member) => member.user_id === partner.userId)?.role).toBe("creator");
    expect(state.couple).toMatchObject({ id: coupleId, status: "active", started_on: "2026-04-13", created_by_user_id: partner.userId });
    expect(state.streak).toMatchObject({
      couple_id: coupleId,
      current_count: 0,
      restorable_count: 12,
      longest_count: 12,
      restorable_through_date: "2026-10-08",
      restore_deadline: "2026-11-09T12:00:00.000Z",
    });
    expect(state.locations).toHaveLength(1);
    expect(state.locations[0]).toMatchObject({ user_id: partner.userId, latitude: 59.9139, longitude: 10.7523, accuracy_m: 25 });
    expect(state.sharing).toMatchObject([{ user_id: partner.userId, is_enabled: true, consent_version: "1" }]);
    expect(state.sessions).toMatchObject([
      { code_id: state.code!.id, user_id: reviewer.userId, couple_id: coupleId, seeded_partner_user_id: partner.userId },
    ]);
    expect(state.code!.redemption_count).toBe(1);
    expect(state.events.map((event) => event.event_kind)).toEqual(["relationship_started", "relationship_started"]);
    // The partner's lapsed subscription is what makes the reviewer see the paywall.
    expect(state.transactions).toMatchObject([
      { user_id: partner.userId, status: "expired", transaction_id: `review-demo-${coupleId}`, environment: "sandbox" },
    ]);

    const [snapshot] = await reviewer.as.query(api.access.get_access_snapshot, {});
    expect(snapshot.relationship_state).toMatchObject({ couple_id: coupleId, partner_user_id: partner.userId, partner_account_name: "Alex" });
    expect(snapshot.couple_entitlement).toMatchObject({ couple_id: coupleId, is_entitled: false });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("is idempotent for the same reviewer even at the redemption ceiling", async () => {
    const t = newTest();
    const { reviewer, codeId } = await demoSetup(t);
    const coupleId = await redeem(t, codeId, reviewer.userId);
    expect(await redeem(t, codeId, reviewer.userId)).toBe(coupleId);
    const code = await t.run((ctx) => ctx.db.query("review_access_codes").first());
    expect(code!.redemption_count).toBe(1);
    expect(await t.run((ctx) => ctx.db.query("couples").collect())).toHaveLength(1);
  });

  test("a consumed code rejects a new reviewer", async () => {
    const t = newTest();
    const { codeId, reviewer } = await demoSetup(t);
    await redeem(t, codeId, reviewer.userId);
    const second = await createSignedInUser(t);
    await expect(redeem(t, codeId, second.userId)).rejects.toThrow(/22023.*review access code is not available/);
  });

  test("a revoked, expired, or unknown code cannot be redeemed, even as a replay", async () => {
    const t = newTest();
    const { codeId, reviewer } = await demoSetup(t);
    await redeem(t, codeId, reviewer.userId);
    expect(await t.mutation(internal.review.revoke_review_access_codes, {})).toBe(1);
    await expect(redeem(t, codeId, reviewer.userId)).rejects.toThrow(/22023/);
    await expect(redeem(t, newUuid(), reviewer.userId)).rejects.toThrow(/22023/);
    expect(await t.mutation(internal.review.revoke_review_access_codes, {})).toBe(0);
    const revoked = await t.run((ctx) => ctx.db.query("review_access_codes").first());
    expect(revoked).toMatchObject({ status: "revoked", revoked_at: NOW.toISOString() });
  });

  test("refuses reviewers and partners that already have a couple", async () => {
    const t = newTest();
    const { partner, codeId, reviewer } = await demoSetup(t);
    await expect(redeem(t, codeId, partner.userId)).rejects.toThrow(/23514.*reviewer cannot be the seeded partner/);

    const busy = await createCouple(t, { entitled: false });
    await expect(redeem(t, codeId, busy.first.userId)).rejects.toThrow(/23505.*reviewer already has an active couple/);

    await redeem(t, codeId, reviewer.userId);
    const code2 = await t.mutation(internal.review.issue_review_access_code, {
      p_code: "SECOND",
      p_seeded_partner_user_id: partner.userId,
    });
    const another = await createSignedInUser(t);
    await expect(redeem(t, code2, another.userId)).rejects.toThrow(
      /23505.*seeded partner still has an active couple; run reset before minting/,
    );
  });

  test("refuses a pair with an active block", async () => {
    const t = newTest();
    const { partner, reviewer, codeId } = await demoSetup(t);
    await t.run(async (ctx) => {
      const [low, high] = [partner.userId, reviewer.userId].sort();
      const pairId = newUuid();
      await ctx.db.insert("relationship_pairs", { id: pairId, user_low_id: low, user_high_id: high, created_at: NOW.toISOString() });
      await ctx.db.insert("relationship_blocks", {
        id: newUuid(),
        pair_id: pairId,
        blocked_by_user_id: reviewer.userId,
        blocked_user_id: partner.userId,
        created_at: NOW.toISOString(),
      });
    });
    await expect(redeem(t, codeId, reviewer.userId)).rejects.toThrow(/42501.*review pair is blocked/);
  });
});

describe("review code lookup", () => {
  test("finds only active, unexpired codes and hashes with SHA-256", async () => {
    const t = newTest();
    const { codeId } = await demoSetup(t);
    expect((await t.query(internal.review.find_active_review_access_code, { p_code: "ABC123" }))?.id).toBe(codeId);
    expect(await t.query(internal.review.find_active_review_access_code, { p_code: "ZZZZZZ" })).toBeNull();
    expect(await t.query(internal.review.hash_review_access_code, { p_code: "ABC123" })).toBe(
      "e0bebd22819993425814866b62701e2919ea26f1370499c1037b53b9d49c2c8a",
    );

    vi.setSystemTime(new Date(NOW.getTime() + 31 * 86_400_000));
    expect(await t.query(internal.review.find_active_review_access_code, { p_code: "ABC123" })).toBeNull();
    expect(await t.mutation(internal.review.expire_stale_review_codes, {})).toBe(1);
    const code = await t.run((ctx) => ctx.db.query("review_access_codes").first());
    expect(code!.status).toBe("expired");
    expect(await t.mutation(internal.review.expire_stale_review_codes, {})).toBe(0);
  });

  test("issuing validates the code row", async () => {
    const t = newTest();
    const { partner } = await demoSetup(t);
    await expect(
      t.mutation(internal.review.issue_review_access_code, { p_code: "ABC123", p_seeded_partner_user_id: partner.userId }),
    ).rejects.toThrow(/23505.*review_access_codes_code_hash_unique/);
    await expect(
      t.mutation(internal.review.issue_review_access_code, { p_code: "NOPARTNER", p_seeded_partner_user_id: null }),
    ).rejects.toThrow(/23514.*review_access_codes_prepaired_partner_check/);
    await expect(
      t.mutation(internal.review.issue_review_access_code, {
        p_code: "ZERO",
        p_seeded_partner_user_id: partner.userId,
        p_max_redemptions: 0,
      }),
    ).rejects.toThrow(/23514/);
    // The purchase-flow scenario needs no partner, and an explicit null never expires.
    await t.mutation(internal.review.issue_review_access_code, {
      p_code: "BUY",
      p_seeded_partner_user_id: null,
      p_scenario: "purchase_flow_unentitled",
      p_expires_at: null,
    });
    const code = await t.query(internal.review.find_active_review_access_code, { p_code: "BUY" });
    expect(code).toMatchObject({ scenario: "purchase_flow_unentitled", max_redemptions: 1, redemption_count: 0 });
    expect(code!.expires_at).toBeUndefined();
  });
});

describe("demo partners", () => {
  test("registers, lists, and re-registers a slot", async () => {
    const t = newTest();
    const first = await createSignedInUser(t, { name: "p1" });
    const second = await createSignedInUser(t, { name: "p2" });
    await t.mutation(internal.review.register_review_demo_partner, { p_slot: 2, p_user_id: second.userId, p_display_name: "Sam" });
    await t.mutation(internal.review.register_review_demo_partner, { p_slot: 1, p_user_id: first.userId, p_display_name: "Alex" });
    expect(await t.query(internal.review.list_review_demo_partners, {})).toEqual([
      { slot: 1, user_id: first.userId, display_name: "Alex" },
      { slot: 2, user_id: second.userId, display_name: "Sam" },
    ]);

    await t.mutation(internal.review.register_review_demo_partner, { p_slot: 1, p_user_id: first.userId, p_display_name: "Alexander" });
    expect((await t.query(internal.review.list_review_demo_partners, {}))[0].display_name).toBe("Alexander");
    const profile = await t.run((ctx) =>
      ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", first.userId)).unique(),
    );
    expect(profile).toMatchObject({
      display_name: "Alexander",
      time_zone_id: "Europe/Oslo",
      moderation_status: "visible",
    });
    expect(profile!.onboarding_completed_at).toBeDefined();

    await expect(
      t.mutation(internal.review.register_review_demo_partner, { p_slot: 3, p_user_id: first.userId, p_display_name: "Dup" }),
    ).rejects.toThrow(/23505.*review_demo_partners_user_unique/);
    await expect(
      t.mutation(internal.review.register_review_demo_partner, { p_slot: 10, p_user_id: first.userId, p_display_name: "Far" }),
    ).rejects.toThrow(/23514/);
    await expect(
      t.mutation(internal.review.register_review_demo_partner, { p_slot: 4, p_user_id: newUuid(), p_display_name: "Ghost" }),
    ).rejects.toThrow(/23503/);
  });

  test("ensure_review_partner restores a hidden profile and keeps an existing time zone", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, { timeZone: "Asia/Tokyo" });
    await t.run(async (ctx) => {
      const profile = await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", user.userId)).unique();
      await ctx.db.patch(profile!._id, { moderation_status: "hidden", deleted_at: NOW.toISOString() });
    });
    expect(await t.mutation(internal.review.ensure_review_partner, { p_user_id: user.userId, p_display_name: "Back" })).toBeNull();
    const profile = await t.run((ctx) =>
      ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", user.userId)).unique(),
    );
    expect(profile).toMatchObject({ display_name: "Back", moderation_status: "visible", time_zone_id: "Asia/Tokyo" });
    expect(profile!.deleted_at).toBeUndefined();
  });
});

describe("reset_review_demo", () => {
  test("deletes the demo couple and its content and leaves real couples alone", async () => {
    const t = newTest();
    const { partner, reviewer, codeId } = await demoSetup(t);
    const demoCoupleId = await redeem(t, codeId, reviewer.userId);
    const real = await createCouple(t, { entitled: false });

    // Content the reviewer created while testing.
    await t.run(async (ctx) => {
      const dayId = await getOrCreateTodayCoupleDay(ctx, demoCoupleId);
      await ctx.db.insert("couple_activity_events", {
        id: newUuid(),
        couple_id: demoCoupleId,
        user_id: reviewer.userId,
        couple_day_id: dayId,
        activity_kind: "memory_created",
        occurred_at: NOW.toISOString(),
        dedupe_key: newUuid(),
        metadata: {},
        created_at: NOW.toISOString(),
      });
      await ctx.db.insert("conversation_threads", {
        id: newUuid(),
        couple_id: demoCoupleId,
        kind: "memory",
        created_by_user_id: reviewer.userId,
        created_at: NOW.toISOString(),
        updated_at: NOW.toISOString(),
        moderation_status: "visible",
      });
    });

    expect(await t.mutation(internal.review.reset_review_demo, {})).toBe(1);

    const left = await t.run(async (ctx) => ({
      couples: await ctx.db.query("couples").collect(),
      members: await ctx.db.query("couple_members").collect(),
      sessions: await ctx.db.query("review_access_sessions").collect(),
      streaks: await ctx.db.query("streak_states").collect(),
      locations: await ctx.db.query("latest_partner_locations").collect(),
      sharing: await ctx.db.query("location_sharing_preferences").collect(),
      threads: await ctx.db.query("conversation_threads").collect(),
      events: await ctx.db.query("relationship_sync_events").collect(),
      days: await ctx.db.query("couple_days").collect(),
      activity: await ctx.db.query("couple_activity_events").collect(),
      transactions: await ctx.db.query("storekit_transactions").collect(),
    }));
    expect(left.couples.map((couple) => couple.id)).toEqual([real.coupleId]);
    expect(left.members.every((member) => member.couple_id === real.coupleId)).toBe(true);
    for (const rows of [left.sessions, left.streaks, left.locations, left.sharing, left.threads, left.events, left.days, left.activity, left.transactions]) {
      expect(rows).toEqual([]);
    }
    expect(partner.userId).toBeDefined();

    // The partner is free to be redeemed again with a new code.
    const next = await t.mutation(internal.review.issue_review_access_code, {
      p_code: "AGAIN",
      p_seeded_partner_user_id: partner.userId,
    });
    expect(await redeem(t, next, reviewer.userId)).not.toBe(demoCoupleId);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
