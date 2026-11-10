import { describe, expect, test } from "vitest";
import { deliverAtFor, LETTER_STATES, nextLetterState } from "./letters";

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
