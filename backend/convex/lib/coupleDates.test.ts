import { describe, expect, test } from "vitest";
import {
  addMonthsToDate,
  countdownDay,
  dateInYear,
  daysBetweenDates,
  milestoneToday,
  nextYearlyOccurrence,
} from "./coupleDates";

describe("nextYearlyOccurrence", () => {
  test("is today when the date comes around today, and counts the years", () => {
    expect(nextYearlyOccurrence("2020-10-21", "2026-10-21")).toEqual({ date: "2026-10-21", years: 6 });
  });

  test("moves to next year once this year's day has passed", () => {
    expect(nextYearlyOccurrence("2020-10-20", "2026-10-21")).toEqual({ date: "2027-10-20", years: 7 });
    expect(nextYearlyOccurrence("2020-12-31", "2026-10-21")).toEqual({ date: "2026-12-31", years: 6 });
  });

  test("a date still ahead is its own first occurrence", () => {
    expect(nextYearlyOccurrence("2027-03-04", "2026-10-21")).toEqual({ date: "2027-03-04", years: 0 });
    expect(nextYearlyOccurrence("2026-10-22", "2026-10-21")).toEqual({ date: "2026-10-22", years: 0 });
  });

  test("29 February falls on 28 February in a year without one", () => {
    expect(nextYearlyOccurrence("2020-02-29", "2026-01-15")).toEqual({ date: "2026-02-28", years: 6 });
    expect(nextYearlyOccurrence("2020-02-29", "2027-03-01")).toEqual({ date: "2028-02-29", years: 8 });
    expect(nextYearlyOccurrence("2020-02-29", "2028-02-29")).toEqual({ date: "2028-02-29", years: 8 });
    expect(dateInYear("2020-02-29", 2100)).toBe("2100-02-28");
  });

  test("works across the new year", () => {
    expect(nextYearlyOccurrence("2020-01-01", "2026-12-31")).toEqual({ date: "2027-01-01", years: 7 });
  });
});

describe("countdownDay", () => {
  test("a one-off countdown keeps its date, past or not", () => {
    expect(countdownDay({ target_date: "2026-01-01" }, "2026-10-21")).toBe("2026-01-01");
    expect(countdownDay({ target_date: "2026-01-01", repeats_yearly: false }, "2026-10-21")).toBe("2026-01-01");
  });

  test("a yearly countdown is never past", () => {
    expect(countdownDay({ target_date: "2023-06-12", repeats_yearly: true }, "2026-10-21")).toBe("2027-06-12");
    expect(countdownDay({ target_date: "2023-10-21", repeats_yearly: true }, "2026-10-21")).toBe("2026-10-21");
  });
});

describe("date helpers", () => {
  test("adds months and cuts the day to a shorter month", () => {
    expect(addMonthsToDate("2026-01-31", 1)).toBe("2026-02-28");
    expect(addMonthsToDate("2028-01-31", 1)).toBe("2028-02-29");
    expect(addMonthsToDate("2026-08-15", 6)).toBe("2027-02-15");
    expect(addMonthsToDate("2026-12-15", 1)).toBe("2027-01-15");
  });

  test("counts whole days between dates across a daylight saving change", () => {
    expect(daysBetweenDates("2026-03-28", "2026-03-30")).toBe(2);
    expect(daysBetweenDates("2026-10-21", "2026-10-20")).toBe(-1);
  });
});

describe("milestoneToday", () => {
  test("finds the first month, half a year and anniversaries", () => {
    expect(milestoneToday("2026-09-21", "2026-10-21")).toEqual({ kind: "first_month" });
    expect(milestoneToday("2026-04-21", "2026-10-21")).toEqual({ kind: "half_year" });
    expect(milestoneToday("2025-10-21", "2026-10-21")).toEqual({ kind: "years", years: 1 });
    expect(milestoneToday("2020-10-21", "2026-10-21")).toEqual({ kind: "years", years: 6 });
  });

  test("finds 100, 500 and every 1,000th day", () => {
    expect(milestoneToday("2026-07-13", "2026-10-21")).toEqual({ kind: "days", days: 100 });
    expect(milestoneToday("2025-06-08", "2026-10-21")).toEqual({ kind: "days", days: 500 });
    expect(milestoneToday("2024-01-25", "2026-10-21")).toEqual({ kind: "days", days: 1_000 });
    expect(milestoneToday("2021-04-30", "2026-10-21")).toEqual({ kind: "days", days: 2_000 });
    // 1,500 is not a milestone.
    expect(milestoneToday("2022-09-12", "2026-10-21")).toBeNull();
  });

  test("is quiet on every other day, including the months the app shows but does not push", () => {
    expect(milestoneToday("2026-08-21", "2026-10-21")).toBeNull();
    expect(milestoneToday("2026-10-20", "2026-10-21")).toBeNull();
    expect(milestoneToday("2026-10-21", "2026-10-21")).toBeNull();
    expect(milestoneToday("2027-01-01", "2026-10-21")).toBeNull();
  });

  test("a 29 February start has its anniversary on 28 February in other years", () => {
    expect(milestoneToday("2024-02-29", "2026-02-28")).toEqual({ kind: "years", years: 2 });
    expect(milestoneToday("2024-02-29", "2028-02-29")).toEqual({ kind: "years", years: 4 });
    expect(milestoneToday("2024-02-29", "2026-03-01")).toBeNull();
  });
});
