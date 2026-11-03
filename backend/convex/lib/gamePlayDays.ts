import { addDaysToDate } from "./time";

/** A couple day (YYYY-MM-DD) and the people who had a game open on it (`game_play_days`). */
export type GamePlayDay = { day: string; user_ids: readonly string[] };

/** What the Games tab shows about the days both partners played. `today` is the couple day they were counted on. */
export type GamePlayDayStats = { streak: number; total: number; today: string };

/**
 * Counts the couple days on which both partners had a game open. `total` counts every such day.
 * `streak` counts the run of such days that ends today. The streak is forgiving: until today ends,
 * a day without play yet keeps the run that ended yesterday. Without a partner both are 0.
 */
export function gamePlayDayStats(
  days: readonly GamePlayDay[],
  members: readonly [string, string] | null,
  today: string,
): GamePlayDayStats {
  if (!members) return { streak: 0, total: 0, today };
  const together = new Set(
    days.filter((row) => members.every((id) => row.user_ids.includes(id))).map((row) => row.day),
  );
  let day = together.has(today) ? today : addDaysToDate(today, -1);
  let streak = 0;
  while (together.has(day)) {
    streak += 1;
    day = addDaysToDate(day, -1);
  }
  return { streak, total: together.size, today };
}
