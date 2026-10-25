// @vitest-environment node
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { makeChain, removeChains, signJws, type Chain } from "./appleChain.testHelpers";
import { newUuid } from "./lib/ids";
import { seedProducts } from "./storekit.testHelpers";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

let apple: Chain;
let fetchMock: ReturnType<typeof vi.fn<(url: string) => Promise<Response>>>;

beforeAll(() => {
  apple = makeChain("webhook");
  vi.spyOn(console, "warn").mockImplementation(() => {});
  vi.spyOn(console, "error").mockImplementation(() => {});
});
afterAll(removeChains);

beforeEach(() => {
  // The action downloads Apple's root certificates once per process. Serve the test root.
  fetchMock = vi.fn(async () => new Response(new Uint8Array(apple.rootDer)));
  vi.stubGlobal("fetch", fetchMock);
  vi.stubEnv("APPLE_BUNDLE_ID", "no.paeonia.app");
  vi.stubEnv("APPLE_APP_APPLE_ID", "");
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

const day = 86_400_000;

function transactionPayload(token: string | undefined, overrides: Record<string, unknown> = {}) {
  return {
    transactionId: "2000000000001",
    originalTransactionId: "2000000000001",
    bundleId: "no.paeonia.app",
    productId: "no.paeonia.couple",
    purchaseDate: Date.now() - day,
    expiresDate: Date.now() + 30 * day,
    environment: "Sandbox",
    type: "Auto-Renewable Subscription",
    signedDate: Date.now(),
    ...(token ? { appAccountToken: token } : {}),
    ...overrides,
  };
}

function signedNotification(
  transaction: Record<string, unknown> | null,
  overrides: Record<string, unknown> = {},
  chain: Chain = apple,
) {
  return signJws(chain, {
    notificationType: "DID_RENEW",
    notificationUUID: newUuid(),
    signedDate: Date.now(),
    data: {
      bundleId: "no.paeonia.app",
      environment: "Sandbox",
      ...(transaction ? { signedTransactionInfo: signJws(chain, transaction) } : {}),
    },
    ...overrides,
  });
}

async function post(t: TestConvex, body: unknown) {
  const response = await t.fetch("/apple/server-notifications", {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function setup() {
  const t = newTest();
  await seedProducts(t);
  const user: TestUser = await createSignedInUser(t);
  const token = await user.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: user.userId });
  return { t, user, token };
}

describe("POST /apple/server-notifications", () => {
  test("records a verified renewal once", async () => {
    const { t, user, token } = await setup();
    const signedPayload = signedNotification(transactionPayload(token));

    expect(await post(t, { signedPayload })).toEqual({
      status: 200,
      body: { received: true, duplicate: false, processed: true },
    });
    const [row] = await t.run((ctx) => ctx.db.query("storekit_transactions").collect());
    expect(row).toMatchObject({ user_id: user.userId, status: "active", app_account_token: token, environment: "sandbox" });
    const [event] = await t.run((ctx) => ctx.db.query("storekit_notification_events").collect());
    expect(event).toMatchObject({ notification_type: "DID_RENEW", environment: "sandbox", signed_payload: signedPayload });
    expect(event.processed_at).toBeDefined();
    expect(fetchMock).toHaveBeenCalledTimes(2);

    expect(await post(t, { signedPayload })).toEqual({
      status: 200,
      body: { received: true, duplicate: true, processed: false },
    });
    expect(await t.run((ctx) => ctx.db.query("storekit_transactions").collect())).toHaveLength(1);
  });

  test("a refund notification revokes access", async () => {
    const { t, user, token } = await setup();
    await post(t, { signedPayload: signedNotification(transactionPayload(token)) });
    const refund = signedNotification(transactionPayload(token), { notificationType: "REFUND" });
    expect((await post(t, { signedPayload: refund })).body).toMatchObject({ processed: true });
    const [row] = await t.run((ctx) => ctx.db.query("storekit_transactions").collect());
    expect(row).toMatchObject({ status: "refunded", revocation_reason: "customer_refund" });
    expect(row.revoked_at).toBeDefined();
    expect((await user.as.query(api.access.get_access_snapshot, {}))[0].user_entitlement?.is_entitled).toBe(false);
  });

  test("a billing grace period keeps both partners in until the grace period ends, then Apple keeps retrying", async () => {
    const t = newTest();
    await seedProducts(t);
    const { first, second } = await createCouple(t, { entitled: false });
    const token = await first.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: first.userId });
    const graceEndsAt = Date.now() + 16 * day;
    const signedPayload = signedNotification(transactionPayload(token, { expiresDate: Date.now() - day }), {
      notificationType: "DID_FAIL_TO_RENEW",
      subtype: "GRACE_PERIOD",
      data: {
        bundleId: "no.paeonia.app",
        environment: "Sandbox",
        signedTransactionInfo: signJws(apple, transactionPayload(token, { expiresDate: Date.now() - day })),
        signedRenewalInfo: signJws(apple, {
          originalTransactionId: "2000000000001",
          autoRenewProductId: "no.paeonia.couple",
          autoRenewStatus: 1,
          isInBillingRetryPeriod: true,
          gracePeriodExpiresDate: graceEndsAt,
          environment: "Sandbox",
          signedDate: Date.now(),
        }),
      },
    });
    expect((await post(t, { signedPayload })).body).toMatchObject({ processed: true });

    const coupleEntitled = async () =>
      await Promise.all(
        [first, second].map(async (user) => (await user.as.query(api.access.get_access_snapshot, {}))[0].couple_entitlement?.is_entitled),
      );
    expect(await coupleEntitled()).toEqual([true, true]);

    const expire = (now: number) =>
      t.mutation(internal.storekit.expire_stale_entitlements, { p_now: new Date(now).toISOString() });
    expect(await expire(Date.now())).toEqual([
      { storekit_transactions_expired: 0, storekit_transactions_in_billing_retry: 0, entitlement_grants_expired: 0 },
    ]);
    expect(await coupleEntitled()).toEqual([true, true]);

    expect(await expire(graceEndsAt + 1)).toEqual([
      { storekit_transactions_expired: 0, storekit_transactions_in_billing_retry: 1, entitlement_grants_expired: 0 },
    ]);
    expect(await coupleEntitled()).toEqual([false, false]);
    const [row] = await t.run((ctx) => ctx.db.query("storekit_transactions").collect());
    expect(row.status).toBe("billing_retry");
    const events = await t.run((ctx) => ctx.db.query("relationship_sync_events").collect());
    expect(events.map((event) => [event.user_id, event.event_kind]).sort()).toEqual(
      [
        [first.userId, "entitlement_lost"],
        [second.userId, "entitlement_lost"],
      ].sort(),
    );
  });

  test("a streak restore refund is logged on the restore ledger", async () => {
    const { t, token } = await setup();
    await t.run(async (ctx) => {
      const product = await ctx.db
        .query("subscription_products")
        .withIndex("by_apple_product_id", (q) => q.eq("apple_product_id", "no.paeonia.streak.restore"))
        .unique();
      await ctx.db.insert("streak_restorations", {
        id: newUuid(),
        couple_id: newUuid(),
        purchaser_user_id: newUuid(),
        product_id: product!.id,
        environment: "sandbox",
        transaction_id: "3000000000001",
        restored_count: 4,
        restored_at: new Date().toISOString(),
        status: "applied",
        created_at: new Date().toISOString(),
      });
    });
    const consumable = transactionPayload(token, {
      transactionId: "3000000000001",
      originalTransactionId: "3000000000001",
      productId: "no.paeonia.streak.restore",
      type: "Consumable",
    });

    // Anything but a refund is acknowledged and ignored.
    expect(await post(t, { signedPayload: signedNotification(consumable, { notificationType: "ONE_TIME_CHARGE" }) })).toEqual({
      status: 200,
      body: { received: true, duplicate: false, processed: false },
    });
    expect(await post(t, { signedPayload: signedNotification(consumable, { notificationType: "REFUND" }) })).toEqual({
      status: 200,
      body: { received: true, duplicate: false, processed: true },
    });
    const [restoration] = await t.run((ctx) => ctx.db.query("streak_restorations").collect());
    expect(restoration.status).toBe("refunded");
    expect(await t.run((ctx) => ctx.db.query("storekit_transactions").collect())).toHaveLength(0);
  });

  test("acknowledges notifications it cannot attribute", async () => {
    const { t } = await setup();
    const signedPayload = signedNotification(transactionPayload(newUuid()));
    expect(await post(t, { signedPayload })).toEqual({
      status: 200,
      body: { received: true, duplicate: false, processed: false },
    });
    const test = signedNotification(null, { notificationType: "TEST" });
    expect(await post(t, { signedPayload: test })).toEqual({
      status: 200,
      body: { received: true, duplicate: false, processed: true },
    });
  });

  test("rejects payloads that do not verify", async () => {
    const { t, token } = await setup();
    const impostor = makeChain("impostor-webhook");
    expect(await post(t, { signedPayload: signedNotification(transactionPayload(token), {}, impostor) })).toEqual({
      status: 400,
      body: { ok: false, error: "Invalid Apple notification" },
    });
    expect(await post(t, { signedPayload: "not-a-jws" })).toEqual({
      status: 400,
      body: { ok: false, error: "Invalid Apple notification" },
    });
    expect(await post(t, {})).toEqual({ status: 400, body: { ok: false, error: "Missing signedPayload" } });
    expect(await post(t, "not json")).toEqual({
      status: 500,
      body: { received: false, processed: false, error: "Unexpected error" },
    });
    expect(await t.run((ctx) => ctx.db.query("storekit_notification_events").collect())).toHaveLength(0);
  });

  test("rejects another app's notification", async () => {
    const { t, token } = await setup();
    vi.stubEnv("APPLE_BUNDLE_ID", "no.other.app");
    expect((await post(t, { signedPayload: signedNotification(transactionPayload(token)) })).status).toBe(400);
  });
});
