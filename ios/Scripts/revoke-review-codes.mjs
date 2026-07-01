#!/usr/bin/env node
// Revoke all active App Review demo access codes.
//
// Run this after the app version is approved so the codes printed in App Review
// notes can no longer be redeemed by anyone who saw them. The demo partner
// accounts and their registry entries are left in place for the next cycle; the
// leftover demo couple data is unreachable and gets wiped by the next mint.
//
// Requires (never commit these):
//   SUPABASE_URL                 e.g. https://api.paeonia.no
//   SUPABASE_SERVICE_ROLE_KEY    service-role key
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node ios/Scripts/revoke-review-codes.mjs

const SUPABASE_URL = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

main().catch((error) => {
  console.error(`\n✗ ${error.message}`);
  process.exit(1);
});

async function main() {
  const revoked = await rpc("revoke_review_access_codes");
  console.log(`✓ Revoked ${revoked ?? 0} active review code(s).`);
}

async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(args ?? {}),
  });

  if (!res.ok) {
    throw new Error(`rpc ${fn} failed (${res.status}): ${await res.text()}`);
  }

  if (res.status === 204) return null;
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing required environment variable: ${name}`);
    process.exit(1);
  }
  return value;
}
