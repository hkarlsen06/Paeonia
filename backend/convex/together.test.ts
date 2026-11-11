import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { newUuid } from "./lib/ids";
import { addDaysToDate } from "./lib/time";
import { enqueueNotificationForUser, insertNotificationOutbox } from "./lib/notifications";
import { cleanupCoupleContent } from "./lib/relationshipCleanup";
import { applyCoupleActivity, applyStreakRestore, refreshStreakAfterProfileTimeZoneChange } from "./lib/streaks";
import { endCouple } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, newTest, setTimeZone, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

// Together days through the public functions: visits, location updates, the streak read, the
// streak crons and the push queue. The couple lives in UTC, so a couple day is a UTC date.

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-09T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const at = (iso: string) => vi.setSystemTime(new Date(iso));

let sequence = 0;
const op = () => ({
  p_client_operation_id: newUuid(),
  p_client_id: "00000000-0000-0000-0000-00000000e201",
  p_client_sequence: ++sequence,
  p_local_created_at: new Date().toISOString(),
});

const saveVisit = (user: TestUser, id: string, start: string, end: string) =>
  user.as.mutation(api.visits.save_visit, { p_visit_id: id, p_start_date: start, p_end_date: end, p_place: null, ...op() });
const deleteVisit = (user: TestUser, id: string) => user.as.mutation(api.visits.delete_visit, { p_visit_id: id, ...op() });
const streak = async (user: TestUser) =>
  (await user.as.query(api.streaks.get_couple_streak, { p_day_key: new Date().toISOString() }))[0];
const stored = (t: TestConvex, coupleId: string) =>
  t.run((ctx) => ctx.db.query("streak_states").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).unique());
/** Every date the couple's together_days rows hold. */
const togetherDates = async (t: TestConvex) => {
  const dates = new Set<string>();
  for (const row of await t.run((ctx) => ctx.db.query("together_days").collect())) {
    for (let date = row.start_date; date <= row.end_date; date = addDaysToDate(date, 1)) dates.add(date);
  }
  return [...dates].sort();
};
const breakCron = (t: TestConvex) =>
  t.mutation(internal.streaks.detect_streak_breaks, { p_now: new Date().toISOString() });

/** Both partners do something at noon UTC on `date`, or at `instant` when given. */
async function bothAct(t: TestConvex, couple: TestCouple, date: string, instant = `${date}T12:00:00.000Z`) {
  const noon = instant;
  await t.run(async (ctx) => {
    const dayId = await getOrCreateCoupleDayAt(ctx, couple.coupleId, noon);
    for (const user of [couple.first, couple.second]) {
      await applyCoupleActivity(ctx, {
        couple_id: couple.coupleId,
        user_id: user.userId,
        couple_day_id: dayId,
        activity_kind: "memory_created",
        occurred_at: noon,
        dedupe_key: `${user.userId}:${date}`,
      });
    }
  });
}

/** A streak of `count` days through `date`, with the free freeze spent on `freezeUsedAt` when given. */
async function streakThrough(t: TestConvex, couple: TestCouple, date: string, count: number, freezeUsedAt?: string) {
  await bothAct(t, couple, date);
  const state = await stored(t, couple.coupleId);
  await t.run((ctx) =>
    ctx.db.patch(state!._id, { current_count: count, longest_count: count, freeze_used_at: freezeUsedAt }),
  );
}

async function newCouple(timeZones: [string, string] = ["UTC", "UTC"]) {
  const t = newTest();
  return { t, couple: await createCouple(t, { timeZones }) };
}

/** Profiles in New York and Oslo, which set the couple's date. Both phones in Oslo, which set the streak's deadline. */
async function movedEast() {
  const s = await newCouple(["America/New_York", "Europe/Oslo"]);
  await addDevice(s.t, s.couple.first.userId, { timeZone: "Europe/Oslo" });
  await addDevice(s.t, s.couple.second.userId, { timeZone: "Europe/Oslo" });
  return s;
}

async function shareLocation(couple: TestCouple) {
  for (const user of [couple.first, couple.second]) {
    await user.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: true,
      p_consent_version: "test-v1",
      p_source: "settings_toggle",
      ...op(),
    });
  }
}

async function sharing(timeZones: [string, string] = ["UTC", "UTC"]) {
  const s = await newCouple(timeZones);
  await shareLocation(s.couple);
  return s;
}

const oslo = { latitude: 59.9139, longitude: 10.7522 };
/** About 300 m north of `oslo`. */
const nearby = { latitude: 59.9166, longitude: 10.7522 };
/** About 5 km north of `oslo`. */
const away = { latitude: 59.9589, longitude: 10.7522 };

const send = (
  user: TestUser,
  coupleId: string,
  where: { latitude: number; longitude: number },
  capturedAt: string,
  accuracy: number | null = 20,
) =>
  user.as.mutation(api.location.update_latest_partner_location, {
    p_couple_id: coupleId,
    p_latitude: where.latitude,
    p_longitude: where.longitude,
    p_accuracy_m: accuracy,
    p_captured_at: capturedAt,
    p_source: "foreground_open",
    ...op(),
  });

const visitRow = (t: TestConvex, id: string) =>
  t.run((ctx) => ctx.db.query("visits").withIndex("by_uuid", (q) => q.eq("id", id)).unique());

describe("a day that ended stays what it was (I1)", () => {
  /** A 30-day streak through 2026-10-09, and a visit from 2026-10-10 to 2026-10-13 planned that evening. */
  async function visiting() {
    const s = await newCouple();
    await streakThrough(s.t, s.couple, "2026-10-09", 30);
    at("2026-10-09T20:00:00.000Z");
    const visitId = newUuid();
    await saveVisit(s.couple.first, visitId, "2026-10-10", "2026-10-13");
    return { ...s, visitId };
  }

  test("deleting a visit the day after it ended keeps the streak", async () => {
    const { t, couple, visitId } = await visiting();
    at("2026-10-14T12:00:00.000Z");
    expect(await streak(couple.first)).toMatchObject({ current_count: 30, next_activity_deadline_at: "2026-10-15T00:00:00.000Z" });
    await deleteVisit(couple.second, visitId);
    expect(await streak(couple.first)).toMatchObject({
      current_count: 30,
      next_activity_deadline_at: "2026-10-15T00:00:00.000Z",
      save_available: false,
      restore_available: false,
    });
    expect(await togetherDates(t)).toEqual(["2026-10-10", "2026-10-11", "2026-10-12", "2026-10-13"]);
    await breakCron(t);
    expect(await stored(t, couple.coupleId)).toMatchObject({ current_count: 30, restorable_count: 0 });
  });

  test("deleting a visit on its third day keeps the days that passed, and today needs both", async () => {
    const { t, couple, visitId } = await visiting();
    at("2026-10-12T12:00:00.000Z");
    await deleteVisit(couple.second, visitId);
    expect(await streak(couple.first)).toMatchObject({
      current_count: 30,
      next_activity_deadline_at: "2026-10-13T00:00:00.000Z",
      freeze_available: true,
      freeze_saved_streak: false,
      save_available: false,
      restore_available: false,
    });
    expect((await stored(t, couple.coupleId))?.freeze_used_at).toBeUndefined();
  });

  test("shortening or moving a visit while it runs changes only today and later", async () => {
    const { t, couple, visitId } = await visiting();
    at("2026-10-12T12:00:00.000Z");
    await saveVisit(couple.first, visitId, "2026-10-10", "2026-10-11");
    expect(await streak(couple.first)).toMatchObject({ current_count: 30, next_activity_deadline_at: "2026-10-13T00:00:00.000Z" });
    await saveVisit(couple.first, visitId, "2026-10-20", "2026-10-23");
    expect(await streak(couple.first)).toMatchObject({ current_count: 30, next_activity_deadline_at: "2026-10-13T00:00:00.000Z" });
    expect(await togetherDates(t)).toEqual(["2026-10-10", "2026-10-11"]);
  });

  test("lengthening a visit while it runs moves the deadline to the day after its new end", async () => {
    const { couple, visitId } = await visiting();
    at("2026-10-12T12:00:00.000Z");
    await saveVisit(couple.first, visitId, "2026-10-10", "2026-10-15");
    expect(await streak(couple.first)).toMatchObject({ current_count: 30, next_activity_deadline_at: "2026-10-17T00:00:00.000Z" });
  });
});

describe("a stored break stays final (I2)", () => {
  /** A 30-day streak through 2026-10-09 broke on 2026-10-10, with the free freeze spent recently. */
  async function broken() {
    const s = await newCouple();
    await streakThrough(s.t, s.couple, "2026-10-09", 30, "2026-10-01T00:00:00.000Z");
    at("2026-10-11T00:30:00.000Z");
    await breakCron(s.t);
    expect(await stored(s.t, s.couple.coupleId)).toMatchObject({
      restorable_count: 30,
      save_deadline: "2026-10-12T00:00:00.000Z",
      restore_deadline: "2026-10-14T00:00:00.000Z",
    });
    return s;
  }

  test("a visit saved later over the missed day does not bring the streak back", async () => {
    const { t, couple } = await broken();
    at("2026-10-12T09:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-10", "2026-10-12");
    await bothAct(t, couple, "2026-10-12");
    expect(await streak(couple.first)).toMatchObject({ current_count: 1, restorable_count: 30, restore_available: true });
  });

  test("months later, a backdated visit does not bring it back either", async () => {
    const { t, couple } = await broken();
    at("2026-12-12T09:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-10", "2026-12-12");
    await bothAct(t, couple, "2026-12-12");
    expect(await streak(couple.first)).toMatchObject({ current_count: 1, restorable_count: 0 });
  });
});

describe("a together day needs nothing and costs nothing (I3)", () => {
  test("the free save day and the paid restore days skip a planned visit", async () => {
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-09", 30, "2026-10-01T00:00:00.000Z");
    at("2026-10-09T20:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-11", "2026-10-13");
    at("2026-10-11T00:30:00.000Z");
    await breakCron(t);
    expect(await streak(couple.first)).toMatchObject({
      restorable_count: 30,
      save_deadline: "2026-10-15T00:00:00.000Z",
      restore_deadline: "2026-10-17T00:00:00.000Z",
    });
  });

  test("activity on a together day counts, and the visit's days still need nothing after it", async () => {
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-09", 5);
    at("2026-10-09T20:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-10", "2026-10-13");
    at("2026-10-11T12:00:00.000Z");
    await bothAct(t, couple, "2026-10-11");
    expect(await streak(couple.first)).toMatchObject({
      current_count: 6,
      last_qualified_date: "2026-10-11",
      next_activity_deadline_at: "2026-10-15T00:00:00.000Z",
    });
  });
});

describe("the pause lasts at most 14 days in a row (I4)", () => {
  test("a 20-day visit rests the streak for its first 14 days", async () => {
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-09", 30);
    at("2026-10-09T20:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-10", "2026-10-29");
    expect(await streak(couple.first)).toMatchObject({
      next_activity_deadline_at: "2026-10-25T00:00:00.000Z",
      rest_starts_at: "2026-10-10T00:00:00.000Z",
      rest_ends_at: "2026-10-24T00:00:00.000Z",
    });
  });

  test("back-to-back visits count as one run", async () => {
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-09", 30);
    at("2026-10-09T20:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-10", "2026-10-19");
    await saveVisit(couple.second, newUuid(), "2026-10-20", "2026-10-29");
    expect(await streak(couple.first)).toMatchObject({ next_activity_deadline_at: "2026-10-25T00:00:00.000Z" });
  });
});

describe("save_visit keeps dates the streak can handle (I5)", () => {
  test("refuses a date before 2000, after 2100, and a visit longer than 366 days", async () => {
    const { couple } = await newCouple();
    const refused = async (start: string, end: string) =>
      ((await saveVisit(couple.first, newUuid(), start, end).then(
        () => null,
        (error) => error,
      )) as { data?: { code: string } } | null)?.data?.code;
    expect(await refused("1999-12-31", "2000-01-02")).toBe("23514");
    expect(await refused("2100-12-30", "2101-01-01")).toBe("23514");
    expect(await refused("2026-10-10", "9999-12-31")).toBe("23514");
    expect(await refused("2026-01-01", "2027-01-02")).toBe("23514");
    expect(await refused("2026-01-01", "2027-01-01")).toBeUndefined();
    expect(await streak(couple.first)).toMatchObject({ current_count: 0 });
  });
});

describe("a couple with no together days keeps main's rules (I6)", () => {
  test("a paid restore, a freeze on the next missed day, then both act: the streak goes on, with no save", async () => {
    // Five days through 2026-10-07. The freeze from 2026-09-10 is ready again on 2026-10-10.
    at("2026-10-07T12:00:00.000Z");
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-07", 5, "2026-09-10T00:00:00.000Z");
    at("2026-10-09T00:30:00.000Z");
    await breakCron(t);
    at("2026-10-10T09:00:00.000Z");
    const restored = await t.run((ctx) =>
      applyStreakRestore(ctx, {
        couple_id: couple.coupleId,
        purchaser_user_id: couple.first.userId,
        product_id: "streak_restore",
        environment: "xcode",
        transaction_id: "restore-1",
      }),
    );
    expect(restored).toMatchObject({ ok: true, restoredCount: 5 });
    // 2026-10-10 is missed, and the freeze covers it.
    at("2026-10-11T00:30:00.000Z");
    await breakCron(t);
    expect(await stored(t, couple.coupleId)).toMatchObject({ freeze_used_at: "2026-10-11T00:00:00.000Z" });
    await bothAct(t, couple, "2026-10-11");
    const state = await stored(t, couple.coupleId);
    expect(state).toMatchObject({ current_count: 6, last_qualified_date: "2026-10-11", freeze_used_at: "2026-10-11T00:00:00.000Z" });
    expect(state?.saved_on).toBeUndefined();
  });
});

describe("location (R2)", () => {
  test("a visitor reaching a phone that sat still for hours rests the streak on that day only", async () => {
    const { t, couple } = await sharing();
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    await streakThrough(t, couple, "2026-10-09", 10);
    at("2026-10-10T01:00:00.000Z");
    await send(couple.second, couple.coupleId, oslo, "2026-10-10T01:00:00.000Z");
    at("2026-10-10T12:30:00.000Z");
    await send(couple.first, couple.coupleId, nearby, "2026-10-10T12:29:00.000Z");
    expect(await togetherDates(t)).toEqual(["2026-10-10"]);
    expect(await streak(couple.first)).toMatchObject({
      current_count: 10,
      next_activity_deadline_at: "2026-10-12T00:00:00.000Z",
      rest_starts_at: "2026-10-10T00:00:00.000Z",
      rest_ends_at: "2026-10-11T00:00:00.000Z",
    });
    // The match stores only the day. The evening reminder finds the deadline it moved, stores it, and stays quiet.
    expect(await t.mutation(internal.streaks.enqueue_evening_streak_reminders, { p_now: "2026-10-10T19:05:00.000Z" })).toBe(0);
    expect((await stored(t, couple.coupleId))?.next_activity_deadline_at).toBe("2026-10-12T00:00:00.000Z");
    // The next day needs both of them again, with no new match.
    at("2026-10-11T19:05:00.000Z");
    expect(await t.mutation(internal.streaks.enqueue_evening_streak_reminders, { p_now: "2026-10-11T19:05:00.000Z" })).toBe(2);
  });

  test("a fix apart, a pause or turning sharing off changes no stored day", async () => {
    const { t, couple } = await sharing();
    await streakThrough(t, couple, "2026-10-09", 10);
    at("2026-10-10T12:00:00.000Z");
    await send(couple.second, couple.coupleId, oslo, "2026-10-10T11:00:00.000Z");
    await send(couple.first, couple.coupleId, nearby, "2026-10-10T11:59:00.000Z");
    at("2026-10-10T15:00:00.000Z");
    await send(couple.first, couple.coupleId, away, "2026-10-10T14:59:00.000Z");
    await couple.second.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: true,
      p_consent_version: "test-v1",
      p_source: "settings_toggle",
      p_paused_until: "2026-10-11T06:00:00.000Z",
      ...op(),
    });
    await couple.first.as.mutation(api.location.update_location_sharing_preference, {
      p_couple_id: couple.coupleId,
      p_is_enabled: false,
      p_consent_version: "test-v1",
      p_source: "settings_toggle",
      ...op(),
    });
    expect(await togetherDates(t)).toEqual(["2026-10-10"]);
    expect(await streak(couple.first)).toMatchObject({ current_count: 10, next_activity_deadline_at: "2026-10-12T00:00:00.000Z" });
  });

  test("a fix captured before midnight and sent after it marks no day", async () => {
    const { t, couple } = await sharing();
    at("2026-10-10T23:30:00.000Z");
    await send(couple.second, couple.coupleId, oslo, "2026-10-10T23:30:00.000Z");
    at("2026-10-11T00:10:00.000Z");
    await send(couple.first, couple.coupleId, nearby, "2026-10-10T23:40:00.000Z");
    expect(await togetherDates(t)).toEqual([]);
  });
});

describe("reminders while together", () => {
  test("the streak reminder comes on the first day apart after a visit, though one came before it", async () => {
    const { t, couple } = await newCouple();
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    await streakThrough(t, couple, "2026-10-09", 5);
    const evening = (now: string) => t.mutation(internal.streaks.enqueue_evening_streak_reminders, { p_now: now });
    const lastHour = (now: string) => t.mutation(internal.streaks.enqueue_due_streak_reminders, { p_now: now });
    at("2026-10-10T19:05:00.000Z");
    expect(await evening("2026-10-10T19:05:00.000Z")).toBe(2);
    at("2026-10-10T21:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-10", "2026-10-12");
    expect(await streak(couple.first)).toMatchObject({ next_activity_deadline_at: "2026-10-14T00:00:00.000Z" });
    expect(await evening("2026-10-11T19:05:00.000Z")).toBe(0);
    at("2026-10-13T19:05:00.000Z");
    expect(await evening("2026-10-13T19:05:00.000Z")).toBe(2);
    expect(await lastHour("2026-10-13T23:30:00.000Z")).toBe(0);
  });

  test("new answers in a topic still reach the partner during a visit", async () => {
    const { t, couple } = await newCouple();
    await addDevice(t, couple.first.userId);
    at("2026-10-09T20:00:00.000Z");
    await saveVisit(couple.second, newUuid(), "2026-10-10", "2026-10-12");
    at("2026-10-11T09:00:00.000Z");
    expect(
      await t.run((ctx) =>
        enqueueNotificationForUser(ctx, {
          recipient_user_id: couple.first.userId,
          kind: "topics_waiting",
          payload: { type: "topics_waiting", couple_id: couple.coupleId },
          dedupe_key: "topics_waiting",
        }),
      ),
    ).toBe(1);
  });

  test("a game turn reminder that comes due during a visit waits for the first day apart", async () => {
    const { t, couple } = await newCouple();
    await addDevice(t, couple.first.userId);
    await addDevice(t, couple.second.userId);
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "en" });
    await couple.first.as.mutation(api.boardGames.ensure_board_game, { p_kind: "connect_four" });
    at("2026-10-09T20:00:00.000Z");
    await saveVisit(couple.second, newUuid(), "2026-10-10", "2026-10-13");
    at("2026-10-12T13:00:00.000Z");
    expect(await t.mutation(internal.gameHooks.send_due_game_turn_reminders, {})).toBe(1);
    expect(await deliverDuePushes(t)).toEqual([]);
    at("2026-10-13T13:00:00.000Z");
    expect(await deliverDuePushes(t)).toEqual([]);
    at("2026-10-14T13:00:00.000Z");
    const sent = await deliverDuePushes(t);
    expect(sent.map((push) => push.payload.type)).toEqual(["game_turn_reminder"]);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a queued reminder for a couple that ended is dropped, not thrown", async () => {
    const { t, couple } = await newCouple();
    const device = await addDevice(t, couple.second.userId);
    await t.run((ctx) =>
      insertNotificationOutbox(ctx, {
        recipient_user_id: couple.second.userId,
        target_device_id: device.id,
        push_token_hash: device.push_token_hash,
        apns_environment: "sandbox",
        kind: "streak_reminder",
        payload: { type: "streak_reminder", couple_id: couple.coupleId, next_activity_deadline_at: "2026-10-11T00:00:00.000Z" },
        dedupe_key: "ended",
      }),
    );
    const row = (await t.run((ctx) => ctx.db.query("notification_outbox").first()))!;
    await endCouple(t, couple.coupleId, couple.first.userId);
    expect(
      await couple.second.as.query(api.notificationState.get_obsolete_notifications, {
        p_notification_ids: [row.id],
        p_now: new Date().toISOString(),
      }),
    ).toEqual([row.id]);
    expect(await t.mutation(internal.pushQueue.prepare_notification, { outbox_id: row.id })).toBeNull();
  });
});

describe("what together days keep", () => {
  test("rows older than 45 days go, and the couple's cleanup removes the rest", async () => {
    at("2026-08-20T20:00:00.000Z");
    const { t, couple } = await newCouple();
    const visitId = newUuid();
    await saveVisit(couple.first, visitId, "2026-08-21", "2026-08-30");
    at("2026-09-05T12:00:00.000Z");
    await deleteVisit(couple.first, visitId);
    expect(await togetherDates(t)).toHaveLength(10);
    at("2026-10-09T12:00:00.000Z");
    await t.mutation(internal.retention.prune_expired_rows, {});
    expect(await togetherDates(t)).toEqual(["2026-08-25", "2026-08-26", "2026-08-27", "2026-08-28", "2026-08-29", "2026-08-30"]);
    const row = await t.run(async (ctx) => (await ctx.db.query("couples").collect()).find((c) => c.id === couple.coupleId)!);
    await t.run((ctx) => cleanupCoupleContent(ctx, row, new Date().toISOString()));
    expect(await togetherDates(t)).toEqual([]);
  });
});

describe("what together days keep when the relationship ends", () => {
  test.each(["leaving", "account deletion"])("the noted dates go at once on %s", async (how) => {
    const { t, couple } = await sharing();
    at("2026-10-10T12:00:00.000Z");
    await send(couple.second, couple.coupleId, oslo, "2026-10-10T11:00:00.000Z");
    await send(couple.first, couple.coupleId, nearby, "2026-10-10T11:59:00.000Z");
    expect(await togetherDates(t)).toEqual(["2026-10-10"]);

    if (how === "leaving") await couple.first.as.mutation(api.relationship.leave_relationship, op());
    else await couple.first.as.mutation(api.identity.request_account_deletion, {});

    expect(await togetherDates(t)).toEqual([]);
  });
});

describe("one clock: the streak deadline's zones say which day an instant is on and when it ended (R1)", () => {
  test("a visit deleted an hour after Oslo midnight keeps the together day that just ended", async () => {
    const { t, couple } = await movedEast();
    await streakThrough(t, couple, "2026-10-09", 30);
    at("2026-10-09T20:00:00.000Z");
    const visitId = newUuid();
    await saveVisit(couple.first, visitId, "2026-10-10", "2026-10-12");
    expect(await streak(couple.first)).toMatchObject({ next_activity_deadline_at: "2026-10-13T22:00:00.000Z" });
    // 01:00 on 2026-10-11 in Oslo, where both phones are, and still 2026-10-10 in New York.
    at("2026-10-10T23:00:00.000Z");
    await deleteVisit(couple.second, visitId);
    expect(await togetherDates(t)).toEqual(["2026-10-10"]);
    expect(await streak(couple.first)).toMatchObject({
      current_count: 30,
      next_activity_deadline_at: "2026-10-11T22:00:00.000Z",
    });
    expect((await stored(t, couple.coupleId))?.freeze_used_at).toBeUndefined();
  });

  test("a visit saved an hour after the break cannot reach the day that broke it, and only gives time to save it", async () => {
    const { t, couple } = await movedEast();
    await streakThrough(t, couple, "2026-10-09", 30, "2026-10-01T00:00:00.000Z");
    at("2026-10-10T22:30:00.000Z");
    await breakCron(t);
    expect(await stored(t, couple.coupleId)).toMatchObject({
      restorable_count: 30,
      save_deadline: "2026-10-11T22:00:00.000Z",
      restore_deadline: "2026-10-13T22:00:00.000Z",
    });
    at("2026-10-10T23:00:00.000Z");
    const visitId = newUuid();
    await saveVisit(couple.first, visitId, "2026-10-10", "2026-10-23");
    expect((await visitRow(t, visitId))?.together_from).toBe("2026-10-11");
    // The break stays. The free save day moves to the first day apart.
    expect(await streak(couple.first)).toMatchObject({
      current_count: 0,
      restorable_count: 30,
      save_available: true,
      save_deadline: "2026-10-24T22:00:00.000Z",
    });
    at("2026-10-24T12:00:00.000Z");
    await bothAct(t, couple, "2026-10-24");
    expect(await stored(t, couple.coupleId)).toMatchObject({ current_count: 31, saved_on: "2026-10-24" });
  });

  test("location fixes an hour after Oslo midnight mark the Oslo date, and the stored break stays", async () => {
    const { t, couple } = await movedEast();
    await shareLocation(couple);
    await streakThrough(t, couple, "2026-10-09", 30, "2026-10-01T00:00:00.000Z");
    at("2026-10-10T22:30:00.000Z");
    await breakCron(t);
    at("2026-10-10T23:00:00.000Z");
    await send(couple.second, couple.coupleId, oslo, "2026-10-10T20:00:00.000Z");
    await send(couple.first, couple.coupleId, nearby, "2026-10-10T23:00:00.000Z");
    expect(await togetherDates(t)).toEqual(["2026-10-11"]);
    at("2026-10-24T12:00:00.000Z");
    await bothAct(t, couple, "2026-10-24");
    expect(await stored(t, couple.coupleId)).toMatchObject({ current_count: 1, restorable_count: 0 });
  });
});

describe("the save day and the restore days are worked out when read (R3)", () => {
  test("a visit saved on the save day moves it to the first day apart, and the break stays until both act", async () => {
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-09", 30, "2026-10-01T00:00:00.000Z");
    at("2026-10-11T00:30:00.000Z");
    await breakCron(t);
    at("2026-10-11T08:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-11", "2026-10-15");
    expect(await streak(couple.first)).toMatchObject({
      current_count: 0,
      save_available: true,
      save_deadline: "2026-10-17T00:00:00.000Z",
      restore_deadline: "2026-10-19T00:00:00.000Z",
      rest_starts_at: null,
      rest_ends_at: null,
    });
    at("2026-10-16T12:00:00.000Z");
    expect(await streak(couple.first)).toMatchObject({ current_count: 0, save_available: true });
    await bothAct(t, couple, "2026-10-16");
    expect(await stored(t, couple.coupleId)).toMatchObject({ current_count: 31, saved_on: "2026-10-16", restorable_count: 0 });
  });

  test("a visit saved after the save day ended moves the restore days past it", async () => {
    const { t, couple } = await newCouple();
    await streakThrough(t, couple, "2026-10-09", 30, "2026-10-01T00:00:00.000Z");
    at("2026-10-11T00:30:00.000Z");
    await breakCron(t);
    at("2026-10-12T08:00:00.000Z");
    await saveVisit(couple.first, newUuid(), "2026-10-11", "2026-10-15");
    expect(await streak(couple.first)).toMatchObject({
      save_available: false,
      restore_available: true,
      restore_deadline: "2026-10-18T00:00:00.000Z",
    });
  });
});

describe("the rest is two instants on the streak's clock (R4)", () => {
  test("Los Angeles and Oslo: on the first visit day in Oslo the streak needs both until Los Angeles midnight, and the rest starts then", async () => {
    at("2026-10-08T20:00:00.000Z");
    const { t, couple } = await newCouple(["America/Los_Angeles", "Europe/Oslo"]);
    await addDevice(t, couple.first.userId, { timeZone: "America/Los_Angeles" });
    await addDevice(t, couple.second.userId, { timeZone: "Europe/Oslo" });
    await bothAct(t, couple, "2026-10-08", "2026-10-08T20:00:00.000Z");
    const state = await stored(t, couple.coupleId);
    await t.run((ctx) => ctx.db.patch(state!._id, { current_count: 20, longest_count: 20 }));
    await saveVisit(couple.second, newUuid(), "2026-10-10", "2026-10-13");
    // 08:05 on 2026-10-10 in Oslo, the visit's first day there. 23:05 on 2026-10-09 in Los Angeles.
    at("2026-10-10T06:05:00.000Z");
    expect(
      await t.mutation(internal.streaks.enqueue_due_streak_reminders, { p_now: "2026-10-10T06:05:00.000Z" }),
    ).toBe(2);
    expect(await streak(couple.second)).toMatchObject({
      current_count: 20,
      next_activity_deadline_at: "2026-10-10T07:00:00.000Z",
      rest_starts_at: "2026-10-10T07:00:00.000Z",
      rest_ends_at: "2026-10-14T07:00:00.000Z",
    });
  });
});

describe("no input a person can reach makes a streak read or write throw (R7)", () => {
  test("a profile zone moves from +14 to -11 an hour after a day of a long visit qualified", async () => {
    at("2026-10-01T10:00:00.000Z");
    const { t, couple } = await newCouple(["Pacific/Kiritimati", "Pacific/Kiritimati"]);
    await saveVisit(couple.first, newUuid(), "2026-10-02", "2026-11-30");
    // 10:30Z on 2026-10-20 is 00:30 on 2026-10-21 in Kiritimati.
    at("2026-10-20T10:30:00.000Z");
    await bothAct(t, couple, "2026-10-21", "2026-10-20T10:30:00.000Z");
    at("2026-10-20T10:40:00.000Z");
    await setTimeZone(t, couple.first.userId, "Pacific/Pago_Pago");
    await t.run((ctx) =>
      refreshStreakAfterProfileTimeZoneChange(ctx, couple.first.userId, "Pacific/Kiritimati", "Pacific/Pago_Pago"),
    );
    expect(await streak(couple.first)).toMatchObject({ current_count: 1 });
  });
});
