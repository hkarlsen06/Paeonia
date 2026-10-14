// Push helpers for the tests. The two dots in the file name keep Convex from bundling it, and
// vitest does not run it.
import { internal } from "./_generated/api";
import type { PreparedNotification } from "./lib/apns";
import { nowIso } from "./lib/time";
import type { TestConvex } from "./test.setup";

/**
 * Stands in for the APNs sends. Tests have no APNs keys, so `push:send_push` leaves every row
 * unsent. This runs the send-time checks on each due unsent notification, oldest first, marks the
 * ones that pass as sent, and returns them. A later call skips them.
 */
export async function deliverDuePushes(t: TestConvex): Promise<PreparedNotification[]> {
  const now = nowIso();
  const rows = (await t.run((ctx) => ctx.db.query("notification_outbox").collect()))
    .filter((row) => row.sent_at === undefined && row.failed_at === undefined && row.scheduled_for <= now)
    .sort((a, b) => a.scheduled_for.localeCompare(b.scheduled_for) || a._creationTime - b._creationTime);
  const delivered: PreparedNotification[] = [];
  for (const row of rows) {
    const prepared = await t.mutation(internal.pushQueue.prepare_notification, { outbox_id: row.id });
    if (!prepared) continue;
    await t.mutation(internal.pushQueue.mark_push_result, { kind: "app", outbox_id: row.id });
    delivered.push(prepared);
  }
  return delivered;
}
