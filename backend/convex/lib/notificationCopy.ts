import type { ReaderCtx } from "./db";
import type { GameKind } from "./games";
import { isJsonObject, jsonbByteLength, jsonbText } from "./json";

/** Port of `internal.notification_locale_language`: Norwegian locales map to 'nb', everything else to 'en'. */
export function notificationLocaleLanguage(locale: string | null | undefined): "nb" | "en" {
  const normalized = (locale ?? "").trim().replace(/_/g, "-").toLowerCase();
  const language = normalized.split("-")[0];
  return language === "no" || language === "nb" || language === "nn" ? "nb" : "en";
}

/**
 * One game's lock-screen copy in one language. Name the game and whose turn it is. Never the move,
 * a word, a drawing, or written content.
 */
type GamePushCopy = {
  name: string;
  /** Falls back to the reminder body. */
  turnReadyBody?: string;
  /** For a game that sends `game_result`. `actor` is the partner's name. */
  resultTitle?: (actor: string) => string;
  resultBody?: string;
  /**
   * Copy for one moment of the game, picked by the push's `step` (`enqueueGamePush`), such as
   * `last_line`. It replaces the title and body of any game push that names it.
   */
  steps?: Record<string, { title: (actor: string) => string; body: string }>;
};

/** Each game adds its entry before it sends pushes. The copy reads `payload.game_kind`. */
export const GAME_PUSH_COPY: { [Kind in GameKind]?: Record<"en" | "nb", GamePushCopy> } = {
  draw_and_guess: {
    en: {
      name: "Draw & Guess",
      turnReadyBody: "Open Paeonia to guess it.",
      resultTitle: (actor) => `${actor} guessed your drawing`,
      resultBody: "Open Paeonia to see how it went.",
    },
    nb: {
      name: "Tegn og gjett",
      turnReadyBody: "Åpne Paeonia for å gjette.",
      resultTitle: (actor) => `${actor} gjettet tegningen din`,
      resultBody: "Åpne Paeonia for å se hvordan det gikk.",
    },
  },
  mind_meld: {
    en: {
      name: "Mind Meld",
      turnReadyBody: "Open Paeonia to pick your word.",
      resultTitle: () => "Your words are in",
      resultBody: "Open Paeonia to see what you both said.",
    },
    nb: {
      name: "Tenk likt",
      turnReadyBody: "Åpne Paeonia for å velge ordet ditt.",
      resultTitle: () => "Ordene deres er klare",
      resultBody: "Åpne Paeonia for å se hva dere sa.",
    },
  },
  story_chain: {
    en: {
      name: "Story Chain",
      turnReadyBody: "Open Paeonia to read the newest line.",
      resultTitle: (actor) => `${actor} named your story`,
      resultBody: "Open Paeonia to read it.",
      steps: {
        last_line: { title: (actor) => `${actor} wrote the last line`, body: "Open Paeonia to give your story a title." },
      },
    },
    nb: {
      name: "Skrivestafett",
      turnReadyBody: "Åpne Paeonia for å lese den nyeste linjen.",
      resultTitle: (actor) => `${actor} ga historien deres en tittel`,
      resultBody: "Åpne Paeonia for å lese den.",
      steps: {
        last_line: { title: (actor) => `${actor} skrev den siste linjen`, body: "Åpne Paeonia for å gi historien en tittel." },
      },
    },
  },
  exquisite_corpse: {
    en: {
      name: "Exquisite corpse",
      resultTitle: (actor) => `${actor} finished your creature`,
      resultBody: "Open it to see the whole thing.",
      steps: {
        body: { title: (actor) => `${actor} drew the head`, body: "Your turn to draw the body." },
        legs: { title: (actor) => `${actor} drew the body`, body: "Your turn to draw the legs." },
      },
    },
    nb: {
      name: "Kadaver exquis",
      resultTitle: (actor) => `${actor} gjorde ferdig skapningen deres`,
      resultBody: "Åpne den for å se hele.",
      steps: {
        body: { title: (actor) => `${actor} har tegnet hodet`, body: "Din tur til å tegne kroppen." },
        legs: { title: (actor) => `${actor} har tegnet kroppen`, body: "Din tur til å tegne beina." },
      },
    },
  },
  connect_four: {
    en: {
      name: "Connect Four",
      turnReadyBody: "Open Paeonia to make your move.",
      resultTitle: () => "Your game of Connect Four is over",
      resultBody: "Open Paeonia to see how it ended.",
    },
    nb: {
      name: "Fire på rad",
      turnReadyBody: "Åpne Paeonia for å gjøre trekket ditt.",
      resultTitle: () => "Spillet deres i Fire på rad er ferdig",
      resultBody: "Åpne Paeonia for å se hvordan det endte.",
    },
  },
  dots_and_boxes: {
    en: {
      name: "Dots and Boxes",
      turnReadyBody: "Open Paeonia to make your move.",
      resultTitle: () => "Your game of Dots and Boxes is over",
      resultBody: "Open Paeonia to see how it ended.",
    },
    nb: {
      name: "Prikker og streker",
      turnReadyBody: "Åpne Paeonia for å gjøre trekket ditt.",
      resultTitle: () => "Spillet deres i Prikker og streker er ferdig",
      resultBody: "Åpne Paeonia for å se hvordan det endte.",
    },
  },
  ultimate_tic_tac_toe: {
    en: {
      name: "Ultimate Tic-Tac-Toe",
      turnReadyBody: "Open Paeonia to make your move.",
      resultTitle: () => "Your game of Ultimate Tic-Tac-Toe is over",
      resultBody: "Open Paeonia to see how it ended.",
    },
    nb: {
      name: "Ultimat bondesjakk",
      turnReadyBody: "Åpne Paeonia for å gjøre trekket ditt.",
      resultTitle: () => "Spillet deres i Ultimat bondesjakk er ferdig",
      resultBody: "Åpne Paeonia for å se hvordan det endte.",
    },
  },
  ludo: {
    en: {
      name: "Ludo",
      turnReadyBody: "Open Paeonia to make your move.",
      resultTitle: () => "Your game of Ludo is over",
      resultBody: "Open Paeonia to see how it ended.",
    },
    nb: {
      name: "Ludo",
      turnReadyBody: "Åpne Paeonia for å gjøre trekket ditt.",
      resultTitle: () => "Spillet deres i Ludo er ferdig",
      resultBody: "Åpne Paeonia for å se hvordan det endte.",
    },
  },
};

/** The copy of the game a push names in `payload.game_kind`, or null when the game has no entry. */
function gamePushCopy(payload: Record<string, unknown>, language: "en" | "nb"): GamePushCopy | null {
  const kind = payload.game_kind;
  return typeof kind === "string" && Object.hasOwn(GAME_PUSH_COPY, kind)
    ? (GAME_PUSH_COPY[kind as GameKind]?.[language] ?? null)
    : null;
}

/** The copy for the push's `payload.step`, or null when the push or the game has none. */
function gamePushStep(payload: Record<string, unknown>, language: "en" | "nb") {
  const steps = gamePushCopy(payload, language)?.steps;
  const step = payload.step;
  return steps && typeof step === "string" && Object.hasOwn(steps, step) ? steps[step] : null;
}

const GAME_PUSH_KINDS: readonly string[] = ["game_turn_ready", "game_result", "game_invite", "game_turn_reminder"];

const SENSITIVE_PAYLOAD_KEYS =
  /"(answer_body|note_body|message_body|body_text|voice_transcript|media_url|signed_url|latitude|longitude|coordinate|invite_code|report_detail|precise_location)"/i;

/** Port of `internal.notification_payload_is_safe`. */
export function notificationPayloadIsSafe(payload: unknown): boolean {
  return (
    isJsonObject(payload) &&
    jsonbByteLength(payload) <= 4096 &&
    !SENSITIVE_PAYLOAD_KEYS.test(jsonbText(payload))
  );
}

/** Port of `internal.notification_actor_display_name`. Returns null when there is no usable actor name. */
export async function notificationActorDisplayName(
  ctx: ReaderCtx,
  payload: Record<string, unknown>,
): Promise<string | null> {
  const candidates = [payload.actor_user_id, payload.sender_user_id].map((value) =>
    value === undefined || value === null ? "" : String(value).trim(),
  );
  const actorIdText = candidates.find((value) => value !== "");
  if (!actorIdText) {
    return null;
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(actorIdText)) {
    return null;
  }
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", actorIdText.toLowerCase()))
    .unique();
  const name = profile?.display_name?.trim();
  return name ? name : null;
}

const gameReminderBody = (nb: boolean) => (nb ? "Åpne Paeonia for å ta turen din." : "Open Paeonia to take your turn.");

/** Port of `internal.notification_alert_body`. Returns null for kinds without alert copy. */
export function notificationAlertBody(
  kind: string,
  payload: Record<string, unknown>,
  locale: string | null | undefined,
): string | null {
  const language = notificationLocaleLanguage(locale);
  const rawDaysLeft = payload.days_left === undefined || payload.days_left === null ? null : String(payload.days_left);
  const daysLeft = Math.max(rawDaysLeft !== null && /^[0-9]+$/.test(rawDaysLeft) ? Number(rawDaysLeft) : 2, 1);
  const nb = language === "nb";
  const step = GAME_PUSH_KINDS.includes(kind) ? gamePushStep(payload, language) : null;
  if (step) return step.body;
  switch (kind) {
    case "widget_updated":
      return nb ? "La til en ny tegning" : "Added a new drawing";
    case "partner_answered":
      return nb
        ? "Dere har svart på samme spørsmål. Åpne Paeonia for å se svaret."
        : "You both answered the same question. Open Paeonia to see what they said.";
    case "daily_challenge_completed":
      return nb
        ? "Åpne Paeonia for å svare og se hva partneren din skrev."
        : "Open Paeonia to answer and reveal what they wrote.";
    case "memory_created":
      return nb ? "Åpne Paeonia for å se det." : "Open Paeonia to see it.";
    case "thread_message_sent":
      return nb ? "Åpne Paeonia for å lese og svare." : "Open Paeonia to read it and reply.";
    case "game_turn_ready":
      return gamePushCopy(payload, language)?.turnReadyBody ?? gameReminderBody(nb);
    case "game_result":
      return gamePushCopy(payload, language)?.resultBody ?? gameReminderBody(nb);
    case "game_invite":
      return nb ? "Åpne Paeonia for å bli med." : "Open Paeonia to join in.";
    case "game_turn_reminder":
      return gameReminderBody(nb);
    case "streak_reminder":
      return nb
        ? "En rask tegning holder. Rekken fortsetter når dere begge har sjekket inn."
        : "A quick drawing is enough. Your streak continues once you've both checked in.";
    case "subscription_trial_reminder":
      return nb
        ? `${daysLeft}${daysLeft === 1 ? " dag igjen. " : " dager igjen. "}Se over abonnementet ditt i App Store.`
        : `${daysLeft}${daysLeft === 1 ? " day left. " : " days left. "}Review your subscription in the App Store.`;
    default:
      return null;
  }
}

/** Port of `internal.notification_alert_title`. */
export async function notificationAlertTitle(
  ctx: ReaderCtx,
  kind: string,
  payload: Record<string, unknown>,
  locale: string | null | undefined,
): Promise<string> {
  const nb = notificationLocaleLanguage(locale) === "nb";
  const name = (await notificationActorDisplayName(ctx, payload)) ?? (nb ? "Partneren din" : "Your partner");
  const step = GAME_PUSH_KINDS.includes(kind) ? gamePushStep(payload, nb ? "nb" : "en") : null;
  if (step) return step.title(name);
  switch (kind) {
    case "widget_updated":
      return name;
    case "partner_answered":
      return nb ? `${name} svarte også` : `${name} answered too`;
    case "daily_challenge_completed":
      return nb ? `${name} fullførte dagens spørsmål` : `${name} finished today's questions`;
    case "memory_created":
      return nb ? `${name} la til et nytt minne` : `${name} added a new memory`;
    case "thread_message_sent":
      return nb ? `${name} sendte deg en melding` : `${name} sent you a message`;
    case "game_turn_ready":
    case "game_turn_reminder": {
      const game = gamePushCopy(payload, nb ? "nb" : "en");
      if (!game) return "Paeonia";
      return nb ? `Din tur i ${game.name}` : `Your turn in ${game.name}`;
    }
    case "game_result":
      return gamePushCopy(payload, nb ? "nb" : "en")?.resultTitle?.(name) ?? "Paeonia";
    case "game_invite": {
      const game = gamePushCopy(payload, nb ? "nb" : "en");
      if (!game) return "Paeonia";
      return nb ? `${name} vil spille ${game.name} med deg` : `${name} wants to play ${game.name} with you`;
    }
    case "streak_reminder":
      return nb ? "Tid for å sjekke inn" : "Time for a quick check-in";
    case "subscription_trial_reminder":
      return nb ? "Prøveperioden avsluttes snart" : "Your free trial ends soon";
    default:
      return "Paeonia";
  }
}

/** Port of `internal.widget_updated_notification_body`. */
export function widgetUpdatedNotificationBody(locale: string | null | undefined): string {
  return notificationAlertBody("widget_updated", {}, locale) as string;
}

