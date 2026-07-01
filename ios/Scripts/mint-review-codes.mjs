#!/usr/bin/env node
// Mint App Review demo access codes.
//
// Run this before every App Store submission. It:
//   1. Ensures three reusable demo partner accounts exist (auth users + profiles).
//   2. Revokes any previously issued review codes.
//   3. Resets each demo partner's world (deletes their prior demo couple and all
//      couple-owned data via the couple-delete cascade, plus the seeded expired
//      subscription) so every review cycle starts clean.
//   4. Issues three fresh 6-char codes and prints them to paste into App Review
//      notes. Only the code hashes are stored in the database.
//
// Because this deletes the previous cycle's demo couples, only run it when you
// are starting a new review cycle (not while a review is mid-flight).
//
// Reads credentials from the repo-root .env (git-ignored):
//   SUPABASE_URL         e.g. https://api.paeonia.no
//   SUPABASE_SECRET_KEY  Supabase secret/service-role key (SUPABASE_SERVICE_ROLE_KEY also accepted)
//
// Usage:
//   pnpm review-codes:mint
//   (or: node ios/Scripts/mint-review-codes.mjs)

import { randomBytes, randomInt } from "node:crypto";
import { join } from "node:path";

// Load the repo-root .env so the pnpm command and a bare `node ...` both work
// without exporting vars by hand. A real shell/CI environment still works if the
// file is absent.
try {
  process.loadEnvFile(join(import.meta.dirname, "..", "..", ".env"));
} catch {
  // No .env file — fall back to the ambient environment.
}

const SUPABASE_URL = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_KEY = requireEnv("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY");

const SLOT_COUNT = 3;
// Neutral, non-partner-sounding demo names (the copy must never read like it came
// from the reviewer's real partner).
const DEMO_NAMES = ["Alex", "Sam", "Nora"];
// Crockford-style base32 minus I/L/O, matching the app's PairingInviteCode alphabet.
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 6;
const EXPIRES_DAYS = 30;
// One reviewer per code. A seeded demo partner can only be in one active couple
// at a time, so a second reviewer must use a *different* code; that is why we
// mint one code per demo partner rather than one shared code.
const MAX_REDEMPTIONS = 1;

main().catch((error) => {
  console.error(`\n✗ ${error.message}`);
  process.exit(1);
});

async function main() {
  console.log("Minting App Review demo codes…\n");

  // 1. Ensure the three demo partners exist and are registered.
  const registered = await rpc("list_review_demo_partners");
  const bySlot = new Map((registered ?? []).map((row) => [row.slot, row]));

  const partners = [];
  for (let slot = 1; slot <= SLOT_COUNT; slot++) {
    const name = DEMO_NAMES[slot - 1];
    let userId = bySlot.get(slot)?.user_id;
    const createdNow = !userId;

    if (createdNow) {
      userId = await createDemoPartnerUser(slot);
      console.log(`  · created demo partner for slot ${slot}`);
    }

    try {
      await rpc("register_review_demo_partner", {
        p_slot: slot,
        p_user_id: userId,
        p_display_name: name,
      });
    } catch (error) {
      // If registration fails for a user we just created, delete the orphan so a
      // retry does not leak a second dormant auth user for this slot. (An
      // unregistered user is invisible to list_review_demo_partners, so the next
      // run would otherwise mint yet another one.)
      if (createdNow) {
        await deleteDemoPartnerUser(userId).catch(() => {});
      }
      throw error;
    }
    partners.push({ slot, userId, name });
  }

  // 2 + 3. Revoke old codes, then wipe the previous cycle's demo couples.
  const revoked = await rpc("revoke_review_access_codes");
  const clearedCouples = await rpc("reset_review_demo");
  console.log(
    `  · revoked ${revoked ?? 0} old code(s), cleared ${clearedCouples ?? 0} demo couple(s)\n`,
  );

  // 4. Issue fresh codes.
  const expiresAt = new Date(Date.now() + EXPIRES_DAYS * 86_400_000).toISOString();
  const issued = [];
  for (const partner of partners) {
    const code = generateCode();
    await rpc("issue_review_access_code", {
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

function printResult(issued, expiresAt) {
  console.log("✓ Review codes ready. Paste these into App Review notes:\n");
  for (const { code, name } of issued) {
    console.log(`    ${code}   (pairs with demo partner “${name}”)`);
  }
  console.log(
    `\n  Valid until ${expiresAt}. Give each reviewer a different code — one code pairs one reviewer with one demo partner.`,
  );
  console.log("  After the app is approved, run: node ios/Scripts/revoke-review-codes.mjs\n");
}

// Creates a dormant auth user for a demo partner. It never signs in; it exists so
// the couple, profile, and location FKs resolve. A profile is auto-created by the
// auth trigger and then filled in by register_review_demo_partner.
async function createDemoPartnerUser(slot) {
  const email = `review-partner-${slot}-${randomBytes(4).toString("hex")}@paeonia-demo.invalid`;
  const body = {
    email,
    password: randomBytes(24).toString("hex"),
    email_confirm: true,
  };

  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    throw new Error(`admin create user failed (${res.status}): ${await res.text()}`);
  }

  const user = await res.json();
  if (!user?.id) {
    throw new Error(`admin create user returned no id: ${JSON.stringify(user)}`);
  }
  return user.id;
}

// Removes a dormant demo auth user. Used only to roll back a user we created this
// run when its registration failed, so a partial failure does not leak accounts.
async function deleteDemoPartnerUser(userId) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
    headers: authHeaders(),
  });

  if (!res.ok && res.status !== 404) {
    throw new Error(`admin delete user failed (${res.status}): ${await res.text()}`);
  }
}

async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(args ?? {}),
  });

  if (!res.ok) {
    throw new Error(`rpc ${fn} failed (${res.status}): ${await res.text()}`);
  }

  if (res.status === 204) return null;
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

function authHeaders() {
  return {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

function generateCode() {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

function requireEnv(...names) {
  for (const name of names) {
    if (process.env[name]) return process.env[name];
  }
  console.error(`Missing required environment variable: ${names.join(" or ")}`);
  process.exit(1);
}
