import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { addDevice, createCouple, createSignedInUser, newTest, relationshipStateOf, type TestConvex } from "./test.setup";

const NOW = "2026-10-14T12:00:00.000Z";
const ADMIN_SUBJECT = "user_admin";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
  vi.stubEnv("PAEONIA_ADMIN_CLERK_USER_IDS", ` ${ADMIN_SUBJECT} , user_other_admin`);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function expectFail(promise: Promise<unknown>, code: string, message?: string) {
  const error = (await promise.then(
    () => null,
    (caught) => caught,
  )) as { data?: { code: string; message: string } } | null;
  expect(error?.data?.code).toBe(code);
  if (message) expect(error?.data?.message).toContain(message);
}

async function createAdmin(t: TestConvex) {
  return await createSignedInUser(t, { subject: ADMIN_SUBJECT, name: "Admin" });
}

describe("admin access", () => {
  test("only the Clerk users in the environment variable are admins", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const user = await createSignedInUser(t, { name: "Someone" });

    expect(await admin.as.query(api.admin.get_admin_status, {})).toEqual({ is_admin: true });
    expect(await user.as.query(api.admin.get_admin_status, {})).toEqual({ is_admin: false });
    await expectFail(user.as.query(api.admin.search_users, {}), "42501", "admin access required");
    await expectFail(user.as.mutation(api.admin.ban_user, { p_user_id: admin.userId, p_reason: "x" }), "42501");
    await expectFail(user.as.query(api.admin.get_audit_log, {}), "42501");
  });

  test("an admin finds users by id, lists the newest, and lists the banned ones", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const user = await createSignedInUser(t, { name: "Someone" });

    const byId = await admin.as.query(api.admin.search_users, { p_query: user.userId.toUpperCase() });
    expect(byId).toEqual([expect.objectContaining({ user_id: user.userId, display_name: "Someone", banned_at: null })]);
    expect((await admin.as.query(api.admin.search_users, {})).map((row) => row.user_id)).toEqual(
      expect.arrayContaining([admin.userId, user.userId]),
    );

    await admin.as.mutation(api.admin.ban_user, { p_user_id: user.userId, p_reason: "spam" });
    const banned = await admin.as.query(api.admin.search_users, { p_banned_only: true });
    expect(banned).toEqual([expect.objectContaining({ user_id: user.userId, banned_at: NOW })]);
  });
});

describe("banning", () => {
  test("a ban closes the account, ends the relationship, turns off pushes, and is logged", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const couple = await createCouple(t);
    const device = await addDevice(t, couple.first.userId);

    expect(
      await admin.as.mutation(api.admin.ban_user, { p_user_id: couple.first.userId, p_reason: "  harassment  " }),
    ).toEqual({ changed: true });

    const [snapshot] = await couple.first.as.query(api.access.get_access_snapshot, {});
    expect(snapshot).toEqual({
      account_status: "banned",
      user_entitlement: null,
      couple_entitlement: null,
      relationship_state: null,
    });
    // Every other function treats the banned person as signed out.
    await expectFail(couple.first.as.query(api.identity.get_notification_preferences, {}), "42501");

    const partnerState = await relationshipStateOf(couple.second);
    expect(partnerState).toMatchObject({ relationship_status: "ended", member_status: "ended_notice_pending" });
    const [partnerSnapshot] = await couple.second.as.query(api.access.get_access_snapshot, {});
    expect(partnerSnapshot.account_status).toBe("active");

    const disabledAt = await t.run(async (ctx) => (await ctx.db.get(device._id))?.disabled_at);
    expect(disabledAt).toBe(NOW);

    const detail = await admin.as.query(api.admin.get_user, { p_user_id: couple.first.userId });
    expect(detail).toMatchObject({ banned_at: NOW, ban_reason: "harassment", banned_by_display_name: "Admin" });
    const log = await admin.as.query(api.admin.get_audit_log, { p_target_user_id: couple.first.userId });
    expect(log).toEqual([
      expect.objectContaining({ action: "user_banned", admin_user_id: admin.userId, reason: "harassment" }),
    ]);

    // A second ban changes nothing and logs nothing.
    expect(await admin.as.mutation(api.admin.ban_user, { p_user_id: couple.first.userId, p_reason: "again" })).toEqual({
      changed: false,
    });
    expect(await admin.as.query(api.admin.get_audit_log, {})).toHaveLength(1);
  });

  test("an unban gives the account back, but the relationship stays ended", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const couple = await createCouple(t);
    await admin.as.mutation(api.admin.ban_user, { p_user_id: couple.first.userId, p_reason: "mistake" });

    expect(await admin.as.mutation(api.admin.unban_user, { p_user_id: couple.first.userId })).toEqual({ changed: true });

    const [snapshot] = await couple.first.as.query(api.access.get_access_snapshot, {});
    expect(snapshot.account_status).toBe("active");
    expect(snapshot.relationship_state).toMatchObject({ relationship_status: "ended" });
    const log = await admin.as.query(api.admin.get_audit_log, {});
    expect(log.map((entry) => entry.action)).toEqual(["user_unbanned", "user_banned"]);
  });

  test("admins can't ban themselves or another admin, and a reason is required", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const otherAdmin = await createSignedInUser(t, { subject: "user_other_admin" });
    const user = await createSignedInUser(t);

    await expectFail(admin.as.mutation(api.admin.ban_user, { p_user_id: admin.userId, p_reason: "x" }), "42501", "yourself");
    await expectFail(
      admin.as.mutation(api.admin.ban_user, { p_user_id: otherAdmin.userId, p_reason: "x" }),
      "42501",
      "admins can't be banned",
    );
    await expectFail(admin.as.mutation(api.admin.ban_user, { p_user_id: user.userId, p_reason: "   " }), "23514");
    await expectFail(
      t.mutation(internal.admin.operator_ban_user, { p_user_id: otherAdmin.userId, p_reason: "x", p_operator: "cli" }),
      "42501",
    );
  });

  test("an operator command bans and unbans with the same rules and logs the operator", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const user = await createSignedInUser(t);

    await t.mutation(internal.admin.operator_ban_user, { p_user_id: user.userId, p_reason: "spam", p_operator: "hjalmar" });
    expect((await user.as.query(api.access.get_access_snapshot, {}))[0].account_status).toBe("banned");
    await t.mutation(internal.admin.operator_unban_user, { p_user_id: user.userId, p_operator: "hjalmar" });
    expect((await user.as.query(api.access.get_access_snapshot, {}))[0].account_status).toBe("active");

    const log = await admin.as.query(api.admin.get_audit_log, {});
    expect(log).toEqual([
      expect.objectContaining({ action: "user_unbanned", admin_user_id: null, operator_identifier: "hjalmar" }),
      expect.objectContaining({ action: "user_banned", admin_user_id: null, operator_identifier: "hjalmar" }),
    ]);
  });

  test("a banned person can still delete their account", async () => {
    const t = newTest();
    const admin = await createAdmin(t);
    const user = await createSignedInUser(t);
    await admin.as.mutation(api.admin.ban_user, { p_user_id: user.userId, p_reason: "spam" });

    const rows = await user.as.mutation(api.identity.request_account_deletion, {});
    expect(rows).toHaveLength(1);
  });
});
