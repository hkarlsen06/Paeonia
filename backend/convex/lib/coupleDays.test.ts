import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { createCouple, newTest } from "../test.setup";
import {
  getOrCreateCoupleDayAt,
  getOrCreateTodayCoupleDay,
  resolveCoupleDayAnchor,
  resolveCoupleDayAnchorAt,
  userLocalDate,
} from "./coupleDays";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
});
afterEach(() => {
  vi.useRealTimers();
});

describe("couple day anchor", () => {
  test("follows the partner whose local clock is furthest behind", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "America/Los_Angeles"] });
    // 02:00 in Oslo on 2026-06-16 is still 17:00 on 2026-06-15 in Los Angeles.
    const anchor = await t.run((ctx) => resolveCoupleDayAnchorAt(ctx, couple.coupleId, "2026-06-16T00:00:00.000Z"));
    expect(anchor).toEqual({
      local_date: "2026-06-15",
      anchor_time_zone_id: "America/Los_Angeles",
      starts_at: "2026-06-15T07:00:00.000Z",
      ends_at: "2026-06-16T07:00:00.000Z",
    });
  });

  test("members without a valid zone count as UTC, and ties break on zone name", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Mars/Olympus", "Europe/London"] });
    // In winter London and UTC share a wall clock. "Europe/London" < "UTC".
    const anchor = await t.run((ctx) => resolveCoupleDayAnchorAt(ctx, couple.coupleId, "2026-01-10T12:00:00.000Z"));
    expect(anchor.anchor_time_zone_id).toBe("Europe/London");
    expect(anchor.local_date).toBe("2026-01-10");
  });

  test("uses the current time by default and rejects a missing timestamp", async () => {
    vi.setSystemTime(new Date("2026-03-29T10:00:00.000Z"));
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const anchor = await t.run((ctx) => resolveCoupleDayAnchor(ctx, couple.coupleId));
    expect(anchor).toMatchObject({
      local_date: "2026-03-29",
      starts_at: "2026-03-28T23:00:00.000Z",
      ends_at: "2026-03-29T22:00:00.000Z",
    });
    await expect(t.run((ctx) => resolveCoupleDayAnchorAt(ctx, couple.coupleId, null))).rejects.toThrow(
      /23514.*daily operation timestamp is required/,
    );
  });

  test("fails without active members", async () => {
    const t = newTest();
    await expect(
      t.run((ctx) => resolveCoupleDayAnchorAt(ctx, "81000000-0000-0000-0000-000000000099", "2026-01-01T00:00:00.000Z")),
    ).rejects.toThrow(/23514.*active couple members are required/);
  });
});

describe("get or create couple day", () => {
  test("returns the same day for any instant inside its window", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const ids = await t.run(async (ctx) => [
      await getOrCreateCoupleDayAt(ctx, couple.coupleId, "2026-03-28T23:00:00.000Z"),
      await getOrCreateCoupleDayAt(ctx, couple.coupleId, "2026-03-29T12:00:00.000Z"),
      await getOrCreateCoupleDayAt(ctx, couple.coupleId, "2026-03-29T21:59:59.999Z"),
      await getOrCreateCoupleDayAt(ctx, couple.coupleId, "2026-03-29T22:00:00.000Z"),
    ]);
    expect(ids[0]).toBe(ids[1]);
    expect(ids[1]).toBe(ids[2]);
    expect(ids[3]).not.toBe(ids[0]);
    const days = await t.run((ctx) => ctx.db.query("couple_days").collect());
    expect(days.map((day) => day.local_date).sort()).toEqual(["2026-03-29", "2026-03-30"]);
    const spring = days.find((day) => day.local_date === "2026-03-29")!;
    expect(Date.parse(spring.ends_at) - Date.parse(spring.starts_at)).toBe(23 * 3_600_000);
  });

  test("today's day uses the clock", async () => {
    vi.setSystemTime(new Date("2026-10-25T12:00:00.000Z"));
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    const id = await t.run((ctx) => getOrCreateTodayCoupleDay(ctx, couple.coupleId));
    const day = await t.run((ctx) => ctx.db.query("couple_days").first());
    expect(day).toMatchObject({ id, local_date: "2026-10-25" });
    expect(Date.parse(day!.ends_at) - Date.parse(day!.starts_at)).toBe(25 * 3_600_000);
  });
});

describe("userLocalDate", () => {
  test("uses the profile zone and falls back to UTC", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Pacific/Auckland", "Mars/Olympus"] });
    const result = await t.run(async (ctx) => ({
      auckland: await userLocalDate(ctx, couple.first.userId, "2026-06-15T14:00:00.000Z"),
      unknown: await userLocalDate(ctx, couple.second.userId, "2026-06-15T23:59:00.000Z"),
    }));
    expect(result).toEqual({ auckland: "2026-06-16", unknown: "2026-06-15" });
  });
});
