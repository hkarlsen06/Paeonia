import { describe, expect, test } from "vitest";
import { createCouple, createSignedInUser, grantLifetime, newTest } from "../test.setup";
import {
  canAccessCoupleContent,
  canAccessVisibleMemory,
  findRelationshipPairId,
  getCurrentEntitledCoupleId,
  getEntitledCoupleIdForUser,
  getOrCreateRelationshipPair,
  hasActiveRelationshipBlock,
  isActiveCoupleMember,
  isActiveEntitledCoupleMember,
  isAdmin,
  isCouplePairMember,
  resolveCurrentCoupleEntitlement,
  resolveUserEntitlement,
  userHasDirectEntitlement,
} from "./access";
import { newUuid } from "./ids";

const PAST = "2020-01-01T00:00:00.000Z";
const FUTURE = "2099-01-01T00:00:00.000Z";

async function insertStorekit(
  t: ReturnType<typeof newTest>,
  userId: string,
  status: "active" | "grace" | "expired" | "billing_retry",
  expiresAt: string | undefined,
) {
  await t.run(async (ctx) => {
    const now = new Date().toISOString();
    const id = newUuid();
    await ctx.db.insert("storekit_transactions", {
      id,
      user_id: userId,
      product_id: newUuid(),
      environment: "sandbox",
      original_transaction_id: `orig-${id}`,
      transaction_id: `tx-${id}`,
      status,
      expires_at: expiresAt,
      created_at: now,
      updated_at: now,
    });
  });
}

describe("entitlements", () => {
  test("a user with nothing is not entitled and every detail is null", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const result = await t.run((ctx) => resolveUserEntitlement(ctx, user.userId));
    expect(result).toEqual({
      user_id: user.userId,
      is_entitled: false,
      source: null,
      status: null,
      product_id: null,
      current_period_end: null,
      updated_at: null,
    });
  });

  test("active and grace StoreKit transactions grant access only before they expire", async () => {
    const t = newTest();
    const active = await createSignedInUser(t);
    const grace = await createSignedInUser(t);
    const lapsed = await createSignedInUser(t);
    const retry = await createSignedInUser(t);
    await insertStorekit(t, active.userId, "active", FUTURE);
    await insertStorekit(t, grace.userId, "grace", FUTURE);
    await insertStorekit(t, lapsed.userId, "active", PAST);
    await insertStorekit(t, retry.userId, "billing_retry", FUTURE);
    const results = await t.run(async (ctx) => [
      await userHasDirectEntitlement(ctx, active.userId),
      await userHasDirectEntitlement(ctx, grace.userId),
      await userHasDirectEntitlement(ctx, lapsed.userId),
      await userHasDirectEntitlement(ctx, retry.userId),
    ]);
    expect(results).toEqual([true, true, false, false]);
  });

  test("lifetime grants never expire, review and test grants need a future expiry", async () => {
    const t = newTest();
    const lifetime = await createSignedInUser(t);
    const review = await createSignedInUser(t);
    const expiredReview = await createSignedInUser(t);
    const revoked = await createSignedInUser(t);
    await grantLifetime(t, lifetime.userId);
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      const base = { granted_at: now, created_at: now, updated_at: now, scope: "review" as const };
      await ctx.db.insert("entitlement_grants", {
        ...base, id: newUuid(), user_id: review.userId, grant_kind: "review", status: "active", expires_at: FUTURE,
      });
      await ctx.db.insert("entitlement_grants", {
        ...base, id: newUuid(), user_id: expiredReview.userId, grant_kind: "review", status: "active", expires_at: PAST,
      });
      await ctx.db.insert("entitlement_grants", {
        ...base, id: newUuid(), user_id: revoked.userId, grant_kind: "lifetime", status: "revoked", revoked_at: now,
      });
    });
    const resolved = await t.run(async (ctx) => ({
      lifetime: await resolveUserEntitlement(ctx, lifetime.userId),
      review: await resolveUserEntitlement(ctx, review.userId),
      expiredReview: await resolveUserEntitlement(ctx, expiredReview.userId),
      revoked: await resolveUserEntitlement(ctx, revoked.userId),
    }));
    expect(resolved.lifetime).toMatchObject({ is_entitled: true, source: "lifetime_grant", status: "lifetime" });
    expect(resolved.review).toMatchObject({ is_entitled: true, source: "review_grant", status: "active" });
    expect(resolved.expiredReview).toMatchObject({ is_entitled: false, status: "expired" });
    expect(resolved.revoked).toMatchObject({ is_entitled: false, status: "revoked" });
  });

  test("the best entitlement ranks lifetime over active over grace", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    await insertStorekit(t, user.userId, "grace", "2098-01-01T00:00:00.000Z");
    await insertStorekit(t, user.userId, "active", FUTURE);
    const grantee = await t.run((ctx) => resolveUserEntitlement(ctx, user.userId));
    expect(grantee).toMatchObject({ is_entitled: true, status: "active", current_period_end: FUTURE });
    await grantLifetime(t, user.userId);
    expect((await t.run((ctx) => resolveUserEntitlement(ctx, user.userId))).status).toBe("lifetime");
  });
});

describe("couple access", () => {
  test("either partner reaches the couple when only one pays", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const result = await t.run(async (ctx) => ({
      firstMember: await isActiveCoupleMember(ctx, couple.first.userId, couple.coupleId),
      secondMember: await isActiveCoupleMember(ctx, couple.second.userId, couple.coupleId),
      secondEntitled: await isActiveEntitledCoupleMember(ctx, couple.second.userId, couple.coupleId),
      canAccess: await canAccessCoupleContent(ctx, couple.second.userId, couple.coupleId),
      current: await getCurrentEntitledCoupleId(ctx, couple.second.userId),
      forUser: await getEntitledCoupleIdForUser(ctx, couple.second.userId),
    }));
    expect(result).toEqual({
      firstMember: true,
      secondMember: true,
      secondEntitled: true,
      canAccess: true,
      current: couple.coupleId,
      forUser: couple.coupleId,
    });
  });

  test("an outsider has no access, even to an entitled couple", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const outsider = await createSignedInUser(t);
    const result = await t.run(async (ctx) => ({
      member: await isActiveCoupleMember(ctx, outsider.userId, couple.coupleId),
      entitled: await canAccessCoupleContent(ctx, outsider.userId, couple.coupleId),
      forUser: await getEntitledCoupleIdForUser(ctx, outsider.userId),
    }));
    expect(result).toEqual({ member: false, entitled: false, forUser: null });
    await expect(t.run((ctx) => getCurrentEntitledCoupleId(ctx, outsider.userId))).rejects.toThrow(
      /42501.*active entitled couple access is required/,
    );
  });

  test("an unentitled couple is a member couple but cannot access content", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    const result = await t.run(async (ctx) => ({
      member: await isActiveCoupleMember(ctx, couple.first.userId, couple.coupleId),
      entitled: await canAccessCoupleContent(ctx, couple.first.userId, couple.coupleId),
      current: await resolveCurrentCoupleEntitlement(ctx, couple.first.userId),
    }));
    expect(result.member).toBe(true);
    expect(result.entitled).toBe(false);
    expect(result.current).toMatchObject({ couple_id: couple.coupleId, is_entitled: false, covering_user_id: null });
  });

  test("the couple entitlement names the covering partner", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const current = await t.run((ctx) => resolveCurrentCoupleEntitlement(ctx, couple.second.userId));
    expect(current).toMatchObject({
      couple_id: couple.coupleId,
      is_entitled: true,
      covering_user_id: couple.first.userId,
      source: "lifetime_grant",
      status: "lifetime",
    });
    const nobody = await createSignedInUser(t);
    expect(await t.run((ctx) => resolveCurrentCoupleEntitlement(ctx, nobody.userId))).toBeNull();
  });

  test("ended couples and former members lose active access but keep pair membership", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      const row = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_user_id", (q) =>
          q.eq("couple_id", couple.coupleId).eq("user_id", couple.second.userId),
        )
        .unique();
      await ctx.db.patch(row!._id, { status: "left", left_at: new Date().toISOString() });
    });
    const result = await t.run(async (ctx) => ({
      leftActive: await isActiveCoupleMember(ctx, couple.second.userId, couple.coupleId),
      leftPair: await isCouplePairMember(ctx, couple.second.userId, couple.pairId),
      stillActive: await isActiveCoupleMember(ctx, couple.first.userId, couple.coupleId),
      outsiderPair: await isCouplePairMember(ctx, newUuid(), couple.pairId),
    }));
    expect(result).toEqual({ leftActive: false, leftPair: true, stillActive: true, outsiderPair: false });
  });

  test("visible memories need access and a visible, undeleted row", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const outsider = await createSignedInUser(t);
    const memoryId = newUuid();
    const hiddenId = newUuid();
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      const base = {
        couple_id: couple.coupleId,
        title: "Trip",
        memory_date: "2026-01-01",
        created_by_user_id: couple.first.userId,
        last_edited_by_user_id: couple.first.userId,
        revision: 1,
        created_at: now,
        updated_at: now,
      };
      await ctx.db.insert("memories", { ...base, id: memoryId, moderation_status: "visible" });
      await ctx.db.insert("memories", { ...base, id: hiddenId, moderation_status: "hidden" });
    });
    const result = await t.run(async (ctx) => ({
      member: await canAccessVisibleMemory(ctx, couple.second.userId, memoryId),
      outsider: await canAccessVisibleMemory(ctx, outsider.userId, memoryId),
      hidden: await canAccessVisibleMemory(ctx, couple.second.userId, hiddenId),
      missing: await canAccessVisibleMemory(ctx, couple.second.userId, newUuid()),
    }));
    expect(result).toEqual({ member: true, outsider: false, hidden: false, missing: false });
  });
});

describe("relationship pairs and blocks", () => {
  test("pairs are order independent and unique", async () => {
    const t = newTest();
    const a = await createSignedInUser(t);
    const b = await createSignedInUser(t);
    const result = await t.run(async (ctx) => {
      const before = await findRelationshipPairId(ctx, a.userId, b.userId);
      const created = await getOrCreateRelationshipPair(ctx, a.userId, b.userId);
      const reversed = await getOrCreateRelationshipPair(ctx, b.userId, a.userId);
      const found = await findRelationshipPairId(ctx, b.userId, a.userId);
      const pair = await ctx.db.query("relationship_pairs").collect();
      return { before, created, reversed, found, pair };
    });
    expect(result.before).toBeNull();
    expect(result.reversed).toBe(result.created);
    expect(result.found).toBe(result.created);
    expect(result.pair).toHaveLength(1);
    expect(result.pair[0].user_low_id < result.pair[0].user_high_id).toBe(true);
  });

  test("a pair needs two distinct users", async () => {
    const t = newTest();
    const a = await createSignedInUser(t);
    await expect(t.run((ctx) => getOrCreateRelationshipPair(ctx, a.userId, a.userId))).rejects.toThrow(
      /23514.*relationship pair requires two distinct users/,
    );
    expect(await t.run((ctx) => findRelationshipPairId(ctx, a.userId, a.userId))).toBeNull();
    expect(await t.run((ctx) => findRelationshipPairId(ctx, a.userId, undefined))).toBeNull();
  });

  test("only unrevoked blocks count", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await t.run((ctx) => hasActiveRelationshipBlock(ctx, couple.pairId))).toBe(false);
    const blockId = await t.run(async (ctx) =>
      ctx.db.insert("relationship_blocks", {
        id: newUuid(),
        pair_id: couple.pairId,
        blocked_by_user_id: couple.first.userId,
        blocked_user_id: couple.second.userId,
        created_at: new Date().toISOString(),
      }),
    );
    expect(await t.run((ctx) => hasActiveRelationshipBlock(ctx, couple.pairId))).toBe(true);
    await t.run((ctx) =>
      ctx.db.patch(blockId, {
        revoked_at: new Date().toISOString(),
        revoked_by_user_id: couple.first.userId,
        revoke_reason: "user_unblocked",
      }),
    );
    expect(await t.run((ctx) => hasActiveRelationshipBlock(ctx, couple.pairId))).toBe(false);
  });

  test("app users are never admins", () => {
    expect(isAdmin()).toBe(false);
  });
});
