import { Workpool } from "@convex-dev/workpool";
import { components } from "../_generated/api";

/**
 * Report snapshot copies (moderation.ts) and Clerk account deletes
 * (accountDeletion.ts). Actions retry by default: 5 tries, about 1, 2, 4 and 8
 * minutes apart. Mutations never retry here, because Convex already retries them.
 */
export const backgroundWorkpool = new Workpool(components.backgroundWorkpool, {
  // Both jobs are rare. A copy holds one media file in memory, so keep this low.
  maxParallelism: 5,
  retryActionsByDefault: true,
  defaultRetryBehavior: { maxAttempts: 5, initialBackoffMs: 60_000, base: 2 },
});
