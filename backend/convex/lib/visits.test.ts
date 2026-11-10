import { describe, expect, test } from "vitest";
import { localDateOf } from "./time";
import { visitPhase } from "./visits";

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

  test("at one moment, partners in Oslo and New York each read the visit on their own day", () => {
    const phases = (instant: string) =>
      ["Europe/Oslo", "America/New_York"].map((zone) => visitPhase(visit, localDateOf(instant, zone)));
    // 04:30 UTC on 20 November is 05:30 in Oslo and still 23:30 on the 19th in New York.
    expect(phases("2026-11-20T04:30:00Z")).toEqual(["ongoing", "upcoming"]);
    // 04:30 UTC on 24 November is the day after the visit in Oslo and its last evening in New York.
    expect(phases("2026-11-24T04:30:00Z")).toEqual(["ended", "ongoing"]);
  });
});
