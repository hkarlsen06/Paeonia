import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { currentQuestionFor, seedCatalog, textQuestions } from "./daily.setup";
import { buildAppRequest } from "./lib/apns";
import { newUuid } from "./lib/ids";
import { questionTimeDue } from "./lib/questionTime";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestUser } from "./test.setup";

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

const at = (hhmm: string) => Date.parse(`2026-10-10T${hhmm}:00.000Z`);

describe("questionTimeDue", () => {
  test("is due from the chosen time for fifteen minutes, in the user's own zone", () => {
    // 2026-10-10: Oslo is UTC+2 (20:00 = 18:00Z), New York is UTC-4 (20:00 = 00:00Z the next day).
    expect(questionTimeDue(at("17:59"), "Europe/Oslo", 1200)).toBeNull();
    expect(questionTimeDue(at("18:00"), "Europe/Oslo", 1200)).toEqual({
      localDate: "2026-10-10",
      expiresAt: "2026-10-10T22:00:00.000Z",
    });
    expect(questionTimeDue(at("18:14"), "Europe/Oslo", 1200)?.localDate).toBe("2026-10-10");
    expect(questionTimeDue(at("18:15"), "Europe/Oslo", 1200)).toBeNull();
    expect(questionTimeDue(at("18:00"), "America/New_York", 1200)).toBeNull();
    expect(questionTimeDue(Date.parse("2026-10-11T00:00:00.000Z"), "America/New_York", 1200)).toEqual({
      localDate: "2026-10-10",
      expiresAt: "2026-10-11T04:00:00.000Z",
    });
  });

  test("a window never crosses local midnight, so a late run does not send yesterday's reminder", async () => {
    // 23:55 in Oslo is 21:55Z. A run at 23:58 (21:58Z) sends it and it expires at midnight (22:00Z).
    expect(questionTimeDue(at("21:58"), "Europe/Oslo", 23 * 60 + 55)).toEqual({
      localDate: "2026-10-10",
      expiresAt: "2026-10-10T22:00:00.000Z",
    });
    // A run at 00:05 (22:05Z) sees the next date, where 23:55 is not due yet.
    expect(questionTimeDue(at("22:05"), "Europe/Oslo", 23 * 60 + 55)).toBeNull();
  });

  test("a time in the hour the clocks skip is due one hour later", () => {
    // 2026-03-29: Oslo goes from 02:00 to 03:00. 02:30 does not exist, so it lands on 03:30 (01:30Z).
    const due = (iso: string) => questionTimeDue(Date.parse(iso), "Europe/Oslo", 2 * 60 + 30);
    expect(due("2026-03-29T01:00:00.000Z")).toBeNull();
    expect(due("2026-03-29T01:30:00.000Z")).toEqual({
      localDate: "2026-03-29",
      expiresAt: "2026-03-29T22:00:00.000Z",
    });
    expect(due("2026-03-29T01:45:00.000Z")).toBeNull();
  });

  test("a time in the hour the clocks repeat is due once", () => {
    // 2026-10-25: Oslo goes back from 03:00 to 02:00. 02:30 happens at 00:30Z and 01:30Z.
    // The later one counts, and the earlier pass stays quiet.
    const due = (iso: string) => questionTimeDue(Date.parse(iso), "Europe/Oslo", 2 * 60 + 30);
    expect(due("2026-10-25T00:30:00.000Z")).toBeNull();
    expect(due("2026-10-25T01:30:00.000Z")?.localDate).toBe("2026-10-25");
    // A normal evening time on that 25-hour day: 20:00 CET is 19:00Z, and the day ends at 23:00Z.
    expect(questionTimeDue(Date.parse("2026-10-25T19:00:00.000Z"), "Europe/Oslo", 1200)).toEqual({
      localDate: "2026-10-25",
      expiresAt: "2026-10-25T23:00:00.000Z",
    });
  });
});

async function questionCouple(options: { entitled?: boolean } = {}) {
  const t = newTest();
  await seedCatalog(t, textQuestions(12));
  const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"], entitled: options.entitled });
  await addDevice(t, couple.first.userId, { timeZone: "Europe/Oslo", locale: "en" });
  await addDevice(t, couple.second.userId, { timeZone: "Europe/Oslo", locale: "nb" });
  return { t, a: couple.first, b: couple.second };
}

const enable = (user: TestUser, minutes = 1200) =>
  user.as.mutation(api.identity.set_question_time_reminder, { p_enabled: true, p_minutes: minutes });
const run = (t: TestConvex, now: string) =>
  t.mutation(internal.questionTime.enqueue_question_time_reminders, { p_now: now });
// Only reminder rows. Answering questions also queues partner pushes such as daily_challenge_completed.
const outbox = (t: TestConvex) =>
  t.run(async (ctx) =>
    (await ctx.db.query("notification_outbox").collect()).filter((row) => row.kind === "question_time_reminder"),
  );

async function answer(t: TestConvex, user: TestUser) {
  await user.as.mutation(api.daily.submit_daily_answer, {
    p_instance_id: (await currentQuestionFor(t, user.userId)).id,
    p_payload: { text: "ok" },
    ...op(),
  });
}

describe("set_question_time_reminder", () => {
  test("is off at 20:00 by default, saves both values, and rejects a time outside the day", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    expect(await user.as.query(api.identity.get_notification_preferences, {})).toMatchObject({
      question_time_enabled: false,
      question_time_minutes: 1200,
    });
    expect(await enable(user, 7 * 60 + 30)).toMatchObject({ question_time_enabled: true, question_time_minutes: 450 });
    for (const bad of [-1, 1440, 12.5]) {
      await expect(
        user.as.mutation(api.identity.set_question_time_reminder, { p_enabled: true, p_minutes: bad }),
      ).rejects.toThrow();
    }
    expect(await user.as.query(api.identity.get_notification_preferences, {})).toMatchObject({
      question_time_minutes: 450,
    });
  });

  test("the generic switch endpoint does not change it", async () => {
    const t = newTest();
    const user = await createSignedInUser(t, {});
    await expect(
      user.as.mutation(api.identity.set_notification_preference, { p_column: "question_time_enabled", p_enabled: true }),
    ).rejects.toThrow();
  });
});

describe("enqueue_question_time_reminders", () => {
  test("sends Paeonia's own copy at the chosen time, once per local date, to the person who chose it", async () => {
    const { t, a, b } = await questionCouple();
    await enable(a);
    expect(await run(t, "2026-10-10T17:55:00Z")).toBe(0);
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    const [row] = await outbox(t);
    expect(row).toMatchObject({
      kind: "question_time_reminder",
      recipient_user_id: a.userId,
      title: "Today's question is ready",
      body: "Today's question is waiting. It takes a minute or two.",
      payload: {
        type: "question_time_reminder",
        route: "daily",
        deeplink: "paeonia://daily/today",
        expires_at: "2026-10-10T22:00:00.000Z",
      },
    });
    expect(JSON.stringify(row.payload)).not.toContain(b.userId);
    // Later runs inside the window and a changed time on the same date add nothing.
    expect(await run(t, "2026-10-10T18:05:00Z")).toBe(0);
    await enable(a, 20 * 60 + 5);
    expect(await run(t, "2026-10-10T18:05:00Z")).toBe(0);
    // The next local date gets its own reminder.
    vi.setSystemTime(new Date("2026-10-11T18:00:00.000Z"));
    expect(await run(t, "2026-10-11T18:05:00Z")).toBe(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("uses the Norwegian copy for a Norwegian phone", async () => {
    const { t, b } = await questionCouple();
    await enable(b);
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    expect((await outbox(t))[0]).toMatchObject({
      title: "Dagens spørsmål er klart",
      body: "Dagens spørsmål venter. Det tar bare et par minutter.",
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("does nothing while the reminder is off, also after it was turned off again", async () => {
    const { t, a } = await questionCouple();
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(0);
    await enable(a);
    await a.as.mutation(api.identity.set_question_time_reminder, { p_enabled: false, p_minutes: 1200 });
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(0);
    expect(await outbox(t)).toHaveLength(0);
  });

  test("follows the phone's time zone, not the partner's", async () => {
    const { t, a } = await questionCouple();
    await addDevice(t, a.userId, { timeZone: "America/New_York", lastSeenAt: "2026-10-10T12:00:00.000Z" });
    await enable(a);
    // 20:00 in Oslo is not 20:00 on the phone that was seen last.
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(0);
    vi.setSystemTime(new Date("2026-10-11T00:00:00.000Z"));
    expect(await run(t, "2026-10-11T00:00:00Z")).toBe(2);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("still sends on a day nobody opened, and when only the partner answered", async () => {
    const { t, a, b } = await questionCouple();
    await enable(a);
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);

    // The next day the partner answers first. That does not stop a's reminder.
    vi.setSystemTime(new Date("2026-10-11T10:00:00.000Z"));
    await b.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    await answer(t, b);
    expect(await run(t, "2026-10-11T18:00:00Z")).toBe(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("skips someone who answered today's question", async () => {
    const { t, a, b } = await questionCouple();
    await enable(a);
    await enable(b);
    vi.setSystemTime(new Date("2026-10-10T17:00:00.000Z"));
    await a.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    await answer(t, a);
    // a has answered, b has not.
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    expect((await outbox(t)).map((row) => row.recipient_user_id)).toEqual([b.userId]);

    // Once b answers too, the next run (without the earlier row to dedupe against) sends nothing.
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("notification_outbox").collect()) await ctx.db.delete(row._id);
    });
    await answer(t, b);
    expect(await run(t, "2026-10-10T18:05:00Z")).toBe(0);
    expect(await outbox(t)).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("skips an unpaired user, an unentitled couple, and a phone that cannot get pushes", async () => {
    const lone = newTest();
    const loner = await createSignedInUser(lone, { timeZone: "Europe/Oslo" });
    await addDevice(lone, loner.userId, { timeZone: "Europe/Oslo" });
    await enable(loner);
    expect(await run(lone, "2026-10-10T18:00:00Z")).toBe(0);

    const free = await questionCouple({ entitled: false });
    await enable(free.a);
    expect(await run(free.t, "2026-10-10T18:00:00Z")).toBe(0);

    const { t, a } = await questionCouple();
    await t.run(async (ctx) => {
      for (const device of await ctx.db.query("user_devices").collect()) {
        await ctx.db.patch(device._id, { disabled_at: "2026-10-09T00:00:00.000Z" });
      }
    });
    await enable(a);
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(0);
    expect(await outbox(t)).toHaveLength(0);
  });

  test("expires at the end of the user's local day and is dropped after it", async () => {
    const { t, a } = await questionCouple();
    await enable(a);
    vi.setSystemTime(new Date("2026-10-10T18:00:00.000Z"));
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    const [prepared] = await deliverDuePushes(t);
    expect(buildAppRequest(prepared, "no.paeonia.app").expiration).toBe(
      String(Date.parse("2026-10-10T22:00:00.000Z") / 1000),
    );

    // A row that is still waiting when the local day ends never goes out.
    const { t: t2, a: a2 } = await questionCouple();
    await enable(a2);
    expect(await run(t2, "2026-10-10T18:00:00Z")).toBe(1);
    vi.setSystemTime(new Date("2026-10-10T22:00:01.000Z"));
    expect(await deliverDuePushes(t2)).toHaveLength(0);
    expect((await outbox(t2))[0]).toMatchObject({ last_error: "notification is out of date" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    await t2.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("answering a question after the reminder was queued drops it before the send", async () => {
    const { t, a } = await questionCouple();
    await enable(a);
    vi.setSystemTime(new Date("2026-10-10T17:00:00.000Z"));
    await a.as.mutation(api.daily.start_daily_challenge_snapshot, op());
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    vi.setSystemTime(new Date("2026-10-10T18:00:30.000Z"));
    await answer(t, a);
    expect(await deliverDuePushes(t)).toHaveLength(0);
    expect((await outbox(t))[0]).toMatchObject({ last_error: "notification is out of date" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("turning it off before the send drops the row", async () => {
    const { t, a } = await questionCouple();
    await enable(a);
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    await a.as.mutation(api.identity.set_question_time_reminder, { p_enabled: false, p_minutes: 1200 });
    vi.setSystemTime(new Date("2026-10-10T18:00:01.000Z"));
    expect(await deliverDuePushes(t)).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("is not streak activity", async () => {
    const { t, a } = await questionCouple();
    await enable(a);
    expect(await run(t, "2026-10-10T18:00:00Z")).toBe(1);
    expect(await t.run((ctx) => ctx.db.query("couple_activity_events").collect())).toHaveLength(0);
    expect(await t.run((ctx) => ctx.db.query("streak_states").collect())).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
