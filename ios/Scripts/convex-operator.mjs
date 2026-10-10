// Shared helper for the App Review scripts. Runs a Convex operator function on
// the production deployment with `npx convex run` from backend/.
//
// Environment:
//   CONVEX_SELF_HOSTED_URL          defaults to https://api.paeonia.no
//   CONVEX_SELF_HOSTED_ADMIN_KEY    the admin key. When unset, the helper reads
//                                   /srv/paeonia/convex/admin-key over `ssh one-s`.
//
// The Convex CLI needs Node 20, 22, or 24 on PATH. Never write the admin key to
// a file in this repository.

import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const BACKEND_DIR = fileURLToPath(new URL("../../backend/", import.meta.url));
const DEFAULT_URL = "https://api.paeonia.no";
const ADMIN_KEY_SSH_HOST = "one-s";
const ADMIN_KEY_PATH = "/srv/paeonia/convex/admin-key";

let cachedTarget;

function resolveTarget() {
  if (cachedTarget) return cachedTarget;

  const url = (process.env.CONVEX_SELF_HOSTED_URL || DEFAULT_URL).replace(/\/+$/, "");
  let adminKey = process.env.CONVEX_SELF_HOSTED_ADMIN_KEY;
  if (!adminKey) {
    try {
      adminKey = execFileSync("ssh", [ADMIN_KEY_SSH_HOST, "cat", ADMIN_KEY_PATH], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }).trim();
    } catch (error) {
      throw new Error(
        `CONVEX_SELF_HOSTED_ADMIN_KEY is not set and reading ${ADMIN_KEY_PATH} over ssh ${ADMIN_KEY_SSH_HOST} failed: ${error.message}`,
      );
    }
  }
  if (!adminKey) {
    throw new Error("The Convex admin key is empty.");
  }

  cachedTarget = { url, adminKey };
  return cachedTarget;
}

/** The deployment URL the next call will use. */
export function convexTargetUrl() {
  return resolveTarget().url;
}

/**
 * Runs `<module>:<function>` with JSON args and returns the parsed result, or
 * null when the function returns nothing.
 */
export function runConvex(functionName, args = {}) {
  const { url, adminKey } = resolveTarget();
  let stdout;
  try {
    stdout = execFileSync(
      "npx",
      [
        "convex",
        "run",
        functionName,
        JSON.stringify(args),
        "--codegen",
        "disable",
        "--typecheck",
        "disable",
      ],
      {
        cwd: BACKEND_DIR,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
        env: {
          ...process.env,
          CONVEX_SELF_HOSTED_URL: url,
          CONVEX_SELF_HOSTED_ADMIN_KEY: adminKey,
          // backend/.env.local points `convex dev` at a local deployment. The CLI
          // refuses to run when CONVEX_DEPLOYMENT is set next to a self-hosted URL.
          CONVEX_DEPLOYMENT: "",
        },
      },
    );
  } catch (error) {
    const detail = String(error.stderr || error.stdout || error.message).trim();
    throw new Error(`convex run ${functionName} failed: ${detail}`);
  }

  const text = stdout.trim();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`convex run ${functionName} returned output that is not JSON: ${text}`);
  }
}
