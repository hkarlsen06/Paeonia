import { adminClerkUserIds } from "./admins";
import type { WriterCtx } from "./db";
import { enqueueNotificationForUser } from "./notifications";

/** What an admin is told waits for them. The push says which kind and nothing else. */
export type AdminCaseKind = "content_report" | "correction_request";

/**
 * Queues one push to every admin when a report or a correction request is filed, so it is seen
 * within the three working days the privacy policy promises. The payload holds only the kind of
 * case: never who filed it, about whom, or what it says. The admin reads the case in the admin
 * area (`admin:list_open_reports`, `admin:list_open_correction_requests`). Deduped per case.
 */
export async function alertAdminsOfNewCase(ctx: WriterCtx, caseKind: AdminCaseKind, caseId: string): Promise<void> {
  for (const clerkUserId of adminClerkUserIds()) {
    const admin = await ctx.db
      .query("users")
      .withIndex("by_clerk_user_id", (q) => q.eq("clerk_user_id", clerkUserId))
      .unique();
    if (!admin) continue;
    await enqueueNotificationForUser(ctx, {
      recipient_user_id: admin.id,
      kind: "admin_case_opened",
      payload: { type: "admin_case_opened", case_kind: caseKind },
      dedupe_key: `admin_case_opened:${caseId}`,
    });
  }
}
