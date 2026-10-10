import { fail } from "./errors";
import type { ReaderCtx } from "./db";

/**
 * Port of `internal.reject_pending_account_client_operation`.
 * Call before writing client_operations, latest_partner_locations,
 * location_sharing_preferences, notification_preferences, privacy_requests
 * (insert), user_devices, and widget_push_devices for `userId`.
 */
export async function assertNoPendingAccountDeletion(ctx: ReaderCtx, userId: string): Promise<void> {
  const job = await ctx.db
    .query("account_deletion_jobs")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .first();
  if (job) {
    fail("42501", "account deletion is in progress");
  }
}
