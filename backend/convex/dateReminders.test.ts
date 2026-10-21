import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { buildAppRequest } from "./lib/apns";
import { newUuid } from "./lib/ids";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
});
afterEach(() => {
  vi.useRealTimers();
});

/** Moves the clock to `now` and runs the morning cron once. Returns how many pushes it queued. */
async function run(t: TestConvex, now: string) {
  vi.setSystemTime(new Date(now));
  return await t.mutation(internal.dateReminders.enqueue_date_reminders, { p_now: now });
}

const outbox = (t: TestConvex) =>
  t.run(async (ctx) => (await ctx.db.query("notification_outbox").collect()).filter((row) => row.kind === "date_reminder"));

/** A couple in Oslo, each with an English or Norwegian phone. */
async function osloCouple(options: { timeZones?: [string, string]; entitled?: boolean } = {}) {
  const t = newTest();
  const zones = options.timeZones ?? ["Europe/Oslo", "Europe/Oslo"];
  const couple = await createCouple(t, { timeZones: zones, entitled: options.entitled });
  await addDevice(t, couple.first.userId, { timeZone: zones[0], locale: "en" });
  await addDevice(t, couple.second.userId, { timeZone: zones[1], locale: "nb" });
  return { t, couple, a: couple.first, b: couple.second };
}

async function setBirthday(t: TestConvex, couple: TestCouple, user: TestUser, birthday: string) {
  await t.run(async (ctx) => {
    const member = await ctx.db
      .query("couple_members")
      .withIndex("by_user_id_status_couple_id", (q) =>
        q.eq("user_id", user.userId).eq("status", "active").eq("couple_id", couple.coupleId),
      )
      .unique();
    await ctx.db.patch(member!._id, { birthday });
  });
}

async function setStartedOn(t: TestConvex, couple: TestCouple, startedOn: string) {
  await t.run(async (ctx) => {
    const row = (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!;
    await ctx.db.patch(row._id, { started_on: startedOn });
  });
}

async function addCountdown(t: TestConvex, couple: TestCouple, date: string, repeatsYearly = false) {
  await t.run(async (ctx) => {
    const now = new Date().toISOString();
    await ctx.db.insert("countdowns", {
      id: newUuid(),
      couple_id: couple.coupleId,
      title: "Secret trip",
      target_date: date,
      repeats_yearly: repeatsYearly ? true : undefined,
      created_by_user_id: couple.first.userId,
      last_edited_by_user_id: couple.first.userId,
      created_at: now,
      updated_at: now,
    });
  });
}

describe("enqueue_date_reminders", () => {
  test("a birthday: the partner hears on the day in English or Norwegian, and the birthday child gets a warm line", async () => {
    const { t, couple, a, b } = await osloCouple();
    await setBirthday(t, couple, b, "2000-10-21");
    // 09:00 in Oslo on 2026-10-21 is 07:00Z.
    expect(await run(t, "2026-10-21T06:55:00Z")).toBe(0);
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);

    const rows = await outbox(t);
    const forPartner = rows.find((row) => row.recipient_user_id === a.userId)!;
    expect(forPartner).toMatchObject({
      title: "Second Partner has a birthday today",
      body: "Send a message to start their day well.",
      payload: {
        type: "date_reminder",
        reminder: "partner_birthday_today",
        actor_user_id: b.userId,
        route: "dates",
        deeplink: "paeonia://dates",
        expires_at: "2026-10-21T22:00:00.000Z",
      },
    });
    const forChild = rows.find((row) => row.recipient_user_id === b.userId)!;
    expect(forChild).toMatchObject({ title: "Gratulerer med dagen!", body: "Håper du får en fin dag." });
    // The birthday child's push names nobody.
    expect(forChild.payload).not.toHaveProperty("actor_user_id");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a birthday: the partner also hears a week ahead, and the birthday child does not", async () => {
    const { t, couple, a, b } = await osloCouple();
    await setBirthday(t, couple, b, "2000-10-28");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(1);
    const [row] = await outbox(t);
    expect(row).toMatchObject({
      recipient_user_id: a.userId,
      title: "Second Partner has a birthday in a week",
      body: "Time to plan something nice.",
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("sends once per device and occurrence, however many runs see the window", async () => {
    const { t, couple, b } = await osloCouple();
    await setBirthday(t, couple, b, "2000-10-21");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    expect(await run(t, "2026-10-21T07:15:00Z")).toBe(0);
    expect(await run(t, "2026-10-21T07:29:00Z")).toBe(0);
    // The window is 30 minutes. Later in the morning nothing is sent, so a late edit does not ping at noon.
    expect(await run(t, "2026-10-21T07:30:00Z")).toBe(0);
    expect(await outbox(t)).toHaveLength(2);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("each partner gets the reminder on their own morning, so two zones can be a day apart", async () => {
    // Auckland is UTC+13 in October. Its 09:00 on 2026-10-21 is 20:00Z on 2026-10-20.
    const { t, couple, a, b } = await osloCouple({ timeZones: ["Pacific/Auckland", "Europe/Oslo"] });
    await addCountdown(t, couple, "2026-10-21");

    expect(await run(t, "2026-10-20T20:00:00Z")).toBe(1);
    expect((await outbox(t))[0].recipient_user_id).toBe(a.userId);
    // Oslo is still on 20 October at that moment, and gets its push on its own morning.
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(1);
    expect((await outbox(t)).map((row) => row.recipient_user_id).sort()).toEqual([a.userId, b.userId].sort());
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("follows the clock change: 09:00 is 08:00Z in winter and 07:00Z in summer", async () => {
    // Oslo goes from 02:00 to 03:00 on 2026-03-29 and back from 03:00 to 02:00 on 2026-10-25.
    const { t, couple } = await osloCouple();
    await addCountdown(t, couple, "2026-03-28");
    await addCountdown(t, couple, "2026-03-29");
    await addCountdown(t, couple, "2026-10-25");
    // 2026-03-28 is CET (UTC+1).
    expect(await run(t, "2026-03-28T07:00:00Z")).toBe(0);
    expect(await run(t, "2026-03-28T08:00:00Z")).toBe(2);
    // 2026-03-29 is CEST (UTC+2) all day, so 08:00Z is already 10:00.
    expect(await run(t, "2026-03-29T08:00:00Z")).toBe(0);
    expect(await run(t, "2026-03-29T07:00:00Z")).toBe(2);
    // 2026-10-25 is CET again after 01:00Z.
    expect(await run(t, "2026-10-25T07:00:00Z")).toBe(0);
    expect(await run(t, "2026-10-25T08:00:00Z")).toBe(2);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a countdown never puts its title on the lock screen, and several on one day are one push", async () => {
    const { t, couple, a } = await osloCouple();
    await addCountdown(t, couple, "2026-10-21");
    await addCountdown(t, couple, "2026-10-21");
    await addCountdown(t, couple, "2026-10-22");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    const row = (await outbox(t)).find((r) => r.recipient_user_id === a.userId)!;
    expect(row).toMatchObject({
      title: "Today's the day",
      body: "2 dates you've been counting down to are here.",
      payload: { reminder: "countdown", count: 2 },
    });
    expect(JSON.stringify(row)).not.toContain("Secret trip");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a yearly countdown comes back every year", async () => {
    const { t, couple } = await osloCouple();
    await addCountdown(t, couple, "2023-10-21", true);
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    expect(await run(t, "2027-10-21T07:00:00Z")).toBe(2);
    expect(await run(t, "2027-10-22T07:00:00Z")).toBe(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the anniversary: a week ahead and on the day, with the number of years", async () => {
    const { t, couple, a } = await osloCouple();
    await setStartedOn(t, couple, "2023-10-21");
    expect(await run(t, "2026-10-14T07:00:00Z")).toBe(2);
    expect((await outbox(t)).find((r) => r.recipient_user_id === a.userId)).toMatchObject({
      title: "Your anniversary is in a week",
    });
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    const today = (await outbox(t)).filter((r) => r.recipient_user_id === a.userId).map((r) => r.title);
    expect(today).toContain("3 years together today");
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a milestone uses the reader's language and number format", async () => {
    const { t, couple, b } = await osloCouple();
    await setStartedOn(t, couple, "2024-01-25");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    const row = (await outbox(t)).find((r) => r.recipient_user_id === b.userId)!;
    expect(row.title).toMatch(/^1\s000 dager sammen i dag$/);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("stays quiet when the person turned the reminders off", async () => {
    const { t, couple, a, b } = await osloCouple();
    await setBirthday(t, couple, b, "2000-10-21");
    expect(
      await a.as.mutation(api.identity.set_notification_preference, { p_column: "date_reminders_enabled", p_enabled: false }),
    ).toMatchObject({ date_reminders_enabled: false });
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(1);
    expect((await outbox(t)).map((r) => r.recipient_user_id)).toEqual([b.userId]);

    // Turning them off after the push was queued drops it before it goes out.
    await b.as.mutation(api.identity.set_notification_preference, { p_column: "date_reminders_enabled", p_enabled: false });
    expect(await deliverDuePushes(t)).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("is on by default", async () => {
    const { a } = await osloCouple();
    expect(await a.as.query(api.identity.get_notification_preferences, {})).toMatchObject({
      date_reminders_enabled: true,
    });
  });

  test("skips an unentitled couple and a person with no push device", async () => {
    const unentitled = await osloCouple({ entitled: false });
    await addCountdown(unentitled.t, unentitled.couple, "2026-10-21");
    expect(await run(unentitled.t, "2026-10-21T07:00:00Z")).toBe(0);

    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await addDevice(t, couple.second.userId, { timeZone: "Europe/Oslo", locale: "en" });
    await addCountdown(t, couple, "2026-10-21");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(1);
    expect((await outbox(t))[0].recipient_user_id).toBe(couple.second.userId);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("goes out at once in the morning, loud, and expires at the end of the local day", async () => {
    const { t, couple } = await osloCouple();
    await addCountdown(t, couple, "2026-10-21");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    const [prepared] = await deliverDuePushes(t);
    // 09:00 is not a quiet hour, so the existing night rule does not soften it.
    expect(prepared.deliver_quietly).toBe(false);
    expect(buildAppRequest(prepared, "no.paeonia.app").expiration).toBe(
      String(Date.parse("2026-10-21T22:00:00.000Z") / 1000),
    );
    expect(JSON.parse(buildAppRequest(prepared, "no.paeonia.app").body).aps).toMatchObject({
      "thread-id": "dates",
      category: "reminder",
    });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a reminder still waiting when the local day ends is dropped", async () => {
    const { t, couple } = await osloCouple();
    await addCountdown(t, couple, "2026-10-21");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    vi.setSystemTime(new Date("2026-10-21T22:00:01.000Z"));
    expect(await deliverDuePushes(t)).toHaveLength(0);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a reminder queued before the couple broke up never goes out", async () => {
    const { t, couple, a } = await osloCouple();
    await addCountdown(t, couple, "2026-10-21");
    expect(await run(t, "2026-10-21T07:00:00Z")).toBe(2);
    await t.run(async (ctx) => {
      const member = (await ctx.db.query("couple_members").collect()).find(
        (row) => row.user_id === a.userId && row.couple_id === couple.coupleId,
      )!;
      await ctx.db.patch(member._id, { status: "left" });
    });
    const delivered = await deliverDuePushes(t);
    expect(delivered.map((p) => p.target_device_id)).toHaveLength(1);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
