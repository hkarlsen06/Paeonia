import { endOfLocalDay, localDateOf, zonedLocalToUtcMs } from "./time";

/** Question time starts at 20:00 until the user picks another time. */
export const DEFAULT_QUESTION_TIME_MINUTES = 20 * 60;
/**
 * A reminder goes out in the first cron run that sees the chosen time, and up to this long after.
 * Three five-minute runs cover a late run. A time that passed longer ago is skipped, so saving
 * the setting in the evening never sends a reminder for a time long gone.
 */
export const QUESTION_TIME_WINDOW_MINUTES = 15;

const MINUTES_PER_DAY = 24 * 60;
const MINUTE_MS = 60_000;

/** True for a whole number of minutes after local midnight, 0 to 1439. */
export function isValidQuestionTimeMinutes(minutes: number): boolean {
  return Number.isInteger(minutes) && minutes >= 0 && minutes < MINUTES_PER_DAY;
}

/**
 * Whether `nowMs` is inside the window that starts at the user's chosen time on their current
 * local date in `timeZone`. Returns that date and when the reminder stops being useful, the end
 * of the same date. A window never crosses local midnight, so a 23:55 reminder that a late run
 * sees at 00:01 is not sent. Null when it is not time yet or the window is over.
 *
 * The chosen time follows `zonedLocalToUtcMs`. On the day the clocks go forward, a time in the
 * skipped hour is due one hour later (02:30 becomes 03:30). On the day they go back, a time in the
 * repeated hour is due once, at its second pass.
 */
export function questionTimeDue(
  nowMs: number,
  timeZone: string,
  minutes: number,
): { localDate: string; expiresAt: string } | null {
  const localDate = localDateOf(nowMs, timeZone);
  const dueMs = zonedLocalToUtcMs(localDate, timeZone, Math.floor(minutes / 60), minutes % 60);
  if (dueMs <= nowMs && nowMs < dueMs + QUESTION_TIME_WINDOW_MINUTES * MINUTE_MS) {
    return { localDate, expiresAt: endOfLocalDay(localDate, timeZone) };
  }
  return null;
}
