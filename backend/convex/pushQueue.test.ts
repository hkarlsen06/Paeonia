import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import type { ApnsSendResult } from "./lib/apns";
import { drainAppNotifications, drainWidgetPushes, type DrainCtx } from "./lib/apnsDrain";
import { newUuid } from "./lib/ids";
import { insertNotificationOutbox, insertWidgetPushOutbox } from "./lib/notifications";
import { addDevice, createSignedInUser, newTest, type TestConvex } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const NOW = "2026-10-10T12:00:00.000Z";
const EARLIER = "2026-10-10T11:00:00.000Z";

async function setup() {
  const t = newTest();
  const user = await createSignedInUser(t, { name: "Receiver" });
  const device = await addDevice(t, user.userId, { token: "device-one" });
  return { t, user, device };
}

type Kind = Parameters<typeof insertNotificationOutbox>[1]["kind"];

async function queue(
  t: TestConvex,
  user: { userId: string },
  device: { id: string; push_token_hash: string },
  options: { kind?: Kind; scheduledFor?: string; pushType?: "alert" | "background"; dedupe?: string } = {},
) {
  const pushType = options.pushType ?? "alert";
  await t.run((ctx) =>
    insertNotificationOutbox(ctx, {
      recipient_user_id: user.userId,
      target_device_id: device.id,
      push_token_hash: device.push_token_hash,
      apns_environment: "sandbox",
      kind: options.kind ?? "memory_created",
      payload: { type: options.kind ?? "memory_created", route: "memories" },
      dedupe_key: options.dedupe ?? newUuid(),
      apns_push_type: pushType,
      title: pushType === "alert" ? "Alex" : null,
      body: pushType === "alert" ? "Open Paeonia to see it." : null,
      scheduled_for: options.scheduledFor ?? EARLIER,
    }),
  );
}

const outboxRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
const claim = (t: TestConvex, args: { p_limit?: number } = {}) =>
  t.mutation(internal.pushQueue.claim_notification_batch, args);

describe("claim_notification_batch", () => {
  test("claims due rows oldest first, leases them for 30 seconds, and returns the device token", async () => {
    const { t, user, device } = await setup();
    await queue(t, user, device, { scheduledFor: "2026-10-10T11:30:00.000Z", dedupe: "b" });
    await queue(t, user, device, { scheduledFor: "2026-10-10T11:00:00.000Z", dedupe: "a" });
    await queue(t, user, device, { scheduledFor: "2026-10-10T12:00:01.000Z", dedupe: "future" });

    const batch = await claim(t);
    expect(batch).toHaveLength(2);
    expect(batch[0]).toMatchObject({
      target_device_id: device.id,
      push_token: device.push_token,
      apns_environment: "sandbox",
      apns_push_type: "alert",
      apns_collapse_id: null,
      title: "Alex",
      body: "Open Paeonia to see it.",
      payload: { type: "memory_created", route: "memories" },
    });
    const rows = await outboxRows(t);
    const byDedupe = (key: string) => rows.find((row) => row.dedupe_key === key)!;
    expect(batch[0].outbox_id).toBe(byDedupe("a").id);
    expect(byDedupe("a")).toMatchObject({
      attempt_count: 1,
      last_attempt_at: NOW,
      scheduled_for: "2026-10-10T12:00:30.000Z",
    });
    expect(byDedupe("future").attempt_count).toBe(0);

    // A second drain skips rows that are leased.
    expect(await claim(t)).toHaveLength(0);
    // Past the lease, the two retries and the row that just became due are all claimable.
    vi.setSystemTime(new Date("2026-10-10T12:00:31.000Z"));
    expect(await claim(t)).toHaveLength(3);
    expect((await outboxRows(t)).find((row) => row.dedupe_key === "a")?.attempt_count).toBe(2);
  });

  test("limits the batch between 1 and 200", async () => {
    const { t, user, device } = await setup();
    for (let index = 0; index < 3; index += 1) await queue(t, user, device);
    expect(await claim(t, { p_limit: 0 })).toHaveLength(1);
    expect(await claim(t, { p_limit: -5 })).toHaveLength(1);
    expect(await claim(t, { p_limit: 1000 })).toHaveLength(1);
  });

  test("fails rows whose device is disabled or whose kind the user turned off", async () => {
    const { t, user, device } = await setup();
    const second = await addDevice(t, user.userId, { token: "device-two" });
    await queue(t, user, device, { kind: "memory_created", dedupe: "memory" });
    await queue(t, user, device, { kind: "thread_message_sent", dedupe: "message" });
    await queue(t, user, second, { kind: "memory_created", dedupe: "disabled-device" });
    await queue(t, user, device, { kind: "entitlement_changed", pushType: "background", dedupe: "always" });
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").first();
      await ctx.db.patch(preference!._id, { memories_enabled: false });
      const row = await ctx.db.query("user_devices").withIndex("by_uuid", (q) => q.eq("id", second.id)).unique();
      await ctx.db.patch(row!._id, { disabled_at: EARLIER });
    });

    const batch = await claim(t);
    const rows = await outboxRows(t);
    const state = (key: string) => rows.find((row) => row.dedupe_key === key)!;
    expect(batch.map((item) => item.outbox_id).sort()).toEqual([state("message").id, state("always").id].sort());
    for (const key of ["memory", "disabled-device"]) {
      expect(state(key)).toMatchObject({
        failed_at: NOW,
        last_attempt_at: NOW,
        last_error: "notification target is no longer eligible",
        attempt_count: 0,
      });
    }
    expect(state("message").failed_at).toBeUndefined();
  });

  test("silent widget updates do not need the widget alert preference", async () => {
    const { t, user, device } = await setup();
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").first();
      await ctx.db.patch(preference!._id, { widget_updates_enabled: false });
    });
    await queue(t, user, device, { kind: "widget_updated", pushType: "background", dedupe: "silent" });
    await queue(t, user, device, { kind: "widget_updated", pushType: "alert", dedupe: "alert" });
    const batch = await claim(t);
    expect(batch).toHaveLength(1);
    expect(batch[0].apns_push_type).toBe("background");
    expect((await outboxRows(t)).find((row) => row.dedupe_key === "alert")?.failed_at).toBe(NOW);
  });

  test("fails rows that used their five attempts before a result was recorded", async () => {
    const { t, user, device } = await setup();
    await queue(t, user, device, { dedupe: "spent" });
    await queue(t, user, device, { dedupe: "spent-with-error" });
    await queue(t, user, device, { dedupe: "fresh" });
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) {
        if (row.dedupe_key === "spent") await ctx.db.patch(row._id, { attempt_count: 5 });
        if (row.dedupe_key === "spent-with-error") await ctx.db.patch(row._id, { attempt_count: 5, last_error: "BadTopic" });
      }
    });
    const batch = await claim(t);
    expect(batch).toHaveLength(1);
    const rows = await outboxRows(t);
    const state = (key: string) => rows.find((row) => row.dedupe_key === key)!;
    expect(state("spent")).toMatchObject({
      failed_at: NOW,
      last_error: "delivery attempt budget exhausted before a result was recorded",
    });
    expect(state("spent-with-error")).toMatchObject({ failed_at: NOW, last_error: "BadTopic" });
    expect(state("fresh").attempt_count).toBe(1);
  });

  test("does not touch a row whose lease is still running at attempt five", async () => {
    const { t, user, device } = await setup();
    await queue(t, user, device, { scheduledFor: "2026-10-10T12:00:20.000Z" });
    await t.run(async (ctx) => {
      const row = (await ctx.db.query("notification_outbox").collect())[0];
      await ctx.db.patch(row._id, { attempt_count: 5 });
    });
    await claim(t);
    expect((await outboxRows(t))[0].failed_at).toBeUndefined();
  });
});

describe("claim_due_notifications", () => {
  test("claims without a lease or attempt budget and gates widget alerts and silent pushes alike", async () => {
    const { t, user, device } = await setup();
    await queue(t, user, device, { dedupe: "plain" });
    await queue(t, user, device, { kind: "widget_updated", pushType: "background", dedupe: "silent" });
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").first();
      await ctx.db.patch(preference!._id, { widget_updates_enabled: false });
      const row = (await ctx.db.query("notification_outbox").collect()).find((item) => item.dedupe_key === "plain")!;
      await ctx.db.patch(row._id, { attempt_count: 7 });
    });
    const claimed = await t.mutation(internal.pushQueue.claim_due_notifications, {});
    expect(claimed).toHaveLength(1);
    expect(claimed[0]).toMatchObject({
      recipient_user_id: user.userId,
      push_token: device.push_token,
      push_token_hash: device.push_token_hash,
      kind: "memory_created",
      payload_version: 1,
      redaction_level: "private",
      attempt_count: 8,
    });
    const rows = await outboxRows(t);
    expect(rows.find((row) => row.dedupe_key === "plain")?.scheduled_for).toBe(EARLIER);
    expect(rows.find((row) => row.dedupe_key === "silent")?.failed_at).toBe(NOW);
    await expect(t.mutation(internal.pushQueue.claim_due_notifications, { p_limit: 501 })).rejects.toThrow(
      /23514.*notification claim limit is out of range/,
    );
  });
});

describe("notification results", () => {
  async function claimed() {
    const { t, user, device } = await setup();
    await queue(t, user, device);
    const [item] = await claim(t);
    return { t, device, user, outboxId: item.outbox_id };
  }
  const row = async (t: TestConvex) => (await outboxRows(t))[0];

  test("success records the provider id and clears the error", async () => {
    const { t, outboxId } = await claimed();
    await t.mutation(internal.pushQueue.mark_notification_result, {
      p_outbox_id: outboxId.toUpperCase(),
      p_success: true,
      p_provider_message_id: "  apns-id-1 ",
    });
    expect(await row(t)).toMatchObject({ sent_at: NOW, provider_message_id: "apns-id-1" });
    // A second result cannot undo a sent row.
    await t.mutation(internal.pushQueue.mark_notification_result, { p_outbox_id: outboxId, p_success: false, p_error: "late" });
    expect(await row(t)).toMatchObject({ sent_at: NOW });
    expect((await row(t)).failed_at).toBeUndefined();
  });

  test("a failure keeps the row for a retry until the fifth attempt", async () => {
    const { t, outboxId } = await claimed();
    await t.mutation(internal.pushQueue.mark_notification_result, { p_outbox_id: outboxId, p_success: false, p_error: "InternalServerError" });
    expect(await row(t)).toMatchObject({ last_error: "InternalServerError" });
    expect((await row(t)).failed_at).toBeUndefined();

    await t.mutation(internal.pushQueue.mark_notification_result, { p_outbox_id: outboxId, p_success: false, p_error: "  " });
    expect((await row(t)).last_error).toBe("delivery failed");

    await t.run(async (ctx) => ctx.db.patch((await ctx.db.query("notification_outbox").first())!._id, { attempt_count: 5 }));
    await t.mutation(internal.pushQueue.mark_notification_result, { p_outbox_id: outboxId, p_success: false, p_error: "Timeout" });
    expect(await row(t)).toMatchObject({ failed_at: NOW, last_error: "Timeout" });
  });

  test("an invalid token fails the row at once and truncates a long error", async () => {
    const { t, outboxId } = await claimed();
    await t.mutation(internal.pushQueue.mark_notification_result, {
      p_outbox_id: outboxId,
      p_success: false,
      p_error: "x".repeat(3000),
      p_invalid_token: true,
    });
    const result = await row(t);
    expect(result.failed_at).toBe(NOW);
    expect(result.last_error).toHaveLength(2000);
  });

  test("mark_notification_sent and mark_notification_failed", async () => {
    const { t, outboxId } = await claimed();
    expect(await t.mutation(internal.pushQueue.mark_notification_failed, { p_outbox_id: outboxId, p_error: " boom ", p_terminal: true })).toBe(true);
    expect(await row(t)).toMatchObject({ failed_at: NOW, last_error: "boom" });
    expect(await t.mutation(internal.pushQueue.mark_notification_failed, { p_outbox_id: outboxId, p_error: "retry" })).toBe(true);
    expect((await row(t)).failed_at).toBeUndefined();
    expect(await t.mutation(internal.pushQueue.mark_notification_sent, { p_outbox_id: outboxId, p_provider_message_id: "id" })).toBe(true);
    expect(await row(t)).toMatchObject({ sent_at: NOW, provider_message_id: "id" });
    expect((await row(t)).last_error).toBeUndefined();
    expect(await t.mutation(internal.pushQueue.mark_notification_sent, { p_outbox_id: outboxId })).toBe(false);
    expect(await t.mutation(internal.pushQueue.mark_notification_failed, { p_outbox_id: outboxId })).toBe(false);
    expect(await t.mutation(internal.pushQueue.mark_notification_sent, { p_outbox_id: newUuid() })).toBe(false);
  });
});

describe("widget pushes", () => {
  async function widgetSetup() {
    const { t, user } = await setup();
    const device = await t.run(async (ctx) => {
      const id = await ctx.db.insert("widget_push_devices", {
        id: newUuid(),
        user_id: user.userId,
        widget_kind: "PaeoniaWidget",
        widget_push_token: "widget-token-1",
        widget_push_token_hash: "w".repeat(64),
        apns_environment: "production",
        last_seen_at: EARLIER,
        revision: 1,
        created_at: EARLIER,
        updated_at: EARLIER,
      });
      return (await ctx.db.get(id))!;
    });
    const push = async (dedupe: string, scheduledFor = EARLIER) =>
      await t.run((ctx) =>
        insertWidgetPushOutbox(ctx, {
          recipient_user_id: user.userId,
          target_widget_device_id: device.id,
          widget_push_token_hash: device.widget_push_token_hash,
          apns_environment: "production",
          payload: { type: "widget_updated" },
          dedupe_key: dedupe,
          apns_collapse_id: "widget:1",
          scheduled_for: scheduledFor,
        }),
      );
    const rows = () => t.run((ctx) => ctx.db.query("widget_push_outbox").collect());
    return { t, user, device, push, rows };
  }

  test("claims due rows without a lease and gives up after five attempts", async () => {
    const { t, device, push, rows } = await widgetSetup();
    await push("a");
    await push("later", "2026-10-10T13:00:00.000Z");
    const batch = await t.mutation(internal.pushQueue.claim_widget_push_batch, {});
    expect(batch).toEqual([
      {
        outbox_id: (await rows()).find((row) => row.dedupe_key === "a")!.id,
        target_widget_device_id: device.id,
        widget_push_token: "widget-token-1",
        apns_environment: "production",
        apns_collapse_id: "widget:1",
        payload: { type: "widget_updated" },
      },
    ]);
    // No lease: the next drain claims it again until the budget ends.
    for (let attempt = 2; attempt <= 5; attempt += 1) {
      expect(await t.mutation(internal.pushQueue.claim_widget_push_batch, {})).toHaveLength(1);
    }
    expect((await rows()).find((row) => row.dedupe_key === "a")?.attempt_count).toBe(5);
    expect(await t.mutation(internal.pushQueue.claim_widget_push_batch, {})).toHaveLength(0);
    expect((await rows()).find((row) => row.dedupe_key === "a")).toMatchObject({ failed_at: NOW, last_error: "attempts exhausted" });
  });

  test("skips disabled devices and records results", async () => {
    const { t, device, push, rows } = await widgetSetup();
    await push("a");
    const outboxId = (await rows())[0].id;
    await t.mutation(internal.pushQueue.disable_device, { kind: "widget", device_id: device.id });
    expect(await t.mutation(internal.pushQueue.claim_widget_push_batch, {})).toHaveLength(0);
    expect(await t.query(internal.pushQueue.has_due_push_notification_work, {})).toBe(false);

    await t.mutation(internal.pushQueue.mark_widget_push_result, { p_outbox_id: outboxId, p_success: false, p_error: "Timeout" });
    expect((await rows())[0]).toMatchObject({ last_error: "Timeout" });
    expect((await rows())[0].failed_at).toBeUndefined();
    await t.mutation(internal.pushQueue.mark_widget_push_result, { p_outbox_id: outboxId, p_success: false, p_error: "BadDeviceToken", p_invalid_token: true });
    expect((await rows())[0].failed_at).toBe(NOW);

    await push("b");
    const second = (await rows()).find((row) => row.dedupe_key === "b")!;
    await t.mutation(internal.pushQueue.mark_widget_push_result, { p_outbox_id: second.id, p_success: true, p_provider_message_id: "apns-1" });
    expect((await rows()).find((row) => row.dedupe_key === "b")).toMatchObject({ sent_at: NOW, provider_message_id: "apns-1" });
    expect((await rows()).find((row) => row.dedupe_key === "b")?.last_error).toBeUndefined();
  });
});

describe("has_due_push_notification_work", () => {
  test("is true only for due rows with attempts left", async () => {
    const { t, user, device } = await setup();
    const due = () => t.query(internal.pushQueue.has_due_push_notification_work, {});
    expect(await due()).toBe(false);
    await queue(t, user, device, { scheduledFor: "2026-10-10T12:00:10.000Z" });
    expect(await due()).toBe(false);
    expect(await t.query(internal.pushQueue.has_due_push_notification_work, { p_now: "2026-10-10T12:00:10.000Z" })).toBe(true);
    await t.run(async (ctx) => ctx.db.patch((await ctx.db.query("notification_outbox").first())!._id, { scheduled_for: EARLIER, attempt_count: 5 }));
    expect(await due()).toBe(false);
    await t.run(async (ctx) => ctx.db.patch((await ctx.db.query("notification_outbox").first())!._id, { attempt_count: 4 }));
    expect(await due()).toBe(true);
  });
});

describe("devices", () => {
  test("disable_device retires the device once, persist_device_environment updates it", async () => {
    const { t, device } = await setup();
    await t.mutation(internal.pushQueue.persist_device_environment, { kind: "app", device_id: device.id, apns_environment: "production" });
    const row = () => t.run((ctx) => ctx.db.query("user_devices").first());
    expect(await row()).toMatchObject({ apns_environment: "production", revision: 2 });
    await t.mutation(internal.pushQueue.disable_device, { kind: "app", device_id: device.id });
    expect(await row()).toMatchObject({ disabled_at: NOW, revision: 3 });
    vi.setSystemTime(new Date("2026-10-10T13:00:00.000Z"));
    await t.mutation(internal.pushQueue.disable_device, { kind: "app", device_id: device.id });
    expect(await row()).toMatchObject({ disabled_at: NOW, revision: 3 });
  });
});

describe("drain orchestration with a stubbed APNs sender", () => {
  const ctxFor = (t: TestConvex): DrainCtx => ({ runMutation: (reference, args) => (t.mutation as (reference: unknown, args: unknown) => Promise<unknown>)(reference, args) });

  test("records each outcome, learns the right environment, and retires dead tokens", async () => {
    const { t, user, device } = await setup();
    const dead = await addDevice(t, user.userId, { token: "dead-device" });
    await queue(t, user, device, { dedupe: "ok" });
    await queue(t, user, dead, { dedupe: "dead" });
    await queue(t, user, device, { dedupe: "flaky" });
    const sent: { token: string; topic: string; pushType: string }[] = [];
    const results: Record<string, ApnsSendResult> = {
      [device.push_token]: { ok: true, providerMessageId: "apns-ok", environment: "production" },
      [dead.push_token]: { ok: false, error: "Unregistered", invalidToken: true, environment: "sandbox" },
    };
    let calls = 0;
    const stats = await drainAppNotifications(
      ctxFor(t),
      async (request) => {
        sent.push({ token: request.token, topic: request.topic, pushType: request.pushType });
        calls += 1;
        if (calls === 3) throw new Error("network down");
        return results[request.token];
      },
      "no.paeonia.app",
    );
    expect(stats).toEqual({ claimed: 3, sent: 1, failed: 2 });
    expect(sent.every((item) => item.topic === "no.paeonia.app" && item.pushType === "alert")).toBe(true);

    const rows = await outboxRows(t);
    const state = (key: string) => rows.find((row) => row.dedupe_key === key)!;
    expect(state("ok")).toMatchObject({ sent_at: NOW, provider_message_id: "apns-ok" });
    expect(state("dead")).toMatchObject({ failed_at: NOW, last_error: "Unregistered" });
    expect(state("flaky").failed_at).toBeUndefined();
    expect(state("flaky").last_error).toBe("network down");

    const devices = await t.run((ctx) => ctx.db.query("user_devices").collect());
    expect(devices.find((row) => row.id === device.id)?.apns_environment).toBe("production");
    expect(devices.find((row) => row.id === dead.id)?.disabled_at).toBe(NOW);
    expect(devices.find((row) => row.id === device.id)?.disabled_at).toBeUndefined();
  });

  test("widget pushes use the widgets topic and retire dead widget tokens", async () => {
    const { t, user } = await setup();
    const widget = await t.run(async (ctx) => {
      const id = await ctx.db.insert("widget_push_devices", {
        id: newUuid(),
        user_id: user.userId,
        widget_kind: "PaeoniaWidget",
        widget_push_token: "widget-token",
        widget_push_token_hash: "w".repeat(64),
        apns_environment: "sandbox",
        last_seen_at: EARLIER,
        revision: 1,
        created_at: EARLIER,
        updated_at: EARLIER,
      });
      return (await ctx.db.get(id))!;
    });
    await t.run((ctx) =>
      insertWidgetPushOutbox(ctx, {
        recipient_user_id: user.userId,
        target_widget_device_id: widget.id,
        widget_push_token_hash: widget.widget_push_token_hash,
        apns_environment: "sandbox",
        payload: { type: "widget_updated" },
        scheduled_for: EARLIER,
      }),
    );
    const requests: { topic: string; pushType: string; expiration?: string }[] = [];
    const stats = await drainWidgetPushes(
      ctxFor(t),
      async (request) => {
        requests.push({ topic: request.topic, pushType: request.pushType, expiration: request.expiration });
        return { ok: false, error: "BadDeviceToken", invalidToken: true };
      },
      "no.paeonia.app",
    );
    expect(stats).toEqual({ claimed: 1, sent: 0, failed: 1 });
    expect(requests).toEqual([{ topic: "no.paeonia.app.push-type.widgets", pushType: "widgets", expiration: "0" }]);
    const rows = await t.run(async (ctx) => ({
      outbox: await ctx.db.query("widget_push_outbox").collect(),
      device: await ctx.db.query("widget_push_devices").first(),
    }));
    expect(rows.outbox[0]).toMatchObject({ failed_at: NOW, last_error: "BadDeviceToken" });
    expect(rows.device?.disabled_at).toBe(NOW);
  });
});
