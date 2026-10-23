import type { Doc, TableNames } from "../_generated/dataModel";

// The one list of what "Download my data" contains. Every table in schema.ts has an entry here, and
// the type below makes `tsc` fail for a table without one. `dataExport.test.ts` also checks each
// entry against the schema. A new table is either exported, with the field that ties its rows to a
// person or couple, or excluded with a reason.
//
// What is in the export (the scope rule, also written in docs/privacy-and-data-export.md):
// - Yours. Everything you wrote, uploaded, chose or set, and your files. Always included.
// - Shared. Things you and your partner hold as one object (the relationship, memories, countdowns,
//   chat threads, streaks, game boards and results). Included while you are in the relationship.
// - Your partner's. What your partner wrote or uploaded, their files, location, settings, devices and
//   private marks. Never included. Where a shared row mixes the two, `select` keeps your part.

/** How long a finished download stays on our servers. */
export const EXPORT_VALID_DAYS = 3;

type Text = { en: string; nb: string };
type Row = Record<string, unknown>;

export type ExportGroup =
  | "account"
  | "settings"
  | "subscription"
  | "relationship"
  | "daily"
  | "chat"
  | "memories"
  | "stories"
  | "drawings"
  | "games"
  | "location"
  | "activity"
  | "safety"
  | "files";

/** The folder of each group in the archive. The README names them in this order. */
export const EXPORT_GROUPS: Record<ExportGroup, { folder: string }> = {
  account: { folder: "account" },
  settings: { folder: "settings" },
  subscription: { folder: "subscription" },
  relationship: { folder: "relationship" },
  daily: { folder: "daily-questions" },
  chat: { folder: "chat" },
  memories: { folder: "memories" },
  stories: { folder: "stories-and-notes" },
  drawings: { folder: "drawings" },
  games: { folder: "games" },
  location: { folder: "location" },
  activity: { folder: "activity" },
  safety: { folder: "privacy-and-safety" },
  files: { folder: "files" },
};

type Shape = {
  /** Fields left out of the file: secrets, and ids that only mean something inside the database. */
  hide?: readonly string[];
  /** Keeps or reshapes a row. Return null to leave it out. `me` is the person who exports. */
  select?: (row: Row, me: string) => Row | null;
};

type Described = Shape & { group: ExportGroup; about: Text };

/** Rows whose `field` is the person: `field` is the first field of `index`. */
type OwnExport = Described & { kind: "own"; field: string; index: string };

/**
 * Rows of the person's couples, read through an index that starts with `couple_id`. With `author`,
 * only rows where that field is the person are kept, in every couple the person was in. Without it
 * the rows are shared, and only the person's current relationship counts.
 */
type CoupleExport = Described & {
  kind: "couple";
  index: string;
  author?: string;
  /**
   * Also exports the rows that the person's own rows of `table` point to through `field`, even when
   * `author` does not match them. `index` on `table` starts with `field`, then `user_id`. Use it where
   * the person writes onto a row the partner created, so an answer is never exported without its question.
   */
  referencedBy?: { table: TableNames; field: string; index: string };
};

/**
 * Rows reached through a row of an exported `parent` table: `field` equals the parent's `parentKey`.
 * Use it only where a parent has a handful of children, since the export reads them with one query.
 */
type ChildExport = Described & {
  kind: "child";
  parent: TableNames;
  parentKey: string;
  field: string;
  index: string;
};

type ExcludedExport = { kind: "excluded"; reason: string };

export type TableExport = OwnExport | CoupleExport | ChildExport | ExcludedExport;
export type ExportedTable = Exclude<TableExport, ExcludedExport>;

const own = (field: string, index: string, spec: Described): OwnExport => ({ kind: "own", field, index, ...spec });
const shared = (index: string, spec: Described): CoupleExport => ({ kind: "couple", index, ...spec });
const yours = (index: string, author: string, spec: Described): CoupleExport => ({
  kind: "couple",
  index,
  author,
  ...spec,
});
const child = (
  parent: TableNames,
  parentKey: string,
  field: string,
  index: string,
  spec: Described,
): ChildExport => ({ kind: "child", parent, parentKey, field, index, ...spec });
const excluded = (reason: string): ExcludedExport => ({ kind: "excluded", reason });

const isRecord = (value: unknown): value is Row => typeof value === "object" && value !== null && !Array.isArray(value);

/** Drops the fields of `row` that name `keys`, for rows that cannot be shared with the other partner. */
function without(row: Row, keys: readonly string[]): Row {
  const copy = { ...row };
  for (const key of keys) delete copy[key];
  return copy;
}

/** A Draw & Guess round shows its word to the guesser only once the round is over. */
function drawAndGuessRound(row: Row, me: string): Row {
  const over = row.state === "solved" || row.state === "missed";
  return row.drawer_user_id === me || over ? row : without(row, ["word", "word_id"]);
}

/** Consensio: the guesser never sees the spot before guessing. */
function consensioRound(row: Row, me: string): Row {
  const hidden = row.placer_user_id !== me && row.guess === undefined;
  return hidden ? without(row, ["spot", "distance", "points"]) : row;
}

/** Consensio: only the person whose turn it is reads the three topic choices. */
function consensioGame(row: Row, me: string): Row {
  return row.turn_user_id === me ? row : without(row, ["choices"]);
}

/** Guess my spot: the photo, place and date belong to the person who sent the round. */
function guessMySpotRound(row: Row, me: string): Row {
  if (row.sender_user_id === me) return row;
  return without(row, [
    "photo_media_asset_id",
    "photo_width",
    "photo_height",
    "spot_latitude",
    "spot_longitude",
    "place_name",
    "place_city",
    "place_country_code",
    "taken_on",
  ]);
}

/** Story Chain: your own lines stay in full. A partner's line keeps only its number and time. */
function storyChainStory(row: Row, me: string): Row {
  const lines = Array.isArray(row.lines) ? row.lines : [];
  return {
    ...row,
    lines: lines.map((line) => {
      if (!isRecord(line) || line.author_user_id === me) return line;
      return { id: line.id, number: line.number, author_user_id: line.author_user_id, created_at: line.created_at, text_included: false };
    }),
  };
}

/** Board games: the hidden photo of a Dots and Boxes game is not part of the result. */
function boardGame(row: Row): Row {
  const copy = without(row, ["photo_media_asset_id"]);
  if (isRecord(copy.previous)) copy.previous = without(copy.previous, ["photo_media_asset_id"]);
  return copy;
}

const BOARD_GAME_SHARED_ABOUT: Text = {
  en: "Your Connect Four, Dots and Boxes, Ultimate Tic-Tac-Toe and Ludo games with your partner: the current game, the score and the last finished game.",
  nb: "Spillene dere har spilt sammen, som Fire på rad, Prikker og streker, Ultimat bondesjakk og Ludo: spillet som pågår, stillingen og siste ferdige spill.",
};

/** Every table, in the schema's own words. Order does not matter. */
export const TABLE_EXPORTS: { [T in TableNames]: TableExport } = {
  // ---- account ----
  users: own("id", "by_uuid", {
    group: "account",
    about: {
      en: "Your account: which sign-in you use (Apple or Google), your email address if they shared it, and when you joined.",
      nb: "Kontoen din: hvilken innlogging du bruker (Apple eller Google), e-postadressen din hvis de delte den, og når du ble med.",
    },
    hide: ["banned_by_user_id"],
  }),
  profiles: own("user_id", "by_user_id", {
    group: "account",
    about: {
      en: "Your profile: name, profile photo, time zone, when you finished setup, and your answer about sharing usage statistics.",
      nb: "Profilen din: navn, profilbilde, tidssone, når du var ferdig med oppsettet, og svaret ditt om å dele bruksstatistikk.",
    },
  }),
  app_account_tokens: own("user_id", "by_user_id", {
    group: "account",
    about: {
      en: "A random code that ties your App Store purchases to your Paeonia account.",
      nb: "En tilfeldig kode som kobler App Store-kjøpene dine til Paeonia-kontoen din.",
    },
  }),
  admin_audit_log: own("target_user_id", "by_target_user_id_created_at", {
    group: "account",
    about: {
      en: "Times your account was blocked or unblocked by our team.",
      nb: "Ganger kontoen din ble sperret eller åpnet igjen av teamet vårt.",
    },
    hide: ["admin_user_id", "operator_identifier"],
  }),
  first_day_drafts: own("user_id", "by_user_id", {
    group: "account",
    about: {
      en: "What you prepared for your first day together before your partner joined.",
      nb: "Det du gjorde klart til første dag sammen, før partneren din ble med.",
    },
  }),

  // ---- phones and settings ----
  user_devices: own("user_id", "by_user_id_disabled_at", {
    group: "settings",
    about: {
      en: "The phones you use Paeonia on: model type, language, time zone, app version and when each was last used. The secret notification codes are left out.",
      nb: "Telefonene du bruker Paeonia på: type, språk, tidssone, appversjon og når hver sist ble brukt. De hemmelige varslingskodene er utelatt.",
    },
    hide: ["push_token", "push_token_hash"],
  }),
  widget_push_devices: own("user_id", "by_user_id_disabled_at", {
    group: "settings",
    about: {
      en: "The widgets on your Home Screen that Paeonia can refresh. The secret codes are left out.",
      nb: "Widgetene på Hjem-skjermen som Paeonia kan oppdatere. De hemmelige kodene er utelatt.",
    },
    hide: ["widget_push_token", "widget_push_token_hash"],
  }),
  notification_preferences: own("user_id", "by_user_id", {
    group: "settings",
    about: {
      en: "Which notifications you turned on, and when your question reminder goes off.",
      nb: "Hvilke varsler du har slått på, og når påminnelsen om spørsmål kommer.",
    },
  }),
  notification_outbox: own("recipient_user_id", "by_recipient_user_id_created_at", {
    group: "settings",
    about: {
      en: "Notifications we sent you in the last 30 days.",
      nb: "Varsler vi har sendt deg de siste 30 dagene.",
    },
    hide: ["push_token_hash"],
  }),

  // ---- subscription ----
  storekit_transactions: own("user_id", "by_user_id_status_expires_at", {
    group: "subscription",
    about: {
      en: "Your App Store purchases and subscription periods. Apple keeps your payment details, not us.",
      nb: "App Store-kjøpene og abonnementsperiodene dine. Apple har betalingsopplysningene dine, ikke vi.",
    },
  }),
  entitlement_grants: own("user_id", "by_user_id_status_expires_at", {
    group: "subscription",
    about: {
      en: "Access to Paeonia that you got without paying, for example a gift or a test.",
      nb: "Tilgang til Paeonia som du fikk uten å betale, for eksempel en gave eller en test.",
    },
  }),
  streak_restorations: own("purchaser_user_id", "by_purchaser_user_id_restored_at", {
    group: "subscription",
    about: {
      en: "Times you bought back a lost streak.",
      nb: "Ganger du kjøpte tilbake en rekke som var brutt.",
    },
  }),
  review_access_sessions: own("user_id", "by_user_id_redeemed_at", {
    group: "subscription",
    about: {
      en: "Use of an App Review access code. Only App Store reviewers have these.",
      nb: "Bruk av en tilgangskode for App Review. Bare de som vurderer appen for App Store har dem.",
    },
  }),

  // ---- relationship ----
  couple_members: own("user_id", "by_user_id_status_couple_id", {
    group: "relationship",
    about: {
      en: "Each relationship you have been part of in Paeonia: when you joined, when you left, your birthday if it was added, and the nickname you gave your partner. Only you can see that nickname, and it is only in your download.",
      nb: "Hvert forhold du har vært med i på Paeonia: når du ble med, når du forlot det, bursdagen din hvis den er lagt til, og kallenavnet du ga partneren din. Bare du ser kallenavnet, og det er bare med i din nedlasting.",
    },
  }),
  couples: child("couple_members", "couple_id", "id", "by_uuid", {
    group: "relationship",
    about: {
      en: "Your relationships: the start date, whether it is still active, and when it ended.",
      nb: "Forholdene dine: startdato, om forholdet fortsatt er aktivt, og når det tok slutt.",
    },
  }),
  relationship_pairs: child("couples", "pair_id", "id", "by_uuid", {
    group: "relationship",
    about: {
      en: "The two accounts behind each relationship you have had.",
      nb: "De to kontoene bak hvert forhold du har hatt.",
    },
  }),
  pairing_invites: own("created_by_user_id", "by_created_by_user_id_status_expires_at", {
    group: "relationship",
    about: {
      en: "Invites you made to connect with a partner.",
      nb: "Invitasjoner du har laget for å koble deg til en partner.",
    },
  }),
  relationship_blocks: child("relationship_pairs", "id", "pair_id", "by_pair_id_revoked_at", {
    group: "relationship",
    about: {
      en: "Blocks you set on a partner.",
      nb: "Blokkeringer du har satt på en partner.",
    },
    select: (row, me) => (row.blocked_by_user_id === me ? row : null),
  }),
  relationship_sync_events: own("user_id", "by_user_id_created_at_id", {
    group: "relationship",
    about: {
      en: "A log of changes to your relationship, such as it starting or ending.",
      nb: "En logg over endringer i forholdet ditt, som at det startet eller tok slutt.",
    },
  }),
  countdowns: shared("by_couple_id_deleted_at", {
    group: "relationship",
    about: {
      en: "The countdowns you and your partner made together.",
      nb: "Nedtellingene du og partneren din har laget sammen.",
    },
  }),
  streak_states: shared("by_couple_id", {
    group: "relationship",
    about: {
      en: "Your streak: how many days in a row, and your longest.",
      nb: "Rekken deres: hvor mange dager på rad, og den lengste.",
    },
  }),
  couple_hearts: yours("by_couple_id_sender_user_id", "sender_user_id", {
    group: "relationship",
    about: {
      en: "How many hearts you have sent your partner and how many you have seen.",
      nb: "Hvor mange hjerter du har sendt partneren din, og hvor mange du har sett.",
    },
  }),
  couple_days: shared("by_couple_id_local_date", {
    group: "relationship",
    about: {
      en: "The days you used Paeonia as a couple. Other files point to these days.",
      nb: "Dagene dere har brukt Paeonia som par. Andre filer peker til disse dagene.",
    },
  }),

  // ---- daily questions ----
  daily_question_answers: own("user_id", "by_user_id_created_at", {
    group: "daily",
    about: {
      en: "Your answers to the daily questions. The text, choices and photos are in the files next to this one.",
      nb: "Svarene dine på dagens spørsmål. Teksten, valgene og bildene ligger i filene ved siden av.",
    },
  }),
  daily_answer_text: child("daily_question_answers", "id", "answer_id", "by_answer_id", {
    group: "daily",
    about: { en: "The text of your answers.", nb: "Teksten i svarene dine." },
  }),
  daily_answer_option_choice: child("daily_question_answers", "id", "answer_id", "by_answer_id", {
    group: "daily",
    about: { en: "The option you picked in either-or questions.", nb: "Valget du tok i enten-eller-spørsmål." },
  }),
  daily_answer_partner_choice: child("daily_question_answers", "id", "answer_id", "by_answer_id", {
    group: "daily",
    about: {
      en: "Who you picked in questions that ask you to choose between the two of you.",
      nb: "Hvem du valgte i spørsmål der du velger mellom dere to.",
    },
  }),
  daily_answer_media: child("daily_question_answers", "id", "answer_id", "by_answer_id_media_asset_id", {
    group: "daily",
    about: {
      en: "Which photos and voice messages belong to your answers. The files are in the files folder.",
      nb: "Hvilke bilder og talemeldinger som hører til svarene dine. Filene ligger i mappen files.",
    },
  }),
  daily_question_instances: {
    ...yours("by_couple_id_question_id", "seeded_for_user_id", {
      group: "daily",
      about: {
        en: "The questions you were given or answered, and on which day.",
        nb: "Spørsmålene du fikk eller svarte på, og hvilken dag.",
      },
    }),
    // A person can answer a question that was given to the partner, in the daily and topic flows.
    referencedBy: { table: "daily_question_answers", field: "instance_id", index: "by_instance_id_user_id" },
  },
  question_version_localizations: child(
    "daily_question_instances",
    "question_version_id",
    "question_version_id",
    "by_question_version_id_locale",
    {
      group: "daily",
      about: {
        en: "The wording of the questions you were given, in English and Norwegian. The questions are written by Paeonia.",
        nb: "Ordlyden i spørsmålene du fikk, på engelsk og norsk. Spørsmålene er skrevet av Paeonia.",
      },
    },
  ),
  daily_question_shuffles: own("user_id", "by_user_id_question_id_exclude_until", {
    group: "daily",
    about: {
      en: "Questions you swapped for another one.",
      nb: "Spørsmål du byttet ut med et annet.",
    },
  }),
  daily_question_threads: shared("by_couple_id_question_id", {
    group: "daily",
    about: {
      en: "Which chat belongs to which question.",
      nb: "Hvilken samtale som hører til hvilket spørsmål.",
    },
  }),
  daily_challenges: own("user_id", "by_user_id", {
    group: "daily",
    about: { en: "Days you finished the daily questions.", nb: "Dager du ble ferdig med dagens spørsmål." },
  }),
  daily_answer_seen_states: own("user_id", "by_user_id", {
    group: "daily",
    about: {
      en: "When you first saw your partner's answers.",
      nb: "Når du første gang så partnerens svar.",
    },
  }),
  topic_question_skips: shared("by_couple_id_question_id", {
    group: "daily",
    about: {
      en: "Topic questions the two of you put aside. It does not say who did it.",
      nb: "Temaspørsmål dere la til side. Det står ikke hvem av dere som gjorde det.",
    },
  }),

  // ---- chat ----
  conversation_threads: shared("by_couple_id_created_at", {
    group: "chat",
    about: {
      en: "The chats you and your partner have, one for each question and each memory.",
      nb: "Samtalene du og partneren din har, én for hvert spørsmål og hvert minne.",
    },
  }),
  thread_messages: own("sender_user_id", "by_sender_user_id_created_at", {
    group: "chat",
    about: {
      en: "The messages you sent. Your partner's messages are not included.",
      nb: "Meldingene du har sendt. Partnerens meldinger er ikke med.",
    },
  }),
  thread_message_media: child("thread_messages", "id", "message_id", "by_message_id_sort_order", {
    group: "chat",
    about: {
      en: "Which photos and voice messages belong to your chat messages. The files are in the files folder.",
      nb: "Hvilke bilder og talemeldinger som hører til meldingene dine. Filene ligger i mappen files.",
    },
  }),
  thread_read_states: own("user_id", "by_user_id", {
    group: "chat",
    about: { en: "How far you have read in each chat.", nb: "Hvor langt du har lest i hver samtale." },
  }),

  // ---- memories ----
  memories: shared("by_couple_id_memory_date_id", {
    group: "memories",
    about: {
      en: "The memories in your shared space: title, date and place.",
      nb: "Minnene i det delte rommet deres: tittel, dato og sted.",
    },
  }),
  memory_notes: own("user_id", "by_user_id_updated_at", {
    group: "memories",
    about: { en: "The notes you wrote on memories.", nb: "Notatene du skrev på minner." },
  }),
  memory_media: own("owner_user_id", "by_owner_user_id_memory_id", {
    group: "memories",
    about: {
      en: "Which photos you added to which memory. The files are in the files folder.",
      nb: "Hvilke bilder du la til i hvilke minner. Filene ligger i mappen files.",
    },
  }),
  memory_threads: child("memories", "id", "memory_id", "by_memory_id", {
    group: "memories",
    about: { en: "Which chat belongs to which memory.", nb: "Hvilken samtale som hører til hvilket minne." },
  }),

  // ---- stories and notes ----
  stories: yours("by_couple_id_created_at", "author_user_id", {
    group: "stories",
    about: {
      en: "The stories you posted: caption and time. The photos are in the files folder.",
      nb: "Storyene du la ut: bildetekst og tidspunkt. Bildene ligger i mappen files.",
    },
  }),
  story_threads: child("stories", "id", "story_id", "by_story_id", {
    group: "stories",
    about: {
      en: "Which chat belongs to which of your stories. Your replies to your partner's stories are in the chat files.",
      nb: "Hvilken samtale som hører til hvilken av storyene dine. Svarene dine på partnerens stories ligger i samtalefilene.",
    },
  }),
  couple_notes: yours("by_couple_id_user_id", "user_id", {
    group: "stories",
    about: {
      en: "Your short note, if one is up right now. Notes are deleted after 24 hours.",
      nb: "Det korte notatet ditt, hvis du har ett oppe nå. Notater slettes etter 24 timer.",
    },
  }),

  // ---- drawings ----
  widget_canvases: shared("by_couple_id", {
    group: "drawings",
    about: {
      en: "The shared drawing board behind your widget.",
      nb: "Den delte tegnebrettet bak widgeten deres.",
    },
  }),
  widget_drawing_revisions: own("author_user_id", "by_author_user_id_created_at", {
    group: "drawings",
    about: {
      en: "The drawings you saved on the shared drawing board. The drawing files are in the files folder.",
      nb: "Tegningene du lagret på det delte tegnebrettet. Tegningsfilene ligger i mappen files.",
    },
  }),

  // ---- location ----
  location_sharing_preferences: own("user_id", "by_user_id", {
    group: "location",
    about: {
      en: "Whether you share your location, since when, and what you agreed to.",
      nb: "Om du deler posisjonen din, siden når, og hva du har samtykket til.",
    },
  }),
  latest_partner_locations: own("user_id", "by_user_id_updated_at", {
    group: "location",
    about: {
      en: "The last location you shared with your partner. We keep no history.",
      nb: "Den siste posisjonen du delte med partneren din. Vi lagrer ingen historikk.",
    },
  }),

  // ---- activity ----
  couple_activity_events: own("user_id", "by_user_id_created_at", {
    group: "activity",
    about: {
      en: "What you did in Paeonia that counts for your streak, such as answering or drawing.",
      nb: "Det du har gjort i Paeonia som teller for rekken, som å svare eller tegne.",
    },
  }),
  reactions: own("user_id", "by_user_id", {
    group: "activity",
    about: {
      en: "The emoji you put on messages, answers, stories, memories, drawings and game creations. The emoji your partner put on your things are not included.",
      nb: "Emojiene du la på meldinger, svar, stories, minner, tegninger og spillskapninger. Emojiene partneren din la på tingene dine er ikke med.",
    },
  }),
  favorites: own("user_id", "by_user_id_created_at", {
    group: "activity",
    about: {
      en: "The questions, answers, drawings and game results you starred as favorites. Your partner cannot see your favorites.",
      nb: "Spørsmålene, svarene, tegningene og spillresultatene du har stjernemerket som favoritter. Partneren din kan ikke se favorittene dine.",
    },
  }),

  // ---- privacy and safety ----
  privacy_requests: own("user_id", "by_user_id_requested_at", {
    group: "safety",
    about: {
      en: "Your requests about your data, such as asking for a correction or deleting your account.",
      nb: "Forespørslene dine om dataene dine, som å be om retting eller å slette kontoen.",
    },
  }),
  privacy_request_events: child("privacy_requests", "id", "request_id", "by_request_id_created_at", {
    group: "safety",
    about: {
      en: "What happened to each of those requests, step by step.",
      nb: "Hva som skjedde med hver av forespørslene, steg for steg.",
    },
  }),
  content_reports: own("reporter_user_id", "by_reporter_user_id_created_at", {
    group: "safety",
    about: {
      en: "Reports you sent to us about your partner.",
      nb: "Rapportene du har sendt oss om partneren din.",
    },
  }),
  content_report_targets: child("content_reports", "id", "report_id", "by_report_id", {
    group: "safety",
    about: {
      en: "What each of your reports was about.",
      nb: "Hva hver av rapportene dine handlet om.",
    },
  }),

  // ---- games ----
  game_settings: shared("by_couple_id", {
    group: "games",
    about: {
      en: "How you and your partner chose to play: together or against each other, and the language.",
      nb: "Hvordan du og partneren din valgte å spille: sammen eller mot hverandre, og språket.",
    },
  }),
  game_invites: yours("by_couple_id_kind_sender_user_id", "sender_user_id", {
    group: "games",
    about: { en: "Invites to play that you sent.", nb: "Spillinvitasjoner du har sendt." },
  }),
  game_plays: shared("by_couple_id_kind", {
    group: "games",
    about: { en: "When you last opened each game.", nb: "Når dere sist åpnet hvert spill." },
  }),
  game_hidden_waits: yours("by_couple_id_user_id_kind", "user_id", {
    group: "games",
    about: { en: "Games you put aside with \"Not now\" until your partner's next move.", nb: "Spill du la til side med «Ikke nå» til partneren din gjør neste trekk." },
  }),
  games: shared("by_couple_id_kind", {
    group: "games",
    about: { en: "Your Draw & Guess game: whose turn it is and the score.", nb: "Tegn og gjett-spillet deres: hvem sin tur det er og stillingen." },
    hide: ["word_choices"],
  }),
  game_moves: shared("by_couple_id", {
    group: "games",
    about: {
      en: "The rounds of Draw & Guess. A word stays out until the round is over, unless you drew it.",
      nb: "Rundene i Tegn og gjett. Ordet er ikke med før runden er over, med mindre du tegnet det.",
    },
    select: drawAndGuessRound,
  }),
  game_guesses: yours("by_couple_id", "user_id", {
    group: "games",
    about: { en: "Your guesses in Draw & Guess.", nb: "Gjettene dine i Tegn og gjett." },
  }),
  story_chain_games: shared("by_couple_id", {
    group: "games",
    about: { en: "Your Story Chain game: whose turn it is and how many stories you have written.", nb: "Skrivestafett-spillet deres: hvem sin tur det er og hvor mange historier dere har skrevet." },
  }),
  story_chain_stories: shared("by_couple_id_story_number", {
    group: "games",
    about: {
      en: "The stories you wrote together. Your lines are in full. For your partner's lines only the number and time are included.",
      nb: "Historiene dere skrev sammen. Linjene dine er med i sin helhet. Fra partnerens linjer er bare nummer og tidspunkt med.",
    },
    select: storyChainStory,
  }),
  mind_meld_games: shared("by_couple_id_game_number", {
    group: "games",
    about: { en: "Your Mind Meld games.", nb: "Tenk likt-spillene dine." },
  }),
  mind_meld_rounds: shared("by_couple_id", {
    group: "games",
    about: { en: "The rounds of Mind Meld and how each one ended.", nb: "Rundene i Tenk likt og hvordan hver endte." },
  }),
  mind_meld_words: yours("by_couple_id", "user_id", {
    group: "games",
    about: { en: "The words you picked in Mind Meld.", nb: "Ordene du valgte i Tenk likt." },
  }),
  consensio_games: shared("by_couple_id", {
    group: "games",
    about: { en: "Your Consensio game: whose turn it is and the score.", nb: "Consensio-spillet deres: hvem sin tur det er og stillingen." },
    select: consensioGame,
  }),
  consensio_rounds: shared("by_couple_id", {
    group: "games",
    about: {
      en: "The rounds of Consensio. A spot your partner placed stays out until you have guessed.",
      nb: "Rundene i Consensio. Et punkt partneren din plasserte er ikke med før du har gjettet.",
    },
    select: consensioRound,
  }),
  guess_my_spot_games: shared("by_couple_id", {
    group: "games",
    about: { en: "Your Guess my spot game: whose turn it is and the score.", nb: "Gjett stedet-spillet deres: hvem sin tur det er og stillingen." },
  }),
  guess_my_spot_rounds: shared("by_couple_id", {
    group: "games",
    about: {
      en: "The rounds of Guess my spot. For photos you sent, the place is included. For photos your partner sent, only your guess and score are.",
      nb: "Rundene i Gjett stedet. For bilder du sendte er stedet med. For bilder partneren din sendte er bare gjettet og poengene dine med.",
    },
    select: guessMySpotRound,
  }),
  exquisite_corpse_games: shared("by_couple_id", {
    group: "games",
    about: { en: "Your Odd Creatures game: whose turn it is.", nb: "Rare skapninger-spillet deres: hvem sin tur det er." },
  }),
  exquisite_corpse_figures: shared("by_couple_id_number", {
    group: "games",
    about: { en: "The creatures you made together.", nb: "Skapningene dere laget sammen." },
  }),
  exquisite_corpse_parts: yours("by_couple_id", "drawer_user_id", {
    group: "games",
    about: {
      en: "The parts of creatures that you drew. The drawings are in the files folder.",
      nb: "Delene av skapninger som du tegnet. Tegningene ligger i mappen files.",
    },
  }),
  board_games: shared("by_couple_id_kind", {
    group: "games",
    about: BOARD_GAME_SHARED_ABOUT,
    select: (row) => boardGame(row),
  }),
  board_game_history: shared("by_couple_id_kind_game_number", {
    group: "games",
    about: {
      en: "Every board game you have finished together, with the moves.",
      nb: "Alle brettspill dere har spilt ferdig sammen, med trekkene.",
    },
  }),
  board_game_marks: yours("by_couple_id_user_id", "user_id", {
    group: "games",
    about: { en: "The mark you drew for yourself in the board games.", nb: "Merket du tegnet til deg selv i brettspillene." },
  }),

  // ---- files ----
  media_assets: own("owner_user_id", "by_owner_user_id_created_at", {
    group: "files",
    about: {
      en: "Every photo, voice message and drawing file you uploaded. The `file` field says where the file is in this download.",
      nb: "Hvert bilde, hver talemelding og hver tegningsfil du har lastet opp. Feltet `file` sier hvor filen ligger i denne nedlastingen.",
    },
    hide: ["storage_id", "reserved_by_client_operation_id"],
  }),

  // ---- not exported ----
  account_deletion_jobs: excluded(
    "Exists only after account deletion has started, and then the person can no longer sign in to ask.",
  ),
  client_operations: excluded(
    "Short-lived copies of what the phone sent, kept 30 days to stop a write from running twice. The content is exported from the real tables.",
  ),
  moderation_actions: excluded(
    "Operator notes about reports. They can name the person who reported, whose rights Art. 15(4) protects.",
  ),
  pair_safety_warning_flags: excluded(
    "Internal safety flags on a pair of accounts. They can show who reported, whose rights Art. 15(4) protects.",
  ),
  pairing_invite_secrets: excluded("Hashed invite codes. Secrets, and they hold no information about the person."),
  report_snapshot_assets: excluded(
    "Copies of reported files, kept up to 180 days for review. They hold other people's content, protected by Art. 15(4).",
  ),
  report_snapshots: excluded(
    "Copies of reported content, kept up to 180 days for review. They hold other people's content, protected by Art. 15(4).",
  ),
  review_access_codes: excluded("Access codes for App Review. They belong to Paeonia, not to a person."),
  review_demo_partners: excluded("Demo accounts for App Review. They are not real people."),
  storekit_notification_events: excluded(
    "Raw notices from Apple. The purchases they describe are in storekit_transactions.",
  ),
  storekit_payloads: excluded(
    "Raw signed data from Apple. The purchases it describes are in storekit_transactions.",
  ),
  widget_push_outbox: excluded(
    "Silent refresh signals for widgets, kept 30 days. They carry no content.",
  ),
  question_answer_kinds: excluded("Paeonia's question catalog. It is the same for everyone and holds no personal data."),
  question_collections: excluded("Paeonia's question catalog. It is the same for everyone and holds no personal data."),
  question_collection_localizations: excluded("Paeonia's question catalog. It is the same for everyone and holds no personal data."),
  question_versions: excluded("Paeonia's question catalog. It is the same for everyone and holds no personal data."),
  questions: excluded("Paeonia's question catalog. It is the same for everyone and holds no personal data."),
  topic_catalog: excluded("Paeonia's question catalog. It is the same for everyone and holds no personal data."),
  subscription_products: excluded("Paeonia's list of App Store products. It is the same for everyone."),
  game_used_words: excluded("Bookkeeping that stops a word from coming back. It holds no content the person wrote."),
  story_chain_used: excluded("Bookkeeping that stops an opening or word from coming back. It holds no content the person wrote."),
  consensio_used_topics: excluded("Bookkeeping that stops a topic from coming back. It holds no content the person wrote."),
  data_exports: excluded("The download job itself. It holds no data beyond the files, which expire after a few days."),
  data_export_parts: excluded("The pieces of a download. They expire after a few days."),
  data_export_chunks: excluded("Data files of a download that is still being built. They are deleted when the zip file that holds them is done."),
};

const SYSTEM_FIELDS = ["_id", "_creationTime"] as const;

/** One stored document as it appears in the export, or null when the export leaves it out. */
export function shapeRow(spec: ExportedTable, doc: Row, me: string): Row | null {
  const row = without(doc, SYSTEM_FIELDS);
  const kept = spec.select ? spec.select(row, me) : row;
  return kept === null || !spec.hide ? kept : without(kept, spec.hide);
}

// ---- files ----

const MEDIA_FOLDERS: Record<string, string> = {
  profile_photo: "profile-photos",
  memory_photo: "memory-photos",
  voice_note: "voice-messages",
  daily_answer_media: "answer-media",
  thread_media: "chat-media",
  widget_drawing_payload: "shared-drawings",
  game_drawing_payload: "game-drawings",
  exquisite_corpse_drawing: "odd-creatures",
  exquisite_corpse_strip: "odd-creatures",
  story_photo: "story-photos",
  guess_my_spot_photo: "guess-my-spot-photos",
};

/**
 * Whether the export holds the file behind a media row: a finished upload that is still stored and
 * that moderation has not removed. Copies kept for a report are other people's content, so they stay out.
 */
export function isExportableMedia(row: Doc<"media_assets">): boolean {
  return (
    row.upload_status === "finalized" &&
    row.storage_id !== undefined &&
    row.storage_delete_status === "none" &&
    row.deleted_at === undefined &&
    row.bucket !== "report-snapshots" &&
    row.moderation_status !== "removed" &&
    row.moderation_status !== "rejected"
  );
}

/** Where a media file sits in the archive, for example `files/memory-photos/2026-10-21_<id>.jpg`. */
export function mediaFilePath(row: Pick<Doc<"media_assets">, "id" | "created_at" | "upload_purpose" | "storage_path" | "media_type">): string {
  const folder = MEDIA_FOLDERS[row.upload_purpose] ?? "other";
  const extension = /\.([a-z0-9]{1,16})$/i.exec(row.storage_path)?.[1]?.toLowerCase();
  const fallback = row.media_type === "image" ? "jpg" : row.media_type === "voice" ? "m4a" : "pkdrawing";
  return `${EXPORT_GROUPS.files.folder}/${folder}/${row.created_at.slice(0, 10)}_${row.id}.${extension ?? fallback}`;
}

/**
 * The exported tables with every parent before its children, and every table that a `referencedBy`
 * entry names before the table that reads it. The build collects them in this order.
 */
export function exportedTablesInOrder(): [TableNames, ExportedTable][] {
  const exported = (Object.entries(TABLE_EXPORTS) as [TableNames, TableExport][]).filter(
    (entry): entry is [TableNames, ExportedTable] => entry[1].kind !== "excluded",
  );
  const ordered: [TableNames, ExportedTable][] = [];
  const placed = new Set<string>();
  while (ordered.length < exported.length) {
    const before = ordered.length;
    for (const entry of exported) {
      const [table, spec] = entry;
      const dependency = spec.kind === "child" ? spec.parent : spec.kind === "couple" ? spec.referencedBy?.table : undefined;
      if (placed.has(table) || (dependency !== undefined && !placed.has(dependency))) continue;
      placed.add(table);
      ordered.push(entry);
    }
    if (ordered.length === before) throw new Error("data export tables have a parent that is missing or a cycle");
  }
  return ordered;
}
