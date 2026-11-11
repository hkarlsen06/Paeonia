import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "../_generated/api";
import { createCouple, newTest, type TestConvex, type TestCouple, type TestUser } from "../test.setup";
import { newUuid } from "./ids";
import {
  distanceMeters,
  isCoupleTogetherAt,
  neededDaysAfter,
  pauseAround,
  pausesOn,
  togetherCaptureAt,
  type TogetherDays,
} from "./together";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-06-28T12:30:00.000Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

const CLIENT_ID = newUuid();
let sequence = 0;

function operation() {
  sequence += 1;
  return {
    p_client_operation_id: newUuid(),
    p_client_id: CLIENT_ID,
    p_client_sequence: sequence,
    p_local_created_at: new Date().toISOString(),
  };
}

const HOME = { latitude: 59.9, longitude: 10.75 };
/** 999 m north of HOME once stored with six decimals. */
const JUST_INSIDE = { latitude: 59.908988, longitude: 10.75 };
/** 1000 m north of HOME once stored with six decimals. */
const JUST_OUTSIDE = { latitude: 59.908994, longitude: 10.75 };

async function share(user: TestUser, coupleId: string, sharing: { enabled?: boolean; pausedUntil?: string } = {}) {
  await user.as.mutation(api.location.update_location_sharing_preference, {
    p_couple_id: coupleId,
    p_is_enabled: sharing.enabled ?? true,
    p_consent_version: "test-v1",
    p_source: "settings_toggle",
    p_paused_until: sharing.pausedUntil,
    ...operation(),
  });
}

async function moveTo(user: TestUser, coupleId: string, at: { latitude: number; longitude: number }) {
  await user.as.mutation(api.location.update_latest_partner_location, {
    p_couple_id: coupleId,
    p_latitude: at.latitude,
    p_longitude: at.longitude,
    p_accuracy_m: 20,
    p_captured_at: new Date(Date.now() - 60_000).toISOString(),
    p_source: "foreground_open",
    ...operation(),
  });
}

const togetherDays = (t: TestConvex, couple: TestCouple) =>
  t.run(async (ctx) =>
    (
      await ctx.db
        .query("together_days")
        .withIndex("by_couple_id_local_date", (q) => q.eq("couple_id", couple.coupleId))
        .collect()
    ).map((day) => day.local_date),
  );

async function sharingCouple() {
  const t = newTest();
  const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
  await share(couple.first, couple.coupleId);
  await share(couple.second, couple.coupleId);
  return { t, couple };
}

describe("location together days", () => {
  test("partners under 1000 m apart record the day once, and 1000 m apart is not together", async () => {
    expect(distanceMeters(HOME, JUST_INSIDE)).toBe(999);
    expect(distanceMeters(HOME, JUST_OUTSIDE)).toBe(1000);

    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    await moveTo(couple.second, couple.coupleId, JUST_OUTSIDE);
    expect(await togetherDays(t, couple)).toEqual([]);

    await moveTo(couple.second, couple.coupleId, JUST_INSIDE);
    await moveTo(couple.first, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual(["2026-06-28"]);
  });

  test("the partner's position may be up to 12 hours old, since a phone at rest sends nothing", async () => {
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    vi.setSystemTime(new Date("2026-06-29T00:35:00.000Z"));
    await moveTo(couple.second, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual([]);
    vi.setSystemTime(new Date("2026-06-29T12:20:00.000Z"));
    await moveTo(couple.first, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual(["2026-06-29"]);
  });

  test("a partner who paused sharing does not count", async () => {
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    await share(couple.first, couple.coupleId, { pausedUntil: "2026-06-28T20:00:00.000Z" });
    await moveTo(couple.second, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual([]);
  });

  test("a partner who turned sharing off does not count", async () => {
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    await share(couple.first, couple.coupleId, { enabled: false });
    await moveTo(couple.second, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual([]);
  });
});

describe("visit boundaries", () => {
  test("a visit covers its first and last couple-local day, including the day the clocks go back", async () => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones: ["Europe/Oslo", "Europe/Oslo"] });
    await t.run((ctx) =>
      ctx.db.insert("visits", {
        id: newUuid(),
        couple_id: couple.coupleId,
        start_date: "2026-10-24",
        end_date: "2026-10-25",
        together_from: "2026-10-01",
        created_by_user_id: couple.first.userId,
        last_edited_by_user_id: couple.first.userId,
        created_at: "2026-10-01T00:00:00.000Z",
        updated_at: "2026-10-01T00:00:00.000Z",
      }),
    );
    const together = (at: string) => t.run((ctx) => isCoupleTogetherAt(ctx, couple.coupleId, at));
    // Oslo is UTC+2 until 01:00Z on 2026-10-25 and UTC+1 after it, so 2026-10-25 lasts 25 hours.
    expect(await together("2026-10-23T21:59:00.000Z")).toBe(false);
    expect(await together("2026-10-23T22:00:00.000Z")).toBe(true);
    expect(await together("2026-10-25T22:59:00.000Z")).toBe(true);
    expect(await together("2026-10-25T23:00:00.000Z")).toBe(false);
  });
});

describe("the 14-day pause", () => {
  const days = (from: string, overrides: Partial<TogetherDays> = {}): TogetherDays => ({
    floor: from,
    rows: new Set(),
    visits: [],
    runSince: null,
    ...overrides,
  });
  const visit = (start_date: string, end_date: string, together_from = "2026-01-01") => ({
    start_date,
    end_date,
    together_from,
  });

  test("the first 14 together days in a row pause the streak, and a day apart starts the count again", () => {
    const long = days("2026-09-01", { visits: [visit("2026-10-01", "2026-10-20"), visit("2026-10-22", "2026-10-25")] });
    expect(pausesOn(long, "2026-09-30")).toBe(false);
    expect(pausesOn(long, "2026-10-01")).toBe(true);
    expect(pausesOn(long, "2026-10-14")).toBe(true);
    expect(pausesOn(long, "2026-10-15")).toBe(false);
    expect(pausesOn(long, "2026-10-21")).toBe(false);
    expect(pausesOn(long, "2026-10-22")).toBe(true);
    expect(neededDaysAfter(long, "2026-09-30", 3)).toEqual(["2026-10-15", "2026-10-16", "2026-10-17"]);
  });

  test("a visit reaches only the days from when its dates were saved", () => {
    const backdated = days("2026-09-20", { visits: [visit("2026-10-01", "2026-10-05", "2026-10-03")] });
    expect(pausesOn(backdated, "2026-10-02")).toBe(false);
    expect(pausesOn(backdated, "2026-10-03")).toBe(true);
    expect(neededDaysAfter(backdated, "2026-09-30", 3)).toEqual(["2026-10-01", "2026-10-02", "2026-10-06"]);
  });

  test("an open location run keeps every later day together, up to the pause", () => {
    const run = days("2026-09-20", { runSince: "2026-10-01", rows: new Set(["2026-09-30"]) });
    expect(pausesOn(run, "2026-10-13")).toBe(true);
    expect(pausesOn(run, "2026-10-14")).toBe(false);
    expect(pauseAround(run, "2026-10-05")).toEqual({ from: "2026-09-30", until: "2026-10-13" });
    expect(pauseAround(run, "2026-10-20")).toBeNull();
  });

  test("the paused days around today are the next planned ones before a visit starts", () => {
    const planned = days("2026-09-20", { visits: [visit("2026-10-10", "2026-10-12")] });
    expect(pauseAround(planned, "2026-10-05")).toEqual({ from: "2026-10-10", until: "2026-10-12" });
    expect(pauseAround(planned, "2026-10-11")).toEqual({ from: "2026-10-10", until: "2026-10-12" });
    expect(pauseAround(planned, "2026-10-13")).toBeNull();
  });
});

describe("togetherCaptureAt", () => {
  const NOW = "2026-10-10T12:00:00.000Z";
  const fix = (capturedAt: string, accuracy: number | null = 20, at = HOME) => ({
    ...at,
    accuracy_m: accuracy ?? undefined,
    captured_at: capturedAt,
  });

  test("dates the day by the later capture, for a fresh fix and a partner's fix up to 12 hours old", () => {
    expect(togetherCaptureAt(fix("2026-10-10T11:30:00.000Z"), fix("2026-10-10T00:30:00.000Z"), NOW)).toBe(
      "2026-10-10T11:30:00.000Z",
    );
    expect(togetherCaptureAt(fix("2026-10-10T10:59:00.000Z"), fix("2026-10-10T11:50:00.000Z"), NOW)).toBeNull();
    expect(togetherCaptureAt(fix("2026-10-10T11:30:00.000Z"), fix("2026-09-09T23:59:00.000Z"), NOW)).toBeNull();
  });

  test("needs both accuracies known and no worse than 500 m, and less than 1000 m between them", () => {
    const fresh = "2026-10-10T11:30:00.000Z";
    expect(togetherCaptureAt(fix(fresh, null), fix(fresh), NOW)).toBeNull();
    expect(togetherCaptureAt(fix(fresh), fix(fresh, 501), NOW)).toBeNull();
    expect(togetherCaptureAt(fix(fresh, 500), fix(fresh, 500, JUST_INSIDE), NOW)).toBe(fresh);
    expect(togetherCaptureAt(fix(fresh), fix(fresh, 20, JUST_OUTSIDE), NOW)).toBeNull();
  });
});
