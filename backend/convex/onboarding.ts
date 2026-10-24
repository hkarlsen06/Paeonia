import { v } from "convex/values";
import { internalQuery, mutation } from "./_generated/server";
import { consumeGlobalRateLimit } from "./lib/rateLimits";
import { nowIso } from "./lib/time";
import { welcomeStep } from "./lib/validators";

// How many installs reach each signed-out welcome step. The app calls this before sign-in,
// once per step per install, without a session. The server keeps only a count per UTC day
// and step, so nothing here can tell people or phones apart.

/** Adds one to today's count for `p_step`. Any other step name fails argument validation. */
export const record_welcome_step = mutation({
  args: { p_step: welcomeStep },
  returns: v.null(),
  handler: async (ctx, args) => {
    await consumeGlobalRateLimit(ctx, "welcomeStep");
    const day = nowIso().slice(0, 10);
    const row = await ctx.db
      .query("welcome_step_counts")
      .withIndex("by_day_step", (q) => q.eq("day", day).eq("step", args.p_step))
      .unique();
    if (row) {
      await ctx.db.patch(row._id, { count: row.count + 1 });
    } else {
      await ctx.db.insert("welcome_step_counts", { day, step: args.p_step, count: 1 });
    }
    return null;
  },
});

/**
 * The counts from `p_from_day` (`YYYY-MM-DD`, inclusive) on, oldest day first. For the
 * operator: `npx convex run onboarding:get_welcome_step_counts '{"p_from_day":"2026-10-01"}'`.
 */
export const get_welcome_step_counts = internalQuery({
  args: { p_from_day: v.string() },
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("welcome_step_counts")
      .withIndex("by_day_step", (q) => q.gte("day", args.p_from_day))
      .collect();
    return rows.map(({ day, step, count }) => ({ day, step, count }));
  },
});
