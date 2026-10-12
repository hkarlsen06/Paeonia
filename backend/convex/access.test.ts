import { generateKeyPairSync, verify } from "node:crypto";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { seedProducts } from "./storekit.testHelpers";
import { createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

const NOW = new Date("2026-10-10T12:00:00.000Z");
const day = 86_400_000;

const keys = generateKeyPairSync("ec", { namedCurve: "prime256v1" });

function b64url(value: string | Buffer): string {
  return Buffer.from(value).toString("base64url");
}

/** A JWS in Apple's shape. The App Store Server API path decodes it without checking the signature. */
function jws(payload: Record<string, unknown>): string {
  return `${b64url(JSON.stringify({ alg: "ES256" }))}.${b64url(JSON.stringify(payload))}.${b64url("signature")}`;
}

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
let fetchMock: ReturnType<typeof vi.fn<Fetch>>;

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status });
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
  vi.stubEnv("APPLE_IAP_KEY_ID", "KEY123");
  vi.stubEnv("APPLE_IAP_ISSUER_ID", "issuer-1");
  vi.stubEnv("APPLE_IAP_PRIVATE_KEY", keys.privateKey.export({ type: "pkcs8", format: "pem" }).toString().replace(/\n/g, "\\n"));
  vi.stubEnv("APPLE_BUNDLE_ID", "no.paeonia.app");
  fetchMock = vi.fn<Fetch>();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

function transactionInfo(token: string | undefined, overrides: Record<string, unknown> = {}) {
  return {
    transactionId: "2000000000001",
    originalTransactionId: "2000000000001",
    bundleId: "no.paeonia.app",
    productId: "no.paeonia.couple",
    purchaseDate: NOW.getTime() - day,
    expiresDate: NOW.getTime() + 30 * day,
    environment: "Sandbox",
    type: "Auto-Renewable Subscription",
    ...(token ? { appAccountToken: token } : {}),
    ...overrides,
  };
}

/** Makes the mocked Apple API answer the transaction lookup. */
function appleReturns(info: Record<string, unknown>, renewal?: Record<string, unknown>) {
  fetchMock.mockImplementation(async (url) => {
    if (url.includes("/inApps/v1/transactions/")) {
      return jsonResponse(200, { signedTransactionInfo: jws(info) });
    }
    if (url.includes("/inApps/v1/subscriptions/")) {
      return renewal
        ? jsonResponse(200, { data: [{ lastTransactions: [{ signedRenewalInfo: jws(renewal) }] }] })
        : jsonResponse(404, {});
    }
    return jsonResponse(500, {});
  });
}

type UploadBody = {
  jws: string;
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  environment: "xcode" | "sandbox" | "production";
  priceDisplay?: string;
};

function uploadBody(info: Record<string, unknown>, overrides: Partial<UploadBody> = {}): UploadBody {
  return {
    jws: jws(info),
    transactionId: String(info.transactionId),
    originalTransactionId: String(info.originalTransactionId),
    productId: String(info.productId),
    environment: "sandbox",
    priceDisplay: "kr 49,00",
    ...overrides,
  };
}

/** The streak restore action takes the upload without `priceDisplay`. */
function restoreBody(info: Record<string, unknown>) {
  const { priceDisplay: _priceDisplay, ...body } = uploadBody(info);
  return body;
}

async function tokenFor(user: TestUser): Promise<string> {
  return await user.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: user.userId });
}

async function setup() {
  const t = newTest();
  await seedProducts(t);
  const user = await createSignedInUser(t);
  return { t, user, token: await tokenFor(user) };
}

async function transactions(t: TestConvex) {
  return await t.run((ctx) => ctx.db.query("storekit_transactions").collect());
}

describe("app account token", () => {
  test("is created once per user and only for the caller", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const other = await createSignedInUser(t);
    const token = await tokenFor(user);
    expect(token).toMatch(/^[0-9a-f-]{36}$/);
    expect(await user.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: user.userId.toUpperCase() })).toBe(token);
    await expect(other.as.mutation(api.access.get_or_create_app_account_token, { p_user_id: user.userId })).rejects.toThrow(
      /42501.*not authorized/,
    );
    await expect(t.mutation(api.access.get_or_create_app_account_token, { p_user_id: user.userId })).rejects.toThrow(/42501/);
    expect(await t.run((ctx) => ctx.db.query("app_account_tokens").collect())).toHaveLength(1);
  });
});

describe("access snapshot", () => {
  test("a user without a couple gets an empty relationship and couple entitlement", async () => {
    const t = newTest();
    const user = await createSignedInUser(t);
    const rows = await user.as.query(api.access.get_access_snapshot, {});
    expect(rows).toEqual([
      {
        user_entitlement: {
          user_id: user.userId,
          is_entitled: false,
          source: null,
          status: null,
          product_id: null,
          current_period_end: null,
          updated_at: null,
        },
        couple_entitlement: null,
        relationship_state: null,
      },
    ]);
    await expect(t.query(api.access.get_access_snapshot, {})).rejects.toThrow(/42501.*authenticated user required/);
  });

  test("a lifetime grant on one partner covers the couple", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const [row] = await couple.second.as.query(api.access.get_access_snapshot, {});
    expect(row.user_entitlement).toMatchObject({ is_entitled: false });
    expect(row.couple_entitlement).toMatchObject({
      couple_id: couple.coupleId,
      is_entitled: true,
      covering_user_id: couple.first.userId,
      source: "lifetime_grant",
      status: "lifetime",
    });
    expect(row.relationship_state).toMatchObject({
      couple_id: couple.coupleId,
      relationship_status: "active",
      member_status: "active",
      partner_user_id: couple.first.userId,
      partner_display_name: "First Partner",
    });
  });
});

describe("verify_purchase", () => {
  test("verifies with Apple, stores the transaction, and entitles the user", async () => {
    const { t, user, token } = await setup();
    const info = transactionInfo(token);
    appleReturns(info, { originalTransactionId: info.originalTransactionId, autoRenewStatus: 1 });

    const result = await user.as.action(api.access.verify_purchase, uploadBody(info));

    expect(result).toEqual({
      entitled: true,
      subscription: {
        status: "active",
        productId: "no.paeonia.couple",
        expiresAt: new Date(NOW.getTime() + 30 * day).toISOString(),
        environment: "sandbox",
        originalTransactionId: "2000000000001",
        transactionId: "2000000000001",
      },
    });
    const [row] = await transactions(t);
    expect(row).toMatchObject({ user_id: user.userId, app_account_token: token, status: "active", environment: "sandbox" });
    const payload = await t.run((ctx) => ctx.db.query("storekit_payloads").first());
    expect(payload!.payload_json).toMatchObject({
      priceDisplay: "kr 49,00",
      transactionInfo: { productId: "no.paeonia.couple" },
      renewalInfo: { autoRenewStatus: 1 },
      verifiedAt: NOW.toISOString(),
    });

    // The first call asks the sandbox API, with a signed ES256 token for the app.
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/2000000000001");
    const bearer = String((init!.headers as Record<string, string>).Authorization).replace("Bearer ", "");
    const [header, claims, signature] = bearer.split(".");
    expect(JSON.parse(Buffer.from(header, "base64url").toString())).toEqual({ alg: "ES256", kid: "KEY123", typ: "JWT" });
    expect(JSON.parse(Buffer.from(claims, "base64url").toString())).toMatchObject({
      iss: "issuer-1",
      aud: "appstoreconnect-v1",
      bid: "no.paeonia.app",
    });
    expect(
      verify("sha256", Buffer.from(`${header}.${claims}`), { key: keys.publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")),
    ).toBe(true);
    expect((await user.as.query(api.access.get_access_snapshot, {}))[0].user_entitlement).toMatchObject({ is_entitled: true, source: "storekit" });
  });

  test("tries the other environment when Apple answers 404", async () => {
    const { user, token } = await setup();
    const info = transactionInfo(token, { environment: "Production" });
    fetchMock.mockImplementation(async (url) =>
      url.startsWith("https://api.storekit-sandbox")
        ? jsonResponse(404, { errorCode: 4040010 })
        : url.includes("/transactions/")
          ? jsonResponse(200, { signedTransactionInfo: jws(info) })
          : jsonResponse(404, {}),
    );
    const result = await user.as.action(api.access.verify_purchase, uploadBody(info, { environment: "sandbox" }));
    expect(result).toMatchObject({ subscription: { environment: "production" } });
    expect(fetchMock.mock.calls[0][0]).toContain("storekit-sandbox");
    expect(fetchMock.mock.calls[1][0]).toContain("api.storekit.itunes");
  });

  test("a lapsed subscription is stored but does not entitle", async () => {
    const { t, user, token } = await setup();
    const info = transactionInfo(token, { expiresDate: NOW.getTime() - day });
    appleReturns(info, { originalTransactionId: info.originalTransactionId, isInBillingRetryPeriod: true });
    const result = await user.as.action(api.access.verify_purchase, uploadBody(info));
    expect(result).toMatchObject({ entitled: false, subscription: { status: "billing_retry" } });
    expect((await transactions(t))[0].status).toBe("billing_retry");
  });

  async function expectFailure(promise: Promise<unknown>, code: string, message: string) {
    await expect(promise).rejects.toMatchObject({ data: { code, message } });
  }

  test("fails with the codes the app matches on", async () => {
    const { t, user, token } = await setup();
    const info = transactionInfo(token);
    appleReturns(info);

    const stranger = await createSignedInUser(t);
    await expectFailure(
      stranger.as.action(api.access.verify_purchase, uploadBody(info)),
      "purchase_linked_to_another_account",
      "Apple transaction belongs to a different user",
    );

    const unregistered = transactionInfo(newUuid());
    appleReturns(unregistered);
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(unregistered)),
      "purchase_linked_to_another_account",
      "Apple appAccountToken is not registered",
    );

    const missingToken = transactionInfo(undefined);
    appleReturns(missingToken);
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(missingToken)),
      "app_account_token_missing",
      "Apple transaction is missing appAccountToken",
    );
    expect(await transactions(t)).toHaveLength(0);
  });

  test("fails requests that are not valid purchases", async () => {
    const { user, token } = await setup();
    const info = transactionInfo(token);

    appleReturns(info);
    await expectFailure(user.as.action(api.access.verify_purchase, uploadBody(info, { jws: "" })), "invalid_request", "Invalid Apple JWS format");
    await expectFailure(user.as.action(api.access.verify_purchase, uploadBody(info, { jws: "nope" })), "invalid_request", "Invalid Apple JWS format");
    await expectFailure(user.as.action(api.access.verify_purchase, uploadBody(info, { transactionId: " " })), "invalid_request", "Missing transactionId");
    // Arguments that are missing or have the wrong type never reach the handler.
    await expect(user.as.action(api.access.verify_purchase, { jws: info as never } as never)).rejects.toThrow(/Validator error/);
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info, { environment: "xcode" })),
      "invalid_request",
      "Local StoreKit transactions cannot be verified by Apple",
    );
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info, { productId: "no.paeonia.other" })),
      "transaction_mismatch",
      "Product does not match Apple verification",
    );
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info, { originalTransactionId: "other" })),
      "transaction_mismatch",
      "Original transaction does not match Apple verification",
    );
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody({ ...info, bundleId: "someone.else" })),
      "transaction_mismatch",
      "Uploaded transaction does not match Apple verification",
    );

    appleReturns(transactionInfo(token, { bundleId: "someone.else" }));
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info)),
      "transaction_mismatch",
      "Uploaded transaction does not match Apple verification",
    );
    appleReturns(transactionInfo(token, { productId: "no.paeonia.streak.restore", type: "Consumable" }));
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(transactionInfo(token, { productId: "no.paeonia.streak.restore" }), { productId: "no.paeonia.streak.restore" })),
      "invalid_transaction",
      "Apple product is not supported",
    );
    appleReturns(transactionInfo(token, { type: "Consumable" }));
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info)),
      "invalid_transaction",
      "Apple transaction is not a subscription",
    );
    appleReturns(transactionInfo(token, { expiresDate: undefined }), {
      originalTransactionId: "2000000000001",
      gracePeriodExpiresDate: NOW.getTime() + day,
    });
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info)),
      "invalid_transaction",
      "Apple subscription is missing an expiry date",
    );
  });

  test("hides Apple's error detail and reports setup problems", async () => {
    const { t, user, token } = await setup();
    const info = transactionInfo(token);
    fetchMock.mockResolvedValue(jsonResponse(500, { secret: "detail" }));
    await expectFailure(user.as.action(api.access.verify_purchase, uploadBody(info)), "apple_verification_failed", "Apple could not verify this purchase");

    await expectFailure(
      t.action(api.access.verify_purchase, uploadBody(info)),
      "not_signed_in",
      "Invalid session",
    );

    vi.stubEnv("APPLE_IAP_PRIVATE_KEY", "");
    await expectFailure(
      user.as.action(api.access.verify_purchase, uploadBody(info)),
      "service_not_ready",
      "Purchase verification is not ready yet.",
    );
  });

  test("rejects a Clerk user that has no Paeonia account yet", async () => {
    const t = newTest();
    await seedProducts(t);
    const info = transactionInfo(newUuid());
    appleReturns(info);
    await expect(
      t.withIdentity({ subject: "user_unprovisioned", issuer: "https://clerk.test" }).action(api.access.verify_purchase, uploadBody(info)),
    ).rejects.toMatchObject({ data: { code: "not_signed_in", message: "Invalid session" } });
  });
});

describe("redeem_streak_restore", () => {
  async function restoreSetup() {
    const t = newTest();
    await seedProducts(t);
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await t.run(async (ctx) => {
      await ctx.db.insert("streak_states", {
        couple_id: couple.coupleId,
        current_count: 0,
        longest_count: 7,
        restorable_count: 7,
        restorable_through_date: "2026-10-08",
        restore_deadline: new Date(NOW.getTime() + day).toISOString(),
        updated_at: NOW.toISOString(),
      });
    });
    return { t, couple, token: await tokenFor(couple.second) };
  }
  const consumable = (token: string | undefined, overrides: Record<string, unknown> = {}) =>
    transactionInfo(token, {
      transactionId: "3000000000001",
      originalTransactionId: "3000000000001",
      productId: "no.paeonia.streak.restore",
      type: "Consumable",
      expiresDate: undefined,
      ...overrides,
    });

  test("restores the couple's streak for the paying partner's couple", async () => {
    const { t, couple, token } = await restoreSetup();
    const info = consumable(token);
    appleReturns(info);

    const result = await couple.second.as.action(api.access.redeem_streak_restore, restoreBody(info));
    expect(result).toEqual({ restoredCount: 7 });
    const [restoration] = await t.run((ctx) => ctx.db.query("streak_restorations").collect());
    expect(restoration).toMatchObject({ couple_id: couple.coupleId, purchaser_user_id: couple.second.userId, restored_count: 7 });
    const state = await t.run((ctx) => ctx.db.query("streak_states").first());
    expect(state).toMatchObject({ current_count: 7, restorable_count: 0 });

    // Redeeming the same purchase again reports the same count.
    expect(await couple.second.as.action(api.access.redeem_streak_restore, restoreBody(info))).toEqual({ restoredCount: 7 });
  });

  test("fails with the codes the app matches on", async () => {
    const { t, couple, token } = await restoreSetup();
    const info = consumable(token);
    appleReturns(info);

    await expect(
      couple.first.as.action(api.access.redeem_streak_restore, restoreBody(info)),
    ).rejects.toMatchObject({ data: { code: "purchase_linked_to_another_account", message: "Apple transaction belongs to a different user" } });

    await t.run(async (ctx) => {
      const state = await ctx.db.query("streak_states").first();
      await ctx.db.patch(state!._id, { restorable_count: 0 });
    });
    await expect(
      couple.second.as.action(api.access.redeem_streak_restore, restoreBody(info)),
    ).rejects.toMatchObject({ data: { code: "no_streak_to_restore", message: "No streak is available to restore" } });

    appleReturns(consumable(undefined));
    await expect(
      couple.second.as.action(api.access.redeem_streak_restore, restoreBody(consumable(undefined))),
    ).rejects.toMatchObject({ data: { code: "app_account_token_missing", message: "Apple transaction is missing appAccountToken" } });

    appleReturns(transactionInfo(token));
    await expect(
      couple.second.as.action(api.access.redeem_streak_restore, restoreBody(transactionInfo(token))),
    ).rejects.toMatchObject({ data: { code: "invalid_transaction", message: "Apple product is not supported" } });

    appleReturns(consumable(token, { type: "Non-Consumable" }));
    await expect(
      couple.second.as.action(api.access.redeem_streak_restore, restoreBody(consumable(token))),
    ).rejects.toMatchObject({ data: { code: "invalid_transaction", message: "Apple transaction is not a streak restore" } });
  });
});
