import type { Doc } from "../_generated/dataModel";
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

/** When a letter arrives. A new kind joins this list and gets its case in `deliverAtFor`. */
export const LETTER_DELIVERY_KINDS = ["now", "at", "morning"] as const;
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

/** Letters count code points, so an emoji is one. */
export const MAX_LETTER_BODY_CODE_POINTS = 2000;
/** How far ahead a letter may be set to arrive. A year, plus a day for a phone clock that runs ahead. */
export const MAX_LETTER_WAIT_MS = 366 * 86_400_000;
/** A morning letter arrives at this hour on the recipient's clock. */
export const MORNING_HOUR = 8;

export type LetterDelivery = { kind: "now" } | { kind: "at"; at: string } | { kind: "morning" };

/**
 * The instant a letter arrives, worked out once when it is sent. A set time that already passed,
 * such as a send that waited offline, arrives at once.
 */
export function deliverAtFor(delivery: LetterDelivery, nowMs: number, recipientTimeZone: string): string {
  switch (delivery.kind) {
    case "now":
      return new Date(nowMs).toISOString();
    case "at":
      return new Date(Math.max(Date.parse(delivery.at), nowMs)).toISOString();
    case "morning":
      return nextLocalHour(nowMs, recipientTimeZone, MORNING_HOUR);
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
