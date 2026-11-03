import { describe, expect, test } from "vitest";
import { gamePlayDayStats, type GamePlayDay } from "./gamePlayDays";

const A = "user-a";
const B = "user-b";
const both = (day: string): GamePlayDay => ({ day, user_ids: [A, B] });

describe("gamePlayDayStats", () => {
  test("counts only the days both partners played", () => {
    const days = [both("2026-10-01"), { day: "2026-10-02", user_ids: [A] }, both("2026-10-03"), { day: "2026-10-04", user_ids: [B] }];
    expect(gamePlayDayStats(days, [A, B], "2026-10-04")).toEqual({ streak: 1, total: 2, today: "2026-10-04" });
  });

  test("a day without play yet keeps yesterday's streak, and a missed day ends it", () => {
    const days = [both("2026-10-01"), both("2026-10-02"), both("2026-10-03")];
    expect(gamePlayDayStats(days, [A, B], "2026-10-03").streak).toBe(3);
    expect(gamePlayDayStats(days, [A, B], "2026-10-04").streak).toBe(3);
    expect(gamePlayDayStats(days, [A, B], "2026-10-05")).toEqual({ streak: 0, total: 3, today: "2026-10-05" });
  });

  test("a streak runs on through the night the clocks change", () => {
    // Europe moves its clocks forward on 2026-03-29, a day 23 hours long.
    const days = [both("2026-03-28"), both("2026-03-29"), both("2026-03-30")];
    expect(gamePlayDayStats(days, [A, B], "2026-03-30").streak).toBe(3);
    // Across a month and a year end too.
    expect(gamePlayDayStats([both("2026-12-31"), both("2027-01-01")], [A, B], "2027-01-02").streak).toBe(2);
  });

  test("a former partner's days and a missing partner count nothing", () => {
    const days = [both("2026-10-01"), { day: "2026-10-02", user_ids: [A, "someone-else"] }];
    expect(gamePlayDayStats(days, [A, B], "2026-10-02")).toEqual({ streak: 1, total: 1, today: "2026-10-02" });
    expect(gamePlayDayStats(days, null, "2026-10-02")).toEqual({ streak: 0, total: 0, today: "2026-10-02" });
  });
});
