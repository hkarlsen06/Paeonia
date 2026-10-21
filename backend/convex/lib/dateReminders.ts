import { countdownDay, milestoneToday, nextYearlyOccurrence, type MilestoneToday } from "./coupleDates";
import { addDaysToDate } from "./time";

// Which gentle reminders a person gets on one local day for the dates the couple keeps. This file
// only decides. `dateReminders.ts` runs it each morning and queues the pushes.
//
// Timing. A reminder goes out at 09:00 on the recipient's own clock, in the zone the streak
// reminders use. The date it is about is a calendar day with no zone, so each partner counts it on
// their own day: Elena's birthday reaches a partner in Auckland a few hours before one in Oslo.
// Morning is early enough to do something with the day and late enough not to wake anyone, and the
// existing night rule (`deliverQuietly`) still covers a phone that is somewhere else at that hour.
//
// Who gets what.
// - The partner of a birthday child hears a week ahead, so there is time to plan, and on the day.
// - The birthday child gets one warm line on the day and nothing before it.
// - Both partners hear about the relationship anniversary a week ahead and on the day.
// - Both hear about the first month, half a year and the round day counts on the day.
// - Both hear on the day of a countdown. Several countdowns on one day are one push.

export const DATE_REMINDER_MINUTES = 9 * 60;
/** Two 15-minute cron runs see the window, so one late run still sends. The dedupe key stops a repeat. */
export const DATE_REMINDER_WINDOW_MINUTES = 30;
export const BIRTHDAY_LEAD_DAYS = 7;
export const ANNIVERSARY_LEAD_DAYS = 7;

export type DateReminderKind =
  | "partner_birthday_soon"
  | "partner_birthday_today"
  | "own_birthday"
  | "anniversary_soon"
  | "milestone"
  | "countdown";

export type DateReminder = {
  reminder: DateReminderKind;
  /** The day the reminder is about, so a reminder is queued once per occurrence. */
  occurrence: string;
  /** The partner whose birthday it is, for the title. */
  subject_user_id?: string;
  /** More fields for the push copy. */
  extra: Record<string, unknown>;
};

export type DateReminderFacts = {
  /** The person the reminders are for. */
  user_id: string;
  /** The recipient's local date. */
  today: string;
  /** The couple's start date, if set. */
  started_on?: string;
  /** Birthdays by user id, for the couple's active members. */
  birthdays: ReadonlyMap<string, string>;
  countdowns: ReadonlyArray<{ target_date: string; repeats_yearly?: boolean }>;
};

/**
 * Whether `day` is a yearly occurrence of `date`, at least one year after it. The day a person was
 * born is not a birthday, and the day a couple met is not yet an anniversary.
 */
function isYearlyOn(date: string, day: string): boolean {
  return yearsOn(date, day) !== null;
}

/** How many years after `date` the yearly occurrence that falls on `day` is, or null when `day` is not one. */
function yearsOn(date: string, day: string): number | null {
  const occurrence = nextYearlyOccurrence(date, day);
  return occurrence.date === day && occurrence.years >= 1 ? occurrence.years : null;
}

function milestoneExtra(milestone: MilestoneToday): Record<string, unknown> {
  switch (milestone.kind) {
    case "years":
      return { milestone: "years", years: milestone.years };
    case "days":
      return { milestone: "days", days: milestone.days };
    default:
      return { milestone: milestone.kind };
  }
}

export function planDateReminders(facts: DateReminderFacts): DateReminder[] {
  const { today } = facts;
  const reminders: DateReminder[] = [];

  for (const [ownerId, birthday] of facts.birthdays) {
    if (ownerId === facts.user_id) {
      if (isYearlyOn(birthday, today)) reminders.push({ reminder: "own_birthday", occurrence: today, extra: {} });
      continue;
    }
    const ahead = addDaysToDate(today, BIRTHDAY_LEAD_DAYS);
    if (isYearlyOn(birthday, ahead)) {
      reminders.push({ reminder: "partner_birthday_soon", occurrence: ahead, subject_user_id: ownerId, extra: {} });
    }
    if (isYearlyOn(birthday, today)) {
      reminders.push({ reminder: "partner_birthday_today", occurrence: today, subject_user_id: ownerId, extra: {} });
    }
  }

  if (facts.started_on !== undefined) {
    const ahead = addDaysToDate(today, ANNIVERSARY_LEAD_DAYS);
    const years = yearsOn(facts.started_on, ahead);
    if (years !== null) {
      reminders.push({ reminder: "anniversary_soon", occurrence: ahead, extra: { years } });
    }
    const milestone = milestoneToday(facts.started_on, today);
    if (milestone !== null) {
      reminders.push({ reminder: "milestone", occurrence: today, extra: milestoneExtra(milestone) });
    }
  }

  const countdownsToday = facts.countdowns.filter((countdown) => countdownDay(countdown, today) === today).length;
  if (countdownsToday > 0) {
    reminders.push({ reminder: "countdown", occurrence: today, extra: { count: countdownsToday } });
  }
  return reminders;
}
