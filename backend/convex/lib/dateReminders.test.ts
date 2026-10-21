import { describe, expect, test } from "vitest";
import { planDateReminders, type DateReminderFacts } from "./dateReminders";

const ME = "11111111-1111-4111-8111-111111111111";
const PARTNER = "22222222-2222-4222-8222-222222222222";

const plan = (facts: Partial<DateReminderFacts> & { today: string }) =>
  planDateReminders({ user_id: ME, birthdays: new Map(), countdowns: [], ...facts });
const kinds = (facts: Partial<DateReminderFacts> & { today: string }) => plan(facts).map((r) => r.reminder);

describe("birthdays", () => {
  const birthdays = new Map([
    [ME, "1999-03-14"],
    [PARTNER, "2000-10-28"],
  ]);

  test("the partner hears a week ahead and on the day, and says whose birthday it is", () => {
    expect(plan({ today: "2026-10-21", birthdays })).toEqual([
      { reminder: "partner_birthday_soon", occurrence: "2026-10-28", subject_user_id: PARTNER, extra: {} },
    ]);
    expect(plan({ today: "2026-10-28", birthdays })).toEqual([
      { reminder: "partner_birthday_today", occurrence: "2026-10-28", subject_user_id: PARTNER, extra: {} },
    ]);
    expect(kinds({ today: "2026-10-27", birthdays })).toEqual([]);
  });

  test("the birthday child gets one note on the day and nothing ahead", () => {
    expect(kinds({ today: "2026-03-14", birthdays })).toEqual(["own_birthday"]);
    expect(kinds({ today: "2026-03-07", birthdays })).toEqual([]);
  });

  test("a 29 February birthday is remembered on 28 February, a week before on 21 February", () => {
    const leap = new Map([[PARTNER, "2000-02-29"]]);
    expect(kinds({ today: "2026-02-21", birthdays: leap })).toEqual(["partner_birthday_soon"]);
    expect(kinds({ today: "2026-02-28", birthdays: leap })).toEqual(["partner_birthday_today"]);
    expect(kinds({ today: "2026-03-01", birthdays: leap })).toEqual([]);
    expect(kinds({ today: "2028-02-29", birthdays: leap })).toEqual(["partner_birthday_today"]);
    expect(kinds({ today: "2028-02-28", birthdays: leap })).toEqual([]);
  });

  test("the day someone was born is not a birthday yet", () => {
    expect(kinds({ today: "2026-10-21", birthdays: new Map([[PARTNER, "2026-10-21"]]) })).toEqual([]);
    expect(kinds({ today: "2026-10-14", birthdays: new Map([[PARTNER, "2026-10-21"]]) })).toEqual([]);
  });

  test("a week ahead can cross the new year", () => {
    expect(kinds({ today: "2026-12-28", birthdays: new Map([[PARTNER, "2001-01-04"]]) })).toEqual([
      "partner_birthday_soon",
    ]);
  });
});

describe("the anniversary and milestones", () => {
  test("both hear a week ahead and on the day of an anniversary", () => {
    expect(plan({ today: "2026-10-14", started_on: "2023-10-21" })).toEqual([
      { reminder: "anniversary_soon", occurrence: "2026-10-21", extra: { years: 3 } },
    ]);
    expect(plan({ today: "2026-10-21", started_on: "2023-10-21" })).toEqual([
      { reminder: "milestone", occurrence: "2026-10-21", extra: { milestone: "years", years: 3 } },
    ]);
  });

  test("the first month, half a year and round day counts are pushed on the day", () => {
    expect(plan({ today: "2026-10-21", started_on: "2026-09-21" })[0]).toMatchObject({
      reminder: "milestone",
      extra: { milestone: "first_month" },
    });
    expect(plan({ today: "2026-10-21", started_on: "2026-07-13" })[0]).toMatchObject({
      extra: { milestone: "days", days: 100 },
    });
    // The other months of the first year stay on the Home tab.
    expect(kinds({ today: "2026-10-21", started_on: "2026-08-21" })).toEqual([]);
  });

  test("a couple whose first anniversary is still ahead gets no anniversary reminder", () => {
    expect(kinds({ today: "2026-10-14", started_on: "2026-10-21" })).toEqual([]);
  });

  test("a couple without a start date gets none", () => {
    expect(kinds({ today: "2026-10-21" })).toEqual([]);
  });
});

describe("countdowns", () => {
  test("one push on the day, counting every countdown that lands on it", () => {
    const countdowns = [
      { target_date: "2026-10-21" },
      { target_date: "2026-10-21" },
      { target_date: "2026-10-22" },
      { target_date: "2026-10-20" },
    ];
    expect(plan({ today: "2026-10-21", countdowns })).toEqual([
      { reminder: "countdown", occurrence: "2026-10-21", extra: { count: 2 } },
    ]);
  });

  test("a yearly countdown comes back on its day each year, a one-off does not", () => {
    const yearly = [{ target_date: "2023-06-12", repeats_yearly: true }];
    expect(kinds({ today: "2026-06-12", countdowns: yearly })).toEqual(["countdown"]);
    expect(kinds({ today: "2026-06-13", countdowns: yearly })).toEqual([]);
    expect(kinds({ today: "2026-06-12", countdowns: [{ target_date: "2023-06-12" }] })).toEqual([]);
  });

  test("a yearly countdown on 29 February comes on 28 February in other years", () => {
    const yearly = [{ target_date: "2024-02-29", repeats_yearly: true }];
    expect(kinds({ today: "2026-02-28", countdowns: yearly })).toEqual(["countdown"]);
    expect(kinds({ today: "2028-02-29", countdowns: yearly })).toEqual(["countdown"]);
    expect(kinds({ today: "2028-02-28", countdowns: yearly })).toEqual([]);
  });
});
