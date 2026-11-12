import { describe, expect, test } from "vitest";
import { recapPeriod } from "./recap";

describe("recapPeriod", () => {
  test("the first anniversary covers the year from the start date", () => {
    expect(recapPeriod("2025-11-11", "2025-06-01", "2026-11-11")).toEqual({
      anniversary_date: "2026-11-11",
      years: 1,
      period_start: "2025-11-11",
      period_end: "2026-11-11",
      since_joined: false,
    });
  });

  test("a later anniversary covers the year since the one before, also days after it", () => {
    expect(recapPeriod("2021-03-05", "2022-01-01", "2026-03-18")).toEqual({
      anniversary_date: "2026-03-05",
      years: 5,
      period_start: "2025-03-05",
      period_end: "2026-03-05",
      since_joined: false,
    });
  });

  test("a couple that joined mid-year gets the time since it joined", () => {
    expect(recapPeriod("2020-11-11", "2026-08-11", "2026-11-11")).toEqual({
      anniversary_date: "2026-11-11",
      years: 6,
      period_start: "2026-08-11",
      period_end: "2026-11-11",
      since_joined: true,
    });
  });

  test("there is none before the first anniversary, or when the couple joined just before it", () => {
    expect(recapPeriod("2026-01-08", "2026-01-08", "2026-11-11")).toBeNull();
    expect(recapPeriod("2020-11-11", "2026-11-01", "2026-11-11")).toBeNull();
    expect(recapPeriod("2020-11-11", "2026-10-28", "2026-11-11")?.period_start).toBe("2026-10-28");
  });

  test("a 29 February start falls on 28 February in other years, like the dates timeline", () => {
    expect(recapPeriod("2024-02-29", "2024-03-01", "2025-02-28")).toMatchObject({
      anniversary_date: "2025-02-28",
      period_start: "2024-03-01",
      since_joined: true,
    });
    expect(recapPeriod("2024-02-29", "2024-01-01", "2028-02-29")).toMatchObject({
      anniversary_date: "2028-02-29",
      years: 4,
      period_start: "2027-02-28",
    });
    expect(recapPeriod("2024-02-29", "2024-01-01", "2027-02-27")?.anniversary_date).toBe("2026-02-28");
  });

  test("partners whose local dates differ see the anniversary on their own day", () => {
    expect(recapPeriod("2025-11-11", "2025-01-01", "2026-11-11")?.anniversary_date).toBe("2026-11-11");
    expect(recapPeriod("2025-11-11", "2025-01-01", "2026-11-10")).toBeNull();
    expect(recapPeriod("2025-11-11", "2025-01-01", "2026-11-12")?.anniversary_date).toBe("2026-11-11");
  });
});
