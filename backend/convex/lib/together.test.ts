import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "../_generated/api";
import { createCouple, newTest, type TestConvex, type TestCouple, type TestUser } from "../test.setup";
import { newUuid } from "./ids";
import { addDaysToDate } from "./time";
import {
  dayEnd,
  dayOf,
  isCoupleTogetherAt,
  isTogether,
  nextNeededDay,
  pausesOn,
  readTogetherDays,
  restSpan,
  streakClock,
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
        .withIndex("by_couple_id_end_date", (q) => q.eq("couple_id", couple.coupleId))
        .collect()
    ).map((row) => `${row.start_date}..${row.end_date}`),
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
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    await moveTo(couple.second, couple.coupleId, JUST_OUTSIDE);
    expect(await togetherDays(t, couple)).toEqual([]);

    await moveTo(couple.second, couple.coupleId, JUST_INSIDE);
    await moveTo(couple.first, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual(["2026-06-28..2026-06-28"]);
  });

  test("the partner's position may be up to 12 hours old, since a phone at rest sends nothing", async () => {
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    vi.setSystemTime(new Date("2026-06-29T00:35:00.000Z"));
    await moveTo(couple.second, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual([]);
    vi.setSystemTime(new Date("2026-06-29T12:20:00.000Z"));
    await moveTo(couple.first, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual(["2026-06-29..2026-06-29"]);
  });

  test("a partner's pause counts as a phone that sent nothing new, since the partner is not told of it", async () => {
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    await share(couple.first, couple.coupleId, { pausedUntil: "2026-06-28T20:00:00.000Z" });
    await moveTo(couple.second, couple.coupleId, HOME);
    expect(await togetherDays(t, couple)).toEqual(["2026-06-28..2026-06-28"]);
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
        first_day_set_at: "2026-10-01T00:00:00.000Z",
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

describe("whether the couple is together on a day", () => {
  const saveVisit = (user: TestUser, coupleId: string, start: string, end: string, id = newUuid()) =>
    user.as.mutation(api.visits.save_visit, { p_visit_id: id, p_start_date: start, p_end_date: end, p_place: null, ...operation() }).then(() => id);
  const together = (t: TestConvex, couple: TestCouple, at = new Date().toISOString()) =>
    t.run((ctx) => isCoupleTogetherAt(ctx, couple.coupleId, at));

  test("a visit that holds today counts, and one that ended yesterday, starts tomorrow or was deleted does not", async () => {
    const { t, couple } = await sharingCouple();
    await saveVisit(couple.first, couple.coupleId, "2026-06-25", "2026-06-27");
    await saveVisit(couple.first, couple.coupleId, "2026-06-29", "2026-07-01");
    const deleted = await saveVisit(couple.first, couple.coupleId, "2026-06-28", "2026-06-28");
    await couple.first.as.mutation(api.visits.delete_visit, { p_visit_id: deleted, ...operation() });
    expect(await together(t, couple)).toBe(false);

    await saveVisit(couple.second, couple.coupleId, "2026-06-27", "2026-06-29");
    expect(await together(t, couple)).toBe(true);
  });

  test("a day location showed them together counts", async () => {
    const { t, couple } = await sharingCouple();
    await moveTo(couple.first, couple.coupleId, HOME);
    await moveTo(couple.second, couple.coupleId, HOME);
    expect(await together(t, couple)).toBe(true);
  });

  test("a visit of one day holds that day on the couple's clock, and not a minute either side", async () => {
    const { t, couple } = await sharingCouple();
    await saveVisit(couple.first, couple.coupleId, "2026-06-28", "2026-06-28");
    // Oslo is UTC+2 in June.
    expect(await together(t, couple, "2026-06-27T21:59:00.000Z")).toBe(false);
    expect(await together(t, couple, "2026-06-27T22:00:00.000Z")).toBe(true);
    expect(await together(t, couple, "2026-06-28T21:59:00.000Z")).toBe(true);
    expect(await together(t, couple, "2026-06-28T22:00:00.000Z")).toBe(false);
  });

  test("a long visit holds today around shorter visits inside it that ended or have not started", async () => {
    const { t, couple } = await sharingCouple();
    await saveVisit(couple.first, couple.coupleId, "2026-06-26", "2026-06-26");
    await saveVisit(couple.first, couple.coupleId, "2026-06-30", "2026-07-02");
    expect(await together(t, couple)).toBe(false);
    await saveVisit(couple.first, couple.coupleId, "2026-06-20", "2026-07-10");
    expect(await together(t, couple)).toBe(true);
  });

  test.each([
    ["Los Angeles and Oslo", ["America/Los_Angeles", "Europe/Oslo"] as [string, string]],
    ["Auckland and Tokyo", ["Pacific/Auckland", "Asia/Tokyo"] as [string, string]],
  ])("answers as reading every together day and visit would, around midnight in %s", async (_, timeZones) => {
    const t = newTest();
    const couple = await createCouple(t, { timeZones });
    let seed = 7;
    const random = (below: number) => {
      seed = (seed * 1_103_515_245 + 12_345) % 2 ** 31;
      return Math.floor((seed / 2 ** 31) * below);
    };
    // Fewer visits than a save allows to be open at once, some long, some overlapping, some
    // counting only from a later day.
    await t.run(async (ctx) => {
      for (let index = 0; index < 18; index += 1) {
        const start = addDaysToDate("2026-06-01", random(90));
        const end = addDaysToDate(start, random(8) === 0 ? random(30) : random(6));
        await ctx.db.insert("visits", {
          id: newUuid(),
          couple_id: couple.coupleId,
          start_date: start,
          end_date: end,
          together_from: addDaysToDate(start, random(2) === 0 ? 1 + random(5) : 0),
          first_day_set_at: "2026-06-01T00:00:00.000Z",
          created_by_user_id: couple.first.userId,
          last_edited_by_user_id: couple.first.userId,
          created_at: "2026-06-01T00:00:00.000Z",
          updated_at: "2026-06-01T00:00:00.000Z",
          ...(random(6) === 0 ? { deleted_at: "2026-06-02T00:00:00.000Z" } : {}),
        });
      }
      for (let index = 0; index < 6; index += 1) {
        const start = addDaysToDate("2026-06-01", random(90));
        const row = { couple_id: couple.coupleId, start_date: start, end_date: addDaysToDate(start, random(5)), source: "location" as const };
        await ctx.db.insert("together_days", { ...row, created_at: "2026-06-01T00:00:00.000Z", updated_at: "2026-06-01T00:00:00.000Z" });
      }
    });
    let togetherCount = 0;
    for (let hour = 0; hour < 100 * 24; hour += 5) {
      const at = new Date(Date.parse("2026-05-30T00:30:00.000Z") + hour * 3_600_000).toISOString();
      const expected = await t.run(async (ctx) => {
        const today = dayOf(await streakClock(ctx, couple.coupleId), at);
        const days = await readTogetherDays(ctx, couple.coupleId, addDaysToDate(today, -16));
        return days !== null && isTogether(days, today);
      });
      expect(await together(t, couple, at), at).toBe(expected);
      if (expected) togetherCount += 1;
    }
    expect(togetherCount).toBeGreaterThan(100);
  });

  /** Runs `isCoupleTogetherAt` at the frozen now and returns its answer and every document it read. */
  async function readsOf(t: TestConvex, couple: TestCouple) {
    return await t.run(async (ctx) => {
      const read: { table: string; end_date?: string }[] = [];
      const counted = (table: string, query: object): object =>
        new Proxy(query, {
          get(target, key) {
            const value = Reflect.get(target, key) as unknown;
            if (typeof value !== "function") return value;
            const call = (...args: unknown[]) => (value as (...a: unknown[]) => unknown).apply(target, args);
            if (key === "collect" || key === "take") {
              return async (...args: unknown[]) => {
                const rows = (await call(...args)) as { end_date?: string }[];
                read.push(...rows.map((row) => ({ table, end_date: row.end_date })));
                return rows;
              };
            }
            if (key === "first" || key === "unique") {
              return async () => {
                const row = (await call()) as { end_date?: string } | null;
                if (row) read.push({ table, end_date: row.end_date });
                return row;
              };
            }
            return (...args: unknown[]) => counted(table, call(...args) as object);
          },
        });
      const db = new Proxy(ctx.db, {
        get: (target, key) => (key === "query" ? (table: never) => counted(table, target.query(table)) : Reflect.get(target, key)),
      });
      const together = await isCoupleTogetherAt({ ...ctx, db }, couple.coupleId, new Date().toISOString());
      return { together, read };
    });
  }

  test("reads the visits that are not over and the days from yesterday on, never the couple's history", async () => {
    const { t, couple } = await sharingCouple();
    // 10 visits that are over, 20 to come, and 45 days in a row from location up to yesterday.
    for (let index = 0; index < 10; index += 1) {
      const day = addDaysToDate("2026-06-01", 2 * index);
      await saveVisit(couple.first, couple.coupleId, day, day);
    }
    for (let index = 0; index < 20; index += 1) {
      const start = addDaysToDate("2026-07-01", 3 * index);
      await saveVisit(couple.first, couple.coupleId, start, addDaysToDate(start, 1));
    }
    await t.run(async (ctx) => {
      for (let back = 1; back <= 45; back += 1) {
        const date = addDaysToDate("2026-06-28", -back);
        const row = { couple_id: couple.coupleId, start_date: date, end_date: date, source: "location" as const };
        await ctx.db.insert("together_days", { ...row, created_at: "2026-06-01T00:00:00.000Z", updated_at: "2026-06-01T00:00:00.000Z" });
      }
    });
    const { together: heavy, read } = await readsOf(t, couple);
    expect(heavy).toBe(false);
    // Yesterday in UTC is the earliest day any phone can be on.
    expect(read.filter((doc) => doc.table === "visits" && doc.end_date! < "2026-06-27")).toEqual([]);
    expect(read.filter((doc) => doc.table === "together_days" && doc.end_date! < "2026-06-27")).toEqual([]);
  });

  test("reads at most 10 documents for a couple with 3 visits to come and one that holds today", async () => {
    const { t, couple } = await sharingCouple();
    for (const start of ["2026-07-05", "2026-08-01", "2026-09-10"]) {
      await saveVisit(couple.first, couple.coupleId, start, addDaysToDate(start, 2));
    }
    await saveVisit(couple.first, couple.coupleId, "2026-06-27", "2026-06-29");
    const { together: met, read } = await readsOf(t, couple);
    expect(met).toBe(true);
    expect(read.length).toBeLessThanOrEqual(10);
  });
});

describe("the streak's clock", () => {
  const laOslo = ["America/Los_Angeles", "Europe/Oslo"];

  test("an instant is on the earlier partner's date, and a date ends at the later midnight", () => {
    // 01:00 on 2026-10-10 in Oslo, 16:00 on 2026-10-09 in Los Angeles.
    expect(dayOf(laOslo, "2026-10-09T23:00:00.000Z")).toBe("2026-10-09");
    expect(dayEnd(laOslo, "2026-10-09")).toBe("2026-10-10T07:00:00.000Z");
    expect(dayOf(laOslo, "2026-10-10T07:00:00.000Z")).toBe("2026-10-10");
  });

  test("a date lasts 25 hours on the day the clocks go back", () => {
    expect(dayEnd(["Europe/Oslo"], "2026-10-24")).toBe("2026-10-24T22:00:00.000Z");
    expect(dayEnd(["Europe/Oslo"], "2026-10-25")).toBe("2026-10-25T23:00:00.000Z");
  });
});

describe("the 14-day pause", () => {
  const days = (from: string, spans: [string, string][]): TogetherDays => ({
    clock: ["UTC"],
    from,
    spans: spans.map(([start_date, end_date]) => ({ start_date, end_date })),
  });

  test("the first 14 together days in a row rest the streak, and a day apart starts the count again", () => {
    const long = days("2026-09-01", [
      ["2026-10-01", "2026-10-20"],
      ["2026-10-22", "2026-10-25"],
    ]);
    expect(pausesOn(long, "2026-09-30")).toBe(false);
    expect(pausesOn(long, "2026-10-01")).toBe(true);
    expect(pausesOn(long, "2026-10-14")).toBe(true);
    expect(pausesOn(long, "2026-10-15")).toBe(false);
    expect(pausesOn(long, "2026-10-21")).toBe(false);
    expect(pausesOn(long, "2026-10-22")).toBe(true);
    expect(nextNeededDay(long, "2026-09-30")).toBe("2026-10-15");
  });

  test("days apart between stored days and visits end a run, and overlapping ones join it", () => {
    const mixed = days("2026-09-20", [
      ["2026-10-01", "2026-10-01"],
      ["2026-10-03", "2026-10-05"],
      ["2026-10-04", "2026-10-07"],
    ]);
    expect(pausesOn(mixed, "2026-10-01")).toBe(true);
    expect(pausesOn(mixed, "2026-10-02")).toBe(false);
    expect(nextNeededDay(mixed, "2026-10-02")).toBe("2026-10-08");
  });

  test("a date before the days read counts as a day apart", () => {
    const late = days("2026-10-05", [["2026-09-01", "2026-10-30"]]);
    expect(pausesOn(late, "2026-10-04")).toBe(false);
    expect(pausesOn(late, "2026-10-18")).toBe(true);
    expect(pausesOn(late, "2026-10-19")).toBe(false);
  });

  test("the resting days hold today, or are the next a visit makes, and start after the streak's last day", () => {
    const planned = days("2026-09-20", [["2026-10-10", "2026-10-12"]]);
    expect(restSpan(planned, "2026-10-04", "2026-10-05")).toEqual({ from: "2026-10-10", until: "2026-10-12" });
    expect(restSpan(planned, "2026-10-09", "2026-10-11")).toEqual({ from: "2026-10-10", until: "2026-10-12" });
    expect(restSpan(planned, "2026-10-10", "2026-10-11")).toEqual({ from: "2026-10-11", until: "2026-10-12" });
    expect(restSpan(planned, "2026-10-12", "2026-10-13")).toBeNull();
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
