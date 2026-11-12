import { describe, expect, test } from "vitest";
import { deliverAtFor, LETTER_STATES, nextLetterState, visitLettersWrittenBefore, visitLetterTime } from "./letters";

const at = (iso: string) => Date.parse(iso);

describe("nextLetterState", () => {
  test("a letter goes sealed, delivered, opened, and nothing moves it back or skips a step", () => {
    expect(nextLetterState("sealed", "deliver")).toBe("delivered");
    expect(nextLetterState("delivered", "open")).toBe("opened");
    expect(nextLetterState("sealed", "open")).toBeNull();
    expect(nextLetterState("delivered", "deliver")).toBeNull();
    expect(nextLetterState("opened", "deliver")).toBeNull();
    expect(nextLetterState("opened", "open")).toBeNull();
  });

  test("every state answers every event", () => {
    for (const state of LETTER_STATES) {
      for (const event of ["deliver", "open"] as const) {
        expect([null, ...LETTER_STATES]).toContain(nextLetterState(state, event));
      }
    }
  });
});

describe("deliverAtFor", () => {
  test("now arrives at the send", () => {
    expect(deliverAtFor({ kind: "now" }, at("2026-11-10T20:00:00.000Z"), "Asia/Tokyo")).toBe("2026-11-10T20:00:00.000Z");
  });

  test("a letter for the next meeting has no time", () => {
    expect(deliverAtFor({ kind: "together" }, at("2026-11-10T20:00:00.000Z"), "Asia/Tokyo")).toBeNull();
  });

  test("a set time arrives then, and a time that passed while the send waited arrives at once", () => {
    const now = at("2026-11-10T20:00:00.000Z");
    expect(deliverAtFor({ kind: "at", at: "2026-11-10T20:02:00.000Z" }, now, "UTC")).toBe("2026-11-10T20:02:00.000Z");
    expect(deliverAtFor({ kind: "at", at: "2026-11-10T19:00:00.000Z" }, now, "UTC")).toBe("2026-11-10T20:00:00.000Z");
  });

  test("morning is the recipient's next 08:00, in their zone", () => {
    const now = at("2026-11-10T20:00:00.000Z");
    // 05:00 the next day in Tokyo, so 08:00 the same Tokyo day.
    expect(deliverAtFor({ kind: "morning" }, now, "Asia/Tokyo")).toBe("2026-11-10T23:00:00.000Z");
    // Noon in Los Angeles, so 08:00 the next day there.
    expect(deliverAtFor({ kind: "morning" }, now, "America/Los_Angeles")).toBe("2026-11-11T16:00:00.000Z");
    // 21:00 in Oslo.
    expect(deliverAtFor({ kind: "morning" }, now, "Europe/Oslo")).toBe("2026-11-11T07:00:00.000Z");
  });

  test("a send at exactly 08:00 waits for the next morning", () => {
    expect(deliverAtFor({ kind: "morning" }, at("2026-11-11T07:00:00.000Z"), "Europe/Oslo")).toBe("2026-11-12T07:00:00.000Z");
  });

  test("morning follows the clocks across daylight saving changes", () => {
    // 23:00 on 28 March in Oslo. The clocks go forward that night, so 08:00 is at 06:00 UTC.
    expect(deliverAtFor({ kind: "morning" }, at("2026-03-28T22:00:00.000Z"), "Europe/Oslo")).toBe("2026-03-29T06:00:00.000Z");
    // Midnight on 25 October in Oslo. The clocks go back that night, so 08:00 is at 07:00 UTC.
    expect(deliverAtFor({ kind: "morning" }, at("2026-10-24T22:00:00.000Z"), "Europe/Oslo")).toBe("2026-10-25T07:00:00.000Z");
    // New York goes back on 1 November.
    expect(deliverAtFor({ kind: "morning" }, at("2026-11-01T03:00:00.000Z"), "America/New_York")).toBe("2026-11-01T13:00:00.000Z");
  });
});

describe("visitLetterTime", () => {
  const visit = (startDate: string, firstDaySetAt: string) => ({ start_date: startDate, first_day_set_at: firstDaySetAt });

  test("a visit brings letters on at 20:00 on its first day on the recipient's clock, once planned 20 hours before", () => {
    expect(visitLetterTime(visit("2026-11-19", "2026-11-18T10:59:00.000Z"), "Pacific/Auckland")).toBe("2026-11-19T07:00:00.000Z");
    expect(visitLetterTime(visit("2026-11-19", "2026-11-18T11:00:00.000Z"), "Pacific/Auckland")).toBe("2026-11-19T07:00:00.000Z");
    expect(visitLetterTime(visit("2026-11-19", "2026-11-18T11:00:00.001Z"), "Pacific/Auckland")).toBeNull();
  });

  test("the 20 hours are counted in real time across daylight saving changes", () => {
    // Oslo goes forward on 29 March, so 20:00 is 18:00 UTC and 20 hours before is 23:00 the evening before.
    expect(visitLetterTime(visit("2026-03-29", "2026-03-28T22:00:00.000Z"), "Europe/Oslo")).toBe("2026-03-29T18:00:00.000Z");
    expect(visitLetterTime(visit("2026-03-29", "2026-03-28T22:00:00.001Z"), "Europe/Oslo")).toBeNull();
    // Oslo goes back on 25 October, so 20:00 is 19:00 UTC and 20 hours before is 01:00 that day.
    expect(visitLetterTime(visit("2026-10-25", "2026-10-24T23:00:00.000Z"), "Europe/Oslo")).toBe("2026-10-25T19:00:00.000Z");
  });
});

describe("visitLettersWrittenBefore", () => {
  test("a visit brings on letters written before its evening and before its first day began in every zone", () => {
    // 20:00 in Auckland comes before noon UTC, so the evening is the bound.
    expect(visitLettersWrittenBefore({ start_date: "2026-11-19" }, "2026-11-19T07:00:00.000Z")).toBe("2026-11-19T07:00:00.000Z");
    // 20:00 in New York comes after the day began in UTC-12, so noon UTC is the bound.
    expect(visitLettersWrittenBefore({ start_date: "2026-11-14" }, "2026-11-15T01:00:00.000Z")).toBe("2026-11-14T12:00:00.000Z");
  });
});
