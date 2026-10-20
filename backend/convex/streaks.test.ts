import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { liveInstancesFor, seedCatalog, textQuestions } from "./daily.setup";
import { newUuid } from "./lib/ids";
import { applyStreakRestore, detectStreakBreak } from "./lib/streaks";
import { addDevice, createCouple, createSignedInUser, newTest, type TestUser } from "./test.setup";

const CLIENT_ID = newUuid();
let sequence = 0;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T10:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

function op() {
  sequence += 1;
  return {
    p_client_operation_id: newUuid(),
    p_client_id: CLIENT_ID,
    p_client_sequence: sequence,
    p_local_created_at: new Date().toISOString(),
  };
}

async function answerAll(t: ReturnType<typeof newTest>, user: TestUser) {
  const mine = (await liveInstancesFor(t, user.userId)).filter((row) => row.seeded_for_user_id === user.userId);
  for (const instance of mine.slice(-2)) {
    await user.as.mutation(api.daily.submit_daily_answer, {
      p_instance_id: instance.id,
      p_payload: { text: "ok" },
      ...op(),
    });
  }
}

async function streakCouple() {
  const t = newTest();
  await seedCatalog(t, textQuestions(12));
  const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
  await couple.first.as.mutation(api.daily.start_daily_challenge_snapshot, op());
  return { t, a: couple.first, b: couple.second, couple };
}

describe("get_couple_streak", () => {
  test("returns one row with zero counts before any activity", async () => {
    const { a } = await streakCouple();
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual([
      {
        current_count: 0,
        longest_count: 0,
        last_qualified_date: null,
        restore_available: false,
        restorable_count: 0,
        restore_deadline: null,
        freeze_available: false,
        freeze_ready_at: null,
        freeze_saved_streak: false,
        next_activity_deadline_at: null,
        current_user_contributed_today: false,
        partner_contributed_today: false,
      },
    ]);
  });

  test("needs a signed-in user in an entitled couple", async () => {
    const t = newTest();
    await expect(t.query(api.streaks.get_couple_streak, {})).rejects.toThrow(/42501.*authenticated user required/);
    const lonely = await createSignedInUser(t);
    await expect(lonely.as.query(api.streaks.get_couple_streak, {})).rejects.toThrow(
      /42501.*active entitled couple access is required/,
    );
  });

  test("a streak shorter than three days restarts without a freeze or a restore offer", async () => {
    const { t, a, b } = await streakCouple();
    await answerAll(t, a);
    await answerAll(t, b);
    expect((await a.as.query(api.streaks.get_couple_streak, {}))[0].current_count).toBe(1);
    // The deadline is local midnight two days after the qualifying day: 2026-10-11T22:00Z in Oslo.
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    const [broken] = await a.as.query(api.streaks.get_couple_streak, {});
    expect(broken).toMatchObject({
      current_count: 0,
      restore_available: false,
      restorable_count: 0,
      restore_deadline: null,
      freeze_available: false,
      freeze_ready_at: null,
      freeze_saved_streak: false,
      current_user_contributed_today: false,
    });
    // The cron stores the restart, which takes the row out of its break scan.
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await t.run((ctx) => ctx.db.query("streak_states").first())).toMatchObject({
      current_count: 0,
      longest_count: 1,
      restorable_count: 0,
    });
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual([broken]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

/** A three-day streak, the shortest one a freeze or restore protects. Its freeze is used unless `freezeReady`. */
async function bothQualified({ freezeReady = false } = {}) {
  const ctx = await streakCouple();
  await answerAll(ctx.t, ctx.a);
  await answerAll(ctx.t, ctx.b);
  await ctx.t.run(async (db) => {
    const row = (await db.db.query("streak_states").first())!;
    await db.db.patch(row._id, {
      current_count: 3,
      longest_count: 3,
      freeze_used_at: freezeReady ? undefined : "2026-09-30T22:00:00.000Z",
    });
  });
  const state = () => ctx.t.run((db) => db.db.query("streak_states").first());
  return { ...ctx, state };
}

describe("streak break without a write", () => {
  test("a break pushes both Lock Screens, because nobody's own app reloads them", async () => {
    const { t, a, b } = await bothQualified();
    for (const [user, token] of [[a, "a"], [b, "b"]] as const) {
      await user.as.mutation(api.widget.register_widget_push_device, {
        p_widget_kind: "PaeoniaWidget",
        p_widget_push_token: token.repeat(64),
        p_apns_environment: "sandbox",
      });
    }
    const lockScreenPushes = async () =>
      (await t.run((db) => db.db.query("widget_push_outbox").collect())).filter(
        (row) => row.payload.type === "lock_screen_updated",
      );
    // The answers' own pushes went out long ago.
    for (const row of await lockScreenPushes()) await t.run((db) => db.db.patch(row._id, { sent_at: "2026-10-10T10:01:00.000Z" }));
    const before = (await lockScreenPushes()).length;
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    const pushes = (await lockScreenPushes()).slice(before);
    expect(pushes.map((row) => row.recipient_user_id).sort()).toEqual([a.userId, b.userId].sort());
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the query reports the break virtually, then the cron stores the same state", async () => {
    const { t, a, state } = await bothQualified();
    // The deadline is 2026-10-11T22:00Z, so the restore offer runs to 2026-10-12T22:00Z.
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    const virtual = await a.as.query(api.streaks.get_couple_streak, {});
    expect(virtual[0]).toMatchObject({
      current_count: 0,
      restorable_count: 3,
      restore_available: true,
      restore_deadline: "2026-10-12T22:00:00.000Z",
      freeze_saved_streak: false,
      freeze_ready_at: "2026-10-30T22:00:00.000Z",
    });
    // The query wrote nothing.
    expect(await state()).toMatchObject({ current_count: 3, restorable_count: 0 });

    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await state()).toMatchObject({
      current_count: 3,
      restorable_count: 3,
      restore_deadline: "2026-10-12T22:00:00.000Z",
    });
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual(virtual);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an expired offer agrees too", async () => {
    const { t, a } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-13T00:00:00.000Z"));
    const virtual = await a.as.query(api.streaks.get_couple_streak, {});
    expect(virtual[0]).toMatchObject({ current_count: 0, restorable_count: 3, restore_available: false });
    await t.run(async (ctx) => {
      const row = (await ctx.db.query("streak_states").first())!;
      await detectStreakBreak(ctx, row.couple_id);
    });
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual(virtual);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a stale stored deadline is re-resolved in memory without a write", async () => {
    const { t, a, state } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
    await t.run(async (ctx) => {
      const row = (await ctx.db.query("streak_states").first())!;
      await ctx.db.patch(row._id, { next_activity_deadline_at: "2026-10-11T00:00:00.000Z" });
    });
    const [streak] = await a.as.query(api.streaks.get_couple_streak, {});
    expect(streak).toMatchObject({ current_count: 3, restorable_count: 0, restore_available: false });
    expect((await state())!.next_activity_deadline_at).toBe("2026-10-11T00:00:00.000Z");
    // The cron stores the corrected deadline and does not open an offer.
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await state()).toMatchObject({ next_activity_deadline_at: "2026-10-11T22:00:00.000Z", restorable_count: 0 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the break scan pages through ended couples and broken streaks to reach ours", async () => {
    const { t, state } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    // Older rows whose deadlines sit before ours in the index: ended couples and broken streaks.
    await t.run(async (ctx) => {
      for (let i = 0; i < 500; i++) {
        // An unbroken streak of a couple that no longer exists or is not active.
        await ctx.db.insert("streak_states", {
          couple_id: crypto.randomUUID(),
          current_count: 3,
          longest_count: 3,
          restorable_count: 0,
          next_activity_deadline_at: "2026-10-11T01:00:00.000Z",
          updated_at: "2026-10-11T01:00:00.000Z",
        });
      }
      for (let i = 0; i < 500; i++) {
        await ctx.db.insert("streak_states", {
          couple_id: crypto.randomUUID(),
          current_count: 3,
          longest_count: 3,
          restorable_count: 3,
          next_activity_deadline_at: "2026-10-11T01:00:00.000Z",
          updated_at: "2026-10-11T01:00:00.000Z",
        });
      }
    });
    // The first page holds 50 of the 1001 rows, and each page schedules the next.
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await state()).toMatchObject({ restorable_count: 0 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await state()).toMatchObject({ restorable_count: 3 });
  });

  test("the cron leaves a streak that already has an offer alone", async () => {
    const { t, state } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    const first = await state();
    vi.setSystemTime(new Date("2026-10-12T00:05:00.000Z"));
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await state()).toEqual(first);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a restore works when only the deadline passed and the cron has not run", async () => {
    const { t, couple, state } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    expect(await state()).toMatchObject({ restorable_count: 0 });
    const result = await t.run((ctx) =>
      applyStreakRestore(ctx, {
        couple_id: couple.coupleId,
        purchaser_user_id: couple.first.userId,
        product_id: newUuid(),
        environment: "sandbox",
        transaction_id: "restore-before-cron",
      }),
    );
    expect(result).toEqual({ ok: true, restoredCount: 3, replayed: false });
    expect(await state()).toMatchObject({ current_count: 3, restorable_count: 0 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a restore after the offer expired is refused", async () => {
    const { t, couple } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-13T00:00:00.000Z"));
    const result = await t.run((ctx) =>
      applyStreakRestore(ctx, {
        couple_id: couple.coupleId,
        purchaser_user_id: couple.first.userId,
        product_id: newUuid(),
        environment: "sandbox",
        transaction_id: "restore-too-late",
      }),
    );
    expect(result).toEqual({ ok: false, error: "No streak is available to restore", status: 409 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("streak freeze", () => {
  test("a ready freeze covers one missed day, in the query and then in the cron", async () => {
    const { t, a, state } = await bothQualified({ freezeReady: true });
    expect((await a.as.query(api.streaks.get_couple_streak, {}))[0]).toMatchObject({
      current_count: 3,
      freeze_available: true,
      freeze_ready_at: null,
      freeze_saved_streak: false,
    });

    // The deadline 2026-10-11T22:00Z passed. The freeze moves it one Oslo day later.
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    const virtual = await a.as.query(api.streaks.get_couple_streak, {});
    expect(virtual[0]).toMatchObject({
      current_count: 3,
      restorable_count: 0,
      restore_available: false,
      freeze_available: false,
      freeze_ready_at: "2026-11-10T22:00:00.000Z",
      freeze_saved_streak: true,
      next_activity_deadline_at: "2026-10-12T22:00:00.000Z",
    });
    expect((await state())!.freeze_used_at).toBeUndefined();

    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await state()).toMatchObject({
      current_count: 3,
      restorable_count: 0,
      freeze_used_at: "2026-10-11T22:00:00.000Z",
      next_activity_deadline_at: "2026-10-12T22:00:00.000Z",
    });
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual(virtual);

    // A second missed day breaks the streak. The restore offer runs from the moved deadline.
    vi.setSystemTime(new Date("2026-10-12T23:00:00.000Z"));
    await t.mutation(internal.streaks.detect_streak_breaks, {});
    expect(await state()).toMatchObject({
      restorable_count: 3,
      restore_deadline: "2026-10-13T22:00:00.000Z",
      freeze_used_at: "2026-10-11T22:00:00.000Z",
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("both partners showing up after the frozen day carry the streak on", async () => {
    const { t, a, b, state } = await bothQualified({ freezeReady: true });
    vi.setSystemTime(new Date("2026-10-12T10:00:00.000Z"));
    await a.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    await answerAll(t, a);
    await answerAll(t, b);
    expect(await state()).toMatchObject({
      current_count: 4,
      longest_count: 4,
      last_qualified_date: "2026-10-12",
      restorable_count: 0,
      freeze_used_at: "2026-10-11T22:00:00.000Z",
    });
    expect((await a.as.query(api.streaks.get_couple_streak, {}))[0]).toMatchObject({
      current_count: 4,
      freeze_available: false,
      freeze_ready_at: "2026-11-10T22:00:00.000Z",
      freeze_saved_streak: false,
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("enqueue_due_streak_reminders", () => {
  test("reminds the partners who have not checked in, once per streak day", async () => {
    const { t, a, b } = await streakCouple();
    await addDevice(t, a.userId);
    await addDevice(t, b.userId);
    await answerAll(t, a);
    await answerAll(t, b);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });

    // Too early: the deadline is more than an hour away.
    vi.setSystemTime(new Date("2026-10-11T12:00:00.000Z"));
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, {})).toBe(0);

    // Within the hour, only the partner who has not contributed today is reminded.
    vi.setSystemTime(new Date("2026-10-11T21:30:00.000Z"));
    await a.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    await answerAll(t, a);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, { p_now: "2026-10-11T21:30:00Z" })).toBe(1);
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox).toHaveLength(1);
    expect(outbox[0]).toMatchObject({
      kind: "streak_reminder",
      recipient_user_id: b.userId,
      apns_collapse_id: `streak:${(await t.run((ctx) => ctx.db.query("couples").first()))!.id}`,
    });
    expect(outbox[0].payload).toMatchObject({
      type: "streak_reminder",
      current_count: 1,
      last_qualified_date: "2026-10-10",
      contribution_needed: true,
      deeplink: "paeonia://streak",
    });
    // Running again does not queue a duplicate.
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, {})).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("reminds each partner at 19:00 local on the last day, once, and not again in the last hour", async () => {
    const { t, a, b } = await streakCouple();
    await addDevice(t, a.userId);
    await addDevice(t, b.userId);
    await answerAll(t, a);
    await answerAll(t, b);
    const clearOutbox = () =>
      t.run(async (ctx) => {
        for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
      });
    await clearOutbox();
    const evening = (now: string) => t.mutation(internal.streaks.enqueue_evening_streak_reminders, { p_now: now });

    // The deadline is 2026-10-11T22:00Z, Oslo midnight. 19:00 in Oslo is 17:00Z.
    expect(await evening("2026-10-11T16:55:00Z")).toBe(0);
    expect(await evening("2026-10-11T17:00:00Z")).toBe(2);
    const sent = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(sent.map((row) => row.recipient_user_id).sort()).toEqual([a.userId, b.userId].sort());
    expect(sent[0]).toMatchObject({ kind: "streak_reminder" });
    expect(await evening("2026-10-11T17:30:00Z")).toBe(0);
    // The hour after 19:00 has passed, so a late run does not send it.
    expect(await evening("2026-10-11T18:05:00Z")).toBe(0);

    // Both partners had the evening reminder, so the last hour stays quiet.
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, { p_now: "2026-10-11T21:30:00Z" })).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the last-hour reminder goes only to a partner who did not get the evening reminder", async () => {
    const { t, a, b } = await streakCouple();
    await addDevice(t, a.userId);
    await addDevice(t, b.userId);
    await answerAll(t, a);
    await answerAll(t, b);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });
    const setStreakReminders = (userId: string, enabled: boolean) =>
      t.run(async (ctx) => {
        const preference = await ctx.db
          .query("notification_preferences")
          .withIndex("by_user_id", (q) => q.eq("user_id", userId))
          .unique();
        await ctx.db.patch(preference!._id, { streak_reminders_enabled: enabled });
      });

    // B has streak reminders off at 19:00, so only A gets the evening reminder.
    await setStreakReminders(b.userId, false);
    expect(await t.mutation(internal.streaks.enqueue_evening_streak_reminders, { p_now: "2026-10-11T17:00:00Z" })).toBe(1);
    // B turns them on later that evening, and gets the last-hour reminder instead. A does not get a second one.
    await setStreakReminders(b.userId, true);
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, { p_now: "2026-10-11T21:30:00Z" })).toBe(1);
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.map((row) => row.recipient_user_id)).toEqual([a.userId, b.userId]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the last-hour reminder skips a partner for whom it is night", async () => {
    const { t, a, b } = await streakCouple();
    await addDevice(t, a.userId);
    await addDevice(t, b.userId);
    await answerAll(t, a);
    await answerAll(t, b);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });
    // The deadline stays 2026-10-11T22:00Z. Seen in Tokyo, 21:30Z is 06:30 the next morning.
    await addDevice(t, b.userId, { timeZone: "Asia/Tokyo", lastSeenAt: "2026-10-11T00:00:00.000Z" });

    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, { p_now: "2026-10-11T21:30:00Z" })).toBe(1);
    const outbox = await t.run((ctx) => ctx.db.query("notification_outbox").collect());
    expect(outbox.map((row) => row.recipient_user_id)).toEqual([a.userId]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a freeze starts a new streak day, so the frozen day gets its own reminders", async () => {
    const { t, a, b } = await bothQualified({ freezeReady: true });
    await addDevice(t, a.userId);
    await addDevice(t, b.userId);
    // detectStreakBreak reads the clock, so move it instead of passing p_now.
    const at = (now: string) => vi.setSystemTime(new Date(now));
    const evening = (now: string) => (at(now), t.mutation(internal.streaks.enqueue_evening_streak_reminders, {}));
    const lastHour = async (now: string) => {
      at(now);
      await t.mutation(internal.streaks.detect_streak_breaks, {});
      return await t.mutation(internal.streaks.enqueue_due_streak_reminders, {});
    };

    // The missed day 2026-10-11: the evening reminder for both partners, so no last-hour reminder.
    expect(await evening("2026-10-11T17:00:00Z")).toBe(2);
    expect(await lastHour("2026-10-11T21:30:00Z")).toBe(0);
    // The deadline passes and the freeze moves it to 2026-10-12T22:00Z.
    expect(await lastHour("2026-10-11T22:05:00Z")).toBe(0);
    expect((await t.run((ctx) => ctx.db.query("streak_states").first()))!.freeze_used_at).toBe("2026-10-11T22:00:00.000Z");
    // The frozen day 2026-10-12 is when the streak is at risk, so it gets its own evening reminder.
    expect(await evening("2026-10-12T17:00:00Z")).toBe(2);
    expect(await lastHour("2026-10-12T21:30:00Z")).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("skips streaks that already broke", async () => {
    const { t, a, b } = await streakCouple();
    await addDevice(t, a.userId);
    await answerAll(t, a);
    await answerAll(t, b);
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    await a.as.query(api.streaks.get_couple_streak, {});
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, {})).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
