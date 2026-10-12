import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { sha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { hashPairingInviteCode } from "./pairing";
import { createCouple, createSignedInUser, grantLifetime, newTest, relationshipStateOf, type TestConvex, type TestUser } from "./test.setup";

const NOW = "2026-10-10T12:00:00.000Z";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(NOW));
  process.env.INVITE_CODE_PEPPER = "test-pepper-value-for-pairing-invite-hashes";
});
afterEach(() => {
  vi.useRealTimers();
  delete process.env.INVITE_CODE_PEPPER;
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
const operation = (clientId = newUuid()) => ({
  p_client_operation_id: newUuid(),
  p_client_id: clientId,
  p_client_sequence: ++sequence,
  p_local_created_at: NOW,
});
const inDays = (days: number) => new Date(Date.parse(NOW) + days * 86_400_000).toISOString();

async function inviter(t: TestConvex, name = "Inviter"): Promise<TestUser> {
  const user = await createSignedInUser(t, { name });
  await grantLifetime(t, user.userId);
  return user;
}

async function createInvite(user: TestUser, code = "ABC123", expiresAt = inDays(7)) {
  return await user.as.mutation(api.pairing.create_pairing_invite, {
    p_invite_code: code,
    ...operation(),
    p_expires_at: expiresAt,
  });
}

describe("invite code hash", () => {
  test("accepts only six characters from the invite alphabet and hashes with the pepper", async () => {
    const hash = await hashPairingInviteCode("ABC123");
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(await hashPairingInviteCode("ABC123")).toBe(hash);
    expect(await hashPairingInviteCode("ABC124")).not.toBe(hash);
    for (const bad of ["abc123", "ABC12", "ABC1234", "ABCDEI", "ABCDEL", "ABCDEO", "ABCDEU", "", null]) {
      await expect(hashPairingInviteCode(bad)).rejects.toMatchObject({ data: { code: "23514", message: "invalid invite code" } });
    }
    process.env.INVITE_CODE_PEPPER = "";
    await expect(hashPairingInviteCode("ABC123")).rejects.toMatchObject({ data: { code: "22023" } });
  });
});

describe("create_pairing_invite", () => {
  test("stores the invite with a hashed code and replays by operation id", async () => {
    const t = newTest();
    const user = await inviter(t);
    const op = operation();
    const args = { p_invite_code: "ABC123", ...op, p_expires_at: inDays(7) };
    const id = await user.as.mutation(api.pairing.create_pairing_invite, args);
    expect(await user.as.mutation(api.pairing.create_pairing_invite, args)).toBe(id);
    const rows = await t.run(async (ctx) => ({
      invites: await ctx.db.query("pairing_invites").collect(),
      secrets: await ctx.db.query("pairing_invite_secrets").collect(),
    }));
    expect(rows.invites).toHaveLength(1);
    expect(rows.invites[0]).toMatchObject({ id, created_by_user_id: user.userId, status: "pending", expires_at: inDays(7) });
    expect(rows.secrets).toEqual([expect.objectContaining({ invite_id: id, code_hash: await hashPairingInviteCode("ABC123") })]);
    expect(JSON.stringify(rows)).not.toContain("ABC123");
  });

  test("a missing expiry defaults to seven days and survives a retry", async () => {
    const t = newTest();
    const user = await inviter(t);
    const args = { p_invite_code: "ABC123", ...operation() };
    const id = await user.as.mutation(api.pairing.create_pairing_invite, args);
    vi.setSystemTime(new Date("2026-10-10T12:00:05.000Z"));
    expect(await user.as.mutation(api.pairing.create_pairing_invite, args)).toBe(id);
    const invite = await t.run((ctx) => ctx.db.query("pairing_invites").first());
    expect(invite?.expires_at).toBe(inDays(7));
  });

  test("rejects out of range expiry, bad codes, missing entitlement, and users who are already paired", async () => {
    const t = newTest();
    const user = await inviter(t);
    await expectFail(createInvite(user, "ABC123", NOW), "23514", "invite expiration is out of range");
    await expectFail(createInvite(user, "ABC123", inDays(31)), "23514", "invite expiration is out of range");
    await expectFail(createInvite(user, "abc123"), "23514", "invalid invite code");

    const unentitled = await createSignedInUser(t, {});
    await expectFail(createInvite(unentitled), "42501", "direct entitlement is required to create an invite");
    await expectFail(
      t.mutation(api.pairing.create_pairing_invite, { p_invite_code: "ABC123", ...operation() }),
      "42501",
      "authenticated user required",
    );

    const couple = await createCouple(t);
    await expectFail(createInvite(couple.first), "23505", "user already has an active couple");
  });

  test("a code collision names the unique constraint the app matches on", async () => {
    const t = newTest();
    const first = await inviter(t, "First");
    const second = await inviter(t, "Second");
    await createInvite(first, "K7M2PQ");
    const error = await createInvite(second, "K7M2PQ").then(
      () => null,
      (caught) => caught,
    );
    expect(error?.data.code).toBe("23505");
    expect(String(error)).toContain("pairing_invite_secrets_code_hash_unique");
    expect(await t.run((ctx) => ctx.db.query("pairing_invites").collect())).toHaveLength(1);
  });
});

describe("preview_pairing_invite", () => {
  test("shows the inviter to another user and logs the attempt", async () => {
    const t = newTest();
    const owner = await inviter(t, "Ada");
    const id = await createInvite(owner);
    const guest = await createSignedInUser(t, {});
    const rows = await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ABC123" });
    expect(rows).toEqual([
      {
        invite_id: id,
        inviter_user_id: owner.userId,
        inviter_display_name: "Ada",
        expires_at: inDays(7),
        has_safety_warning: false,
      },
    ]);
    const attempts = await t.run((ctx) => ctx.db.query("pairing_invite_attempts").collect());
    expect(attempts).toEqual([expect.objectContaining({ user_id: guest.userId, success: true, matched_invite_id: id })]);
    expect(attempts[0].code_hash_prefix).toBe((await hashPairingInviteCode("ABC123")).slice(0, 12));
  });

  test("hides unknown, expired, revoked, and blocked invites and a hidden inviter name", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const id = await createInvite(owner);
    const guest = await createSignedInUser(t, {});

    expect(await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ZZZZZZ" })).toEqual([]);
    const failed = await t.run((ctx) => ctx.db.query("pairing_invite_attempts").collect());
    expect(failed[0]).toMatchObject({ success: false, failure_reason: "not_found" });

    await t.run(async (ctx) => {
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_user_id", (q) => q.eq("user_id", owner.userId))
        .unique();
      await ctx.db.patch(profile!._id, { moderation_status: "hidden" });
    });
    const hidden = await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ABC123" });
    expect(hidden[0].inviter_display_name).toBeNull();

    // An active block between the two hides the invite.
    await t.run(async (ctx) => {
      const [low, high] = owner.userId < guest.userId ? [owner.userId, guest.userId] : [guest.userId, owner.userId];
      const pairId = newUuid();
      await ctx.db.insert("relationship_pairs", { id: pairId, user_low_id: low, user_high_id: high, created_at: NOW });
      await ctx.db.insert("relationship_blocks", {
        id: newUuid(),
        pair_id: pairId,
        blocked_by_user_id: guest.userId,
        blocked_user_id: owner.userId,
        created_at: NOW,
      });
    });
    expect(await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ABC123" })).toEqual([]);

    await owner.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: id });
    expect(await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ABC123" })).toEqual([]);
  });

  test("warns when the pair has a safety flag", async () => {
    const t = newTest();
    const owner = await inviter(t);
    await createInvite(owner);
    const guest = await createSignedInUser(t, {});
    await t.run(async (ctx) => {
      const [low, high] = owner.userId < guest.userId ? [owner.userId, guest.userId] : [guest.userId, owner.userId];
      const pairId = newUuid();
      await ctx.db.insert("relationship_pairs", { id: pairId, user_low_id: low, user_high_id: high, created_at: NOW });
      await ctx.db.insert("pair_safety_warning_flags", { id: newUuid(), pair_id: pairId, source_report_id: newUuid(), created_at: NOW });
    });
    const rows = await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ABC123" });
    expect(rows[0].has_safety_warning).toBe(true);
  });

  test("throttles a user after thirty attempts and ten misses on one code", async () => {
    const t = newTest();
    const guest = await createSignedInUser(t, {});
    for (let attempt = 0; attempt < 10; attempt += 1) {
      expect(await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ZZZZZZ" })).toEqual([]);
    }
    await expectFail(guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "ZZZZZZ" }), "53300", "too many invite attempts for this code");
    // Different codes keep counting against the per-user budget.
    await t.run(async (ctx) => {
      for (let index = 0; index < 30; index += 1) {
        await ctx.db.insert("pairing_invite_attempts", {
          id: newUuid(),
          code_hash_prefix: `p${index}`,
          user_id: guest.userId,
          success: true,
          attempted_at: NOW,
        });
      }
    });
    await expectFail(guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "WWWWWW" }), "53300", "too many invite attempts");
    // The window is ten minutes.
    vi.setSystemTime(new Date("2026-10-10T12:11:00.000Z"));
    expect(await guest.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "WWWWWW" })).toEqual([]);
  });

  test("an App Review demo code returns the seeded partner", async () => {
    const t = newTest();
    const partner = await createSignedInUser(t, { name: "Demo Partner" });
    const reviewer = await createSignedInUser(t, {});
    const codeId = newUuid();
    await t.run(async (ctx) => {
      await ctx.db.insert("review_access_codes", {
        id: codeId,
        code_hash: await sha256Hex("REVIEW-CODE"),
        seeded_partner_user_id: partner.userId,
        scenario: "pre_paired_entitled",
        status: "active",
        max_redemptions: 5,
        redemption_count: 0,
        created_at: NOW,
      });
    });
    const rows = await reviewer.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: "REVIEW-CODE" });
    expect(rows).toEqual([
      {
        invite_id: codeId,
        inviter_user_id: partner.userId,
        inviter_display_name: "Demo Partner",
        expires_at: inDays(1),
        has_safety_warning: false,
      },
    ]);
  });
});

describe("accept_pairing_invite", () => {
  test("creates the couple, both members, an accepted invite, and refresh events", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const guest = await createSignedInUser(t, {});
    const inviteId = await createInvite(owner);
    const op = operation();
    const coupleId = await guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...op, p_started_on: "2024-02-29" });
    expect(await guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...op, p_started_on: "2024-02-29" })).toBe(coupleId);

    const rows = await t.run(async (ctx) => ({
      couples: await ctx.db.query("couples").collect(),
      members: await ctx.db.query("couple_members").collect(),
      invite: await ctx.db.query("pairing_invites").first(),
      pairs: await ctx.db.query("relationship_pairs").collect(),
      events: await ctx.db.query("relationship_sync_events").collect(),
      attempts: await ctx.db.query("pairing_invite_attempts").collect(),
    }));
    expect(rows.couples).toHaveLength(1);
    expect(rows.couples[0]).toMatchObject({ id: coupleId, status: "active", started_on: "2024-02-29", created_by_user_id: owner.userId });
    expect(rows.pairs).toHaveLength(1);
    expect(rows.members.map((member) => [member.user_id, member.role, member.status]).sort()).toEqual(
      [
        [owner.userId, "creator", "active"],
        [guest.userId, "partner", "active"],
      ].sort(),
    );
    expect(rows.invite).toMatchObject({ id: inviteId, status: "accepted", accepted_by_user_id: guest.userId, couple_id: coupleId });
    expect(rows.events).toHaveLength(2);
    expect(rows.events[0]).toMatchObject({
      event_kind: "relationship_started",
      reason: "pairing_invite_accepted",
      initiated_by_user_id: guest.userId,
      local_purge_scope: { relationship: "refresh", entitlement: "refresh" },
    });
    expect(rows.attempts).toEqual([expect.objectContaining({ success: true, matched_invite_id: inviteId })]);

    const state = await relationshipStateOf(guest);
    expect(state).toMatchObject({ couple_id: coupleId, partner_user_id: owner.userId, started_on: "2024-02-29" });
  });

  test("the started date defaults to unset", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const guest = await createSignedInUser(t, {});
    await createInvite(owner);
    await guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() });
    expect((await t.run((ctx) => ctx.db.query("couples").first()))?.started_on).toBeUndefined();
  });

  test("rejects unknown codes, your own invite, closed invites, and expired invites", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const guest = await createSignedInUser(t, {});
    const inviteId = await createInvite(owner);
    const accept = (user: TestUser, code = "ABC123") =>
      user.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: code, ...operation() });

    await expectFail(accept(guest, "ZZZZZZ"), "22023", "pairing invite is not available");
    await expectFail(accept(owner), "23514", "users cannot accept their own invite");
    await expectFail(accept(guest, "bad"), "23514", "invalid invite code");
    await expectFail(
      t.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() }),
      "42501",
      "authenticated user required",
    );

    vi.setSystemTime(new Date(inDays(8)));
    await expectFail(accept(guest), "22023", "pairing invite is expired");
    vi.setSystemTime(new Date(NOW));

    await owner.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: inviteId });
    await expectFail(accept(guest), "22023", "pairing invite is not pending");
    expect(await t.run((ctx) => ctx.db.query("couples").collect())).toHaveLength(0);
  });

  test("rejects when either user already has an active couple", async () => {
    const t = newTest();
    const owner = await inviter(t);
    await createInvite(owner);
    const paired = await createCouple(t, { entitled: false });
    await expectFail(
      paired.first.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() }),
      "23505",
      "one of the users already has an active couple",
    );

    // The inviter paired with someone else after creating the invite.
    const t2 = newTest();
    const second = await createCouple(t2);
    const guest = await createSignedInUser(t2, {});
    await t2.run(async (ctx) => {
      const invite = {
        id: newUuid(),
        created_by_user_id: second.first.userId,
        status: "pending" as const,
        expires_at: inDays(3),
        created_at: NOW,
        updated_at: NOW,
      };
      await ctx.db.insert("pairing_invites", invite);
      await ctx.db.insert("pairing_invite_secrets", { invite_id: invite.id, code_hash: await hashPairingInviteCode("MMMMMM"), created_at: NOW });
    });
    await expectFail(
      guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "MMMMMM", ...operation() }),
      "23505",
      "one of the users already has an active couple",
    );
  });

  test("refuses to pair a blocked pair, and works again after the block is lifted", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const guest = await createSignedInUser(t, {});
    await createInvite(owner);
    await t.run(async (ctx) => {
      const [low, high] = owner.userId < guest.userId ? [owner.userId, guest.userId] : [guest.userId, owner.userId];
      const pairId = newUuid();
      await ctx.db.insert("relationship_pairs", { id: pairId, user_low_id: low, user_high_id: high, created_at: NOW });
      await ctx.db.insert("relationship_blocks", {
        id: newUuid(),
        pair_id: pairId,
        blocked_by_user_id: owner.userId,
        blocked_user_id: guest.userId,
        created_at: NOW,
      });
    });
    await expectFail(
      guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() }),
      "42501",
      "pairing is blocked for this pair",
    );
    await t.run(async (ctx) => {
      const block = (await ctx.db.query("relationship_blocks").first())!;
      await ctx.db.patch(block._id, { revoked_at: NOW, revoked_by_user_id: owner.userId, revoke_reason: "user_unblocked" });
    });
    const coupleId = await guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() });
    expect(coupleId).toBeDefined();
  });

  test("an accepted invite cannot be used a second time", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const guest = await createSignedInUser(t, {});
    const other = await createSignedInUser(t, {});
    await createInvite(owner);
    await guest.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() });
    await expectFail(
      other.as.mutation(api.pairing.accept_pairing_invite, { p_invite_code: "ABC123", ...operation() }),
      "22023",
      "pairing invite is not pending",
    );
  });
});

describe("revoke, validate, and rotate", () => {
  test("revoke_pairing_invite only revokes the caller's pending invites", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const other = await createSignedInUser(t, {});
    const id = await createInvite(owner);
    expect(await other.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: id })).toBe(false);
    expect(await owner.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: newUuid() })).toBe(false);
    expect(await owner.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: id.toUpperCase() })).toBe(true);
    expect(await owner.as.mutation(api.pairing.revoke_pairing_invite, { p_invite_id: id })).toBe(false);
    expect(await t.run((ctx) => ctx.db.query("pairing_invites").first())).toMatchObject({ status: "revoked", revoked_at: NOW });
  });

  test("validate_my_pairing_invite reports the status and expires stale invites", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const other = await createSignedInUser(t, {});
    const id = await createInvite(owner);
    const notFound = [{ invite_id: null, status: "not_found", expires_at: null }];

    expect(await owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "ABC123" })).toEqual([
      { invite_id: id, status: "pending", expires_at: inDays(7) },
    ]);
    expect(await other.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "ABC123" })).toEqual(notFound);
    expect(await owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "ZZZZZZ" })).toEqual(notFound);
    expect(await owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: null, p_invite_code: "ABC123" })).toEqual(notFound);
    expect(await owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "  " })).toEqual(notFound);
    await expectFail(owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "bad" }), "23514");

    vi.setSystemTime(new Date(inDays(8)));
    expect(await owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "ABC123" })).toEqual([
      { invite_id: id, status: "expired", expires_at: inDays(7) },
    ]);
    // The query does not write. The expiry cron persists the status.
    expect(await t.run((ctx) => ctx.db.query("pairing_invites").first())).toMatchObject({ status: "pending" });
    expect(await t.mutation(internal.pairing.expire_stale_pairing_invites, {})).toBe(1);
    expect(await t.run((ctx) => ctx.db.query("pairing_invites").first())).toMatchObject({ status: "expired" });
    expect(await owner.as.query(api.pairing.validate_my_pairing_invite, { p_invite_id: id, p_invite_code: "ABC123" })).toEqual([
      { invite_id: id, status: "expired", expires_at: inDays(7) },
    ]);
  });

  test("rotate_pairing_invite issues a new invite and revokes the old one", async () => {
    const t = newTest();
    const owner = await inviter(t);
    const other = await inviter(t, "Other");
    const oldId = await createInvite(owner);
    const op = operation();
    const args = { p_current_invite_id: oldId, p_invite_code: "K7M2PQ", ...op, p_expires_at: inDays(5) };
    const newId = await owner.as.mutation(api.pairing.rotate_pairing_invite, args);
    expect(newId).not.toBe(oldId);
    expect(await owner.as.mutation(api.pairing.rotate_pairing_invite, args)).toBe(newId);

    const invites = await t.run((ctx) => ctx.db.query("pairing_invites").collect());
    const byId = Object.fromEntries(invites.map((invite) => [invite.id, invite]));
    expect(byId[oldId]).toMatchObject({ status: "revoked", revoked_at: NOW });
    expect(byId[newId]).toMatchObject({ status: "pending", expires_at: inDays(5) });

    await expectFail(
      other.as.mutation(api.pairing.rotate_pairing_invite, { p_current_invite_id: newId, p_invite_code: "N9N9N9", ...operation(), p_expires_at: inDays(5) }),
      "22023",
      "current invite is not available",
    );
    await expectFail(
      owner.as.mutation(api.pairing.rotate_pairing_invite, { p_current_invite_id: null, p_invite_code: "N9N9N9", ...operation() }),
      "23514",
      "current invite id is required",
    );
    await expectFail(
      owner.as.mutation(api.pairing.rotate_pairing_invite, { p_current_invite_id: newId, p_invite_code: "K7M2PQ", ...operation(), p_expires_at: inDays(5) }),
      "23505",
      "pairing_invite_secrets_code_hash_unique",
    );
  });
});

describe("cleanup", () => {
  test("expire_stale_pairing_invites expires only pending invites past their expiry", async () => {
    const t = newTest();
    const owner = await inviter(t);
    await createInvite(owner, "ABC123", inDays(1));
    expect(await t.mutation(internal.pairing.expire_stale_pairing_invites, {})).toBe(0);
    expect(await t.mutation(internal.pairing.expire_stale_pairing_invites, { p_now: inDays(2) })).toBe(1);
    expect(await t.mutation(internal.pairing.expire_stale_pairing_invites, { p_now: inDays(2) })).toBe(0);
    expect((await t.run((ctx) => ctx.db.query("pairing_invites").first()))?.status).toBe("expired");
    await expectFail(t.mutation(internal.pairing.expire_stale_pairing_invites, { p_limit: 0 }), "23514", "expiry limit is out of range");
  });

  test("cleanup_attempt_logs deletes the old pairing and review attempts first", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    await t.run(async (ctx) => {
      for (const attemptedAt of [inDays(-40), inDays(-31), inDays(-1)]) {
        await ctx.db.insert("pairing_invite_attempts", {
          id: newUuid(),
          code_hash_prefix: "abc",
          user_id: user.userId,
          success: false,
          attempted_at: attemptedAt,
        });
      }
      await ctx.db.insert("review_access_attempts", {
        id: newUuid(),
        user_id: user.userId,
        code_hash_prefix: "abc",
        success: false,
        attempted_at: inDays(-45),
      });
    });
    const limited = await t.mutation(internal.pairing.cleanup_attempt_logs, { p_limit: 1 });
    expect(limited).toEqual({ pairing_attempts_deleted: 1, review_attempts_deleted: 1 });
    const rest = await t.mutation(internal.pairing.cleanup_attempt_logs, {});
    expect(rest).toEqual({ pairing_attempts_deleted: 1, review_attempts_deleted: 0 });
    expect(await t.run((ctx) => ctx.db.query("pairing_invite_attempts").collect())).toHaveLength(1);
    await expectFail(t.mutation(internal.pairing.cleanup_attempt_logs, { p_limit: 0 }), "23514");
  });
});
