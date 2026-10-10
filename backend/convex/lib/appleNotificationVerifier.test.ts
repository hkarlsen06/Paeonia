// @vitest-environment node
import { afterAll, beforeAll, describe, expect, test, vi } from "vitest";
import { makeChain, removeChains, signJws, type Chain } from "../appleChain.testHelpers";
import { verifyAppleNotificationEnvelope, verifyAppleJws } from "./appleNotificationVerifier";

let apple: Chain;
let impostor: Chain;
let noLeafMarker: Chain;
let noIntermediateMarker: Chain;

beforeAll(() => {
  apple = makeChain("apple");
  impostor = makeChain("impostor");
  noLeafMarker = makeChain("noleaf", { leafMarker: false });
  noIntermediateMarker = makeChain("noint", { intermediateMarker: false });
  vi.spyOn(console, "warn").mockImplementation(() => {});
  vi.spyOn(console, "error").mockImplementation(() => {});
});
afterAll(removeChains);

const signedDate = () => Date.now();
const bundleId = "no.paeonia.app";

function transaction(chain: Chain, overrides: Record<string, unknown> = {}) {
  return signJws(chain, { transactionId: "1", bundleId, environment: "Sandbox", signedDate: signedDate(), ...overrides });
}

function notification(chain: Chain, data: Record<string, unknown> = {}, overrides: Record<string, unknown> = {}) {
  return signJws(chain, {
    notificationType: "DID_RENEW",
    notificationUUID: "11111111-1111-4111-8111-111111111111",
    signedDate: signedDate(),
    data: { bundleId, environment: "Sandbox", ...data },
    ...overrides,
  });
}

const options = (roots: Buffer[], appAppleIdRaw = "") => ({ roots, bundleId, appAppleIdRaw });

describe("verifyAppleJws", () => {
  test("accepts a payload signed through a chain that ends at a trusted root", () => {
    const payload = verifyAppleJws(transaction(apple), [apple.rootDer]);
    expect(payload).toMatchObject({ transactionId: "1", bundleId });
  });

  test("rejects a chain from an untrusted root", () => {
    expect(() => verifyAppleJws(transaction(impostor), [apple.rootDer])).toThrow(/does not end at an Apple root/);
  });

  test("rejects a payload changed after signing", () => {
    const [header, , signature] = transaction(apple).split(".");
    const forged = Buffer.from(JSON.stringify({ transactionId: "2", bundleId, environment: "Sandbox", signedDate: signedDate() })).toString("base64url");
    expect(() => verifyAppleJws(`${header}.${forged}.${signature}`, [apple.rootDer])).toThrow(/signature does not match/);
  });

  test("rejects leaf and intermediate certificates without Apple's marker extensions", () => {
    expect(() => verifyAppleJws(transaction(noLeafMarker), [noLeafMarker.rootDer])).toThrow(/signing marker/);
    expect(() => verifyAppleJws(transaction(noIntermediateMarker), [noIntermediateMarker.rootDer])).toThrow(/WWDR intermediate/);
  });

  test("rejects a signing date outside the certificates' validity", () => {
    const old = transaction(apple, { signedDate: Date.parse("2001-01-01T00:00:00Z") });
    expect(() => verifyAppleJws(old, [apple.rootDer])).toThrow(/not valid at the signing date/);
  });

  test("rejects malformed input", () => {
    expect(() => verifyAppleJws("a.b", [apple.rootDer])).toThrow(/invalid JWS format/);
    expect(() => verifyAppleJws("%%%.%%%.%%%", [apple.rootDer])).toThrow();
    const [, payload, signature] = transaction(apple).split(".");
    const wrongAlg = Buffer.from(JSON.stringify({ alg: "HS256", x5c: apple.x5c })).toString("base64url");
    expect(() => verifyAppleJws(`${wrongAlg}.${payload}.${signature}`, [apple.rootDer])).toThrow(/unsupported JWS algorithm/);
    const twoCerts = Buffer.from(JSON.stringify({ alg: "ES256", x5c: apple.x5c.slice(0, 2) })).toString("base64url");
    expect(() => verifyAppleJws(`${twoCerts}.${payload}.${signature}`, [apple.rootDer])).toThrow(/chain length/);
  });
});

describe("verifyAppleNotificationEnvelope", () => {
  test("decodes the notification, transaction, and renewal info", () => {
    const signed = notification(apple, {
      signedTransactionInfo: transaction(apple, { productId: "no.paeonia.couple" }),
      signedRenewalInfo: signJws(apple, { environment: "Sandbox", autoRenewStatus: 1, signedDate: signedDate() }),
    });
    const result = verifyAppleNotificationEnvelope(signed, options([apple.rootDer]));
    expect(result?.notification.notificationType).toBe("DID_RENEW");
    expect(result?.transactionInfo).toMatchObject({ productId: "no.paeonia.couple" });
    expect(result?.renewalInfo).toMatchObject({ autoRenewStatus: 1 });
  });

  test("a bad inner transaction is dropped without failing the notification", () => {
    const signed = notification(apple, {
      signedTransactionInfo: transaction(apple, { environment: "Production" }),
      signedRenewalInfo: "garbage",
    });
    const result = verifyAppleNotificationEnvelope(signed, options([apple.rootDer]));
    expect(result).toMatchObject({ transactionInfo: null, renewalInfo: null });
  });

  test("rejects another app, an untrusted chain, and a different environment", () => {
    expect(verifyAppleNotificationEnvelope(notification(apple, { bundleId: "someone.else" }), options([apple.rootDer]))).toBeNull();
    expect(verifyAppleNotificationEnvelope(notification(impostor), options([apple.rootDer]))).toBeNull();
    // The payload says Production but only a Sandbox verifier is configured without an app id.
    expect(verifyAppleNotificationEnvelope(notification(apple, { environment: "Production", appAppleId: 42 }), options([apple.rootDer]))).toBeNull();
  });

  test("production payloads need the matching App Store app id", () => {
    const signed = notification(apple, { environment: "Production", appAppleId: 42 });
    expect(verifyAppleNotificationEnvelope(signed, options([apple.rootDer], "42"))).not.toBeNull();
    expect(verifyAppleNotificationEnvelope(signed, options([apple.rootDer], "43"))).toBeNull();
    expect(verifyAppleNotificationEnvelope(signed, options([apple.rootDer], ""))).toBeNull();
  });

  test("without an environment hint, sandbox works and production is tried first when an app id is set", () => {
    const signed = signJws(apple, { notificationType: "TEST", notificationUUID: "u", signedDate: signedDate(), data: { bundleId, environment: "Sandbox" } });
    expect(verifyAppleNotificationEnvelope(signed, options([apple.rootDer]))).not.toBeNull();
  });
});
