import type { ReaderCtx } from "./db";
import type { GameKind } from "./games";
import { isJsonObject, jsonbByteLength, jsonbText } from "./json";
import { nameForViewer } from "./partnerNames";

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
      turnReadyBody: "Guess what they drew.",
      resultTitle: (actor) => `${actor} guessed your drawing`,
      resultBody: "See how it went.",
    },
    nb: {
      name: "Tegn og gjett",
      turnReadyBody: "Gjett hva som er tegnet.",
      resultTitle: (actor) => `${actor} gjettet tegningen din`,
      resultBody: "Se hvordan det gikk.",
    },
  },
  mind_meld: {
    en: {
      name: "Mind Meld",
      turnReadyBody: "Pick your word.",
      resultTitle: () => "Your words are in",
      resultBody: "See what you both said.",
    },
    nb: {
      name: "Tenk likt",
      turnReadyBody: "Velg ordet ditt.",
      resultTitle: () => "Ordene deres er klare",
      resultBody: "Se hva dere begge sa.",
    },
  },
  story_chain: {
    en: {
      name: "Story Chain",
      turnReadyBody: "Read the newest line and add yours.",
      resultTitle: (actor) => `${actor} named your story`,
      resultBody: "Read the whole story.",
      steps: {
        last_line: { title: (actor) => `${actor} wrote the last line`, body: "Give your story a title." },
      },
    },
    nb: {
      name: "Skrivestafett",
      turnReadyBody: "Les den nyeste linjen og skriv din.",
      resultTitle: (actor) => `${actor} ga historien deres en tittel`,
      resultBody: "Les hele historien.",
      steps: {
        last_line: { title: (actor) => `${actor} skrev den siste linjen`, body: "Gi historien en tittel." },
      },
    },
  },
  exquisite_corpse: {
    en: {
      name: "Odd Creatures",
      resultTitle: (actor) => `${actor} finished your creature`,
      resultBody: "See the whole creature.",
      steps: {
        body: { title: (actor) => `${actor} drew the head`, body: "Your turn to draw the body." },
        legs: { title: (actor) => `${actor} drew the body`, body: "Your turn to draw the legs." },
      },
    },
    nb: {
      name: "Rare skapninger",
      resultTitle: (actor) => `${actor} gjorde ferdig skapningen deres`,
      resultBody: "Se hele skapningen.",
      steps: {
        body: { title: (actor) => `${actor} har tegnet hodet`, body: "Din tur til å tegne kroppen." },
        legs: { title: (actor) => `${actor} har tegnet kroppen`, body: "Din tur til å tegne beina." },
      },
    },
  },
  connect_four: {
    en: {
      name: "Connect Four",
      turnReadyBody: "Make your move.",
      resultTitle: (actor) => `${actor} finished your game of Connect Four`,
      resultBody: "See how it ended.",
    },
    nb: {
      name: "Fire på rad",
      turnReadyBody: "Gjør trekket ditt.",
      resultTitle: (actor) => `${actor} avsluttet spillet deres i Fire på rad`,
      resultBody: "Se hvordan det endte.",
    },
  },
  dots_and_boxes: {
    en: {
      name: "Dots and Boxes",
      turnReadyBody: "Make your move.",
      resultTitle: (actor) => `${actor} finished your game of Dots and Boxes`,
      resultBody: "See how it ended.",
    },
    nb: {
      name: "Prikker og streker",
      turnReadyBody: "Gjør trekket ditt.",
      resultTitle: (actor) => `${actor} avsluttet spillet deres i Prikker og streker`,
      resultBody: "Se hvordan det endte.",
    },
  },
  ultimate_tic_tac_toe: {
    en: {
      name: "Ultimate Tic-Tac-Toe",
      turnReadyBody: "Make your move.",
      resultTitle: (actor) => `${actor} finished your game of Ultimate Tic-Tac-Toe`,
      resultBody: "See how it ended.",
    },
    nb: {
      name: "Ultimat bondesjakk",
      turnReadyBody: "Gjør trekket ditt.",
      resultTitle: (actor) => `${actor} avsluttet spillet deres i Ultimat bondesjakk`,
      resultBody: "Se hvordan det endte.",
    },
  },
  ludo: {
    en: {
      name: "Ludo",
      turnReadyBody: "Make your move.",
      resultTitle: (actor) => `${actor} finished your game of Ludo`,
      resultBody: "See how it ended.",
    },
    nb: {
      name: "Ludo",
      turnReadyBody: "Gjør trekket ditt.",
      resultTitle: (actor) => `${actor} avsluttet spillet deres i Ludo`,
      resultBody: "Se hvordan det endte.",
    },
  },
  consensio: {
    en: {
      name: "Consensio",
      turnReadyBody: "Make your guess.",
      resultTitle: (actor) => `${actor} made a guess`,
      resultBody: "See how close they got.",
      steps: {
        guessed: { title: (actor) => `${actor} guessed and left you one to guess`, body: "See how close they got." },
      },
    },
    nb: {
      name: "Consensio",
      turnReadyBody: "Gjør gjetningen din.",
      resultTitle: (actor) => `${actor} har gjettet`,
      resultBody: "Se hvor nær gjetningen var.",
      steps: {
        guessed: { title: (actor) => `${actor} har gjettet og lagt igjen en til deg`, body: "Se hvor nær gjetningen var." },
      },
    },
  },
  guess_my_spot: {
    en: {
      name: "Guess my spot",
      turnReadyBody: "Guess where the photo was taken.",
      resultTitle: (actor) => `${actor} made a guess`,
      resultBody: "See how close they got.",
      steps: {
        guessed: { title: (actor) => `${actor} guessed and sent you a photo`, body: "See how close they got." },
      },
    },
    nb: {
      name: "Gjett hvor",
      turnReadyBody: "Gjett hvor bildet er tatt.",
      resultTitle: (actor) => `${actor} har gjettet`,
      resultBody: "Se hvor nær gjetningen var.",
      steps: {
        guessed: { title: (actor) => `${actor} har gjettet og sendt deg et bilde`, body: "Se hvor nær gjetningen var." },
      },
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
  /"(answer_body|note_body|message_body|body_text|voice_transcript|media_url|signed_url|latitude|longitude|coordinate|place|invite_code|report_detail|precise_location)"/i;

/** Port of `internal.notification_payload_is_safe`. */
export function notificationPayloadIsSafe(payload: unknown): boolean {
  return (
    isJsonObject(payload) &&
    jsonbByteLength(payload) <= 4096 &&
    !SENSITIVE_PAYLOAD_KEYS.test(jsonbText(payload))
  );
}

/**
 * Port of `internal.notification_actor_display_name`. What `viewerUserId`, who receives the push,
 * calls the person who caused it: their nickname for the partner when they set one, otherwise the
 * partner's own name. Returns null when the payload names nobody or the name is unusable.
 */
export async function notificationActorDisplayName(
  ctx: ReaderCtx,
  viewerUserId: string,
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
  return await nameForViewer(ctx, viewerUserId, actorIdText.toLowerCase());
}

/** What a reaction was on, as the second line of its push: "to your story". Names no content. */
const REACTION_PUSH_TARGET: Record<string, Record<"en" | "nb", string>> = {
  story: { en: "to your story", nb: "på storyen din" },
  memory: { en: "to your memory", nb: "på minnet ditt" },
  widget_drawing: { en: "to your drawing", nb: "på tegningen din" },
  draw_and_guess_round: { en: "to your round of Draw & Guess", nb: "på runden deres i Tegn og gjett" },
  exquisite_corpse_figure: { en: "to your creature", nb: "på skapningen deres" },
  story_chain_story: { en: "to your story in Story Chain", nb: "på historien deres i Skrivestafett" },
};

const gameReminderBody = (nb: boolean) => (nb ? "Fortsett der dere slapp." : "Pick up where you left off.");

/**
 * Which of `count` wordings a daily reminder uses. `seed` is a time that moves one day per day (the
 * end of the local day, or the streak deadline), so the wording changes from one day to the next, and
 * the title, the body and every retry of one reminder agree.
 */
function dailyVariant(seed: unknown, count: number): number {
  const ms = typeof seed === "string" ? Date.parse(seed) : Number.NaN;
  return Number.isNaN(ms) ? 0 : Math.floor(ms / 86_400_000) % count;
}

/** A whole number in the reader's language, with its thousands separator (1,000 or 1 000). */
const formatCount = (value: number, nb: boolean) => value.toLocaleString(nb ? "nb-NO" : "en-US");

/** The `reminder` a date push names (`dateReminders.ts`), or null for a value this file has no copy for. */
function dateReminderKind(payload: Record<string, unknown>) {
  const reminder = payload.reminder;
  return reminder === "partner_birthday_soon" ||
    reminder === "partner_birthday_today" ||
    reminder === "own_birthday" ||
    reminder === "anniversary_soon" ||
    reminder === "milestone" ||
    reminder === "countdown"
    ? reminder
    : null;
}

/** A positive whole number from the payload, or 1 when it is missing. */
const payloadCount = (value: unknown) => (typeof value === "number" && Number.isInteger(value) && value > 0 ? value : 1);

const QUESTION_TIME_VARIANTS = 3;
const STREAK_VARIANTS = 3;

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
      return nb ? "Tegnet noe til deg" : "Drew something for you";
    case "partner_answered":
      // `question_count` is how many of the recipient's questions the partner answered in this push.
      if (typeof payload.question_count === "number" && payload.question_count > 1) {
        return nb ? "Nå kan du se svarene." : "Their answers are ready to see.";
      }
      return nb ? "Nå kan du se svaret." : "Their answer is ready to see.";
    case "daily_challenge_completed":
      // `to_answer`: the partner's questions still wait for the recipient's answer. `to_see`: the
      // partner answered the recipient's questions too. Set at send time (lib/dailyPartnerPush.ts).
      if (payload.to_answer === false) {
        return nb ? "Nå kan du se svarene." : "Their answers are ready to see.";
      }
      if (payload.to_see === true) {
        return nb
          ? "Se svarene, og svar så på spørsmålene som venter."
          : "See their answers, then answer their questions.";
      }
      return nb ? "Svar selv, så ser du svarene." : "Answer their questions to see what they wrote.";
    case "memory_created":
      return nb ? "Se det blant minnene deres." : "See it in your memories.";
    case "story_posted":
      return nb ? "Den ligger på Hjem i 24 timer." : "It's on Home for 24 hours.";
    case "thread_message_sent":
      // Every chat push has the same shape and never names the topic, so a Flirt chat looks like any other.
      return nb ? "Sendte deg en melding" : "Sent you a message";
    case "topics_waiting":
      return nb ? "Se hva som venter i Temaer." : "See what's waiting in Topics.";
    case "reaction_added": {
      const target = typeof payload.target_kind === "string" ? REACTION_PUSH_TARGET[payload.target_kind] : undefined;
      return target?.[language] ?? (nb ? "Se hva det gjelder." : "See what it was on.");
    }
    case "game_turn_ready":
      return gamePushCopy(payload, language)?.turnReadyBody ?? gameReminderBody(nb);
    case "game_result":
      return gamePushCopy(payload, language)?.resultBody ?? gameReminderBody(nb);
    case "game_invite":
      return nb ? "Bli med når du er klar." : "Join in when you're ready.";
    case "game_turn_reminder":
      return gameReminderBody(nb);
    case "data_export_ready":
      return nb ? "Kopien din er klar til nedlasting." : "Your copy is ready to download.";
    case "partner_joined":
      return nb ? "Se deres første dag sammen." : "See your first day together.";
    case "pairing_invite_reminder":
      return nb ? "Kanskje lenken ble borte. Send den til partneren din igjen." : "Maybe the link got lost. Send it to your partner again.";
    case "date_reminder":
      switch (dateReminderKind(payload)) {
        case "partner_birthday_soon":
          return nb ? "Nå er det tid til å planlegge noe fint." : "Time to plan something nice.";
        case "partner_birthday_today":
          return nb ? "Send en hilsen, så starter dagen fint." : "Send a message to start their day well.";
        case "own_birthday":
          return nb ? "Håper du får en fin dag." : "Hope you have a lovely day.";
        case "anniversary_soon":
          return nb ? "Tid til å planlegge noe sammen." : "Time to plan something together.";
        case "milestone":
          return nb ? "Ta en stund til å feire." : "Take a moment to celebrate.";
        case "countdown":
          return payloadCount(payload.count) > 1
            ? nb
              ? `${formatCount(payloadCount(payload.count), nb)} datoer dere har talt ned til er her.`
              : `${formatCount(payloadCount(payload.count), nb)} dates you've been counting down to are here.`
            : nb
              ? "En dato dere har talt ned til er her."
              : "A date you've been counting down to is here.";
        default:
          return null;
      }
    case "question_time_reminder":
      switch (dailyVariant(payload.expires_at, QUESTION_TIME_VARIANTS)) {
        case 1:
          return nb ? "Svar på dine, så ser du hva partneren din sa." : "Answer yours, then see what your partner said.";
        case 2:
          return nb ? "Svar når du har noen minutter." : "Answer when you have a few minutes.";
        default:
          return nb ? "To spørsmål venter. Det tar bare noen minutter." : "Two questions are waiting. They take a few minutes.";
      }
    case "streak_reminder":
      // `partner_checked_in`: the partner already did their part today (streaks.ts).
      if (payload.partner_checked_in === true) {
        return nb ? "Noe lite fra deg holder rekken i gang." : "Anything small from you keeps your streak going.";
      }
      switch (dailyVariant(payload.next_activity_deadline_at, STREAK_VARIANTS)) {
        case 1:
          return nb
            ? "Litt fra hver av dere holder rekken i gang."
            : "One small thing from each of you keeps your streak going.";
        case 2:
          return nb
            ? "En melding, en tegning eller et svar teller som innsjekk."
            : "A message, a drawing or an answer all count as a check-in.";
        default:
          return nb ? "Noe lite holder, som en melding eller en tegning." : "Anything small counts, like a message or a drawing.";
      }
    case "subscription_trial_reminder":
      return nb
        ? `${daysLeft}${daysLeft === 1 ? " dag igjen. " : " dager igjen. "}Se over abonnementet ditt i App Store.`
        : `${daysLeft}${daysLeft === 1 ? " day left. " : " days left. "}Review your subscription in the App Store.`;
    default:
      return null;
  }
}

/**
 * Port of `internal.notification_alert_title`. `recipientUserId` is who receives the push, so a name
 * in the title is what that person calls the partner (see `nameForViewer`).
 */
export async function notificationAlertTitle(
  ctx: ReaderCtx,
  recipientUserId: string,
  kind: string,
  payload: Record<string, unknown>,
  locale: string | null | undefined,
): Promise<string> {
  const nb = notificationLocaleLanguage(locale) === "nb";
  const actorName = await notificationActorDisplayName(ctx, recipientUserId, payload);
  // `name` starts a title. `inSentence` goes later in one, so a missing name reads "your partner".
  const name = actorName ?? (nb ? "Partneren din" : "Your partner");
  const inSentence = actorName ?? (nb ? "partneren din" : "your partner");
  // For a push whose game or kind has no copy. iOS already shows the app name, so the title never repeats it.
  const fallback = nb ? `Noe nytt fra ${inSentence}` : `Something new from ${inSentence}`;
  const step = GAME_PUSH_KINDS.includes(kind) ? gamePushStep(payload, nb ? "nb" : "en") : null;
  if (step) return step.title(name);
  switch (kind) {
    case "partner_answered":
      return nb ? `${name} svarte også` : `${name} answered too`;
    case "daily_challenge_completed":
      return nb ? `${name} fullførte dagens spørsmål` : `${name} finished today's questions`;
    case "memory_created":
      return nb ? `${name} la til et minne` : `${name} added a memory`;
    case "story_posted":
      return nb ? `${name} delte en story` : `${name} shared a story`;
    case "widget_updated":
    case "thread_message_sent":
      // The notification service extension shows these as messages from the sender.
      return name;
    case "topics_waiting":
      return nb ? `Nye svar fra ${name}` : `New answers from ${name}`;
    case "reaction_added": {
      const emoji = typeof payload.emoji === "string" ? ` ${payload.emoji}` : "";
      return nb ? `${name} reagerte${emoji}` : `${name} reacted${emoji}`;
    }
    case "game_turn_ready":
    case "game_turn_reminder": {
      const game = gamePushCopy(payload, nb ? "nb" : "en");
      if (!game) return fallback;
      return nb ? `Din tur i ${game.name}` : `Your turn in ${game.name}`;
    }
    case "game_result":
      return gamePushCopy(payload, nb ? "nb" : "en")?.resultTitle?.(name) ?? fallback;
    case "game_invite": {
      const game = gamePushCopy(payload, nb ? "nb" : "en");
      if (!game) return fallback;
      return nb ? `${name} vil spille ${game.name} med deg` : `${name} wants to play ${game.name} with you`;
    }
    case "data_export_ready":
      // Paeonia's own voice: the payload names nobody.
      return nb ? "Dataene dine er klare" : "Your data is ready";
    case "partner_joined":
      return nb ? `${name} ble med deg` : `${name} joined you`;
    case "pairing_invite_reminder":
      // Paeonia's own voice. Nobody has joined, so there is no partner to name.
      return nb ? "Invitasjonen din venter fortsatt" : "Your invite is still waiting";
    case "date_reminder":
      return dateReminderTitle(payload, nb, name);
    case "question_time_reminder":
      // Paeonia's own voice: the payload names nobody, so no wording sounds like the partner sent it.
      switch (dailyVariant(payload.expires_at, QUESTION_TIME_VARIANTS)) {
        case 1:
          return nb ? "Spørsmålstid" : "Question time";
        case 2:
          return nb ? "De to spørsmålene dine er her" : "Your two questions are here";
        default:
          return nb ? "Dagens spørsmål er klare" : "Today's questions are ready";
      }
    case "streak_reminder":
      // `actor_user_id` is the partner here (streaks.ts).
      if (payload.partner_checked_in === true) {
        return nb ? `${name} har sjekket inn i dag` : `${name} checked in today`;
      }
      switch (dailyVariant(payload.next_activity_deadline_at, STREAK_VARIANTS)) {
        case 1:
          return nb ? `Sjekk inn med ${inSentence} i dag` : `Check in with ${inSentence} today`;
        case 2:
          return nb ? `Si hei til ${inSentence}` : `Say hi to ${inSentence}`;
        default:
          return nb ? "Tid for å sjekke inn" : "Time for a quick check-in";
      }
    case "subscription_trial_reminder":
      return nb ? "Prøveperioden avsluttes snart" : "Your free trial ends soon";
    default:
      return fallback;
  }
}

/**
 * The title of a date push. These never name a countdown, because the words on a lock screen
 * belong to the couple. `name` is the partner the push is about, taken from `actor_user_id`.
 */
function dateReminderTitle(payload: Record<string, unknown>, nb: boolean, name: string): string {
  switch (dateReminderKind(payload)) {
    case "partner_birthday_soon":
      return nb ? `${name} har bursdag om en uke` : `${name} has a birthday in a week`;
    case "partner_birthday_today":
      return nb ? `${name} har bursdag i dag` : `${name} has a birthday today`;
    case "own_birthday":
      return nb ? "Gratulerer med dagen!" : "Happy birthday!";
    case "anniversary_soon":
      return nb ? "Dere har jubileum om en uke" : "Your anniversary is in a week";
    case "milestone":
      return milestoneTitle(payload, nb);
    case "countdown":
      return nb ? "I dag er dagen" : "Today's the day";
    default:
      return nb ? "Noe å glede seg til" : "Something to look forward to";
  }
}

function milestoneTitle(payload: Record<string, unknown>, nb: boolean): string {
  const years = payloadCount(payload.years);
  const days = payloadCount(payload.days);
  switch (payload.milestone) {
    case "first_month":
      return nb ? "Én måned sammen i dag" : "One month together today";
    case "half_year":
      return nb ? "Et halvt år sammen i dag" : "Half a year together today";
    case "years":
      if (years === 1) return nb ? "Ett år sammen i dag" : "One year together today";
      return nb ? `${formatCount(years, nb)} år sammen i dag` : `${formatCount(years, nb)} years together today`;
    default:
      return nb ? `${formatCount(days, nb)} dager sammen i dag` : `${formatCount(days, nb)} days together today`;
  }
}

/** Port of `internal.widget_updated_notification_body`. */
export function widgetUpdatedNotificationBody(locale: string | null | undefined): string {
  return notificationAlertBody("widget_updated", {}, locale) as string;
}

