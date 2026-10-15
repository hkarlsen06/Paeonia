import { expect, test } from "vitest";
import { internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { addDaysToInstant, nowIso } from "./lib/time";
import { newTest } from "./test.setup";

test("prune_expired_rows deletes client operations and outbox rows older than 30 days", async () => {
  const t = newTest();
  const now = nowIso();
  const old = addDaysToInstant(now, -31);
  const recent = addDaysToInstant(now, -29);
  await t.run(async (ctx) => {
    for (const created_at of [old, recent]) {
      await ctx.db.insert("client_operations", {
        id: newUuid(),
        user_id: newUuid(),
        client_operation_id: newUuid(),
        client_id: newUuid(),
        client_sequence: 1,
        local_created_at: created_at,
        operation_kind: "test",
        idempotency_scope: "test",
        request_hash: "x",
        status: "succeeded",
        attempt_count: 1,
        last_attempt_at: created_at,
        created_at,
        updated_at: created_at,
      });
      await ctx.db.insert("widget_push_outbox", {
        id: newUuid(),
        recipient_user_id: newUuid(),
        target_widget_device_id: newUuid(),
        widget_push_token_hash: "x",
        apns_environment: "production",
        kind: "widget_updated",
        payload: {},
        scheduled_for: created_at,
        sent_at: created_at,
        created_at,
      });
    }
  });

  await t.mutation(internal.retention.prune_expired_rows, {});

  const left = await t.run(async (ctx) => ({
    operations: (await ctx.db.query("client_operations").collect()).map((row) => row.created_at),
    widgetPushes: (await ctx.db.query("widget_push_outbox").collect()).map((row) => row.created_at),
  }));
  expect(left).toEqual({ operations: [recent], widgetPushes: [recent] });
});
