import { parseDate } from "./time";

// Calendar math for the dates a couple keeps: birthdays, countdowns that repeat every year, and
// the relationship milestones. Every date is a `YYYY-MM-DD` calendar day with no time zone. Each
// phone counts days in its own zone, so the callers pass the day it is for the person they mean.
// The iOS twin of this file is `CoupleDateTimeline` (`Features/Countdown/CoupleDates`). A change
// to a rule here needs the same change there.

const pad = (value: number, length = 2) => String(value).padStart(length, "0");

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function format(year: number, month: number, day: number): string {
  return `${pad(year, 4)}-${pad(month)}-${pad(day)}`;
}

/** `date` moved to `year`. A 29 February falls on 28 February in a year that has no 29th. */
export function dateInYear(date: string, year: number): string {
  const [, month, day] = parseDate(date);
  return format(year, month, Math.min(day, daysInMonth(year, month)));
}

/** `date` plus whole months. The day is kept, or cut to the last day of a shorter month (31 January plus a month is 28 February). */
export function addMonthsToDate(date: string, months: number): string {
  const [year, month, day] = parseDate(date);
  const index = year * 12 + (month - 1) + months;
  const targetYear = Math.floor(index / 12);
  const targetMonth = (index % 12) + 1;
  return format(targetYear, targetMonth, Math.min(day, daysInMonth(targetYear, targetMonth)));
}

/** Whole calendar days from `from` to `to`. Negative when `to` is earlier. */
export function daysBetweenDates(from: string, to: string): number {
  const [fromYear, fromMonth, fromDay] = parseDate(from);
  const [toYear, toMonth, toDay] = parseDate(to);
  return Math.round((Date.UTC(toYear, toMonth - 1, toDay) - Date.UTC(fromYear, fromMonth - 1, fromDay)) / 86_400_000);
}

export type YearlyOccurrence = {
  /** The day it falls on. */
  date: string;
  /** How many years after `date` it is. 0 for the first occurrence, which is `date` itself. */
  years: number;
};

/**
 * The next time a date that repeats every year comes around, `today` included. A date still ahead
 * is its own first occurrence. Birthdays, yearly countdowns and the relationship anniversary all
 * use this, so the 29 February rule lives in one place.
 */
export function nextYearlyOccurrence(date: string, today: string): YearlyOccurrence {
  const [originalYear] = parseDate(date);
  const [todayYear] = parseDate(today);
  const year = Math.max(originalYear, todayYear);
  const thisYear = dateInYear(date, year);
  return thisYear >= today
    ? { date: thisYear, years: year - originalYear }
    : { date: dateInYear(date, year + 1), years: year + 1 - originalYear };
}

/**
 * When a countdown counts down to, seen from `today`. A countdown that does not repeat keeps its
 * date, even after it passed. One that repeats every year is never past: it shows its next
 * occurrence.
 */
export function countdownDay(countdown: { target_date: string; repeats_yearly?: boolean }, today: string): string {
  return countdown.repeats_yearly === true ? nextYearlyOccurrence(countdown.target_date, today).date : countdown.target_date;
}

export type MilestoneToday =
  | { kind: "first_month" }
  | { kind: "half_year" }
  | { kind: "years"; years: number }
  | { kind: "days"; days: number };

/** The round day counts the app calls milestones before every 1,000th day takes over. */
const EARLY_DAY_MILESTONES = [100, 500];
const DAY_MILESTONE_STRIDE = 1_000;

/**
 * The milestone the couple reaches on `today`, if any. This is the part of the app's milestone
 * schedule worth a push: the first month, half a year, every anniversary and the round day counts
 * (100, 500, then every 1,000th). The other months of the first year show on the Home tab but do
 * not send a push. When two fall on the same day the anniversary wins over half a year, which wins
 * over the first month, which wins over a day count, like the app's tie-break.
 */
export function milestoneToday(startedOn: string, today: string): MilestoneToday | null {
  const anniversary = nextYearlyOccurrence(startedOn, today);
  if (anniversary.date === today && anniversary.years >= 1) return { kind: "years", years: anniversary.years };
  if (addMonthsToDate(startedOn, 6) === today) return { kind: "half_year" };
  if (addMonthsToDate(startedOn, 1) === today) return { kind: "first_month" };
  const days = daysBetweenDates(startedOn, today);
  const isDayMilestone =
    EARLY_DAY_MILESTONES.includes(days) || (days >= DAY_MILESTONE_STRIDE && days % DAY_MILESTONE_STRIDE === 0);
  return isDayMilestone ? { kind: "days", days } : null;
}
