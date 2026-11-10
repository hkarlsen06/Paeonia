import { describe, expect, test } from "vitest";
import { currentOrNextVisit, visitPhase } from "./visits";

const visit = { start_date: "2026-11-20", end_date: "2026-11-23" };

describe("visitPhase", () => {
  test("the day before the start is upcoming, and the start day is ongoing", () => {
    expect(visitPhase(visit, "2026-11-19")).toBe("upcoming");
    expect(visitPhase(visit, "2026-11-20")).toBe("ongoing");
  });

  test("the end day is ongoing, and the day after it is ended", () => {
    expect(visitPhase(visit, "2026-11-23")).toBe("ongoing");
    expect(visitPhase(visit, "2026-11-24")).toBe("ended");
  });

  test("a one-day visit is ongoing on that day only", () => {
    const day = { start_date: "2026-11-20", end_date: "2026-11-20" };
    expect(visitPhase(day, "2026-11-19")).toBe("upcoming");
    expect(visitPhase(day, "2026-11-20")).toBe("ongoing");
    expect(visitPhase(day, "2026-11-21")).toBe("ended");
  });

  test("each partner reads the visit on their own local day", () => {
    // 23:30 on 19 November in New York is already 20 November in Oslo.
    const newYork = "2026-11-19";
    const oslo = "2026-11-20";
    expect(visitPhase(visit, newYork)).toBe("upcoming");
    expect(visitPhase(visit, oslo)).toBe("ongoing");
    // 23:30 on 23 November in New York is 24 November in Oslo, after the last day there.
    expect(visitPhase(visit, "2026-11-23")).toBe("ongoing");
    expect(visitPhase(visit, "2026-11-24")).toBe("ended");
  });
});

describe("currentOrNextVisit", () => {
  const past = { start_date: "2026-10-01", end_date: "2026-10-03" };
  const later = { start_date: "2026-12-20", end_date: "2026-12-27" };

  test("picks the ongoing visit, else the soonest upcoming one, and skips the ones that are over", () => {
    expect(currentOrNextVisit([later, past, visit], "2026-11-21")).toBe(visit);
    expect(currentOrNextVisit([later, past, visit], "2026-11-10")).toBe(visit);
    expect(currentOrNextVisit([later, past, visit], "2026-11-24")).toBe(later);
    expect(currentOrNextVisit([past], "2026-11-24")).toBeNull();
  });
});
