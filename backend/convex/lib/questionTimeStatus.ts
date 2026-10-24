import type { ReaderCtx } from "./db";
import { findCoupleDayAt } from "./coupleDays";
import { isVisibleAnswer } from "./dailyQuestions";

/**
 * True when the user has a visible answer on a question of the couple day running at `now`. A day nobody has opened yet does not exist, so nothing is started.
 * The reminder cron asks this before queueing, and `prepare_notification` asks it again before
 * every send attempt, so a retry after the user answered never goes out.
 */
export async function hasStartedToday(ctx: ReaderCtx, coupleId: string, userId: string, now: string): Promise<boolean> {
  const day = await findCoupleDayAt(ctx, coupleId, now);
  if (!day) return false;
  const instances = await ctx.db
    .query("daily_question_instances")
    .withIndex("by_couple_day_id_status", (q) => q.eq("couple_day_id", day.id))
    .collect();
  for (const instance of instances) {
    const answer = await ctx.db
      .query("daily_question_answers")
      .withIndex("by_instance_id_user_id", (q) => q.eq("instance_id", instance.id).eq("user_id", userId))
      .unique();
    if (isVisibleAnswer(answer)) return true;
  }
  return false;
}
