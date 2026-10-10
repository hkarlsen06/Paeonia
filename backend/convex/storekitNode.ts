"use node";

import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { appleBundleId } from "./lib/appleStoreKit";
import { APPLE_ROOT_CA_URLS, verifyAppleNotificationEnvelope } from "./lib/appleNotificationVerifier";

let rootCertificates: Promise<Buffer[]> | null = null;

/** Apple's root certificates, fetched once per process. */
function loadAppleRootCertificates(): Promise<Buffer[]> {
  rootCertificates ??= Promise.all(
    APPLE_ROOT_CA_URLS.map(async (url) => {
      const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
      if (!response.ok) {
        throw new Error(`Failed to fetch Apple root certificate: ${url}`);
      }
      return Buffer.from(await response.arrayBuffer());
    }),
  ).catch((error) => {
    rootCertificates = null;
    throw error;
  });
  return rootCertificates;
}

/**
 * Verifies an App Store Server Notification V2 payload against Apple's root
 * certificates and returns the decoded notification, transaction info, and
 * renewal info. Returns null when the payload is not valid.
 */
export const verify_notification = internalAction({
  args: { signedPayload: v.string() },
  handler: async (_ctx, args) => {
    let roots: Buffer[];
    try {
      roots = await loadAppleRootCertificates();
    } catch (error) {
      console.error("[apple-server-notifications] verification failed", error instanceof Error ? error.message : error);
      return null;
    }
    const verified = verifyAppleNotificationEnvelope(args.signedPayload, {
      roots,
      bundleId: appleBundleId(),
      appAppleIdRaw: process.env.APPLE_APP_APPLE_ID ?? "",
    });
    // Convex values cannot carry undefined fields, so round-trip through JSON.
    return verified ? (JSON.parse(JSON.stringify(verified)) as typeof verified) : null;
  },
});
