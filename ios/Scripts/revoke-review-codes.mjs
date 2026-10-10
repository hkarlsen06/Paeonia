#!/usr/bin/env bun
// Revoke all active App Review demo access codes.
//
// Run this after the app version is approved so the codes printed in App Review
// notes can no longer be redeemed by anyone who saw them. The demo partner
// accounts and their registry entries are left in place for the next cycle; the
// leftover demo couple data is unreachable and gets wiped by the next mint.
//
// Calls the Convex operator function review:revoke_review_access_codes on the
// production deployment with `npx convex run` from backend/. See
// ios/Scripts/convex-operator.mjs for the environment it reads
// (CONVEX_SELF_HOSTED_URL, CONVEX_SELF_HOSTED_ADMIN_KEY).
//
// Usage:
//   bun run review-codes:revoke
//   (or: bun ios/Scripts/revoke-review-codes.mjs)

import { convexTargetUrl, runConvex } from "./convex-operator.mjs";

try {
  const target = convexTargetUrl();
  const revoked = runConvex("review:revoke_review_access_codes");
  console.log(`✓ Revoked ${revoked ?? 0} active review code(s) on ${target}.`);
} catch (error) {
  console.error(`\n✗ ${error.message}`);
  process.exit(1);
}
