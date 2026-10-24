import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newTest } from "./test.setup";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-24T23:30:00Z"));
});
afterEach(() => {
  vi.useRealTimers();
});

describe("welcome step counts", () => {
  test("refuses a step that is not on the list", async () => {
    const t = newTest();
    await expect(
      t.mutation(api.onboarding.record_welcome_step, { p_step: "user_id_123" as "welcome_shown" }),
    ).rejects.toThrow();
    expect(await t.query(internal.onboarding.get_welcome_step_counts, { p_from_day: "2026-01-01" })).toEqual([]);
  });

  test("counts per UTC day and step without a session", async () => {
    const t = newTest();
    await t.mutation(api.onboarding.record_welcome_step, { p_step: "welcome_shown" });
    await t.mutation(api.onboarding.record_welcome_step, { p_step: "welcome_shown" });
    await t.mutation(api.onboarding.record_welcome_step, { p_step: "start_chosen" });
    vi.setSystemTime(new Date("2026-10-25T00:10:00Z"));
    await t.mutation(api.onboarding.record_welcome_step, { p_step: "welcome_shown" });

    const counts = await t.query(internal.onboarding.get_welcome_step_counts, { p_from_day: "2026-10-24" });
    expect(counts).toEqual(
      expect.arrayContaining([
        { day: "2026-10-24", step: "welcome_shown", count: 2 },
        { day: "2026-10-24", step: "start_chosen", count: 1 },
        { day: "2026-10-25", step: "welcome_shown", count: 1 },
      ]),
    );
    expect(counts).toHaveLength(3);
    expect(await t.query(internal.onboarding.get_welcome_step_counts, { p_from_day: "2026-10-25" })).toEqual([
      { day: "2026-10-25", step: "welcome_shown", count: 1 },
    ]);
  });

  test("stores only the day, the step and the count", async () => {
    const t = newTest();
    await t.mutation(api.onboarding.record_welcome_step, { p_step: "signed_in" });
    const rows = await t.run((ctx) => ctx.db.query("welcome_step_counts").collect());
    expect(rows).toHaveLength(1);
    expect(Object.keys(rows[0]).sort()).toEqual(["_creationTime", "_id", "count", "day", "step"]);
  });
});
