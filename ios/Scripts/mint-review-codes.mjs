#!/usr/bin/env bun
// Mint App Review demo access codes.
//
// Run this before every App Store submission. It:
//   1. Checks that three reusable demo partner accounts are registered.
//   2. Revokes any previously issued review codes.
//   3. Resets each demo partner's world (deletes their prior demo couple and all
//      couple-owned data, plus the seeded expired subscription) so every review
//      cycle starts clean.
//   4. Issues three fresh 6-char codes and prints them to paste into App Review
//      notes. Only the code hashes are stored in the database.
//
// Because this deletes the previous cycle's demo couples, only run it when you
// are starting a new review cycle (not while a review is mid-flight).
//
// It calls the Convex operator functions in backend/convex/review.ts on the
// production deployment with `npx convex run` from backend/. See
// ios/Scripts/convex-operator.mjs for the environment it reads
// (CONVEX_SELF_HOSTED_URL, CONVEX_SELF_HOSTED_ADMIN_KEY).
//
// Demo partners are ordinary Paeonia users, and Convex only creates users when a
// Clerk account signs in. To add a partner, sign in once on a spare Clerk
// account (Apple or Google) in the app, copy that user's `id` from the `users`
// table in the Convex dashboard, and pass it here:
//   --partner SLOT=USER_ID     (SLOT is 1, 2, or 3; repeat for each new partner)
// A slot that is already registered does not need the flag. Passing the flag for
// a registered slot replaces that slot's partner.
//
// Usage:
//   bun run review-codes:mint
//   bun run review-codes:mint -- --partner 1=<uuid> --partner 2=<uuid> --partner 3=<uuid>
//   (or: bun ios/Scripts/mint-review-codes.mjs)

import { randomInt } from "node:crypto";
import { convexTargetUrl, runConvex } from "./convex-operator.mjs";

const SLOT_COUNT = 3;
// Neutral, non-partner-sounding demo names (the copy must never read like it came
// from the reviewer's real partner).
const DEMO_NAMES = ["Alex", "Sam", "Nora"];
// Crockford-style base32 minus I/L/O, matching the app's PairingInviteCode alphabet.
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 6;
const EXPIRES_DAYS = 30;
// One reviewer per code. A seeded demo partner can only be in one active couple
// at a time, so a second reviewer must use a different code; that is why we
// mint one code per demo partner rather than one shared code.
const MAX_REDEMPTIONS = 1;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

try {
  main();
} catch (error) {
  console.error(`\n✗ ${error.message}`);
  process.exit(1);
}

function main() {
  const requested = parsePartnerFlags(process.argv.slice(2));
  console.log(`Minting App Review demo codes on ${convexTargetUrl()}...\n`);

  // 1. Resolve a user for every demo slot before changing anything.
  const registered = runConvex("review:list_review_demo_partners") ?? [];
  const bySlot = new Map(registered.map((row) => [row.slot, row]));

  const partners = [];
  const missing = [];
  for (let slot = 1; slot <= SLOT_COUNT; slot++) {
    const userId = requested.get(slot) ?? bySlot.get(slot)?.user_id;
    if (!userId) {
      missing.push(slot);
      continue;
    }
    partners.push({ slot, userId, name: DEMO_NAMES[slot - 1] });
  }
  if (missing.length > 0) {
    throw new Error(
      `No demo partner is registered for slot ${missing.join(", ")}. ` +
        "Sign in once on a spare Clerk account in the app, copy that user's id from the " +
        "users table in the Convex dashboard, and rerun with " +
        missing.map((slot) => `--partner ${slot}=<uuid>`).join(" ") +
        ".",
    );
  }

  // Register (or refresh) each partner so its profile is complete and visible.
  for (const partner of partners) {
    runConvex("review:register_review_demo_partner", {
      p_slot: partner.slot,
      p_user_id: partner.userId,
      p_display_name: partner.name,
    });
  }

  // 2 + 3. Revoke old codes, then wipe the previous cycle's demo couples.
  const revoked = runConvex("review:revoke_review_access_codes");
  const clearedCouples = runConvex("review:reset_review_demo");
  console.log(
    `  · revoked ${revoked ?? 0} old code(s), cleared ${clearedCouples ?? 0} demo couple(s)\n`,
  );

  // 4. Issue fresh codes.
  const expiresAt = new Date(Date.now() + EXPIRES_DAYS * 86_400_000).toISOString();
  const issued = [];
  for (const partner of partners) {
    const code = generateCode();
    runConvex("review:issue_review_access_code", {
      p_code: code,
      p_seeded_partner_user_id: partner.userId,
      p_scenario: "pre_paired_paywalled",
      p_expires_at: expiresAt,
      p_max_redemptions: MAX_REDEMPTIONS,
    });
    issued.push({ ...partner, code });
  }

  printResult(issued, expiresAt);
}

function parsePartnerFlags(argv) {
  const requested = new Map();
  for (let index = 0; index < argv.length; index++) {
    const flag = argv[index];
    if (flag === "--") continue;
    if (flag !== "--partner") {
      throw new Error(`Unknown argument: ${flag}. The only flag is --partner SLOT=USER_ID.`);
    }
    const value = argv[++index] ?? "";
    const [slotText, userId] = value.split("=");
    const slot = Number(slotText);
    if (!Number.isInteger(slot) || slot < 1 || slot > SLOT_COUNT || !UUID_PATTERN.test(userId ?? "")) {
      throw new Error(`Bad --partner value "${value}". Use SLOT=USER_ID, with SLOT from 1 to ${SLOT_COUNT}.`);
    }
    requested.set(slot, userId.toLowerCase());
  }
  return requested;
}

function printResult(issued, expiresAt) {
  console.log("✓ Review codes ready. Paste these into App Review notes:\n");
  for (const { code, name } of issued) {
    console.log(`    ${code}   (pairs with demo partner "${name}")`);
  }
  console.log(
    `\n  Valid until ${expiresAt}. Give each reviewer a different code. One code pairs one reviewer with one demo partner.`,
  );
  console.log("  After the app is approved, run: bun ios/Scripts/revoke-review-codes.mjs\n");
}

function generateCode() {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return code;
}
