import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { addDevice, createCouple, newTest, type TestConvex } from "../test.setup";
import { newUuid } from "./ids";
import {
  enqueueMemoryCreatedNotification,
  enqueueNotificationForUser,
  enqueuePartnerNotification,
  enqueueWidgetPushForUser,
  enqueueWidgetUpdateAlert,
  notificationAlertBody,
  notificationLocaleLanguage,
  notificationPayloadIsSafe,
} from "./notifications";
import { enqueueDailyPartnerPush } from "./dailyPartnerPush";
import { enqueueGamePush } from "./games";
import { GAME_PUSH_COPY, notificationAlertTitle } from "./notificationCopy";
import { GAME_KINDS } from "./validators";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

async function outbox(t: TestConvex) {
  return await t.run((ctx) => ctx.db.query("notification_outbox").collect());
}

describe("notification copy", () => {
  test("locale language", () => {
    expect(notificationLocaleLanguage("nb-NO")).toBe("nb");
    expect(notificationLocaleLanguage("no_NO")).toBe("nb");
    expect(notificationLocaleLanguage("nn")).toBe("nb");
    expect(notificationLocaleLanguage("en-GB")).toBe("en");
    expect(notificationLocaleLanguage(null)).toBe("en");
    expect(notificationLocaleLanguage("  ")).toBe("en");
  });

  test("alert bodies", () => {
    expect(notificationAlertBody("streak_reminder", {}, "en")).toBe("Anything small counts, like a message or a drawing.");
    expect(notificationAlertBody("streak_reminder", { partner_checked_in: true }, "nb")).toBe(
      "Noe lite fra deg holder rekken i gang.",
    );
    expect(notificationAlertBody("partner_answered", {}, "nb")).toBe("Nå kan du se svaret.");
    expect(notificationAlertBody("thread_message_sent", {}, "en")).toBe("Sent you a message");
    expect(notificationAlertBody("subscription_trial_reminder", { days_left: 1 }, "en")).toBe(
      "1 day left. Review your subscription in the App Store.",
    );
    expect(notificationAlertBody("subscription_trial_reminder", { days_left: "3" }, "nb")).toBe(
      "3 dager igjen. Se over abonnementet ditt i App Store.",
    );
    expect(notificationAlertBody("subscription_trial_reminder", {}, "en")).toBe(
      "2 days left. Review your subscription in the App Store.",
    );
    expect(notificationAlertBody("location_updated", {}, "en")).toBeNull();
  });

  describe("game pushes", () => {
    const pushKinds = ["game_turn_ready", "game_turn_reminder", "game_result", "game_invite"] as const;

    test("a game without copy gets a title naming the partner, and turn and result pushes use the reminder body", async () => {
      const t = newTest();
      const couple = await createCouple(t);
      // A kind that has no copy yet, while there is one.
      const uncopied = GAME_KINDS.find((kind) => !GAME_PUSH_COPY[kind]);
      for (const gameKind of [uncopied, "constructor", undefined]) {
        const payload = { game_kind: gameKind, actor_user_id: couple.first.userId };
        for (const kind of pushKinds) {
          expect(await t.run((ctx) => notificationAlertTitle(ctx, couple.second.userId, kind, payload, "en"))).toBe("Something new from First Partner");
          expect(await t.run((ctx) => notificationAlertTitle(ctx, couple.second.userId, kind, payload, "nb"))).toBe("Noe nytt fra First Partner");
        }
        expect(notificationAlertBody("game_turn_ready", payload, "en")).toBe("Pick up where you left off.");
        expect(notificationAlertBody("game_result", payload, "nb")).toBe("Fortsett der dere slapp.");
        expect(notificationAlertBody("game_invite", payload, "en")).toBe("Join in when you're ready.");
      }
    });

    test("a step picks its own title and body, and any other push keeps the game's copy", async () => {
      // A stand-in for a game with steps. The table is restored after the test.
      GAME_PUSH_COPY.story_chain = {
        en: { name: "Story chain", steps: { last_line: { title: (actor) => `${actor} wrote the last line`, body: "Open Paeonia to name your story." } } },
        nb: { name: "Historiekjede", steps: { last_line: { title: (actor) => `${actor} skrev siste linje`, body: "Åpne Paeonia for å gi historien et navn." } } },
      };
      try {
        const t = newTest();
        const couple = await createCouple(t);
        await addDevice(t, couple.second.userId, { locale: "en-US" });
        await addDevice(t, couple.second.userId, { locale: "nb-NO" });
        const push = (step: string | undefined, key: string) =>
          t.run((ctx) =>
            enqueueGamePush(ctx, {
              kind: "game_turn_ready",
              game_kind: "story_chain",
              couple_id: couple.coupleId,
              actor_user_id: couple.first.userId,
              recipient_user_id: couple.second.userId,
              dedupe_key: key,
              step,
            }),
          );
        await push("last_line", "with-step");
        await push(undefined, "without-step");
        await push("not_a_step", "unknown-step");
        const rows = await outbox(t);
        const copy = (key: string) =>
          rows
            .filter((row) => (row.dedupe_key ?? "").startsWith(`${key}:`))
            .map((row) => [row.title, row.body])
            .sort();
        expect(copy("with-step")).toEqual([
          ["First Partner skrev siste linje", "Åpne Paeonia for å gi historien et navn."],
          ["First Partner wrote the last line", "Open Paeonia to name your story."],
        ]);
        expect(rows.find((row) => (row.dedupe_key ?? "").startsWith("with-step:"))?.payload).toMatchObject({ step: "last_line" });
        expect(copy("without-step")).toEqual([
          ["Din tur i Historiekjede", "Fortsett der dere slapp."],
          ["Your turn in Story chain", "Pick up where you left off."],
        ]);
        expect(copy("unknown-step")).toEqual(copy("without-step"));
        await t.finishAllScheduledFunctions(vi.runAllTimers);
      } finally {
        delete GAME_PUSH_COPY.story_chain;
      }
    });

    test("without a partner name the result title says 'Your partner'", async () => {
      const t = newTest();
      const payload = { game_kind: "draw_and_guess", actor_user_id: newUuid() };
      expect(await t.run((ctx) => notificationAlertTitle(ctx, newUuid(), "game_result", payload, "en"))).toBe("Your partner guessed your drawing");
      expect(await t.run((ctx) => notificationAlertTitle(ctx, newUuid(), "game_invite", payload, "nb"))).toBe("Partneren din vil spille Tegn og gjett med deg");
    });
  });

  test("payload safety rejects sensitive keys, non-objects, and oversize payloads", () => {
    expect(notificationPayloadIsSafe({ type: "memory_created", route: "memories" })).toBe(true);
    expect(notificationPayloadIsSafe({ latitude: 1 })).toBe(false);
    expect(notificationPayloadIsSafe({ place: { name: "Bryggen" } })).toBe(false);
    expect(notificationPayloadIsSafe({ nested: { Message_Body: "x" } })).toBe(false);
    expect(notificationPayloadIsSafe([])).toBe(false);
    expect(notificationPayloadIsSafe(null)).toBe(false);
    expect(notificationPayloadIsSafe({ pad: "x".repeat(5000) })).toBe(false);
  });
});

describe("enqueueNotificationForUser", () => {
  test("queues one alert per active device with localized copy and the actor name", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "nb-NO" });
    await addDevice(t, couple.second.userId, { locale: "en-US" });
    const disabled = await addDevice(t, couple.second.userId);
    await t.run((ctx) => ctx.db.patch(disabled._id, { disabled_at: "2026-10-10T11:00:00.000Z" }));

    const queued = await t.run((ctx) =>
      enqueueNotificationForUser(ctx, {
        recipient_user_id: couple.second.userId,
        kind: "memory_created",
        payload: { type: "memory_created", actor_user_id: couple.first.userId },
        dedupe_key: "memory_created:abc",
        apns_collapse_id: " memory:abc ",
      }),
    );
    expect(queued).toBe(2);
    const rows = (await outbox(t)).sort((a, b) => (a.body ?? "").localeCompare(b.body ?? ""));
    expect(rows.map((row) => [row.title, row.body])).toEqual([
      ["First Partner la til et minne", "Se det blant minnene deres."],
      ["First Partner added a memory", "See it in your memories."],
    ]);
    expect(rows[0]).toMatchObject({
      kind: "memory_created",
      redaction_level: "private",
      apns_push_type: "alert",
      apns_collapse_id: "memory:abc",
      payload_version: 1,
      scheduled_for: "2026-10-10T12:00:00.000Z",
    });
    expect(rows[0].dedupe_key).toBe(`memory_created:abc:${rows[0].target_device_id}`);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a repeated dedupe key queues nothing", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    const args = {
      recipient_user_id: couple.second.userId,
      kind: "memory_created",
      payload: { type: "memory_created" },
      dedupe_key: "same-key",
    };
    expect(await t.run((ctx) => enqueueNotificationForUser(ctx, args))).toBe(1);
    expect(await t.run((ctx) => enqueueNotificationForUser(ctx, args))).toBe(0);
    expect(await outbox(t)).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("respects preferences, including location updates being on by default", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId);
    await t.run(async (ctx) => {
      const preference = await ctx.db
        .query("notification_preferences")
        .withIndex("by_user_id", (q) => q.eq("user_id", couple.second.userId))
        .unique();
      await ctx.db.patch(preference!._id, { memories_enabled: false });
    });
    const memory = await t.run((ctx) =>
      enqueueNotificationForUser(ctx, { recipient_user_id: couple.second.userId, kind: "memory_created", payload: { type: "x" } }),
    );
    const location = await t.run((ctx) =>
      enqueueNotificationForUser(ctx, { recipient_user_id: couple.second.userId, kind: "location_updated", payload: { type: "x" } }),
    );
    const streak = await t.run((ctx) =>
      enqueueNotificationForUser(ctx, { recipient_user_id: couple.second.userId, kind: "streak_reminder", payload: { type: "x" } }),
    );
    expect([memory, location, streak]).toEqual([0, 1, 1]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("message copy names the sender, or says 'Your partner' without a name", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    expect(
      await t.run((ctx) => notificationAlertTitle(ctx, couple.second.userId, "thread_message_sent", { sender_user_id: newUuid() }, "en")),
    ).toBe("Your partner");
    await t.run((ctx) =>
      enqueueNotificationForUser(ctx, {
        recipient_user_id: couple.second.userId,
        kind: "thread_message_sent",
        payload: { type: "thread_message_sent", sender_user_id: couple.first.userId },
      }),
    );
    const [row] = await outbox(t);
    expect(row.title).toBe("First Partner");
    expect(row.body).toBe("Sent you a message");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("validates recipient, kind, redaction, and payload", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    const base = { recipient_user_id: couple.second.userId, kind: "memory_created", payload: { type: "x" } };
    await expect(t.run((ctx) => enqueueNotificationForUser(ctx, { ...base, recipient_user_id: null }))).rejects.toThrow(
      /23514.*notification recipient is required/,
    );
    await expect(t.run((ctx) => enqueueNotificationForUser(ctx, { ...base, kind: "nope" }))).rejects.toThrow(
      /notification kind is not supported/,
    );
    await expect(t.run((ctx) => enqueueNotificationForUser(ctx, { ...base, redaction_level: "generic" }))).rejects.toThrow(
      /only private notification payloads are supported for MVP/,
    );
    await expect(t.run((ctx) => enqueueNotificationForUser(ctx, { ...base, payload: { longitude: 1 } }))).rejects.toThrow(
      /notification payload contains sensitive or unsupported fields/,
    );
  });

  test("partner notifications skip the actor", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    const queued = await t.run((ctx) =>
      enqueuePartnerNotification(ctx, {
        couple_id: couple.coupleId,
        actor_user_id: couple.first.userId,
        kind: "memory_created",
        payload: { type: "memory_created" },
      }),
    );
    expect(queued).toBe(1);
    expect((await outbox(t))[0].recipient_user_id).toBe(couple.second.userId);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("trigger helpers", () => {
  test("memory created notifies the partner once and skips hidden memories", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "en" });
    const memoryId = newUuid();
    const memory = await t.run(async (ctx) => {
      const now = new Date().toISOString();
      const id = await ctx.db.insert("memories", {
        id: memoryId,
        couple_id: couple.coupleId,
        title: "Trip",
        memory_date: "2026-10-01",
        created_by_user_id: couple.first.userId,
        last_edited_by_user_id: couple.first.userId,
        revision: 1,
        moderation_status: "visible",
        created_at: now,
        updated_at: now,
      });
      return (await ctx.db.get(id))!;
    });
    await t.run((ctx) => enqueueMemoryCreatedNotification(ctx, memory));
    await t.run((ctx) => enqueueMemoryCreatedNotification(ctx, memory));
    await t.run((ctx) => enqueueMemoryCreatedNotification(ctx, { ...memory, moderation_status: "hidden" }));
    const rows = await outbox(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: couple.second.userId,
      title: "First Partner added a memory",
      apns_collapse_id: `memory:${memoryId}`,
    });
    expect(rows[0].payload).toEqual({
      type: "memory_created",
      couple_id: couple.coupleId,
      memory_id: memoryId,
      actor_user_id: couple.first.userId,
      route: "memories",
      deeplink: `paeonia://memories/memory?memoryId=${memoryId}`,
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("each answer tells the partner: answered first, then answered too", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["UTC", "UTC"] });
    await addDevice(t, couple.first.userId, { locale: "en" });
    await addDevice(t, couple.second.userId, { locale: "en" });
    const dayId = newUuid();
    const instanceId = newUuid();
    const insertAnswer = (userId: string) =>
      t.run(async (ctx) => {
        const now = new Date().toISOString();
        const id = await ctx.db.insert("daily_question_answers", {
          id: newUuid(), instance_id: instanceId, user_id: userId, created_at: now, updated_at: now, moderation_status: "visible",
        });
        return (await ctx.db.get(id))!;
      });
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      await ctx.db.insert("couple_days", {
        id: dayId, couple_id: couple.coupleId, local_date: "2026-10-10", anchor_time_zone_id: "UTC",
        starts_at: "2026-10-10T00:00:00.000Z", ends_at: "2026-10-11T00:00:00.000Z", created_at: now,
      });
      await ctx.db.insert("daily_question_instances", {
        id: instanceId, couple_day_id: dayId, couple_id: couple.coupleId, question_id: newUuid(), question_version_id: newUuid(),
        status: "active", created_at: now,
      });
    });
    const instance = async () =>
      (await t.run((ctx) => ctx.db.query("daily_question_instances").withIndex("by_uuid", (q) => q.eq("id", instanceId)).unique()))!;
    const firstAnswer = await insertAnswer(couple.first.userId);
    const firstInstance = await instance();
    await t.run((ctx) => enqueueDailyPartnerPush(ctx, firstAnswer, firstInstance));
    expect((await outbox(t)).map((row) => [row.kind, row.recipient_user_id, row.title])).toEqual([
      ["daily_challenge_completed", couple.second.userId, "First Partner answered today's question"],
    ]);
    const secondAnswer = await insertAnswer(couple.second.userId);
    await t.run((ctx) => enqueueDailyPartnerPush(ctx, secondAnswer, firstInstance));
    const rows = (await outbox(t)).filter((row) => row.recipient_user_id === couple.first.userId);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: couple.first.userId,
      kind: "partner_answered",
      title: "Second Partner answered too",
      apns_collapse_id: `daily:${couple.coupleId}`,
      // The push waits in the recipient's daily lane, so more answers right after join it.
      scheduled_for: "2026-10-10T12:01:15.000Z",
    });
    expect(rows[0].payload).toMatchObject({
      instance_ids: [instanceId],
      deeplink: `paeonia://daily/reveal?instanceId=${instanceId}&coupleDayId=${dayId}`,
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("widget update alert titles the notification with the author name", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "nb" });
    const args = { couple_id: couple.coupleId, author_user_id: couple.first.userId, canvas_id: newUuid(), revision_id: newUuid() };
    expect(await t.run((ctx) => enqueueWidgetUpdateAlert(ctx, args))).toBe(1);
    expect(await t.run((ctx) => enqueueWidgetUpdateAlert(ctx, args))).toBe(0);
    const [row] = await outbox(t);
    expect(row).toMatchObject({
      kind: "widget_updated",
      title: "First Partner",
      body: "Tegnet noe til deg",
      apns_collapse_id: `widget-alert:${couple.coupleId}`,
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("widget pushes", () => {
  test("queues for active PaeoniaWidget devices and dedupes pending rows", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await t.run(async (ctx) => {
      const now = new Date().toISOString();
      const device = (widget_kind: string) => ({
        id: newUuid(),
        user_id: couple.second.userId,
        widget_kind,
        widget_push_token: "w".repeat(24),
        widget_push_token_hash: widget_kind.padEnd(64, "0"),
        apns_environment: "sandbox" as const,
        last_seen_at: now,
        revision: 1,
        created_at: now,
        updated_at: now,
      });
      await ctx.db.insert("widget_push_devices", device("PaeoniaWidget"));
      await ctx.db.insert("widget_push_devices", device("OtherWidget"));
    });
    const args = { recipient_user_id: couple.second.userId, kind: "widget_updated", payload: { revision: 1 }, dedupe_key: "rev-1" };
    expect(await t.run((ctx) => enqueueWidgetPushForUser(ctx, args))).toBe(1);
    expect(await t.run((ctx) => enqueueWidgetPushForUser(ctx, args))).toBe(0);
    await expect(t.run((ctx) => enqueueWidgetPushForUser(ctx, { ...args, kind: "other" }))).rejects.toThrow(
      /unsupported widget push kind/,
    );
    // A sent row no longer blocks a new one.
    await t.run(async (ctx) => {
      const row = await ctx.db.query("widget_push_outbox").first();
      await ctx.db.patch(row!._id, { sent_at: "2026-10-10T12:00:00.000Z" });
    });
    expect(await t.run((ctx) => enqueueWidgetPushForUser(ctx, args))).toBe(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
