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
  for (const instance of mine.slice(-3)) {
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
  await couple.first.as.mutation(api.daily.start_daily_challenge, op());
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

  test("a streak that missed its deadline reads zero with a restore offer", async () => {
    const { t, a, b } = await streakCouple();
    await answerAll(t, a);
    await answerAll(t, b);
    expect((await a.as.query(api.streaks.get_couple_streak, {}))[0].current_count).toBe(1);
    // The deadline is local midnight two days after the qualifying day: 2026-10-11T22:00Z in Oslo.
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    const [broken] = await a.as.query(api.streaks.get_couple_streak, {});
    expect(broken).toMatchObject({
      current_count: 0,
      restore_available: true,
      restorable_count: 1,
      restore_deadline: "2026-10-12T22:00:00.000Z",
      current_user_contributed_today: false,
    });
  });
});

async function bothQualified() {
  const ctx = await streakCouple();
  await answerAll(ctx.t, ctx.a);
  await answerAll(ctx.t, ctx.b);
  const state = () => ctx.t.run((db) => db.db.query("streak_states").first());
  return { ...ctx, state };
}

describe("streak break without a write", () => {
  test("the query reports the break virtually, then the cron stores the same state", async () => {
    const { t, a, state } = await bothQualified();
    // The deadline is 2026-10-11T22:00Z, so the restore offer runs to 2026-10-12T22:00Z.
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    const virtual = await a.as.query(api.streaks.get_couple_streak, {});
    expect(virtual[0]).toMatchObject({
      current_count: 0,
      restorable_count: 1,
      restore_available: true,
      restore_deadline: "2026-10-12T22:00:00.000Z",
    });
    // The query wrote nothing.
    expect(await state()).toMatchObject({ current_count: 1, restorable_count: 0, restore_available: false });

    await t.mutation(internal.streaks.enqueue_due_streak_reminders, {});
    expect(await state()).toMatchObject({
      current_count: 1,
      restorable_count: 1,
      restore_available: true,
      restore_deadline: "2026-10-12T22:00:00.000Z",
    });
    expect(await a.as.query(api.streaks.get_couple_streak, {})).toEqual(virtual);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an expired offer agrees too", async () => {
    const { t, a } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-13T00:00:00.000Z"));
    const virtual = await a.as.query(api.streaks.get_couple_streak, {});
    expect(virtual[0]).toMatchObject({ current_count: 0, restorable_count: 1, restore_available: false });
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
    expect(streak).toMatchObject({ current_count: 1, restorable_count: 0, restore_available: false });
    expect((await state())!.next_activity_deadline_at).toBe("2026-10-11T00:00:00.000Z");
    // The cron stores the corrected deadline and does not open an offer.
    await t.mutation(internal.streaks.enqueue_due_streak_reminders, {});
    expect(await state()).toMatchObject({ next_activity_deadline_at: "2026-10-11T22:00:00.000Z", restorable_count: 0 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("already-broken streaks and ended couples don't use up the cron's batch", async () => {
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
          restore_available: false,
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
          restore_available: true,
          restorable_count: 3,
          next_activity_deadline_at: "2026-10-11T01:00:00.000Z",
          updated_at: "2026-10-11T01:00:00.000Z",
        });
      }
    });
    await t.mutation(internal.streaks.enqueue_due_streak_reminders, {});
    expect(await state()).toMatchObject({ restorable_count: 1, restore_available: true });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the cron leaves a streak that already has an offer alone", async () => {
    const { t, state } = await bothQualified();
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    await t.mutation(internal.streaks.enqueue_due_streak_reminders, {});
    const first = await state();
    vi.setSystemTime(new Date("2026-10-12T00:05:00.000Z"));
    await t.mutation(internal.streaks.enqueue_due_streak_reminders, {});
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
    expect(result).toEqual({ ok: true, restoredCount: 1, replayed: false });
    expect(await state()).toMatchObject({ current_count: 1, restorable_count: 0, restore_available: false });
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
    await a.as.mutation(api.daily.start_daily_challenge, op());
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
