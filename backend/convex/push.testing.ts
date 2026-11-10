// Push helpers for the tests. The two dots in the file name keep Convex from bundling it, and
// vitest does not run it.
import type { WorkId } from "@convex-dev/workpool";
import { internal } from "./_generated/api";
import type { PreparedNotification } from "./lib/apns";
import { transactionIso, type TestConvex } from "./test.setup";
import { pushStatus } from "./lib/pushStatus";
import type { PushOutcome } from "./pushQueue";

/** Hands one finished send to `push_finished`, as pushWorkpool does once APNs answered or the retries ran out. */
export async function finishPush(
  t: TestConvex,
  context: { kind: "app" | "widget"; outbox_id: string },
  result: { kind: "success"; returnValue: PushOutcome } | { kind: "failed"; error: string },
): Promise<void> {
  await t.mutation(internal.pushQueue.push_finished, { workId: "test-work" as WorkId, context, result });
}

/**
 * Stands in for the APNs sends. Tests have no APNs keys, so `push:send_push` leaves every row
 * unsent. This runs the send-time checks on each due unsent notification, oldest first, marks the
 * ones that pass as sent, and returns them. A later call skips them.
 */
export async function deliverDuePushes(t: TestConvex): Promise<PreparedNotification[]> {
  const records = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
  const now = await transactionIso(t);
  const rows = records
    .filter((row) => pushStatus(row) === "pending" && row.scheduled_for <= now)
    .sort((a, b) => a.scheduled_for.localeCompare(b.scheduled_for) || a._creationTime - b._creationTime);
  const delivered: PreparedNotification[] = [];
  for (const row of rows) {
    const prepared = await t.mutation(internal.pushQueue.prepare_notification, { outbox_id: row.id });
    if (!prepared) continue;
    await finishPush(t, { kind: "app", outbox_id: row.id }, {
      kind: "success",
      returnValue: { device_id: prepared.target_device_id, invalid_token: false },
    });
    delivered.push(prepared);
  }
  return delivered;
}
