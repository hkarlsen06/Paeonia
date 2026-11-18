import type { FunctionReturnType } from "convex/server";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { cleanupCoupleContent } from "./lib/relationshipCleanup";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { failure, setMediaEnv, uploadAsset } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createSignedInUser, grantLifetime, newTest, relationshipStateOf, type TestConvex, type TestUser } from "./test.setup";

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

let sequence = 0;
const operation = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: newUuid(),
  p_client_sequence: ++sequence,
  p_local_created_at: NOW,
});
const inDays = (days: number) => new Date(Date.now() + days * 86_400_000).toISOString();

async function invite(user: TestUser, code: string) {
  return await user.as.mutation(api.pairing.create_pairing_invite, { p_invite_code: code, ...operation(), p_expires_at: inDays(7) });
}

async function join(user: TestUser, code: string, restore?: boolean) {
  return await user.as.mutation(api.pairing.accept_pairing_invite, {
    p_invite_code: code,
    ...operation(),
    ...(restore === undefined ? {} : { p_restore: restore }),
  });
}

async function answer(user: TestUser, inviteId: string, requester: TestUser, restore: boolean) {
  return await user.as.mutation(api.pairing.answer_relationship_restore, {
    p_invite_id: inviteId,
    p_requester_user_id: requester.userId,
    p_restore: restore,
    ...operation(),
  });
}

async function preview(user: TestUser, code: string) {
  const [row] = await user.as.mutation(api.pairing.preview_pairing_invite, { p_invite_code: code });
  return row;
}

async function memoryTitles(user: TestUser) {
  const rows = await user.as.query(api.memories.get_memories, {});
  return rows.map((row) => row.title);
}

/**
 * Alex invites Robin, they pair, write a memory, set a nickname and send hearts, and Alex leaves.
 * Alex then shares a new code.
 */
async function leftCouple(t: TestConvex) {
  const alex = await createSignedInUser(t, { name: "Alex" });
  await grantLifetime(t, alex.userId);
  const robin = await createSignedInUser(t, { name: "Robin" });
  await invite(alex, "ABC123");
  const coupleId = (await join(robin, "ABC123"))!;
  await robin.as.mutation(api.memories.create_memory, {
    p_memory_id: newUuid(),
    p_title: "Lake day",
    p_memory_date: "2026-10-01",
    p_note_body: "We swam until sunset.",
    p_media_asset_ids: null,
    ...operation(),
  });
  await alex.as.mutation(api.partnerNickname.set_partner_nickname, { p_nickname: "Bean" });
  await alex.as.mutation(api.hearts.send_hearts, { p_count: 3, ...operation() });
  expect(await t.run((ctx) => ctx.db.query("couple_hearts").collect())).not.toEqual([]);
  await alex.as.mutation(api.relationship.leave_relationship, operation());
  vi.setSystemTime(new Date(Date.parse(NOW) + 86_400_000));
  const inviteId = await invite(alex, "DEF456");
  return { alex, robin, coupleId, inviteId };
}

async function restoreRequestOf(user: TestUser) {
  return (await user.as.query(api.access.get_access_snapshot, {}))[0].restore_request;
}

type SyncEvents = FunctionReturnType<typeof api.relationship.get_relationship_sync_events>;

/** Every relationship event of `user`, read the way the app pages through them. */
async function pagedEvents(user: TestUser, limit: number) {
  const all: SyncEvents = [];
  let after: { created_at: string; id: string } | null = null;
  for (;;) {
    const page: SyncEvents = await user.as.query(api.relationship.get_relationship_sync_events, {
      p_limit: limit,
      p_after_created_at: after?.created_at ?? null,
      p_after_id: after?.id ?? null,
    });
    if (page.length === 0) return all;
    all.push(...page);
    after = page[page.length - 1];
  }
}

async function coupleRow(t: TestConvex, coupleId: string) {
  return await t.run((ctx) => ctx.db.query("couples").withIndex("by_uuid", (q) => q.eq("id", coupleId)).unique());
}

describe("bringing an ended relationship back", () => {
  test("opens the old couple only after both said yes, with what was hidden and without what was deleted", async () => {
    const t = newTest();
    const { alex, robin, coupleId, inviteId } = await leftCouple(t);
    await addDevice(t, alex.userId);

    expect(await preview(robin, "DEF456")).toMatchObject({ can_restore: true, restore_requested: false });
    expect(await join(robin, "DEF456", true)).toBeNull();
    expect(await preview(robin, "DEF456")).toMatchObject({ can_restore: true, restore_requested: true });

    // Robin's yes alone opens nothing.
    expect((await coupleRow(t, coupleId))?.status).toBe("ended");
    await expect(memoryTitles(robin)).rejects.toThrow();
    const [snapshot] = await alex.as.query(api.access.get_access_snapshot, {});
    expect(snapshot.restore_request).toEqual({
      invite_id: inviteId,
      partner_user_id: robin.userId,
      partner_name: "Robin",
      partner_profile_photo_asset_id: null,
      requested_at: expect.any(String),
    });
    const asked = await t.run((ctx) =>
      ctx.db
        .query("notification_outbox")
        .withIndex("by_recipient_user_id_created_at", (q) => q.eq("recipient_user_id", alex.userId))
        .collect(),
    );
    expect(asked.filter((row) => row.kind === "relationship_restore").map((row) => row.payload.step)).toEqual(["requested"]);

    expect(await answer(alex, inviteId, robin, true)).toEqual({ couple_id: coupleId, restored: true });

    expect(await coupleRow(t, coupleId)).toMatchObject({ status: "active" });
    expect((await coupleRow(t, coupleId))?.delete_after).toBeUndefined();
    expect(await memoryTitles(robin)).toEqual(["Lake day"]);
    expect(await memoryTitles(alex)).toEqual(["Lake day"]);
    for (const user of [alex, robin]) {
      expect(await relationshipStateOf(user)).toMatchObject({
        couple_id: coupleId,
        relationship_status: "active",
        member_status: "active",
        partner_nickname: null,
      });
    }
    const left = await t.run(async (ctx) => ({
      hearts: await ctx.db.query("couple_hearts").collect(),
      events: await ctx.db
        .query("relationship_sync_events")
        .withIndex("by_couple_id_created_at_id", (q) => q.eq("couple_id", coupleId))
        .collect(),
    }));
    expect(left.hearts).toEqual([]);
    expect(left.events.filter((event) => event.reason === "relationship_restored")).toHaveLength(2);
    expect((await alex.as.query(api.access.get_access_snapshot, {}))[0].restore_request).toBeNull();

    // Neither the cleanup nor the purge touches the couple after its old deadline.
    expect(
      await t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" }),
    ).toEqual([]);
    expect(await memoryTitles(robin)).toEqual(["Lake day"]);

    // A retry of the answer returns the same result.
    expect(await answer(alex, inviteId, robin, true))
      .toEqual({ couple_id: coupleId, restored: true });
  });

  test("a start fresh from the inviter pairs the two in a new, empty couple", async () => {
    const t = newTest();
    const { alex, robin, coupleId, inviteId } = await leftCouple(t);
    await join(robin, "DEF456", true);
    const result = await answer(alex, inviteId, robin, false);
    expect(result.restored).toBe(false);
    expect(result.couple_id).not.toBe(coupleId);
    expect(await memoryTitles(robin)).toEqual([]);
    expect((await coupleRow(t, coupleId))?.status).toBe("ended");
  });

  test("a start fresh from the joiner while waiting pairs them new, and a late yes from the inviter gets that couple", async () => {
    const t = newTest();
    const { alex, robin, coupleId, inviteId } = await leftCouple(t);
    await join(robin, "DEF456", true);
    const fresh = await join(robin, "DEF456");
    expect(fresh).not.toBe(coupleId);
    expect(await answer(alex, inviteId, robin, true)).toEqual({ couple_id: fresh, restored: false });
    // Robin's start fresh after Alex brought it back finds the old couple instead of an error.
    expect(await join(robin, "DEF456")).toBe(fresh);
  });

  test("someone outside the couple can't answer, and their own use of the code pairs them new", async () => {
    const t = newTest();
    const { alex, robin, inviteId } = await leftCouple(t);
    await join(robin, "DEF456", true);
    const stranger = await createSignedInUser(t, { name: "Sam" });
    await expect(answer(stranger, inviteId, robin, true)).rejects.toMatchObject({ data: { code: "22023" } });
    await expect(answer(robin, inviteId, robin, true)).rejects.toMatchObject({ data: { code: "22023" } });
    expect((await alex.as.query(api.access.get_access_snapshot, {}))[0].restore_request?.partner_user_id).toBe(robin.userId);

    const other = await createSignedInUser(t, { name: "Kim" });
    const owner = await createSignedInUser(t, { name: "Lee" });
    await grantLifetime(t, owner.userId);
    await invite(owner, "GHJ789");
    expect(await preview(other, "GHJ789")).toMatchObject({ can_restore: false });
    expect(await join(other, "GHJ789", true)).toEqual(expect.any(String));
  });

  test("a report or a safety warning in the pair means a quiet fresh start", async () => {
    for (const table of ["content_reports", "pair_safety_warning_flags"] as const) {
      const t = newTest();
      const { alex, robin, coupleId } = await leftCouple(t);
      const pairId = (await coupleRow(t, coupleId))!.pair_id;
      await t.run(async (ctx) => {
        if (table === "content_reports") {
          await ctx.db.insert("content_reports", {
            id: newUuid(),
            reporter_user_id: robin.userId,
            reported_user_id: alex.userId,
            couple_id: coupleId,
            pair_id: pairId,
            reason: "harassment",
            status: "rejected",
            block_requested: false,
            leave_requested: false,
            created_at: NOW,
            updated_at: NOW,
          });
        } else {
          await ctx.db.insert("pair_safety_warning_flags", { id: newUuid(), pair_id: pairId, created_at: NOW });
        }
      });
      expect(await preview(robin, "DEF456")).toMatchObject({ can_restore: false, restore_requested: false });
      const joined = await join(robin, "DEF456", true);
      expect(joined).not.toBeNull();
      expect(joined).not.toBe(coupleId);
      expect((await alex.as.query(api.access.get_access_snapshot, {}))[0].restore_request).toBeNull();
    }
  });

  test("a blocked pair sees no invite at all", async () => {
    const t = newTest();
    const { alex, robin, coupleId } = await leftCouple(t);
    const pairId = (await coupleRow(t, coupleId))!.pair_id;
    await t.run((ctx) =>
      ctx.db.insert("relationship_blocks", {
        id: newUuid(),
        pair_id: pairId,
        blocked_by_user_id: alex.userId,
        blocked_user_id: robin.userId,
        created_at: NOW,
      }),
    );
    expect(await preview(robin, "DEF456")).toBeUndefined();
    await expect(join(robin, "DEF456", true)).rejects.toMatchObject({ data: { code: "42501" } });
  });

  test("a couple past its cleanup deadline, or ended by account deletion, can't come back", async () => {
    const t = newTest();
    const { alex, robin } = await leftCouple(t);
    vi.setSystemTime(new Date(Date.parse(NOW) + 31 * 86_400_000));
    await invite(alex, "KMN234");
    expect(await preview(robin, "KMN234")).toMatchObject({ can_restore: false });

    const t2 = newTest();
    const deleting = await createSignedInUser(t2, { name: "Dana" });
    await grantLifetime(t2, deleting.userId);
    const partner = await createSignedInUser(t2, { name: "Pat" });
    await invite(deleting, "ABC123");
    const coupleId = (await join(partner, "ABC123"))!;
    const pairId = (await coupleRow(t2, coupleId))!.pair_id;
    await t2.run((ctx) => endRelationshipForPair(ctx, pairId, deleting.userId, "account_deletion"));
    await grantLifetime(t2, partner.userId);
    await invite(partner, "PQR567");
    expect(await preview(deleting, "PQR567")).toMatchObject({ can_restore: false });
  });

  test("a member whose account deletion started can't bring it back, and a request from them lapses", async () => {
    const t = newTest();
    const { alex, robin, coupleId, inviteId } = await leftCouple(t);
    await join(robin, "DEF456", true);
    await t.run((ctx) =>
      ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: robin.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        created_at: NOW,
        updated_at: NOW,
      }),
    );
    expect(await answer(alex, inviteId, robin, true)).toEqual({ couple_id: null, restored: false });
    expect((await coupleRow(t, coupleId))?.status).toBe("ended");
    expect((await alex.as.query(api.access.get_access_snapshot, {}))[0].restore_request).toBeNull();
  });

  test("the answer is about the person the inviter saw, and nobody else can use the invite while that request stands", async () => {
    const t = newTest();
    // Alex left Robin, then paired with Sam and left Sam too. Both couples can still come back.
    const { alex, robin, coupleId: robinCouple } = await leftCouple(t);
    const sam = await createSignedInUser(t, { name: "Sam" });
    await invite(alex, "GHJ789");
    const samCouple = (await join(sam, "GHJ789"))!;
    await alex.as.mutation(api.relationship.leave_relationship, operation());
    vi.setSystemTime(new Date(Date.now() + 60_000));
    const inviteId = await invite(alex, "KMN234");
    expect(await preview(sam, "KMN234")).toMatchObject({ can_restore: true });

    expect(await join(robin, "KMN234", true)).toBeNull();
    expect(await preview(sam, "KMN234")).toBeUndefined();
    await expect(join(sam, "KMN234", true)).rejects.toMatchObject({ data: { code: "22023" } });
    await expect(join(sam, "KMN234")).rejects.toMatchObject({ data: { code: "22023" } });
    expect((await restoreRequestOf(alex))?.partner_user_id).toBe(robin.userId);

    // Had Sam's request replaced Robin's, Alex's yes on Robin's request would not bring Sam back.
    const setRequester = (userId: string) =>
      t.run(async (ctx) => {
        const row = (await ctx.db.query("pairing_invites").withIndex("by_uuid", (q) => q.eq("id", inviteId)).unique())!;
        await ctx.db.patch(row._id, { restore_requested_by_user_id: userId });
      });
    await setRequester(sam.userId);
    expect(await answer(alex, inviteId, robin, true)).toEqual({ couple_id: null, restored: false });
    expect((await coupleRow(t, samCouple))?.status).toBe("ended");
    expect((await restoreRequestOf(alex))?.partner_user_id).toBe(sam.userId);

    await setRequester(robin.userId);
    expect(await answer(alex, inviteId, robin, true)).toEqual({ couple_id: robinCouple, restored: true });
    expect((await coupleRow(t, samCouple))?.status).toBe("ended");
  });

  test("a report, block or ban after the request stops the question, its push and the answer", async () => {
    for (const change of ["report", "block", "ban"] as const) {
      const t = newTest();
      const { alex, robin, coupleId, inviteId } = await leftCouple(t);
      await addDevice(t, alex.userId);
      await join(robin, "DEF456", true);
      expect(await restoreRequestOf(alex)).not.toBeNull();

      if (change === "ban") {
        await t.run(async (ctx) => {
          const user = (await ctx.db.query("users").withIndex("by_uuid", (q) => q.eq("id", robin.userId)).unique())!;
          await ctx.db.patch(user._id, { banned_at: NOW });
        });
      } else {
        await robin.as.mutation(api.reports.submit_leave_and_report, {
          p_reason: "harassment",
          p_note: null,
          p_target_kind: "conduct",
          p_target_id: alex.userId,
          p_target_aux_id: null,
          p_block_reported_user: change === "block",
          ...operation(),
        });
      }

      expect(await restoreRequestOf(alex)).toBeNull();
      const sent = await deliverDuePushes(t);
      expect(sent.filter((push) => push.payload.type === "relationship_restore")).toEqual([]);
      expect(await answer(alex, inviteId, robin, true)).toEqual({ couple_id: null, restored: false });
      expect((await coupleRow(t, coupleId))?.status).toBe("ended");
    }
  });

  test("the person who answers sees the requester's photo while the request stands, and nobody else does", async () => {
    setMediaEnv();
    const t = newTest();
    const { alex, robin } = await leftCouple(t);
    const stranger = await createSignedInUser(t, { name: "Sam" });
    const photo = await uploadAsset(t, robin, {
      kind: "profile_photo",
      purpose: "profile_photo",
      mediaType: "image",
      extension: "jpg",
      mime: "image/jpeg",
      parentId: robin.userId,
    });
    await t.run(async (ctx) => {
      const profile = await ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", robin.userId)).unique();
      await ctx.db.patch(profile!._id, { profile_photo_asset_id: photo.assetId });
    });
    const read = (user: TestUser) => user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: photo.assetId });

    // Alex left, so the old couple no longer shows Robin's photo to Alex.
    expect(await failure(read(alex))).toMatchObject({ code: "42501" });

    await join(robin, "DEF456", true);
    expect((await restoreRequestOf(alex))?.partner_profile_photo_asset_id).toBe(photo.assetId);
    expect(await read(alex)).toHaveLength(1);
    expect(await failure(read(stranger))).toMatchObject({ code: "42501" });

    await robin.as.mutation(api.reports.submit_leave_and_report, {
      p_reason: "harassment",
      p_note: null,
      p_target_kind: "conduct",
      p_target_id: alex.userId,
      p_target_aux_id: null,
      p_block_reported_user: true,
      ...operation(),
    });
    expect(await restoreRequestOf(alex)).toBeNull();
    expect(await failure(read(alex))).toMatchObject({ code: "42501" });
  });

  test("a phone that missed the end of a couple that came back is never told to purge it, and a later end still reaches it", async () => {
    const t = newTest();
    const { alex, robin, coupleId, inviteId } = await leftCouple(t);
    await join(robin, "DEF456", true);
    await answer(alex, inviteId, robin, true);
    const kinds = async () =>
      (await pagedEvents(robin, 1)).filter((event) => event.couple_id === coupleId).map((event) => event.event_kind);

    expect(await kinds()).toEqual(["relationship_started", "relationship_started"]);

    vi.setSystemTime(new Date(Date.now() + 60_000));
    await alex.as.mutation(api.relationship.leave_relationship, operation());
    expect(await kinds()).toEqual(["relationship_started", "relationship_started", "relationship_ended"]);
  });

  test("a cleanup that started first wins: the answer pairs them new and the old couple stays as the cleanup left it", async () => {
    const t = newTest();
    const { alex, robin, coupleId, inviteId } = await leftCouple(t);
    await join(robin, "DEF456", true);
    // One chunk of a cleanup that ran out of budget part way.
    const done = await t.run(async (ctx) => {
      const couple = (await ctx.db.query("couples").withIndex("by_uuid", (q) => q.eq("id", coupleId)).unique())!;
      return (await cleanupCoupleContent(ctx, couple, NOW, { left: 0 })).done;
    });
    expect(done).toBe(false);

    const result = await answer(alex, inviteId, robin, true);
    expect(result.restored).toBe(false);
    expect(result.couple_id).not.toBe(coupleId);
    expect(await coupleRow(t, coupleId)).toMatchObject({ status: "ended", cleanup_started_at: expect.any(String) });
    expect(await memoryTitles(robin)).toEqual([]);
  });
});
