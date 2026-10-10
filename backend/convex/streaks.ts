import { v } from "convex/values";
import { internalMutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { getByUuid } from "./lib/db";
import { optionalTimestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import { detectStreakBreak, getCoupleStreakParticipationForUser, readCoupleStreak } from "./lib/streaks";
import { addHours, nowIso } from "./lib/time";

/**
 * The streak card: counts, restore offer, and who has contributed today. Returns one row, like the SQL function.
 * A query cannot store the restore offer. It reports a just-broken streak from the clock and the stored deadline,
 * and `enqueue_due_streak_reminders` persists the same state within one cron interval.
 */
export const get_couple_streak = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const streak = await readCoupleStreak(ctx, coupleId);
    const participation = await getCoupleStreakParticipationForUser(ctx, coupleId, userId, nowIso());
    return [{ ...streak, ...participation }];
  },
});

/** Streaks whose deadline passed longer ago than this have an expired restore offer, so the cron skips them. */
const BREAK_LOOKBACK_HOURS = 48;
/** Most streaks the cron inspects per run for a newly passed deadline. */
const BREAK_BATCH_LIMIT = 500;

/**
 * Port of `internal.enqueue_due_streak_reminders`. Queues a check-in reminder for
 * each partner who has not contributed today, for streaks whose deadline falls
 * within the next hour. Returns how many notifications were queued.
 *
 * It also stores the broken state for streaks whose deadline just passed, which
 * opens the restore offer. `get_couple_streak` is a query and cannot write, so
 * this run is what makes a subscribed streak card flip.
 */
export const enqueue_due_streak_reminders = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();

    // The index range holds only deadlines that passed in the lookback window, oldest first.
    // Already-broken rows and ended couples keep their deadline, so skip them before
    // counting toward the limit. Otherwise they would hide newer breaks for the whole window.
    // ponytail: unbroken rows past the limit wait for the next run. Raise it if breaks pile up faster than 500 per 5 minutes.
    let broken = 0;
    for await (const state of ctx.db
      .query("streak_states")
      .withIndex("by_next_activity_deadline_at", (q) =>
        q.gt("next_activity_deadline_at", addHours(now, -BREAK_LOOKBACK_HOURS)).lte("next_activity_deadline_at", now),
      )) {
      if (state.current_count <= 0 || state.restorable_count !== 0) continue;
      const couple = await getByUuid(ctx, "couples", state.couple_id);
      if (couple?.status !== "active") continue;
      if (broken >= BREAK_BATCH_LIMIT) break;
      broken += 1;
      await detectStreakBreak(ctx, state.couple_id);
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
