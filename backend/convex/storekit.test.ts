import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import crons from "./crons";
import { newUuid } from "./lib/ids";
import { seedProducts, storekitArgs } from "./storekit.testHelpers";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

const NOW = new Date("2026-10-10T12:00:00.000Z");
const hoursFromNow = (hours: number) => new Date(NOW.getTime() + hours * 3_600_000).toISOString();

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});
afterEach(() => {
  vi.useRealTimers();
});

async function tokenFor(user: TestUser): Promise<string> {
  return await user.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: user.userId });
}

async function transactions(t: TestConvex) {
  return await t.run((ctx) => ctx.db.query("storekit_transactions").collect());
}

describe("record_verified_storekit_transaction", () => {
  test("stores the payload and an active transaction that entitles the user", async () => {
    const t = newTest();
    await seedProducts(t);
    const user = await createSignedInUser(t);
    const token = await tokenFor(user);

    const result = await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, expiresAt: hoursFromNow(72) }),
    );

    expect(result).toMatchObject({ ok: true });
    const rows = await transactions(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      user_id: user.userId,
      app_account_token: token,
      status: "active",
      environment: "sandbox",
    });
    expect(result).toMatchObject({ productId: rows[0].product_id, transactionId: rows[0].id, payloadId: rows[0].raw_payload_id });

    const snapshot = await user.as.query(api.access.get_access_snapshot, {});
    expect(snapshot[0].user_entitlement).toMatchObject({ is_entitled: true, source: "storekit", status: "active" });
  });

  test("recording the same transaction again updates one row", async () => {
    const t = newTest();
    await seedProducts(t);
    const user = await createSignedInUser(t);
    const token = await tokenFor(user);

    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, expiresAt: hoursFromNow(72) }),
    );
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, status: "expired", expiresAt: hoursFromNow(-1) }),
    );

    const rows = await transactions(t);
    expect(rows).toHaveLength(1);
    expect(rows[0].status).toBe("expired");
    // Every call archives its own payload, like the SQL insert.
    expect(await t.run((ctx) => ctx.db.query("storekit_payloads").collect())).toHaveLength(2);
  });

  test("rejects a missing user, a missing token, and another user's token", async () => {
    const t = newTest();
    await seedProducts(t);
    const alice = await createSignedInUser(t);
    const bob = await createSignedInUser(t);
    const aliceToken = await tokenFor(alice);
    const record = (args: Parameters<typeof storekitArgs>[0]) =>
      t.mutation(internal.storekit.record_verified_storekit_transaction, storekitArgs(args));

    expect(await record({ userId: null, token: aliceToken })).toEqual({ ok: false, error: "Invalid user", status: 401 });
    expect(await record({ userId: alice.userId, token: null })).toEqual({
      ok: false,
      error: "Apple transaction is missing appAccountToken",
      status: 403,
    });
    expect(await record({ userId: bob.userId, token: aliceToken })).toEqual({
      ok: false,
      error: "Apple transaction belongs to a different user",
      status: 403,
    });
    expect(await transactions(t)).toHaveLength(0);
  });

  test("rejects a transaction id already owned by another user", async () => {
    const t = newTest();
    await seedProducts(t);
    const alice = await createSignedInUser(t);
    const bob = await createSignedInUser(t);
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: alice.userId, token: await tokenFor(alice), transactionId: "shared-1" }),
    );

    const result = await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: bob.userId, token: await tokenFor(bob), transactionId: "shared-1" }),
    );
    expect(result).toEqual({ ok: false, error: "Apple transaction belongs to a different user", status: 403 });
    expect((await transactions(t))[0].user_id).toBe(alice.userId);
  });

  test("rejects a product that is unknown or inactive", async () => {
    const t = newTest();
    await seedProducts(t);
    const user = await createSignedInUser(t);
    const token = await tokenFor(user);
    const unknown = await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, productId: "no.paeonia.unknown" }),
    );
    expect(unknown).toEqual({ ok: false, error: "Apple product is not active in Paeonia", status: 400 });

    await t.run(async (ctx) => {
      const product = await ctx.db
        .query("subscription_products")
        .withIndex("by_apple_product_id", (q) => q.eq("apple_product_id", "no.paeonia.couple"))
        .unique();
      await ctx.db.patch(product!._id, { is_active: false });
    });
    const inactive = await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token }),
    );
    expect(inactive).toMatchObject({ ok: false, status: 400 });
  });

  test("one paying partner unlocks the couple for both, and outsiders see nothing", async () => {
    const t = newTest();
    await seedProducts(t);
    const couple = await createCouple(t, { entitled: false });
    const outsider = await createSignedInUser(t);
    const [first, second] = [couple.first, couple.second];

    expect((await second.as.query(api.access.get_access_snapshot, {}))[0].couple_entitlement).toMatchObject({ is_entitled: false });

    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: first.userId, token: await tokenFor(first), expiresAt: hoursFromNow(72) }),
    );

    const [snapshot] = await second.as.query(api.access.get_access_snapshot, {});
    expect(snapshot.user_entitlement?.is_entitled).toBe(false);
    expect(snapshot.couple_entitlement).toMatchObject({ couple_id: couple.coupleId, is_entitled: true, covering_user_id: first.userId });
    expect(snapshot.relationship_state).toMatchObject({ couple_id: couple.coupleId, partner_user_id: first.userId });

    expect((await outsider.as.query(api.access.get_access_snapshot, {}))[0].couple_entitlement).toBeNull();
    expect((await outsider.as.query(api.access.get_access_snapshot, {}))[0].user_entitlement).toMatchObject({ is_entitled: false });
  });
});

describe("record_storekit_server_notification", () => {
  async function setup() {
    const t = newTest();
    await seedProducts(t);
    const user = await createSignedInUser(t);
    return { t, user, token: await tokenFor(user) };
  }
  const base = (overrides: Record<string, unknown> = {}) => ({
    p_notification_uuid: newUuid(),
    p_notification_type: "DID_RENEW",
    p_subtype: null,
    p_environment: "sandbox",
    p_original_transaction_id: "orig-1",
    p_transaction_id: "tx-1",
    p_apple_product_id: "no.paeonia.couple",
    p_status: "active",
    p_expires_at: hoursFromNow(72),
    p_signed_notification_payload: "signed-notification",
    p_signed_transaction_info: "signed-transaction",
    p_payload_json: { notification: { notificationType: "DID_RENEW" } },
    ...overrides,
  });

  test("a TEST notification is acknowledged and marked processed", async () => {
    const { t } = await setup();
    const result = await t.mutation(
      internal.storekit.record_storekit_server_notification,
      base({ p_notification_type: "TEST", p_original_transaction_id: null, p_transaction_id: null }),
    );
    expect(result).toEqual({ ok: true, duplicate: false, processed: true, test: true });
    const events = await t.run((ctx) => ctx.db.query("storekit_notification_events").collect());
    expect(events[0].processed_at).toBeDefined();
  });

  test("a repeated notification uuid is a duplicate", async () => {
    const { t, user, token } = await setup();
    const args = base({ p_app_account_token: token });
    const first = await t.mutation(internal.storekit.record_storekit_server_notification, args);
    const second = await t.mutation(internal.storekit.record_storekit_server_notification, {
      ...args,
      p_signed_notification_payload: "other-signature",
    });
    expect(first).toMatchObject({ ok: true, duplicate: false, processed: true });
    expect(second).toEqual({ ok: true, duplicate: true, processed: false });
    expect((await transactions(t))[0].user_id).toBe(user.userId);
    // The same signed payload is archived once per environment.
    const again = await t.mutation(internal.storekit.record_storekit_server_notification, {
      ...base({ p_app_account_token: token, p_transaction_id: "tx-2" }),
      p_signed_notification_payload: "other-signature",
    });
    expect(again).toMatchObject({ ok: true, processed: true });
    const payloads = await t.run((ctx) => ctx.db.query("storekit_payloads").collect());
    expect(payloads.filter((row) => row.payload_kind === "server_notification")).toHaveLength(2);
  });

  test("a notification without transaction info is accepted but not processed", async () => {
    const { t } = await setup();
    const result = await t.mutation(
      internal.storekit.record_storekit_server_notification,
      base({ p_original_transaction_id: null, p_transaction_id: null }),
    );
    expect(result).toEqual({ ok: true, duplicate: false, processed: false, status: 202 });
    const events = await t.run((ctx) => ctx.db.query("storekit_notification_events").collect());
    expect(events[0].processing_error).toBe("Apple notification did not include transaction info");
  });

  test("a notification nobody owns is accepted but not processed", async () => {
    const { t } = await setup();
    const result = await t.mutation(
      internal.storekit.record_storekit_server_notification,
      base({ p_app_account_token: newUuid() }),
    );
    expect(result).toEqual({ ok: true, duplicate: false, processed: false, status: 202 });
    const events = await t.run((ctx) => ctx.db.query("storekit_notification_events").collect());
    expect(events[0].processing_error).toBe("Could not resolve Apple notification purchase owner");
  });

  test("a renewal without a token finds the owner through the original transaction", async () => {
    const { t, user, token } = await setup();
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, transactionId: "tx-0", originalTransactionId: "orig-1" }),
    );
    const result = await t.mutation(
      internal.storekit.record_storekit_server_notification,
      base({ p_app_account_token: token, p_transaction_id: "tx-1" }),
    );
    expect(result).toMatchObject({ ok: true, processed: true, transaction: { ok: true } });
    expect((await transactions(t)).map((row) => row.transaction_id).sort()).toEqual(["tx-0", "tx-1"]);
  });

  test("a token that disagrees with the stored owner is a conflict", async () => {
    const { t, user, token } = await setup();
    const other = await createSignedInUser(t);
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, transactionId: "tx-1", originalTransactionId: "orig-1" }),
    );
    const result = await t.mutation(
      internal.storekit.record_storekit_server_notification,
      base({ p_app_account_token: await tokenFor(other) }),
    );
    expect(result).toEqual({
      ok: false,
      error: "Apple notification purchase owner does not match existing transaction owner",
      status: 409,
    });
  });

  test("rejects bad input as values", async () => {
    const { t } = await setup();
    const call = (overrides: Record<string, unknown>) =>
      t.mutation(internal.storekit.record_storekit_server_notification, base(overrides));
    expect(await call({ p_notification_uuid: null })).toEqual({ ok: false, error: "Invalid notification UUID", status: 400 });
    expect(await call({ p_notification_type: "  " })).toEqual({ ok: false, error: "Invalid notification type", status: 400 });
    expect(await call({ p_environment: "xcode" })).toEqual({ ok: false, error: "Invalid StoreKit environment", status: 400 });
    expect(await call({ p_payload_json: [] })).toEqual({ ok: false, error: "Invalid notification payload", status: 400 });
  });

  test("a refund notification marks the transaction refunded", async () => {
    const { t, user, token } = await setup();
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: user.userId, token, transactionId: "tx-1", originalTransactionId: "orig-1" }),
    );
    await t.mutation(
      internal.storekit.record_storekit_server_notification,
      base({
        p_notification_type: "REFUND",
        p_app_account_token: token,
        p_status: "refunded",
        p_revoked_at: NOW.toISOString(),
        p_revocation_reason: "customer_refund",
      }),
    );
    const [row] = await transactions(t);
    expect(row).toMatchObject({ status: "refunded", revocation_reason: "customer_refund" });
    expect((await user.as.query(api.access.get_access_snapshot, {}))[0].user_entitlement?.is_entitled).toBe(false);
  });
});

describe("streak restore recording", () => {
  async function setup() {
    const t = newTest();
    await seedProducts(t);
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await t.run(async (ctx) => {
      await ctx.db.insert("streak_states", {
        couple_id: couple.coupleId,
        current_count: 0,
        longest_count: 5,
        restorable_count: 5,
        restorable_through_date: "2026-10-08",
        restore_deadline: hoursFromNow(24),
        updated_at: NOW.toISOString(),
      });
    });
    return { t, couple, token: await tokenFor(couple.first) };
  }
  const restoreArgs = (userId: string | null, token: string | null, transactionId = "restore-1") => ({
    p_user_id: userId,
    p_app_account_token: token,
    p_apple_product_id: "no.paeonia.streak.restore",
    p_environment: "sandbox",
    p_original_transaction_id: transactionId,
    p_transaction_id: transactionId,
    p_purchased_at: NOW.toISOString(),
    p_signed_payload: "signed",
    p_payload_json: { transactionInfo: {} },
  });

  test("restores the shared streak once and replays safely", async () => {
    const { t, couple, token } = await setup();
    const first = await t.mutation(internal.storekit.record_verified_streak_restore, restoreArgs(couple.first.userId, token));
    expect(first).toEqual({ ok: true, restoredCount: 5, replayed: false });
    const again = await t.mutation(internal.storekit.record_verified_streak_restore, restoreArgs(couple.first.userId, token));
    expect(again).toEqual({ ok: true, restoredCount: 5, replayed: true });

    const [restoration] = await t.run((ctx) => ctx.db.query("streak_restorations").collect());
    expect(restoration).toMatchObject({ couple_id: couple.coupleId, purchaser_user_id: couple.first.userId, status: "applied" });
    expect(await t.mutation(internal.storekit.mark_streak_restore_refunded, { p_environment: "sandbox", p_transaction_id: "restore-1" })).toBe(true);
    expect(await t.mutation(internal.storekit.mark_streak_restore_refunded, { p_environment: "sandbox", p_transaction_id: "restore-1" })).toBe(false);
    const [refunded] = await t.run((ctx) => ctx.db.query("streak_restorations").collect());
    expect(refunded.status).toBe("refunded");
  });

  test("fails with the Edge Function messages", async () => {
    const { t, couple, token } = await setup();
    const call = (args: ReturnType<typeof restoreArgs>) => t.mutation(internal.storekit.record_verified_streak_restore, args);
    expect(await call(restoreArgs(null, token))).toEqual({ ok: false, error: "Invalid user", status: 401 });
    expect(await call(restoreArgs(couple.first.userId, null))).toEqual({
      ok: false,
      error: "Apple transaction is missing appAccountToken",
      status: 403,
    });
    expect(await call(restoreArgs(couple.first.userId, newUuid()))).toEqual({
      ok: false,
      error: "Apple appAccountToken is not registered",
      status: 403,
    });
    expect(await call(restoreArgs(couple.second.userId, token))).toEqual({
      ok: false,
      error: "Apple transaction belongs to a different user",
      status: 403,
    });
    expect(await call({ ...restoreArgs(couple.first.userId, token), p_apple_product_id: "no.paeonia.couple" })).toEqual({
      ok: false,
      error: "Apple product is not active in Paeonia",
      status: 400,
    });
    // Nothing is stored for failed attempts.
    expect(await t.run((ctx) => ctx.db.query("storekit_payloads").collect())).toHaveLength(0);
  });

  test("needs an entitled couple, and a streak that can be restored", async () => {
    const { t, couple, token } = await setup();
    await t.run(async (ctx) => {
      const grants = await ctx.db.query("entitlement_grants").collect();
      for (const grant of grants) await ctx.db.patch(grant._id, { status: "revoked" });
    });
    expect(await t.mutation(internal.storekit.record_verified_streak_restore, restoreArgs(couple.first.userId, token))).toEqual({
      ok: false,
      error: "No entitled couple for this user",
      status: 403,
    });

    await t.run(async (ctx) => {
      const grants = await ctx.db.query("entitlement_grants").collect();
      for (const grant of grants) await ctx.db.patch(grant._id, { status: "active" });
      const state = await ctx.db.query("streak_states").first();
      await ctx.db.patch(state!._id, { restore_deadline: hoursFromNow(-1) });
    });
    expect(await t.mutation(internal.storekit.record_verified_streak_restore, restoreArgs(couple.first.userId, token))).toEqual({
      ok: false,
      error: "No streak is available to restore",
      status: 409,
    });
  });
});

describe("expire_stale_entitlements", () => {
  test("expires lapsed transactions and grants and tells a couple that lost its last entitlement", async () => {
    const t = newTest();
    await seedProducts(t);
    const couple = await createCouple(t, { entitled: false });
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: couple.first.userId, token: await tokenFor(couple.first), expiresAt: hoursFromNow(1) }),
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("entitlement_grants", {
        id: newUuid(),
        user_id: couple.second.userId,
        grant_kind: "test",
        status: "active",
        scope: "user",
        granted_at: NOW.toISOString(),
        expires_at: hoursFromNow(1),
        created_at: NOW.toISOString(),
        updated_at: NOW.toISOString(),
      });
    });

    // Nothing is stale yet.
    expect(await t.mutation(internal.storekit.expire_stale_entitlements, {})).toEqual([
      { storekit_transactions_expired: 0, entitlement_grants_expired: 0 },
    ]);

    vi.setSystemTime(new Date(NOW.getTime() + 2 * 3_600_000));
    expect(await t.mutation(internal.storekit.expire_stale_entitlements, {})).toEqual([
      { storekit_transactions_expired: 1, entitlement_grants_expired: 1 },
    ]);
    expect((await transactions(t))[0].status).toBe("expired");
    const events = await t.run((ctx) => ctx.db.query("relationship_sync_events").collect());
    expect(events.map((event) => event.user_id).sort()).toEqual([couple.first.userId, couple.second.userId].sort());
    expect(events[0]).toMatchObject({
      couple_id: couple.coupleId,
      event_kind: "entitlement_lost",
      reason: "entitlement_expired",
      relationship_status: "active",
      member_status: "active",
      local_purge_scope: { entitlement: "refresh", relationship_content: "hide", media_cache: "purge", widget_cache: "purge" },
    });
  });

  test("stays quiet while another member still has access", async () => {
    const t = newTest();
    await seedProducts(t);
    const couple = await createCouple(t, { entitled: true });
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: couple.second.userId, token: await tokenFor(couple.second), expiresAt: hoursFromNow(1) }),
    );
    vi.setSystemTime(new Date(NOW.getTime() + 2 * 3_600_000));
    await t.mutation(internal.storekit.expire_stale_entitlements, {});
    expect(await t.run((ctx) => ctx.db.query("relationship_sync_events").collect())).toHaveLength(0);
  });

  test("runs every five minutes, and queries report a lapsed row as not entitled before it runs", async () => {
    const job = (crons as unknown as { crons: Record<string, { schedule: unknown }> }).crons["expire-stale-entitlements"];
    expect(job.schedule).toEqual({ type: "interval", minutes: 5 });

    const t = newTest();
    await seedProducts(t);
    const couple = await createCouple(t, { entitled: false });
    await t.mutation(
      internal.storekit.record_verified_storekit_transaction,
      storekitArgs({ userId: couple.first.userId, token: await tokenFor(couple.first), expiresAt: hoursFromNow(1) }),
    );
    vi.setSystemTime(new Date(NOW.getTime() + 2 * 3_600_000));
    expect((await couple.first.as.query(api.access.get_access_snapshot, {}))[0].user_entitlement?.is_entitled).toBe(false);
    expect((await transactions(t))[0].status).not.toBe("expired");
    await t.mutation(internal.storekit.expire_stale_entitlements, {});
    expect((await transactions(t))[0].status).toBe("expired");
  });

  test("validates its limits", async () => {
    const t = newTest();
    await expect(t.mutation(internal.storekit.expire_stale_entitlements, { p_limit: 5001 })).rejects.toThrow(
      /entitlement expiry limit is out of range/,
    );
    await expect(t.mutation(internal.storekit.expire_stale_entitlements, { p_now: null })).rejects.toThrow(
      /entitlement expiry timestamp is required/,
    );
  });
});

describe("queue_subscription_trial_reminders", () => {
  type Seed = { id: string; userId: string };

  async function trial(
    t: TestConvex,
    name: string,
    options: {
      expiresInHours: number;
      discount?: string;
      transactionId?: string;
      devices?: string[];
    },
  ): Promise<Seed> {
    const user = await createSignedInUser(t, { name });
    for (const locale of options.devices ?? ["en"]) {
      await addDevice(t, user.userId, { locale, token: `${name}-${locale}` });
    }
    return await t.run(async (ctx) => {
      const product = await ctx.db
        .query("subscription_products")
        .withIndex("by_apple_product_id", (q) => q.eq("apple_product_id", "no.paeonia.couple.year"))
        .unique();
      const now = NOW.toISOString();
      await ctx.db.insert("storekit_payloads", {
        id: newUuid(),
        payload_kind: "transaction",
        environment: "sandbox",
        original_transaction_id: name,
        transaction_id: options.transactionId ?? name,
        payload_json: { transactionInfo: { offerType: 1, offerDiscountType: options.discount ?? "FREE_TRIAL" } },
        received_at: now,
        created_at: now,
      });
      const payload = (await ctx.db.query("storekit_payloads").order("desc").first())!;
      const id = newUuid();
      await ctx.db.insert("storekit_transactions", {
        id,
        user_id: user.userId,
        product_id: product!.id,
        environment: "sandbox",
        original_transaction_id: name,
        transaction_id: options.transactionId ?? name,
        status: "active",
        purchased_at: hoursFromNow(-12 * 24),
        expires_at: hoursFromNow(options.expiresInHours),
        raw_payload_id: payload.id,
        created_at: now,
        updated_at: now,
      });
      return { id, userId: user.userId };
    });
  }

  async function reminders(t: TestConvex): Promise<Doc<"notification_outbox">[]> {
    return (await t.run((ctx) => ctx.db.query("notification_outbox").collect())).filter(
      (row) => row.kind === "subscription_trial_reminder",
    );
  }

  test("queues verified free trials per device, in bounded batches, once", async () => {
    const t = newTest();
    await seedProducts(t);
    const one = await trial(t, "trial-one", { expiresInHours: 48.5, devices: ["en", "nb-NO"] });
    const paid = await trial(t, "paid-intro", { expiresInHours: 48.6, discount: "PAY_AS_YOU_GO" });
    const two = await trial(t, "trial-two", { expiresInHours: 48.7 });
    const nonInitial = await trial(t, "noninitial-original", { expiresInHours: 48.3, transactionId: "noninitial-second" });
    const future = await trial(t, "future-trial", { expiresInHours: 96 });
    const noDevice = await trial(t, "no-device-trial", { expiresInHours: 48.2, devices: [] });

    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, { p_batch_size: 1 })).toBe(2);
    let rows = await reminders(t);
    expect(rows).toHaveLength(2);
    expect(rows.map((row) => row.title).sort()).toEqual(["Prøveperioden avsluttes snart", "Your free trial ends soon"]);
    expect(rows.map((row) => row.body).sort()).toEqual([
      "2 dager igjen. Se over abonnementet ditt i App Store.",
      "2 days left. Review your subscription in the App Store.",
    ]);
    expect(rows[0].payload).toMatchObject({
      deeplink: "paeonia://settings/subscription",
      subscription_id: one.id,
      route: "subscription",
      days_left: 2,
    });
    expect(Math.abs(Date.parse(rows[0].scheduled_for) - (NOW.getTime() + 0.5 * 3_600_000))).toBeLessThan(1000);

    for (const skipped of [paid, nonInitial, future, noDevice]) {
      expect(rows.some((row) => row.recipient_user_id === skipped.userId)).toBe(false);
    }

    // The next run moves past the fully queued trial instead of starving trial-two.
    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, { p_batch_size: 1 })).toBe(1);
    expect((await reminders(t)).some((row) => row.recipient_user_id === two.userId)).toBe(true);
    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, { p_batch_size: 1 })).toBe(0);
    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, {})).toBe(0);

    // An expiry change from Apple removes the stale reminder, through the write helper.
    const { patchStorekitTransaction } = await import("./lib/storekit");
    await t.run(async (ctx) => {
      const tx = await ctx.db.query("storekit_transactions").withIndex("by_uuid", (q) => q.eq("id", one.id)).unique();
      await patchStorekitTransaction(ctx, tx!, { expires_at: hoursFromNow(72) });
    });
    rows = await reminders(t);
    expect(rows.some((row) => row.recipient_user_id === one.userId)).toBe(false);
    expect(rows).toHaveLength(1);

    await t.run(async (ctx) => {
      const tx = await ctx.db.query("storekit_transactions").withIndex("by_uuid", (q) => q.eq("id", two.id)).unique();
      await patchStorekitTransaction(ctx, tx!, { status: "expired" });
    });
    expect(await reminders(t)).toHaveLength(0);
    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, {})).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a trial found with less than a day left says one day, and goes out now", async () => {
    const t = newTest();
    await seedProducts(t);
    await trial(t, "late-trial", { expiresInHours: 10 });
    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, {})).toBe(1);
    const [row] = await reminders(t);
    expect(row.body).toBe("1 day left. Review your subscription in the App Store.");
    expect(row.payload).toMatchObject({ days_left: 1 });
    expect(row.scheduled_for).toBe(NOW.toISOString());
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("deleting the transaction removes its reminders", async () => {
    const t = newTest();
    await seedProducts(t);
    const one = await trial(t, "trial-one", { expiresInHours: 48.5 });
    expect(await t.mutation(internal.storekit.queue_subscription_trial_reminders, {})).toBe(1);
    const { deleteStorekitTransaction } = await import("./lib/storekit");
    await t.run(async (ctx) => {
      const tx = await ctx.db.query("storekit_transactions").withIndex("by_uuid", (q) => q.eq("id", one.id)).unique();
      await deleteStorekitTransaction(ctx, tx!);
    });
    expect(await reminders(t)).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("runs hourly at minute 15", () => {
    const job = (crons as unknown as { crons: Record<string, { schedule: unknown; name: string }> }).crons[
      "queue-subscription-trial-reminders"
    ];
    expect(job.schedule).toEqual({ type: "cron", cron: "15 * * * *" });
  });
});
