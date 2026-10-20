import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import type { ApnsSendRequest, ApnsSendResult } from "./lib/apns";
import { newUuid } from "./lib/ids";
import { insertNotificationOutbox, insertWidgetPushOutbox } from "./lib/notifications";
import { addDevice, createSignedInUser, newTest, type TestConvex } from "./test.setup";

// Stands in for APNs. `push:send_push` imports `sendWithEnvironmentFallback` from lib/apns.
const send = vi.hoisted(() => vi.fn<(request: ApnsSendRequest) => Promise<ApnsSendResult>>());
vi.mock("./lib/apns", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./lib/apns")>()),
  sendWithEnvironmentFallback: (request: ApnsSendRequest) => send(request),
}));

const APNS_ENV = ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_PRIVATE_KEY"] as const;

// All timers are fake, so queued sends run only when a test calls `drain`.
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
  send.mockReset();
  for (const name of APNS_ENV) delete process.env[name];
});

const NOW = "2026-10-10T12:00:00.000Z";
const EARLIER = "2026-10-10T11:00:00.000Z";
const LATER = "2026-10-10T13:00:00.000Z";

function configureApns() {
  for (const name of APNS_ENV) process.env[name] = "test-value";
}

/** Runs every queued send, its retries, and its completion, advancing the fake clock as needed. */
const drain = (t: TestConvex) => t.finishAllScheduledFunctions(vi.runAllTimers);

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
const rowByDedupe = async (t: TestConvex, key: string) => (await outboxRows(t)).find((row) => row.dedupe_key === key)!;
const prepare = async (t: TestConvex, key: string) =>
  await t.mutation(internal.pushQueue.prepare_notification, { outbox_id: (await rowByDedupe(t, key)).id });

describe("prepare_notification", () => {
  test("returns the copy, payload, and device token of a pending row", async () => {
    const { t, user, device } = await setup();
    await queue(t, user, device, { dedupe: "a" });
    expect(await prepare(t, "a")).toEqual({
      outbox_id: (await rowByDedupe(t, "a")).id,
      target_device_id: device.id,
      push_token: device.push_token,
      apns_environment: "sandbox",
      apns_push_type: "alert",
      apns_collapse_id: null,
      title: "Alex",
      body: "Open Paeonia to see it.",
      payload: { type: "memory_created", route: "memories" },
      deliver_quietly: false,
      badge: null,
    });
    // A sent row is not sent again.
    await t.mutation(internal.pushQueue.mark_push_result, { kind: "app", outbox_id: (await rowByDedupe(t, "a")).id });
    expect(await prepare(t, "a")).toBeNull();
  });

  test("fails rows whose device is disabled or whose kind the user turned off", async () => {
    const { t, user, device } = await setup();
    const second = await addDevice(t, user.userId, { token: "device-two" });
    await queue(t, user, device, { kind: "memory_created", dedupe: "memory" });
    await queue(t, user, device, { kind: "thread_message_sent", dedupe: "message" });
    await queue(t, user, second, { kind: "memory_created", dedupe: "disabled-device" });
    await queue(t, user, device, { kind: "subscription_trial_reminder", pushType: "background", dedupe: "always" });
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").first();
      await ctx.db.patch(preference!._id, { memories_enabled: false });
      const row = await ctx.db.query("user_devices").withIndex("by_uuid", (q) => q.eq("id", second.id)).unique();
      await ctx.db.patch(row!._id, { disabled_at: EARLIER });
    });

    for (const key of ["memory", "disabled-device"]) {
      expect(await prepare(t, key)).toBeNull();
      expect(await rowByDedupe(t, key)).toMatchObject({
        failed_at: NOW,
        last_error: "notification target is no longer eligible",
      });
    }
    expect(await prepare(t, "message")).not.toBeNull();
    expect(await prepare(t, "always")).not.toBeNull();
    expect((await rowByDedupe(t, "message")).failed_at).toBeUndefined();
  });

  test("fails reminders that are out of date instead of sending them", async () => {
    const { t, user, device } = await setup();
    const reminder = (dedupe: string, deadline: string) =>
      t.run((ctx) =>
        insertNotificationOutbox(ctx, {
          recipient_user_id: user.userId,
          target_device_id: device.id,
          push_token_hash: device.push_token_hash,
          apns_environment: "sandbox",
          kind: "streak_reminder",
          payload: { type: "streak_reminder", next_activity_deadline_at: deadline },
          dedupe_key: dedupe,
          title: "Time for a quick check-in",
          body: "A quick drawing is enough.",
          scheduled_for: EARLIER,
        }),
      );
    await reminder("passed", "2026-10-10T11:59:00.000Z");
    await reminder("upcoming", "2026-10-10T12:30:00.000Z");

    expect(await prepare(t, "passed")).toBeNull();
    expect(await rowByDedupe(t, "passed")).toMatchObject({ failed_at: NOW, last_error: "notification is out of date" });
    expect(await prepare(t, "upcoming")).not.toBeNull();
  });

  test("silent widget updates do not need the widget alert preference", async () => {
    const { t, user, device } = await setup();
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").first();
      await ctx.db.patch(preference!._id, { widget_updates_enabled: false });
    });
    await queue(t, user, device, { kind: "widget_updated", pushType: "background", dedupe: "silent" });
    await queue(t, user, device, { kind: "widget_updated", pushType: "alert", dedupe: "alert" });
    expect((await prepare(t, "silent"))?.apns_push_type).toBe("background");
    expect(await prepare(t, "alert")).toBeNull();
    expect((await rowByDedupe(t, "alert")).failed_at).toBe(NOW);
  });
});

describe("mark_push_result", () => {
  async function queued() {
    const { t, user, device } = await setup();
    await queue(t, user, device, { dedupe: "a" });
    return { t, outboxId: (await rowByDedupe(t, "a")).id };
  }
  const row = async (t: TestConvex) => (await outboxRows(t))[0];

  test("success records the provider id, and a later result cannot undo it", async () => {
    const { t, outboxId } = await queued();
    await t.mutation(internal.pushQueue.mark_push_result, {
      kind: "app",
      outbox_id: outboxId.toUpperCase(),
      provider_message_id: "  apns-id-1 ",
    });
    expect(await row(t)).toMatchObject({ sent_at: NOW, provider_message_id: "apns-id-1" });
    await t.mutation(internal.pushQueue.mark_push_result, { kind: "app", outbox_id: outboxId, error: "late" });
    expect((await row(t)).failed_at).toBeUndefined();
    expect((await row(t)).last_error).toBeUndefined();
  });

  test("a failure fails the row and truncates a long error", async () => {
    const { t, outboxId } = await queued();
    await t.mutation(internal.pushQueue.mark_push_result, { kind: "app", outbox_id: outboxId, error: "x".repeat(3000) });
    const result = await row(t);
    expect(result.failed_at).toBe(NOW);
    expect(result.last_error).toHaveLength(2000);
  });

  test("a blank error still says the delivery failed", async () => {
    const { t, outboxId } = await queued();
    await t.mutation(internal.pushQueue.mark_push_result, { kind: "app", outbox_id: outboxId, error: "  " });
    expect(await row(t)).toMatchObject({ failed_at: NOW, last_error: "delivery failed" });
  });
});

async function addWidgetDevice(t: TestConvex, userId: string) {
  return await t.run(async (ctx) => {
    const id = await ctx.db.insert("widget_push_devices", {
      id: newUuid(),
      user_id: userId,
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
}

async function queueWidgetPush(t: TestConvex, userId: string, device: { id: string; widget_push_token_hash: string }) {
  await t.run((ctx) =>
    insertWidgetPushOutbox(ctx, {
      recipient_user_id: userId,
      target_widget_device_id: device.id,
      widget_push_token_hash: device.widget_push_token_hash,
      apns_environment: "production",
      payload: { type: "widget_updated" },
      dedupe_key: "a",
      apns_collapse_id: "widget:1",
      scheduled_for: EARLIER,
    }),
  );
}

const widgetRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("widget_push_outbox").collect());

describe("prepare_widget_push", () => {
  test("returns the widget token, and fails the row once the widget device is disabled", async () => {
    const { t, user } = await setup();
    const device = await addWidgetDevice(t, user.userId);
    await queueWidgetPush(t, user.userId, device);
    const outboxId = (await widgetRows(t))[0].id;
    expect(await t.mutation(internal.pushQueue.prepare_widget_push, { outbox_id: outboxId })).toEqual({
      outbox_id: outboxId,
      target_widget_device_id: device.id,
      widget_push_token: "widget-token-1",
      apns_environment: "production",
      apns_collapse_id: "widget:1",
      payload: { type: "widget_updated" },
    });

    await t.mutation(internal.pushQueue.disable_device, { kind: "widget", device_id: device.id });
    expect(await t.mutation(internal.pushQueue.prepare_widget_push, { outbox_id: outboxId })).toBeNull();
    expect((await widgetRows(t))[0]).toMatchObject({ failed_at: NOW, last_error: "notification target is no longer eligible" });
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

describe("send_push through pushWorkpool", () => {
  const deviceRow = async (t: TestConvex, id: string) =>
    (await t.run((ctx) => ctx.db.query("user_devices").collect())).find((row) => row.id === id)!;

  test("a send that APNs accepts marks the row sent and remembers the host", async () => {
    const { t, user, device } = await setup();
    configureApns();
    send.mockResolvedValue({ ok: true, providerMessageId: "apns-ok", environment: "production" });
    await queue(t, user, device, { dedupe: "ok" });
    await drain(t);

    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0]).toMatchObject({ token: device.push_token, topic: "no.paeonia.app", pushType: "alert" });
    const row = await rowByDedupe(t, "ok");
    expect(row).toMatchObject({ provider_message_id: "apns-ok" });
    expect(row.sent_at).toBeDefined();
    expect(row.failed_at).toBeUndefined();
    expect((await deviceRow(t, device.id)).apns_environment).toBe("production");
  });

  test("a push queued for later is checked again when it is due", async () => {
    const { t, user, device } = await setup();
    configureApns();
    send.mockResolvedValue({ ok: true, providerMessageId: "apns-ok" });
    await queue(t, user, device, { dedupe: "later", scheduledFor: LATER });
    // The user turns memories off before the push is due.
    await t.run(async (ctx) => {
      const preference = await ctx.db.query("notification_preferences").first();
      await ctx.db.patch(preference!._id, { memories_enabled: false });
    });
    await drain(t);

    expect(send).not.toHaveBeenCalled();
    const row = await rowByDedupe(t, "later");
    expect(row.last_error).toBe("notification target is no longer eligible");
    expect(row.failed_at! >= LATER).toBe(true);
  });

  test("a dead token is not retried and retires the device", async () => {
    const { t, user, device } = await setup();
    configureApns();
    send.mockResolvedValue({ ok: false, error: "Unregistered", invalidToken: true, environment: "sandbox" });
    await queue(t, user, device, { dedupe: "dead" });
    await drain(t);

    expect(send).toHaveBeenCalledTimes(1);
    const row = await rowByDedupe(t, "dead");
    expect(row.last_error).toBe("Unregistered");
    expect(row.failed_at).toBeDefined();
    expect((await deviceRow(t, device.id)).disabled_at).toBeDefined();
  });

  test("other failures retry, then fail the row once the five attempts are used", async () => {
    const { t, user, device } = await setup();
    configureApns();
    send.mockResolvedValue({ ok: false, error: "InternalServerError", environment: "sandbox" });
    await queue(t, user, device, { dedupe: "flaky" });
    await drain(t);

    expect(send).toHaveBeenCalledTimes(5);
    const row = await rowByDedupe(t, "flaky");
    expect(row.last_error).toContain("InternalServerError");
    expect(row.failed_at).toBeDefined();
    expect(row.sent_at).toBeUndefined();
    expect((await deviceRow(t, device.id)).disabled_at).toBeUndefined();
  });

  test("a network error retries and the next attempt can still send", async () => {
    const { t, user, device } = await setup();
    configureApns();
    send.mockRejectedValueOnce(new Error("network down")).mockResolvedValue({ ok: true, providerMessageId: "apns-2" });
    await queue(t, user, device, { dedupe: "retry" });
    await drain(t);

    expect(send).toHaveBeenCalledTimes(2);
    expect(await rowByDedupe(t, "retry")).toMatchObject({ provider_message_id: "apns-2" });
    expect((await rowByDedupe(t, "retry")).failed_at).toBeUndefined();
  });

  test("widget pushes use the widgets topic and retire dead widget tokens", async () => {
    const { t, user } = await setup();
    configureApns();
    send.mockResolvedValue({ ok: false, error: "BadDeviceToken", invalidToken: true });
    const device = await addWidgetDevice(t, user.userId);
    await queueWidgetPush(t, user.userId, device);
    await drain(t);

    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0]).toMatchObject({
      token: "widget-token-1",
      topic: "no.paeonia.app.push-type.widgets",
      pushType: "widgets",
      expiration: "0",
    });
    expect((await widgetRows(t))[0]).toMatchObject({ last_error: "BadDeviceToken" });
    expect((await widgetRows(t))[0].failed_at).toBeDefined();
    expect((await t.run((ctx) => ctx.db.query("widget_push_devices").first()))?.disabled_at).toBeDefined();
  });

  test("without APNs keys nothing is sent or retried, and the row stays unsent", async () => {
    const { t, user, device } = await setup();
    await queue(t, user, device, { dedupe: "local" });
    await drain(t);

    expect(send).not.toHaveBeenCalled();
    const row = await rowByDedupe(t, "local");
    expect(row.sent_at).toBeUndefined();
    expect(row.failed_at).toBeUndefined();
  });
});
