import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, type MutationCtx, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import { getByUuid } from "./lib/db";
import { optionalTimestampArg } from "./lib/ids";
import { enqueueNotificationForUser } from "./lib/notifications";
import {
  EVENING_REMINDER_LEAD_HOURS,
  eveningReminderAt,
  lastHourReminderAllowed,
  resolveMemberStreakTimeZone,
} from "./lib/streakDeadlines";
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
 * within the next hour, unless it is night where that partner is
 * (`lastHourReminderAllowed`). Returns how many notifications were queued.
 *
 * It also stores what happened to streaks whose deadline just passed: a used
 * freeze, a restarted short streak, or an open restore offer. `get_couple_streak`
 * is a query and cannot write, so this run is what makes a subscribed streak card flip.
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

    const due = await ctx.db
      .query("streak_states")
      .withIndex("by_next_activity_deadline_at", (q) =>
        q.gt("next_activity_deadline_at", now).lte("next_activity_deadline_at", addHours(now, 1)),
      )
      .collect();
    let queued = 0;
    for (const state of due) {
      queued += await remindPartners(ctx, state, now, "last_hour", async (userId) =>
        lastHourReminderAllowed(now, await resolveMemberStreakTimeZone(ctx, userId)),
      );
    }
    return queued;
  },
});

/**
 * Queues the evening check-in reminder: 19:00 in each partner's own zone on the
 * last day before the deadline (see `eveningReminderAt`), for partners who have
 * not contributed today. A separate job from the break scan, so a slow run here
 * never holds up breaks or the last-hour reminder. Returns how many were queued.
 */
export const enqueue_evening_streak_reminders = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    // The evening reminder is at most a day before the latest time it can be, two hours before the
    // deadline. One more hour covers a day that is 25 hours long when the clocks go back.
    // ponytail: this reads about half of all live streaks each run. Store each partner's reminder time on the row if it outgrows one mutation.
    const upcoming = await ctx.db
      .query("streak_states")
      .withIndex("by_next_activity_deadline_at", (q) =>
        q.gt("next_activity_deadline_at", addHours(now, EVENING_REMINDER_LEAD_HOURS)).lte(
          "next_activity_deadline_at",
          addHours(now, EVENING_REMINDER_LEAD_HOURS + 25),
        ),
      )
      .collect();
    let queued = 0;
    for (const state of upcoming) {
      queued += await remindPartners(ctx, state, now, "evening", async (userId, deadline) => {
        const eveningAt = eveningReminderAt(deadline, await resolveMemberStreakTimeZone(ctx, userId));
        return eveningAt <= now && now < addHours(eveningAt, 1);
      });
    }
    return queued;
  },
});

/**
 * Queues one streak reminder for each active partner of a live streak who is due
 * and has not contributed to today's couple day. Deduped per partner, reminder
 * kind, and streak day. A freeze starts a new streak day without a newly
 * qualified date, so its stamp is part of the key.
 */
async function remindPartners(
  ctx: MutationCtx,
  state: Doc<"streak_states">,
  now: string,
  reminder: "last_hour" | "evening",
  isDue: (userId: string, deadline: string) => Promise<boolean>,
): Promise<number> {
  const deadline = state.next_activity_deadline_at;
  const couple = await getByUuid(ctx, "couples", state.couple_id);
  if (couple?.status !== "active" || state.restorable_count !== 0 || deadline === undefined) {
    return 0;
  }
  const members = await ctx.db
    .query("couple_members")
    .withIndex("by_couple_id_status", (q) => q.eq("couple_id", state.couple_id).eq("status", "active"))
    .collect();
  const streakDay =
    state.last_qualified_date === undefined
      ? null
      : `${state.last_qualified_date}${state.freeze_used_at === undefined ? "" : `:freeze:${state.freeze_used_at}`}`;
  let contributed: Set<string> | null = null;
  let queued = 0;
  for (const member of members) {
    if (!(await isDue(member.user_id, deadline))) continue;
    contributed ??= await contributorsToday(ctx, state.couple_id, now);
    if (contributed.has(member.user_id)) continue;
    queued += await enqueueNotificationForUser(ctx, {
      recipient_user_id: member.user_id,
      kind: "streak_reminder",
      payload: {
        type: "streak_reminder",
        couple_id: state.couple_id,
        current_count: state.current_count,
        last_qualified_date: state.last_qualified_date ?? null,
        next_activity_deadline_at: deadline,
        contribution_needed: true,
        route: "streak",
        deeplink: "paeonia://streak",
      },
      dedupe_key:
        streakDay === null
          ? null
          : reminder === "evening"
            ? `streak_reminder:evening:${state.couple_id}:${streakDay}:${member.user_id}`
            : `streak_reminder:${state.couple_id}:${streakDay}:${member.user_id}`,
      redaction_level: "private",
      apns_push_type: "alert",
      apns_collapse_id: `streak:${state.couple_id}`,
      scheduled_for: now,
    });
  }
  return queued;
}

/** Who has contributed to the couple day running at `now`. */
async function contributorsToday(ctx: MutationCtx, coupleId: string, now: string): Promise<Set<string>> {
  const currentDayId = await getOrCreateCoupleDayAt(ctx, coupleId, now);
  const events = await ctx.db
    .query("couple_activity_events")
    .withIndex("by_couple_day_id", (q) => q.eq("couple_day_id", currentDayId))
    .collect();
  return new Set(events.filter((event) => event.couple_id === coupleId).map((event) => event.user_id));
}
