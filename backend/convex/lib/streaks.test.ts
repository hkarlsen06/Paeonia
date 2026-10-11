import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { addDevice, createCouple, newTest, setTimeZone, type TestConvex } from "../test.setup";
import { newUuid } from "./ids";
import {
  applyCoupleActivity,
  applyStreakRestore,
  detectStreakBreak,
  getCoupleDayStreakQualifiedAt,
  getCoupleStreakForCouple,
  getCoupleStreakParticipationForUser,
  recordCoupleActivity,
  refreshStreakAfterDeviceTimeZoneChange,
  refreshStreakAfterProfileTimeZoneChange,
  resolveNextActivityDeadlineAt,
  resolveStreakDeadlineAt,
} from "./streaks";
import { getOrCreateCoupleDayAt } from "./coupleDays";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-10T12:00:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

async function streakState(t: TestConvex, coupleId: string) {
  return await t.run((ctx) =>
    ctx.db.query("streak_states").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).unique(),
  );
}

async function insertDay(t: TestConvex, coupleId: string, localDate: string, startsAt: string, endsAt: string) {
  const id = newUuid();
  await t.run((ctx) =>
    ctx.db.insert("couple_days", {
      id,
      couple_id: coupleId,
      local_date: localDate,
      anchor_time_zone_id: "UTC",
      starts_at: startsAt,
      ends_at: endsAt,
      created_at: "2026-10-10T00:00:00.000Z",
    }),
  );
  return id;
}

describe("streak deadlines", () => {
  test("daylight saving uses midnight after the next local day, not a fixed 48 hours", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const result = await t.run(async (ctx) => [
      await resolveNextActivityDeadlineAt(ctx, couple.coupleId, "2026-03-28T12:00:00.000Z"),
      await resolveNextActivityDeadlineAt(ctx, couple.coupleId, "2026-10-24T12:00:00.000Z"),
    ]);
    expect(result).toEqual(["2026-03-29T22:00:00.000Z", "2026-10-25T23:00:00.000Z"]);
  });

  test("the streak waits for the partner whose midnight comes last, and a device zone beats the profile zone", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const observed = "2099-07-13T12:00:00.000Z";
    await addDevice(t, couple.second.userId, { timeZone: "America/Los_Angeles" });
    expect(await t.run((ctx) => resolveNextActivityDeadlineAt(ctx, couple.coupleId, observed))).toBe(
      "2099-07-15T07:00:00.000Z",
    );
    await setTimeZone(t, couple.second.userId, "Pacific/Auckland");
    expect(await t.run((ctx) => resolveNextActivityDeadlineAt(ctx, couple.coupleId, observed))).toBe(
      "2099-07-15T07:00:00.000Z",
    );
    expect(await t.run((ctx) => resolveStreakDeadlineAt(ctx, couple.coupleId, observed, 1))).toBe(
      "2099-07-14T07:00:00.000Z",
    );
  });

  test("ignores disabled devices and devices with invalid zones", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const observed = "2099-07-13T12:00:00.000Z";
    const disabled = await addDevice(t, couple.second.userId, { timeZone: "Pacific/Auckland" });
    await t.run((ctx) => ctx.db.patch(disabled._id, { disabled_at: "2026-10-10T11:00:00.000Z" }));
    await addDevice(t, couple.second.userId, { timeZone: "Mars/Olympus" });
    expect(await t.run((ctx) => resolveNextActivityDeadlineAt(ctx, couple.coupleId, observed))).toBe(
      "2099-07-14T22:00:00.000Z",
    );
  });

  test("validates its inputs", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await expect(t.run((ctx) => resolveStreakDeadlineAt(ctx, couple.coupleId, "2026-01-01T00:00:00.000Z", 3))).rejects.toThrow(
      /23514.*local deadline offset must be one or two days/,
    );
    await expect(t.run((ctx) => resolveStreakDeadlineAt(ctx, null, "2026-01-01T00:00:00.000Z", 1))).rejects.toThrow(
      /23514.*couple and observed timestamp are required/,
    );
    await expect(
      t.run((ctx) => resolveStreakDeadlineAt(ctx, newUuid(), "2026-01-01T00:00:00.000Z", 1)),
    ).rejects.toThrow(/23514.*active couple members are required/);
  });

  test("drawings from both partners start the streak, and zone changes move the live deadline", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Pacific/Auckland"] });
    const observed = "2099-07-13T12:00:00.000Z";
    const device = await addDevice(t, couple.second.userId, { timeZone: "America/Los_Angeles" });
    const dayId = await t.run((ctx) => getOrCreateCoupleDayAt(ctx, couple.coupleId, observed));
    await t.run(async (ctx) => {
      await applyCoupleActivity(ctx, {
        couple_id: couple.coupleId,
        user_id: couple.first.userId,
        couple_day_id: dayId,
        activity_kind: "widget_drawing_saved",
        occurred_at: observed,
        dedupe_key: "streak-deadline-test:drawing",
      });
      await applyCoupleActivity(ctx, {
        couple_id: couple.coupleId,
        user_id: couple.second.userId,
        couple_day_id: dayId,
        activity_kind: "widget_drawing_saved",
        occurred_at: observed,
        dedupe_key: "streak-deadline-test:partner-drawing",
      });
    });
    expect(await streakState(t, couple.coupleId)).toMatchObject({ current_count: 1 });
    const event = await t.run((ctx) =>
      ctx.db.query("couple_activity_events").withIndex("by_dedupe_key", (q) => q.eq("dedupe_key", "streak-deadline-test:drawing")).unique(),
    );
    expect(event?.activity_kind).toBe("widget_drawing_saved");

    // Profile zone changes do not matter while a device zone is active.
    await setTimeZone(t, couple.second.userId, "America/Los_Angeles");
    await t.run((ctx) => refreshStreakAfterProfileTimeZoneChange(ctx, couple.second.userId, "Pacific/Auckland", "America/Los_Angeles"));
    expect((await streakState(t, couple.coupleId))?.next_activity_deadline_at).toBe("2099-07-15T07:00:00.000Z");

    // Travel reported by the active device moves the deadline again.
    const lastSeen = "2026-10-10T12:00:01.000Z";
    await t.run((ctx) => ctx.db.patch(device._id, { time_zone_id: "Pacific/Auckland", last_seen_at: lastSeen }));
    await t.run((ctx) =>
      refreshStreakAfterDeviceTimeZoneChange(
        ctx,
        couple.second.userId,
        { time_zone_id: "Pacific/Auckland", last_seen_at: lastSeen },
        { time_zone_id: "America/Los_Angeles", last_seen_at: device.last_seen_at },
      ),
    );
    expect((await streakState(t, couple.coupleId))?.next_activity_deadline_at).toBe("2099-07-15T12:00:00.000Z");
  });

  test("an unchanged device update does not refresh anything", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["UTC", "UTC"] });
    const snapshot = { time_zone_id: "UTC", last_seen_at: "2026-10-10T12:00:00.000Z" };
    await t.run((ctx) => refreshStreakAfterDeviceTimeZoneChange(ctx, couple.first.userId, snapshot, snapshot));
    expect(await streakState(t, couple.coupleId)).toBeNull();
  });
});

describe("mutual participation", () => {
  async function setup() {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["UTC", "UTC"] });
    const yesterday = await insertDay(t, couple.coupleId, "2026-10-09", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z");
    const today = await insertDay(t, couple.coupleId, "2026-10-10", "2026-10-10T00:00:00.000Z", "2026-10-11T00:00:00.000Z");
    const activity = (userId: string, dayId: string, kind: string, at: string, key: string) =>
      t.run((ctx) =>
        applyCoupleActivity(ctx, {
          couple_id: couple.coupleId,
          user_id: userId,
          couple_day_id: dayId,
          activity_kind: kind,
          occurred_at: at,
          dedupe_key: key,
        }),
      );
    return { t, couple, yesterday, today, activity };
  }

  test("one partner cannot start or extend the streak, repeat events do not qualify the day", async () => {
    const { t, couple, yesterday, today, activity } = await setup();
    await activity(couple.first.userId, yesterday, "daily_challenge_completed", "2026-10-09T10:00:00.000Z", "first-a");
    expect(await streakState(t, couple.coupleId)).toBeNull();
    await activity(couple.first.userId, yesterday, "widget_drawing_saved", "2026-10-09T11:00:00.000Z", "second-a");
    expect(await t.run((ctx) => getCoupleDayStreakQualifiedAt(ctx, couple.coupleId, yesterday))).toBeNull();

    await activity(couple.second.userId, yesterday, "memory_created", "2026-10-09T12:00:00.000Z", "first-b");
    expect(await streakState(t, couple.coupleId)).toMatchObject({ current_count: 1, longest_count: 1, last_qualified_date: "2026-10-09" });
    expect(await t.run((ctx) => getCoupleDayStreakQualifiedAt(ctx, couple.coupleId, yesterday))).toBe(
      "2026-10-09T12:00:00.000Z",
    );

    await activity(couple.first.userId, today, "thread_message_sent", "2026-10-10T10:00:00.000Z", "next-day-a");
    expect((await streakState(t, couple.coupleId))?.current_count).toBe(1);

    expect(
      await t.run((ctx) =>
        getCoupleStreakParticipationForUser(ctx, couple.coupleId, couple.first.userId, "2026-10-10T23:30:00.000Z"),
      ),
    ).toEqual({ current_user_contributed_today: true, partner_contributed_today: false });
    expect(
      await t.run((ctx) =>
        getCoupleStreakParticipationForUser(ctx, couple.coupleId, couple.second.userId, "2026-10-10T23:30:00.000Z"),
      ),
    ).toEqual({ current_user_contributed_today: false, partner_contributed_today: true });
  });

  test("both partners on the next day extend the streak", async () => {
    const { t, couple, yesterday, today, activity } = await setup();
    await activity(couple.first.userId, yesterday, "memory_created", "2026-10-09T10:00:00.000Z", "a1");
    await activity(couple.second.userId, yesterday, "memory_created", "2026-10-09T11:00:00.000Z", "b1");
    await activity(couple.first.userId, today, "memory_created", "2026-10-10T09:00:00.000Z", "a2");
    await activity(couple.second.userId, today, "memory_created", "2026-10-10T10:00:00.000Z", "b2");
    expect(await streakState(t, couple.coupleId)).toMatchObject({
      current_count: 2,
      longest_count: 2,
      last_qualified_date: "2026-10-10",
      restorable_count: 0,
      // Local midnight two days after 2026-10-10 in UTC.
      next_activity_deadline_at: "2026-10-12T00:00:00.000Z",
    });
  });

  test("a gap longer than the deadline restarts at one and offers a restore", async () => {
    const { t, couple, yesterday, activity } = await setup();
    await activity(couple.first.userId, yesterday, "memory_created", "2026-10-09T10:00:00.000Z", "a1");
    await activity(couple.second.userId, yesterday, "memory_created", "2026-10-09T11:00:00.000Z", "b1");
    // Deadline was 2026-10-11T00:00Z. A day qualifying after it breaks the streak.
    const late = await insertDay(t, couple.coupleId, "2026-10-12", "2026-10-12T00:00:00.000Z", "2026-10-13T00:00:00.000Z");
    await activity(couple.first.userId, late, "memory_created", "2026-10-12T09:00:00.000Z", "a3");
    await activity(couple.second.userId, late, "memory_created", "2026-10-12T10:00:00.000Z", "b3");
    expect(await streakState(t, couple.coupleId)).toMatchObject({
      current_count: 1,
      longest_count: 1,
      restorable_count: 1,
      restorable_through_date: "2026-10-09",
      restore_deadline: "2026-10-12T00:00:00.000Z",
    });
  });

  test("dedupe keys make repeats a no-op that returns the first event id", async () => {
    const { t, couple, yesterday, activity } = await setup();
    const first = await activity(couple.first.userId, yesterday, "memory_created", "2026-10-09T10:00:00.000Z", "same");
    const second = await activity(couple.first.userId, yesterday, "memory_created", "2026-10-09T10:05:00.000Z", " same ");
    expect(second).toBe(first);
    expect(await t.run(async (ctx) => (await ctx.db.query("couple_activity_events").collect()).length)).toBe(1);
  });

  test("validates the activity", async () => {
    const { t, couple, yesterday } = await setup();
    const base = {
      couple_id: couple.coupleId,
      user_id: couple.first.userId,
      couple_day_id: yesterday,
      activity_kind: "memory_created",
      dedupe_key: "k",
    };
    await expect(t.run((ctx) => applyCoupleActivity(ctx, { ...base, activity_kind: "nope" }))).rejects.toThrow(
      /23514.*couple activity kind is not supported/,
    );
    await expect(t.run((ctx) => applyCoupleActivity(ctx, { ...base, dedupe_key: "  " }))).rejects.toThrow(
      /couple activity dedupe key is required/,
    );
    await expect(t.run((ctx) => applyCoupleActivity(ctx, { ...base, couple_day_id: newUuid() }))).rejects.toThrow(
      /couple activity day is invalid/,
    );
    await expect(t.run((ctx) => applyCoupleActivity(ctx, { ...base, user_id: newUuid() }))).rejects.toThrow(
      /couple activity user must be an active couple member/,
    );
  });

  test("recordCoupleActivity is idempotent per client operation", async () => {
    const { t, couple } = await setup();
    const client = {
      client_operation_id: newUuid(),
      client_id: newUuid(),
      client_sequence: 1,
      local_created_at: "2026-10-10T12:00:00.000Z",
    };
    const args = { activity_kind: "memory_created", dedupe_key: "record-1", client };
    const first = await couple.first.as.run((ctx) => recordCoupleActivity(ctx, couple.first.userId, args));
    const second = await couple.first.as.run((ctx) => recordCoupleActivity(ctx, couple.first.userId, args));
    expect(second).toBe(first);
    expect(await t.run(async (ctx) => (await ctx.db.query("couple_activity_events").collect()).length)).toBe(1);
    await expect(
      couple.first.as.run((ctx) =>
        recordCoupleActivity(ctx, couple.first.userId, { ...args, dedupe_key: "record-2" }),
      ),
    ).rejects.toThrow(/client operation replay hash mismatch/);
  });

  test("a restore does not add today when only one partner contributed", async () => {
    const { t, couple, yesterday, today, activity } = await setup();
    await activity(couple.first.userId, yesterday, "memory_created", "2026-10-09T10:00:00.000Z", "a1");
    await activity(couple.second.userId, yesterday, "memory_created", "2026-10-09T11:00:00.000Z", "b1");
    await activity(couple.first.userId, today, "memory_created", "2026-10-10T09:00:00.000Z", "a2");
    const state = await streakState(t, couple.coupleId);
    await t.run((ctx) =>
      ctx.db.patch(state!._id, {
        current_count: 1,
        longest_count: 9,
        next_activity_deadline_at: "2026-10-10T11:00:00.000Z",
        restore_available: true,
        restorable_count: 9,
        restorable_through_date: "2026-10-09",
        restore_deadline: "2026-10-10T13:00:00.000Z",
      }),
    );
    const restore = {
      couple_id: couple.coupleId,
      purchaser_user_id: couple.first.userId,
      product_id: newUuid(),
      environment: "sandbox" as const,
      transaction_id: "restore-tx",
      original_transaction_id: "restore-original",
      purchased_at: "2026-10-10T12:00:00.000Z",
    };
    expect(await t.run((ctx) => applyStreakRestore(ctx, restore))).toEqual({ ok: true, restoredCount: 9, replayed: false });
    expect(await streakState(t, couple.coupleId)).toMatchObject({
      current_count: 9,
      longest_count: 9,
      last_qualified_date: "2026-10-09",
      restorable_count: 0,
      restore_available: false,
      last_restore_transaction_id: "restore-tx",
    });
    expect(await t.run((ctx) => applyStreakRestore(ctx, restore))).toEqual({ ok: true, restoredCount: 9, replayed: true });
    expect(
      await t.run((ctx) => applyStreakRestore(ctx, { ...restore, transaction_id: "another-tx" })),
    ).toEqual({ ok: false, error: "No streak is available to restore", status: 409 });
  });

  test("a restore adds today when both partners contributed", async () => {
    const { t, couple, yesterday, today, activity } = await setup();
    await activity(couple.first.userId, yesterday, "memory_created", "2026-10-09T10:00:00.000Z", "a1");
    await activity(couple.second.userId, yesterday, "memory_created", "2026-10-09T11:00:00.000Z", "b1");
    await activity(couple.first.userId, today, "memory_created", "2026-10-10T09:00:00.000Z", "a2");
    await activity(couple.second.userId, today, "memory_created", "2026-10-10T10:00:00.000Z", "b2");
    const state = await streakState(t, couple.coupleId);
    await t.run((ctx) =>
      ctx.db.patch(state!._id, { restorable_count: 4, restorable_through_date: "2026-10-08", restore_deadline: "2026-10-10T13:00:00.000Z" }),
    );
    const result = await t.run((ctx) =>
      applyStreakRestore(ctx, {
        couple_id: couple.coupleId,
        purchaser_user_id: couple.first.userId,
        product_id: newUuid(),
        environment: "sandbox",
        transaction_id: "restore-tx-2",
      }),
    );
    expect(result).toEqual({ ok: true, restoredCount: 5, replayed: false });
    expect(await streakState(t, couple.coupleId)).toMatchObject({ current_count: 5, last_qualified_date: "2026-10-10" });
  });
});

describe("restore around daylight saving", () => {
  // In Oslo 2026-03-29 has 23 hours and 2026-10-25 has 25 hours.
  test.each([
    ["the first hour after the spring change", "2026-03-29T22:30:00.000Z", "2026-03-29", "2026-03-30T22:00:00.000Z"],
    ["the last hour of the autumn change", "2026-10-25T22:30:00.000Z", "2026-10-24", "2026-10-25T23:00:00.000Z"],
  ])("a restore in %s counts yesterday by the calendar", async (_name, now, yesterday, deadline) => {
    vi.setSystemTime(new Date(now));
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await t.run((ctx) =>
      ctx.db.insert("streak_states", {
        couple_id: couple.coupleId,
        current_count: 0,
        longest_count: 6,
        restore_available: true,
        restorable_count: 6,
        restorable_through_date: "2026-01-01",
        restore_deadline: new Date(Date.parse(now) + 3_600_000).toISOString(),
        updated_at: now,
      }),
    );
    const result = await t.run((ctx) =>
      applyStreakRestore(ctx, {
        couple_id: couple.coupleId,
        purchaser_user_id: couple.first.userId,
        product_id: newUuid(),
        environment: "sandbox",
        transaction_id: `restore-${now}`,
      }),
    );
    expect(result).toEqual({ ok: true, restoredCount: 6, replayed: false });
    // The couple keeps all of today to check in.
    expect(await streakState(t, couple.coupleId)).toMatchObject({
      current_count: 6,
      last_qualified_date: yesterday,
      next_activity_deadline_at: deadline,
    });
  });
});

describe("streak read model", () => {
  async function setup() {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["UTC", "UTC"] });
    const dayId = await insertDay(t, couple.coupleId, "2026-10-09", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z");
    await t.run(async (ctx) => {
      await ctx.db.insert("streak_states", {
        couple_id: couple.coupleId,
        current_count: 5,
        longest_count: 8,
        last_qualified_date: "2026-10-09",
        last_qualified_couple_day_id: dayId,
        restore_available: false,
        next_activity_deadline_at: "2026-10-10T13:00:00.000Z",
        updated_at: "2026-10-10T00:00:00.000Z",
        restorable_count: 0,
      });
      await ctx.db.insert("couple_activity_events", {
        id: newUuid(),
        couple_id: couple.coupleId,
        user_id: couple.first.userId,
        couple_day_id: dayId,
        activity_kind: "widget_drawing_saved",
        occurred_at: "2026-10-10T11:00:00.000Z",
        dedupe_key: "streak-read-model:latest-activity",
        metadata: {},
        created_at: "2026-10-10T11:00:00.000Z",
      });
    });
    return { t, couple };
  }

  test("an active streak exposes its stored count", async () => {
    const { t, couple } = await setup();
    const streak = await t.run((ctx) => getCoupleStreakForCouple(ctx, couple.coupleId));
    expect(streak).toMatchObject({ current_count: 5, longest_count: 8, restore_available: false, restorable_count: 0 });
  });

  test("a broken streak shows zero while its restore offer is open, then stops offering it", async () => {
    const { t, couple } = await setup();
    await t.run(async (ctx) => {
      const event = await ctx.db.query("couple_activity_events").first();
      await ctx.db.patch(event!._id, { occurred_at: "2026-10-07T11:00:00.000Z" });
    });
    // Latest event 2026-10-07 gives a deadline of 2026-10-09T00:00Z, so the restore offer runs to 2026-10-10T00:00Z... already past.
    const state = await streakState(t, couple.coupleId);
    await t.run((ctx) => ctx.db.patch(state!._id, { next_activity_deadline_at: "2026-10-08T00:00:00.000Z" }));
    const broken = await t.run((ctx) => getCoupleStreakForCouple(ctx, couple.coupleId));
    expect(broken).toMatchObject({ current_count: 0, restorable_count: 5, restore_available: false });
    expect(broken.restore_deadline).toBe("2026-10-10T00:00:00.000Z");
  });

  test("a recent break keeps the restore offer open", async () => {
    const { t, couple } = await setup();
    await t.run(async (ctx) => {
      const event = await ctx.db.query("couple_activity_events").first();
      // Deadline = 2026-10-10T00:00Z (event on 2026-10-08, +2 local days), restore until 2026-10-11T00:00Z.
      await ctx.db.patch(event!._id, { occurred_at: "2026-10-08T11:00:00.000Z" });
    });
    const broken = await t.run((ctx) => getCoupleStreakForCouple(ctx, couple.coupleId));
    expect(broken).toMatchObject({ current_count: 0, restorable_count: 5, restore_available: true });
    expect(broken.restore_deadline).toBe("2026-10-11T00:00:00.000Z");
  });

  test("new activity after a break exposes the restarted streak despite an old restore snapshot", async () => {
    const { t, couple } = await setup();
    const state = await streakState(t, couple.coupleId);
    await t.run((ctx) =>
      ctx.db.patch(state!._id, {
        current_count: 1,
        last_qualified_date: "2026-10-10",
        next_activity_deadline_at: "2026-10-10T13:00:00.000Z",
        restorable_count: 5,
        restorable_through_date: "2026-10-08",
        restore_deadline: "2026-10-09T00:00:00.000Z",
      }),
    );
    const streak = await t.run((ctx) => getCoupleStreakForCouple(ctx, couple.coupleId));
    expect(streak).toMatchObject({ current_count: 1, restore_available: false });
  });

  test("requires a couple", async () => {
    const t = newTest();
    await expect(t.run((ctx) => getCoupleStreakForCouple(ctx, null))).rejects.toThrow(
      /42501.*active entitled couple access is required/,
    );
  });

  test("detectStreakBreak leaves a healthy streak alone", async () => {
    const { t, couple } = await setup();
    await t.run((ctx) => detectStreakBreak(ctx, couple.coupleId));
    expect(await streakState(t, couple.coupleId)).toMatchObject({ restorable_count: 0, current_count: 5 });
  });
});
