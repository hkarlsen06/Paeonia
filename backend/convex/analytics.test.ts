import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { createCouple, newTest } from "./test.setup";

const POSTHOG = "https://eu.posthog.com/api/projects/309819";

type Call = { url: string; body: unknown };

/** Records every request and answers like PostHog. */
function stubPostHog(inactivePersonIds: string[] = []): Call[] {
  const calls: Call[] = [];
  vi.stubGlobal("fetch", async (input: string | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, body: JSON.parse(String(init?.body ?? "null")) });
    if (url === `${POSTHOG}/query/`) {
      return Response.json({ results: inactivePersonIds.map((id) => [id]) });
    }
    return Response.json({ deletion_errors: [] }, { status: 202 });
  });
  return calls;
}

beforeEach(() => {
  vi.useFakeTimers();
  process.env.POSTHOG_PERSONAL_API_KEY = "phx_test_posthog";
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  delete process.env.POSTHOG_PERSONAL_API_KEY;
});

describe("usage sharing", () => {
  test("is unanswered until the person answers, then keeps the answer", async () => {
    const t = newTest();
    const calls = stubPostHog();
    const { first } = await createCouple(t);

    expect(await first.as.query(api.analytics.get_usage_sharing, {})).toEqual({ shares_usage: null });
    await first.as.mutation(api.analytics.set_usage_sharing, { p_shares: false, p_notice: "2026-10-17" });
    expect(await first.as.query(api.analytics.get_usage_sharing, {})).toEqual({ shares_usage: false });

    const profile = await t.run((ctx) =>
      ctx.db.query("profiles").withIndex("by_user_id", (q) => q.eq("user_id", first.userId)).unique(),
    );
    expect(profile).toMatchObject({ shares_usage: false, shares_usage_notice: "2026-10-17" });
    expect(profile?.shares_usage_decided_at).toBeDefined();

    // A first no never tells PostHog about the person.
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(calls).toHaveLength(0);
  });

  test("saying no after a yes deletes the person in PostHog", async () => {
    const t = newTest();
    const calls = stubPostHog();
    const { first } = await createCouple(t);

    await first.as.mutation(api.analytics.set_usage_sharing, { p_shares: true, p_notice: "2026-10-17" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(calls).toHaveLength(0);

    await first.as.mutation(api.analytics.set_usage_sharing, { p_shares: false, p_notice: "2026-10-17" });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(calls).toEqual([
      {
        url: `${POSTHOG}/persons/bulk_delete/`,
        body: { distinct_ids: [first.userId], delete_events: true, delete_recordings: true },
      },
    ]);
  });
});

describe("inactive people", () => {
  test("deletes everyone PostHog has not heard from in a year", async () => {
    const t = newTest();
    const calls = stubPostHog(["person-1", "person-2"]);

    expect(await t.action(internal.analytics.delete_inactive_analytics_persons, {})).toBe(2);
    expect(calls[1]).toEqual({
      url: `${POSTHOG}/persons/bulk_delete/`,
      body: { ids: ["person-1", "person-2"], delete_events: true, delete_recordings: true },
    });
  });

  test("sends no delete when nobody is inactive", async () => {
    const t = newTest();
    const calls = stubPostHog();

    expect(await t.action(internal.analytics.delete_inactive_analytics_persons, {})).toBe(0);
    expect(calls.map((call) => call.url)).toEqual([`${POSTHOG}/query/`]);
  });
});
