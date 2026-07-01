#!/usr/bin/env node
// Revoke all active App Review demo access codes.
//
// Run this after the app version is approved so the codes printed in App Review
// notes can no longer be redeemed by anyone who saw them. The demo partner
// accounts and their registry entries are left in place for the next cycle; the
// leftover demo couple data is unreachable and gets wiped by the next mint.
//
// Reads credentials from the repo-root .env (git-ignored):
//   SUPABASE_URL         e.g. https://api.paeonia.no
//   SUPABASE_SECRET_KEY  Supabase secret/service-role key (SUPABASE_SERVICE_ROLE_KEY also accepted)
//
// Usage:
//   pnpm review-codes:revoke
//   (or: node ios/Scripts/revoke-review-codes.mjs)

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

function requireEnv(...names) {
  for (const name of names) {
    if (process.env[name]) return process.env[name];
  }
  console.error(`Missing required environment variable: ${names.join(" or ")}`);
  process.exit(1);
}
