import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { createCouple, newTest, type TestConvex, type TestUser } from "./test.setup";

const NOW = new Date("2026-10-10T12:00:00.000Z");
const DAY = 86_400_000;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});
afterEach(() => {
  vi.useRealTimers();
});

const inDays = (days: number) => new Date(Date.now() + days * DAY).toISOString();

async function coupleHasAccess(user: TestUser): Promise<boolean> {
  const [snapshot] = await user.as.query(api.access.get_access_snapshot, {});
  return snapshot.couple_entitlement?.is_entitled === true;
}

function createTestGrant(
  t: TestConvex,
  userId: string,
  overrides: Partial<{ p_grant_kind: "lifetime" | "test"; p_reason: string; p_granted_by: string; p_expires_at: string }> = {},
) {
  return t.mutation(internal.entitlementGrants.create_entitlement_grant, {
    p_user_id: userId,
    p_grant_kind: "test",
    p_reason: "QA on build 41",
    p_granted_by: "hjalmar",
    p_expires_at: inDays(30),
    ...overrides,
  });
}

const grantRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("entitlement_grants").collect());

describe("entitlement grants", () => {
  test("a grant to one partner gives the couple access and records who gave it and why", async () => {
    const t = newTest();
    const { first, second } = await createCouple(t, { entitled: false });
    expect(await coupleHasAccess(second)).toBe(false);

    const result = await createTestGrant(t, first.userId);

    expect(result.created).toBe(true);
    expect(await coupleHasAccess(second)).toBe(true);
    expect(await grantRows(t)).toMatchObject([
      { id: result.grant_id, user_id: first.userId, status: "active", reason: "QA on build 41", granted_by: "hjalmar" },
    ]);
  });

  test("a user has one live grant per kind and product", async () => {
    const t = newTest();
    const { first } = await createCouple(t, { entitled: false });
    const original = await createTestGrant(t, first.userId);

    const again = await createTestGrant(t, first.userId, { p_reason: "another reason", p_expires_at: inDays(90) });
    expect(again).toEqual({ grant_id: original.grant_id, created: false, expires_at: original.expires_at });
    expect((await createTestGrant(t, first.userId, { p_grant_kind: "lifetime" })).created).toBe(true);

    // Once the test grant ran out, a new one replaces it before the expiry cron marks the old one.
    vi.setSystemTime(NOW.getTime() + 31 * DAY);
    const renewed = await createTestGrant(t, first.userId);
    expect(renewed.created).toBe(true);
    const testGrants = (await grantRows(t)).filter((grant) => grant.grant_kind === "test");
    expect(testGrants.map((grant) => [grant.id, grant.status])).toEqual([
      [original.grant_id, "expired"],
      [renewed.grant_id, "active"],
    ]);
  });

  test("a revoked grant removes the couple's access", async () => {
    const t = newTest();
    const { first, second } = await createCouple(t, { entitled: false });
    const { grant_id } = await createTestGrant(t, first.userId);
    const revoke = (reason: string) =>
      t.mutation(internal.entitlementGrants.revoke_entitlement_grant, { p_grant_id: grant_id, p_reason: reason });

    expect(await revoke("QA finished")).toEqual({ changed: true });

    expect(await coupleHasAccess(second)).toBe(false);
    expect(await grantRows(t)).toMatchObject([
      { status: "revoked", revoked_at: NOW.toISOString(), revoked_reason: "QA finished" },
    ]);
    // A second revoke keeps the first record.
    expect(await revoke("again")).toEqual({ changed: false });
    expect((await grantRows(t))[0].revoked_reason).toBe("QA finished");
    // A revoked grant does not block a new one.
    expect((await createTestGrant(t, first.userId)).created).toBe(true);
    expect(await coupleHasAccess(second)).toBe(true);
  });

  test("refuses a grant without a reason, a granter, a known user, or an end", async () => {
    const t = newTest();
    const { first } = await createCouple(t, { entitled: false });

    await expect(createTestGrant(t, first.userId, { p_reason: "  " })).rejects.toThrow(/needs a reason/);
    await expect(createTestGrant(t, first.userId, { p_granted_by: "" })).rejects.toThrow(/needs granted_by/);
    await expect(createTestGrant(t, newUuid())).rejects.toThrow(/does not exist/);
    await expect(
      t.mutation(internal.entitlementGrants.create_entitlement_grant, {
        p_user_id: first.userId,
        p_grant_kind: "test",
        p_reason: "QA",
        p_granted_by: "hjalmar",
      }),
    ).rejects.toThrow(/needs expires_at/);
    await expect(createTestGrant(t, first.userId, { p_expires_at: inDays(-1) })).rejects.toThrow(/in the future/);
    expect(await grantRows(t)).toEqual([]);

    const { grant_id } = await createTestGrant(t, first.userId);
    await expect(
      t.mutation(internal.entitlementGrants.revoke_entitlement_grant, { p_grant_id: grant_id, p_reason: "" }),
    ).rejects.toThrow(/needs a reason/);
    expect((await grantRows(t))[0].status).toBe("active");
  });
});
