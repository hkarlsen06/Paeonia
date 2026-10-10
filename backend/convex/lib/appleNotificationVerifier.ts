"use node";

// Verifies Apple's signed App Store payloads (JWS with an x5c certificate
// chain) against Apple's root certificates. Port of the checks that
// `@apple/app-store-server-library` SignedDataVerifier runs with online
// checks off, written against node:crypto so no dependency is needed.
import { createPublicKey, verify as verifySignature, X509Certificate } from "node:crypto";

export const APPLE_ROOT_CA_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
];

// DER encodings of the Apple marker extensions the leaf and intermediate must carry.
// 1.2.840.113635.100.6.11.1 (Mac App Store receipt signing) and 1.2.840.113635.100.6.2.1 (WWDR intermediate).
const LEAF_MARKER_OID = Buffer.from("060a2a864886f76364060b01", "hex");
const INTERMEDIATE_MARKER_OID = Buffer.from("060a2a864886f76364060201", "hex");

export type AppleSigningEnvironment = "Sandbox" | "Production";

export type AppleVerifierConfig = {
  roots: Buffer[];
  environment: AppleSigningEnvironment;
  bundleId: string;
  /** Required when `environment` is Production. */
  appAppleId?: number;
};

export class AppleVerificationError extends Error {
  override name = "AppleVerificationError";
}

function reject(reason: string): never {
  throw new AppleVerificationError(reason);
}

function decodeSegment(segment: string): Record<string, any> {
  try {
    return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  } catch {
    return reject("malformed JWS segment");
  }
}

function certificateIsValidAt(certificate: X509Certificate, at: Date): boolean {
  return new Date(certificate.validFrom) <= at && at <= new Date(certificate.validTo);
}

/**
 * Checks the JWS chain and signature, and returns the decoded payload. The
 * header carries leaf, intermediate, and root; the intermediate must be signed
 * by one of `roots`, and the three trusted certificates must be valid at the
 * signing date.
 */
export function verifyAppleJws(jws: string, roots: Buffer[]): Record<string, any> {
  const parts = jws.split(".");
  if (parts.length !== 3 || parts.some((part) => part === "")) {
    return reject("invalid JWS format");
  }
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeSegment(encodedHeader);
  const payload = decodeSegment(encodedPayload);

  if (header.alg !== "ES256") {
    return reject("unsupported JWS algorithm");
  }
  const chain: unknown = header.x5c;
  if (!Array.isArray(chain) || chain.length !== 3 || chain.some((item) => typeof item !== "string")) {
    return reject("invalid certificate chain length");
  }
  const [leaf, intermediate] = (chain as string[]).slice(0, 2).map((item) => new X509Certificate(Buffer.from(item, "base64")));

  const trustedRoot = roots
    .map((der) => new X509Certificate(der))
    .find((candidate) => intermediate.checkIssued(candidate) && intermediate.verify(candidate.publicKey));
  if (!trustedRoot) {
    return reject("certificate chain does not end at an Apple root");
  }
  const signedAt = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : new Date();
  for (const certificate of [leaf, intermediate, trustedRoot]) {
    if (!certificateIsValidAt(certificate, signedAt)) {
      return reject("certificate is not valid at the signing date");
    }
  }
  if (!leaf.checkIssued(intermediate) || !leaf.verify(intermediate.publicKey)) {
    return reject("leaf certificate is not signed by the intermediate");
  }
  if (!intermediate.ca || intermediate.raw.indexOf(INTERMEDIATE_MARKER_OID) === -1) {
    return reject("intermediate certificate is not an Apple WWDR intermediate");
  }
  if (leaf.raw.indexOf(LEAF_MARKER_OID) === -1) {
    return reject("leaf certificate does not carry the Apple signing marker");
  }

  const key = createPublicKey(leaf.publicKey.export({ type: "spki", format: "pem" }));
  const signature = Buffer.from(encodedSignature, "base64url");
  const valid =
    signature.length === 64 &&
    verifySignature("sha256", Buffer.from(`${encodedHeader}.${encodedPayload}`), { key, dsaEncoding: "ieee-p1363" }, signature);
  if (!valid) {
    return reject("signature does not match");
  }
  return payload;
}

/** Port of `SignedDataVerifier.verifyAndDecodeNotification`. */
export function verifyNotificationJws(jws: string, config: AppleVerifierConfig): Record<string, any> {
  const notification = verifyAppleJws(jws, config.roots);
  const container = notification.data ?? notification.summary ?? notification.appData ?? notification.externalPurchaseToken;
  const bundleId = container?.bundleId;
  const appAppleId = container?.appAppleId;
  const environment = container?.environment;
  if (bundleId !== config.bundleId || (config.environment === "Production" && appAppleId !== config.appAppleId)) {
    return reject("invalid app identifier");
  }
  if (environment !== config.environment) {
    return reject("invalid environment");
  }
  return notification;
}

/** Port of `SignedDataVerifier.verifyAndDecodeTransaction`. */
export function verifyTransactionJws(jws: string, config: AppleVerifierConfig): Record<string, any> {
  const transaction = verifyAppleJws(jws, config.roots);
  if (transaction.bundleId !== config.bundleId) {
    return reject("invalid app identifier");
  }
  if (transaction.environment !== config.environment) {
    return reject("invalid environment");
  }
  return transaction;
}

/** Port of `SignedDataVerifier.verifyAndDecodeRenewalInfo`. */
export function verifyRenewalInfoJws(jws: string, config: AppleVerifierConfig): Record<string, any> {
  const renewal = verifyAppleJws(jws, config.roots);
  if (renewal.environment !== config.environment) {
    return reject("invalid environment");
  }
  return renewal;
}

export type VerifiedAppleNotification = {
  notification: Record<string, any>;
  transactionInfo: Record<string, any> | null;
  renewalInfo: Record<string, any> | null;
};

function environmentHint(signedPayload: string): AppleSigningEnvironment | null {
  try {
    const payload = decodeSegment(signedPayload.split(".")[1] ?? "");
    const environment = payload?.data?.environment ?? payload?.summary?.environment ?? payload?.appData?.environment;
    return environment === "Production" || environment === "Sandbox" ? environment : null;
  } catch {
    return null;
  }
}

/**
 * Port of `verifyAppleNotification` plus the transaction and renewal decoding
 * of the apple-server-notifications Edge Function. The payload names its
 * environment, which picks the verifier. Without a hint, Production is tried
 * first when an App Store app id is configured, then Sandbox.
 * Returns null when no verifier accepts the payload.
 */
export function verifyAppleNotificationEnvelope(
  signedPayload: string,
  options: { roots: Buffer[]; bundleId: string; appAppleIdRaw: string },
): VerifiedAppleNotification | null {
  const sandbox: AppleVerifierConfig = { roots: options.roots, environment: "Sandbox", bundleId: options.bundleId };
  const production = (): AppleVerifierConfig => {
    const appAppleId = Number(options.appAppleIdRaw);
    if (!Number.isFinite(appAppleId) || appAppleId <= 0) {
      throw new Error("APPLE_APP_APPLE_ID must be set for Production Apple notifications");
    }
    return { roots: options.roots, environment: "Production", bundleId: options.bundleId, appAppleId };
  };

  let configs: AppleVerifierConfig[];
  try {
    const hint = environmentHint(signedPayload);
    configs =
      hint === "Sandbox"
        ? [sandbox]
        : hint === "Production"
          ? [production()]
          : options.appAppleIdRaw
            ? [production(), sandbox]
            : [sandbox];
  } catch (error) {
    console.error("[apple-server-notifications] verification failed", error instanceof Error ? error.message : error);
    return null;
  }

  for (const config of configs) {
    let notification: Record<string, any>;
    try {
      notification = verifyNotificationJws(signedPayload, config);
    } catch (error) {
      console.warn("[apple-server-notifications] verification attempt failed", error instanceof Error ? error.message : error);
      continue;
    }
    return {
      notification,
      transactionInfo: decodeOrNull(notification.data?.signedTransactionInfo, (jws) => verifyTransactionJws(jws, config)),
      renewalInfo: decodeOrNull(notification.data?.signedRenewalInfo, (jws) => verifyRenewalInfoJws(jws, config)),
    };
  }
  console.error("[apple-server-notifications] signed payload verification failed");
  return null;
}

function decodeOrNull(
  jws: unknown,
  verify: (jws: string) => Record<string, any>,
): Record<string, any> | null {
  if (typeof jws !== "string" || jws === "") {
    return null;
  }
  try {
    return verify(jws);
  } catch (error) {
    console.error("[apple-server-notifications] decode failed", error instanceof Error ? error.message : error);
    return null;
  }
}
