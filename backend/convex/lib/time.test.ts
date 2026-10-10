import { describe, expect, test } from "vitest";
import {
  addDaysToDate,
  endOfLocalDay,
  isValidTimeZone,
  localDateOf,
  localMidnightAfter,
  startOfLocalDay,
  zonedLocalToUtcMs,
} from "./time";

describe("local dates", () => {
  test("local date of an instant follows the zone", () => {
    expect(localDateOf("2026-03-28T23:30:00.000Z", "Europe/Oslo")).toBe("2026-03-29");
    expect(localDateOf("2026-03-28T23:30:00.000Z", "America/Los_Angeles")).toBe("2026-03-28");
    expect(localDateOf("2026-03-28T23:30:00.000Z", "UTC")).toBe("2026-03-28");
  });

  test("adds days to a date string across month and leap boundaries", () => {
    expect(addDaysToDate("2026-01-31", 1)).toBe("2026-02-01");
    expect(addDaysToDate("2028-02-28", 2)).toBe("2028-03-01");
    expect(addDaysToDate("2026-01-01", -1)).toBe("2025-12-31");
  });

  test("validates zone names", () => {
    expect(isValidTimeZone("Europe/Oslo")).toBe(true);
    expect(isValidTimeZone("UTC")).toBe(true);
    expect(isValidTimeZone("Mars/Olympus")).toBe(false);
    expect(isValidTimeZone(undefined)).toBe(false);
    expect(isValidTimeZone("")).toBe(false);
  });
});

describe("Europe/Oslo daylight saving", () => {
  test("the spring-forward day is 23 hours long", () => {
    expect(startOfLocalDay("2026-03-29", "Europe/Oslo")).toBe("2026-03-28T23:00:00.000Z");
    expect(endOfLocalDay("2026-03-29", "Europe/Oslo")).toBe("2026-03-29T22:00:00.000Z");
  });

  test("the fall-back day is 25 hours long", () => {
    expect(startOfLocalDay("2026-10-25", "Europe/Oslo")).toBe("2026-10-24T22:00:00.000Z");
    expect(endOfLocalDay("2026-10-25", "Europe/Oslo")).toBe("2026-10-25T23:00:00.000Z");
  });

  test("midnight after the next local day is not a fixed 48 hours", () => {
    expect(localMidnightAfter("2026-03-28T12:00:00.000Z", "Europe/Oslo", 2)).toBe("2026-03-29T22:00:00.000Z");
    expect(localMidnightAfter("2026-10-24T12:00:00.000Z", "Europe/Oslo", 2)).toBe("2026-10-25T23:00:00.000Z");
  });

  test("a time inside the spring-forward gap uses the offset from before the gap", () => {
    // 02:30 does not exist on 2026-03-29. Postgres returns 03:30 local, 01:30Z.
    expect(new Date(zonedLocalToUtcMs("2026-03-29", "Europe/Oslo", 2, 30)).toISOString()).toBe(
      "2026-03-29T01:30:00.000Z",
    );
  });

  test("an ambiguous fall-back time resolves to standard time", () => {
    // 02:30 happens twice on 2026-10-25. Postgres picks the later one, 01:30Z.
    expect(new Date(zonedLocalToUtcMs("2026-10-25", "Europe/Oslo", 2, 30)).toISOString()).toBe(
      "2026-10-25T01:30:00.000Z",
    );
  });
});

describe("date-line zones", () => {
  test("Kiritimati (UTC+14) is a day ahead of Pago Pago (UTC-11)", () => {
    const instant = "2026-06-15T12:00:00.000Z";
    expect(localDateOf(instant, "Pacific/Kiritimati")).toBe("2026-06-16");
    expect(localDateOf(instant, "Pacific/Pago_Pago")).toBe("2026-06-15");
    expect(startOfLocalDay("2026-06-16", "Pacific/Kiritimati")).toBe("2026-06-15T10:00:00.000Z");
    expect(endOfLocalDay("2026-06-15", "Pacific/Pago_Pago")).toBe("2026-06-16T11:00:00.000Z");
  });

  test("Apia skipped 2011-12-30 entirely", () => {
    expect(localDateOf("2011-12-30T12:00:00.000Z", "Pacific/Apia")).toBe("2011-12-31");
    expect(startOfLocalDay("2011-12-31", "Pacific/Apia")).toBe("2011-12-30T10:00:00.000Z");
  });
});
