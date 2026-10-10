import { v } from "convex/values";
import { internalMutation, mutation } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { getByUuid } from "./lib/db";
import { optionalTimestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import { getCoupleStreakForCouple, getCoupleStreakParticipationForUser, refreshStreakDeadline } from "./lib/streaks";
import { addHours, nowIso } from "./lib/time";

/** The streak card: counts, restore offer, and who has contributed today. Returns one row, like the SQL function. */
export const get_couple_streak = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const streak = await getCoupleStreakForCouple(ctx, coupleId);
    const participation = await getCoupleStreakParticipationForUser(ctx, coupleId, userId, nowIso());
    return [{ ...streak, ...participation }];
  },
});

/**
 * Port of `internal.enqueue_due_streak_reminders`. Queues a check-in reminder for
 * each partner who has not contributed today, for streaks whose deadline falls
 * within the next hour. Returns how many notifications were queued.
 */
export const enqueue_due_streak_reminders = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();

    // Zone changes can move a stored deadline, so re-resolve every running streak first.
    // ponytail: scans all streak rows each run. Page through them if the table outgrows one mutation.
    const states = await ctx.db.query("streak_states").collect();
    for (const state of states) {
      const couple = await getByUuid(ctx, "couples", state.couple_id);
      if (couple?.status === "active" && state.current_count > 0 && state.restorable_count === 0) {
        await refreshStreakDeadline(ctx, state.couple_id);
      }
    }

    const horizon = addHours(now, 1);
    const due = await ctx.db
      .query("streak_states")
      .withIndex("by_next_activity_deadline_at", (q) => q.gt("next_activity_deadline_at", now).lte("next_activity_deadline_at", horizon))
      .collect();

    let queued = 0;
    for (const state of due) {
      const couple = await getByUuid(ctx, "couples", state.couple_id);
      if (couple?.status !== "active" || state.restorable_count !== 0 || state.next_activity_deadline_at === undefined) {
        continue;
      }
      const currentDayId = await getOrCreateCoupleDayAt(ctx, state.couple_id, now);
      const events = await ctx.db
        .query("couple_activity_events")
        .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", currentDayId))
        .collect();
      const contributed = new Set(events.filter((event) => event.couple_id === state.couple_id).map((event) => event.user_id));
      const members = await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_status", (q) => q.eq("couple_id", state.couple_id).eq("status", "active"))
        .collect();
      for (const member of members) {
        if (contributed.has(member.user_id)) continue;
        queued += await enqueueNotificationForUser(ctx, {
          recipient_user_id: member.user_id,
          kind: "streak_reminder",
          payload: {
            type: "streak_reminder",
            couple_id: state.couple_id,
            current_count: state.current_count,
            last_qualified_date: state.last_qualified_date ?? null,
            next_activity_deadline_at: state.next_activity_deadline_at,
            contribution_needed: true,
            route: "streak",
            deeplink: "paeonia://streak",
          },
          dedupe_key:
            state.last_qualified_date === undefined
              ? null
              : `streak_reminder:${state.couple_id}:${state.last_qualified_date}:${member.user_id}`,
          redaction_level: "private",
          apns_push_type: "alert",
          apns_collapse_id: `streak:${state.couple_id}`,
          scheduled_for: now,
        });
      }
    }
    return queued;
  },
});
