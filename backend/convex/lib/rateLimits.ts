import { HOUR, MINUTE, RateLimiter } from "@convex-dev/rate-limiter";
import { components } from "../_generated/api";
import type { MutationCtx } from "../_generated/server";
import { fail } from "./errors";

/**
 * Every rate limit, keyed by the Paeonia user id. Content limits sit far above
 * what a couple does, and their capacity lets a phone that was offline for days
 * send its whole backlog at once (a chat message holds up to 4 photos, a memory
 * up to 5 per partner).
 */
const LIMITS = {
  // Replaces the SQL ten-minute window: 30 invite code tries per user, and 10
  // failed tries of one code. `pairing.ts` consumes them where the SQL logged an attempt.
  pairingInviteAttempt: { kind: "token bucket", rate: 30, period: 10 * MINUTE },
  pairingInviteCodeFailure: { kind: "token bucket", rate: 10, period: 10 * MINUTE },
  pairingInviteCreate: { kind: "token bucket", rate: 30, period: HOUR },
  threadMessage: { kind: "token bucket", rate: 600, period: HOUR, capacity: 300 },
  memoryCreate: { kind: "token bucket", rate: 100, period: HOUR, capacity: 100 },
  mediaUpload: { kind: "token bucket", rate: 300, period: HOUR, capacity: 300 },
  // One call per batch of Home heart taps, so a person tapping for a minute uses a few.
  heartsSend: { kind: "token bucket", rate: 120, period: HOUR, capacity: 60 },
  contentReport: { kind: "token bucket", rate: 10, period: HOUR, capacity: 10 },
} as const;

export const rateLimiter = new RateLimiter(components.rateLimiter, LIMITS);

export type RateLimitName = keyof typeof LIMITS;

/**
 * Takes one from the user's `name` bucket, or fails with
 * `53300 too many requests: <name>` when it is empty. Call it inside the
 * `runClientOperation` callback, so a replay of a stored write costs nothing and
 * a refused write rolls back with the mutation. The app keeps a write refused
 * with `53300` and sends it again later.
 */
export async function consumeRateLimit(ctx: MutationCtx, name: RateLimitName, userId: string): Promise<void> {
  const { ok } = await rateLimiter.limit(ctx, name, { key: userId });
  if (!ok) fail("53300", `too many requests: ${name}`);
}
