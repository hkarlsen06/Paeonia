import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { liveInstancesFor, seedCatalog, textQuestions } from "./daily.setup";
import { newUuid } from "./lib/ids";
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
    expect(await a.as.mutation(api.streaks.get_couple_streak, {})).toEqual([
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
    await expect(t.mutation(api.streaks.get_couple_streak, {})).rejects.toThrow(/42501.*authenticated user required/);
    const lonely = await createSignedInUser(t);
    await expect(lonely.as.mutation(api.streaks.get_couple_streak, {})).rejects.toThrow(
      /42501.*active entitled couple access is required/,
    );
  });

  test("a streak that missed its deadline reads zero and opens a restore offer", async () => {
    const { t, a, b } = await streakCouple();
    await answerAll(t, a);
    await answerAll(t, b);
    expect((await a.as.mutation(api.streaks.get_couple_streak, {}))[0].current_count).toBe(1);
    // The deadline is local midnight two days after the qualifying day: 2026-10-11T22:00Z in Oslo.
    vi.setSystemTime(new Date("2026-10-12T00:00:00.000Z"));
    const [broken] = await a.as.mutation(api.streaks.get_couple_streak, {});
    expect(broken).toMatchObject({
      current_count: 0,
      restore_available: true,
      restorable_count: 1,
      restore_deadline: "2026-10-12T22:00:00.000Z",
      current_user_contributed_today: false,
    });
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
    await a.as.mutation(api.streaks.get_couple_streak, {});
    expect(await t.mutation(internal.streaks.enqueue_due_streak_reminders, {})).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
