import type { Doc } from "../_generated/dataModel";
import { fail } from "./errors";
import { charLength } from "./text";
import { addDaysToDate, localDateOf, zonedLocalToUtcMs } from "./time";

// A letter stays sealed until it is delivered, then the recipient opens it. Only `nextLetterState`
// moves a letter between states, and only `deliverAtFor` decides when it arrives.

/** The templates a letter starts from. The app holds their names, first lines and art (`LetterTemplate.swift`). */
export const LETTER_TEMPLATE_KEYS = [
  "blank",
  "good_morning",
  "good_night",
  "birthday",
  "anniversary",
  "miss_you",
  "good_luck",
  "thank_you",
] as const;
export type LetterTemplateKey = (typeof LETTER_TEMPLATE_KEYS)[number];

/**
 * When a letter arrives. A new kind joins this list and gets its case in `deliverAtFor`. A
 * `together` letter has no time: it waits for the partners' next meeting (`letters.ts`).
 */
export const LETTER_DELIVERY_KINDS = ["now", "at", "morning", "together"] as const;
export type LetterDeliveryKind = (typeof LETTER_DELIVERY_KINDS)[number];

export const LETTER_STATES = ["sealed", "delivered", "opened"] as const;
export type LetterState = (typeof LETTER_STATES)[number];
export type LetterEvent = "deliver" | "open";

const TRANSITIONS: Record<LetterState, Partial<Record<LetterEvent, LetterState>>> = {
  sealed: { deliver: "delivered" },
  delivered: { open: "opened" },
  opened: {},
};

/** The state `event` moves a letter to, or null when it does not apply, so a repeat changes nothing. */
export function nextLetterState(state: LetterState, event: LetterEvent): LetterState | null {
  return TRANSITIONS[state][event] ?? null;
}

/** The letter pushes' switch. A row from before letters existed has none, and that reads as on. */
export function lettersEnabled(preference: Pick<Doc<"notification_preferences">, "letters_enabled">): boolean {
  return preference.letters_enabled !== false;
}

/** Letters count code points, so "❤️" is two, the heart and the sign that makes it red. */
export const MAX_LETTER_BODY_CODE_POINTS = 2000;

/**
 * The note as it is stored, without the white space JavaScript's `trim` removes at either end.
 * That includes U+FEFF and leaves U+0085. Fails with `23514` when it is empty and with `22001`
 * when it is longer than the limit, which the app tells the author in its own words. The app
 * applies the same rule before it sends (`LetterBody.swift`), so change the two together.
 */
export function parseLetterBody(raw: string): string {
  const body = raw.trim();
  if (body === "") fail("23514", "letter is empty");
  if (charLength(body) > MAX_LETTER_BODY_CODE_POINTS) {
    fail("22001", `letter is longer than ${MAX_LETTER_BODY_CODE_POINTS} characters`);
  }
  return body;
}

/** The most letters waiting to be opened that a read returns or a badge counts. */
export const MAX_WAITING_LETTERS = 50;
/** The newest letters of each mailbox list that `get_letters` returns. */
export const MAILBOX_FIRST_PAGE = 25;
/** The most letters one page of `get_older_letters` returns. */
export const MAX_OLDER_PAGE = 50;
/** The due letters one run of the delivery sweep handles before it schedules the next page. */
export const DUE_LETTER_PAGE = 50;
/** How far ahead a letter may be set to arrive. A year, plus a day for a phone clock that runs ahead. */
export const MAX_LETTER_WAIT_MS = 366 * 86_400_000;
/** A morning letter arrives at this hour on the recipient's clock. */
export const MORNING_HOUR = 8;
/**
 * A letter for the next meeting that location has not delivered arrives at this hour on the
 * recipient's clock, on the first day of a visit planned ahead (`visitLetterTime`).
 */
export const VISIT_LETTER_HOUR = 20;
/**
 * How long before that hour a visit's first day must be set. On most days this is midnight on the
 * recipient's clock as the server reads it at that hour, so planning a visit on its own first day
 * brings no letter on unless the recipient's phone reports a zone further west before then.
 */
export const VISIT_LETTER_NOTICE_MS = 20 * 3_600_000;
/** How many UTC days back the delivery sweep looks for visits whose evening has brought letters on. */
export const VISIT_SWEEP_DAYS = 3;

/**
 * The instant `visit` brings on the letters for the next meeting that wait for someone in
 * `recipientTimeZone`: `VISIT_LETTER_HOUR` on its first day on their clock. Null when the first
 * day was set less than `VISIT_LETTER_NOTICE_MS` before then.
 */
export function visitLetterTime(
  visit: Pick<Doc<"visits">, "start_date" | "first_day_set_at">,
  recipientTimeZone: string,
): string | null {
  const at = zonedLocalToUtcMs(visit.start_date, recipientTimeZone, VISIT_LETTER_HOUR);
  return Date.parse(visit.first_day_set_at) <= at - VISIT_LETTER_NOTICE_MS ? new Date(at).toISOString() : null;
}

/**
 * The letters a visit brings on were written before `visitLetterTime` and before noon UTC on its
 * first day, when that day has begun in every time zone, since none is more than 12 hours behind
 * UTC. The composer offers a visit only while its first day is still ahead on one partner's
 * clock, so every letter it took for the visit was written before then, and a letter written
 * after the visit is never brought on by it when the recipient's clock moves west.
 */
export function visitLettersWrittenBefore(visit: Pick<Doc<"visits">, "start_date">, letterTime: string): string {
  const firstDayBegun = `${visit.start_date}T12:00:00.000Z`;
  return letterTime < firstDayBegun ? letterTime : firstDayBegun;
}

export type LetterDelivery = { kind: "now" } | { kind: "at"; at: string } | { kind: "morning" } | { kind: "together" };

/**
 * The instant a letter arrives, worked out once when it is sent, or null for a letter that waits
 * for the next meeting. A set time that already passed, such as a send that waited offline,
 * arrives at once.
 */
export function deliverAtFor(delivery: LetterDelivery, nowMs: number, recipientTimeZone: string): string | null {
  switch (delivery.kind) {
    case "now":
      return new Date(nowMs).toISOString();
    case "at":
      return new Date(Math.max(Date.parse(delivery.at), nowMs)).toISOString();
    case "morning":
      return nextLocalHour(nowMs, recipientTimeZone, MORNING_HOUR);
    case "together":
      return null;
    default:
      return delivery satisfies never;
  }
}

/** The first `hour`:00 on the zone's clock strictly after `nowMs`. */
export function nextLocalHour(nowMs: number, timeZone: string, hour: number): string {
  const today = localDateOf(nowMs, timeZone);
  const todayAt = zonedLocalToUtcMs(today, timeZone, hour);
  const at = todayAt > nowMs ? todayAt : zonedLocalToUtcMs(addDaysToDate(today, 1), timeZone, hour);
  return new Date(at).toISOString();
}
