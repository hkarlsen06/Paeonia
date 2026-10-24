// @vitest-environment node
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { makeChain, removeChains, signJws, type Chain } from "./appleChain.testHelpers";
import { newUuid } from "./lib/ids";
import { deliverDuePushes } from "./push.testing";
import { seedProducts } from "./storekit.testHelpers";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

// What the payer and the partner hear before access ends: a failed renewal payment (payer only)
// and a subscription the payer stopped (both, five days before the end). Driven through Apple's
// signed server notifications, the way they arrive.

let apple: Chain;
beforeAll(() => {
  apple = makeChain("subscription-notices");
  vi.spyOn(console, "warn").mockImplementation(() => {});
  vi.spyOn(console, "error").mockImplementation(() => {});
});
afterAll(removeChains);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-11-01T12:00:00.000Z"));
  // The webhook downloads Apple's root certificates. Serve the test root.
  vi.stubGlobal("fetch", vi.fn(async () => new Response(new Uint8Array(apple.rootDer))));
  vi.stubEnv("APPLE_BUNDLE_ID", "no.paeonia.app");
  vi.stubEnv("APPLE_APP_APPLE_ID", "");
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

const day = 86_400_000;

type Notice = {
  type: string;
  subtype?: string;
  transactionId?: string;
  originalTransactionId?: string;
  expiresDate: number;
  renewal: Record<string, unknown>;
};

/** Posts one signed App Store server notification for the payer's subscription. */
async function notify(t: TestConvex, token: string, notice: Notice) {
  const transaction = {
    transactionId: notice.transactionId ?? "2000000000001",
    originalTransactionId: notice.originalTransactionId ?? "2000000000001",
    bundleId: "no.paeonia.app",
    productId: "no.paeonia.couple",
    purchaseDate: Date.now() - day,
    expiresDate: notice.expiresDate,
    environment: "Sandbox",
    type: "Auto-Renewable Subscription",
    appAccountToken: token,
    signedDate: Date.now(),
  };
  const signedPayload = signJws(apple, {
    notificationType: notice.type,
    ...(notice.subtype ? { subtype: notice.subtype } : {}),
    notificationUUID: newUuid(),
    signedDate: Date.now(),
    data: {
      bundleId: "no.paeonia.app",
      environment: "Sandbox",
      signedTransactionInfo: signJws(apple, transaction),
      signedRenewalInfo: signJws(apple, {
        originalTransactionId: notice.originalTransactionId ?? "2000000000001",
        autoRenewProductId: "no.paeonia.couple",
        environment: "Sandbox",
        signedDate: Date.now(),
        ...notice.renewal,
      }),
    },
  });
  const response = await t.fetch("/apple/server-notifications", { method: "POST", body: JSON.stringify({ signedPayload }) });
  expect(await response.json()).toMatchObject({ processed: true });
}

/** A couple where `payer` subscribes through Apple and both partners have a phone. */
async function payingCouple() {
  const t = newTest();
  await seedProducts(t);
  const { first: payer, second: partner, coupleId } = await createCouple(t, { entitled: false });
  const token = await payer.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: payer.userId });
  const payerDevice = await addDevice(t, payer.userId, { locale: "en-US" });
  const partnerDevice = await addDevice(t, partner.userId, { locale: "nb-NO" });
  return { t, payer, partner, coupleId, token, payerDevice, partnerDevice };
}

const snapshot = async (user: TestUser) => (await user.as.query(api.access.get_access_snapshot, {}))[0];
const outbox = (t: TestConvex, kind: string) =>
  t.run(async (ctx) => (await ctx.db.query("notification_outbox").collect()).filter((row) => row.kind === kind));

describe("a failed renewal payment", () => {
  test("tells only the payer, once, and a recovered payment clears it", async () => {
    const { t, payer, partner, token, payerDevice } = await payingCouple();
    const outsider = await createSignedInUser(t, { name: "Outsider" });
    await addDevice(t, outsider.userId);
    await notify(t, token, { type: "SUBSCRIBED", expiresDate: Date.now() + 2 * day, renewal: { autoRenewStatus: 1 } });

    const failed: Notice = {
      type: "DID_FAIL_TO_RENEW",
      subtype: "GRACE_PERIOD",
      expiresDate: Date.now() - 1000,
      renewal: { autoRenewStatus: 1, isInBillingRetryPeriod: true, gracePeriodExpiresDate: Date.now() + 16 * day },
    };
    await notify(t, token, failed);
    // Apple sends the failure again under a new id. Still one push for this period.
    await notify(t, token, failed);

    // The payer's own entitlement says grace, which is what the app shows the payment notice for.
    expect((await snapshot(payer)).user_entitlement).toMatchObject({ is_entitled: true, status: "grace" });
    expect((await snapshot(payer)).couple_entitlement).toMatchObject({ status: "grace", access_ends_at: null });
    // The partner keeps access and never sees why.
    const partnerView = await snapshot(partner);
    expect(partnerView.couple_entitlement).toMatchObject({ is_entitled: true, status: "active", access_ends_at: null });
    expect(partnerView.user_entitlement).toMatchObject({ is_entitled: false, status: null });
    // Someone outside the couple sees nothing of it, and nobody signed out reads anything.
    const outsiderView = await snapshot(outsider);
    expect(outsiderView.couple_entitlement).toBeNull();
    expect(outsiderView.user_entitlement).toMatchObject({ is_entitled: false, status: null });
    await expect(t.query(api.access.get_access_snapshot, {})).rejects.toThrow(/42501/);

    const pushes = await outbox(t, "subscription_payment_failed");
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toMatchObject({
      recipient_user_id: payer.userId,
      target_device_id: payerDevice.id,
      title: "Your payment didn't go through",
      body: "Update your payment details in the App Store to keep Paeonia for you both.",
      payload: { deeplink: "paeonia://settings/subscription" },
    });

    // The payment goes through before the push is sent: it is dropped, and the notice clears.
    await notify(t, token, {
      type: "DID_RENEW",
      subtype: "BILLING_RECOVERY",
      transactionId: "2000000000002",
      expiresDate: Date.now() + 30 * day,
      renewal: { autoRenewStatus: 1 },
    });
    expect((await snapshot(payer)).user_entitlement).toMatchObject({ is_entitled: true, status: "active" });
    expect(await deliverDuePushes(t)).toEqual([]);
    expect((await outbox(t, "subscription_payment_failed"))[0].last_error).toBe("notification is out of date");
  });

  test("a lapsed subscription without a grace period still tells the payer", async () => {
    const { t, payer, partner, token } = await payingCouple();
    await notify(t, token, { type: "SUBSCRIBED", expiresDate: Date.now() + 2 * day, renewal: { autoRenewStatus: 1 } });
    await notify(t, token, {
      type: "DID_FAIL_TO_RENEW",
      expiresDate: Date.now() - 1000,
      renewal: { autoRenewStatus: 1, isInBillingRetryPeriod: true },
    });
    const delivered = await deliverDuePushes(t);
    expect(delivered.map((push) => push.payload.type)).toEqual(["subscription_payment_failed"]);
    expect((await outbox(t, "subscription_payment_failed")).map((row) => row.recipient_user_id)).toEqual([payer.userId]);
    expect((await snapshot(partner)).couple_entitlement?.is_entitled).toBe(false);
  });
});

describe("a subscription the payer stopped", () => {
  test("warns both partners five days before access ends, once, and turning renewal back on clears it", async () => {
    const { t, payer, partner, token, payerDevice, partnerDevice } = await payingCouple();
    const endsAt = Date.now() + 10 * day;
    await notify(t, token, { type: "SUBSCRIBED", expiresDate: endsAt, renewal: { autoRenewStatus: 1 } });
    expect((await snapshot(partner)).couple_entitlement?.access_ends_at).toBeNull();

    await notify(t, token, {
      type: "DID_CHANGE_RENEWAL_STATUS",
      subtype: "AUTO_RENEW_DISABLED",
      expiresDate: endsAt,
      renewal: { autoRenewStatus: 0 },
    });
    const endsAtIso = new Date(endsAt).toISOString();
    // Both see the end. Only the payer's own entitlement says it is theirs.
    expect((await snapshot(payer)).couple_entitlement?.access_ends_at).toBe(endsAtIso);
    expect((await snapshot(payer)).user_entitlement).toMatchObject({ source: "storekit", will_renew: false });
    expect((await snapshot(partner)).couple_entitlement?.access_ends_at).toBe(endsAtIso);
    expect((await snapshot(partner)).user_entitlement?.is_entitled).toBe(false);

    const runCron = () => t.mutation(internal.storekit.queue_subscription_ending_reminders, {});
    // Ten days out is too early.
    expect(await runCron()).toBe(0);
    vi.setSystemTime(endsAt - 5 * day - 30 * 60_000);
    expect(await runCron()).toBe(2);
    expect(await runCron()).toBe(0);

    const pushes = await outbox(t, "subscription_ending");
    const payerPush = pushes.find((row) => row.target_device_id === payerDevice.id);
    const partnerPush = pushes.find((row) => row.target_device_id === partnerDevice.id);
    expect(payerPush).toMatchObject({
      title: "Paeonia ends in 5 days",
      body: "Turn your subscription back on in the App Store to keep it for you both.",
      scheduled_for: new Date(endsAt - 5 * day).toISOString(),
      payload: { own_subscription: true, deeplink: "paeonia://settings/subscription", ends_at: endsAtIso },
    });
    expect(partnerPush).toMatchObject({
      title: "Paeonia avsluttes om 5 dager",
      body: "Fram til da fungerer alt som vanlig.",
      payload: { own_subscription: false, deeplink: "paeonia://home", ends_at: endsAtIso },
    });
    // The lock screen never says who stopped paying.
    expect(JSON.stringify(partnerPush)).not.toContain("First Partner");

    // Turning renewal back on before they are sent removes both pushes and clears the notice.
    const renewal = (autoRenewStatus: number) =>
      notify(t, token, { type: "DID_CHANGE_RENEWAL_STATUS", expiresDate: endsAt, renewal: { autoRenewStatus } });
    await renewal(1);
    expect((await snapshot(partner)).couple_entitlement?.access_ends_at).toBeNull();
    expect(await outbox(t, "subscription_ending")).toEqual([]);
    expect(await runCron()).toBe(0);

    // Off again in the same period: the warning comes back, still once.
    await renewal(0);
    expect(await runCron()).toBe(2);
    expect(await runCron()).toBe(0);

    // A copy that waits is dropped at send time when renewal is on by then.
    await t.run(async (ctx) => {
      const tx = (await ctx.db.query("storekit_transactions").collect())[0];
      await ctx.db.patch(tx._id, { auto_renew_off: undefined });
    });
    vi.setSystemTime(endsAt - 5 * day);
    expect(await deliverDuePushes(t)).toEqual([]);
    expect((await outbox(t, "subscription_ending")).map((row) => row.last_error)).toEqual([
      "notification is out of date",
      "notification is out of date",
    ]);
  });

  test("stays quiet while the partner's own subscription keeps going", async () => {
    const { t, partner, token } = await payingCouple();
    const partnerToken = await partner.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: partner.userId });
    const endsAt = Date.now() + 4 * day;
    await notify(t, token, { type: "DID_CHANGE_RENEWAL_STATUS", expiresDate: endsAt, renewal: { autoRenewStatus: 0 } });
    await notify(t, partnerToken, {
      type: "SUBSCRIBED",
      transactionId: "2000000000009",
      originalTransactionId: "2000000000009",
      expiresDate: Date.now() + 2 * day,
      renewal: { autoRenewStatus: 1 },
    });
    expect((await snapshot(partner)).couple_entitlement?.access_ends_at).toBeNull();
    expect(await t.mutation(internal.storekit.queue_subscription_ending_reminders, {})).toBe(0);
  });
});
