import { EXPORT_GROUPS, EXPORT_VALID_DAYS, type ExportGroup } from "./dataExportRegistry";

// The README.md inside every export, in plain language. It is also the "supplementary information"
// of GDPR Art. 15(1) and 15(2): purposes, categories, recipients, retention, rights, the right to
// complain, and where the data came from. Keep it in line with the privacy policy
// (marketing/src/lib/i18n/dictionaries/legal.*.ts) and docs/privacy-and-data-export.md.

export type ExportLocale = "en" | "nb";

export type ReadmeFile = {
  path: string;
  group: ExportGroup;
  rows: number;
  about: string;
};

export type ReadmeInput = {
  locale: ExportLocale;
  generatedAt: string;
  userId: string;
  includeFiles: boolean;
  /** The zip files that make up this download, in order. */
  partNames: string[];
  files: ReadmeFile[];
  /** How many photos, voice messages and drawings are in the download, and how many could not be included. */
  mediaCount: number;
  mediaSkippedCount: number;
};

const GROUP_TITLES: Record<ExportGroup, Record<ExportLocale, string>> = {
  account: { en: "Your account", nb: "Kontoen din" },
  settings: { en: "Your phones and settings", nb: "Telefonene og innstillingene dine" },
  subscription: { en: "Subscription and purchases", nb: "Abonnement og kjøp" },
  relationship: { en: "Your relationship", nb: "Forholdet ditt" },
  daily: { en: "Daily questions", nb: "Dagens spørsmål" },
  chat: { en: "Chat", nb: "Samtaler" },
  memories: { en: "Memories", nb: "Minner" },
  stories: { en: "Stories and notes", nb: "Stories og notater" },
  drawings: { en: "Drawings", nb: "Tegninger" },
  games: { en: "Games", nb: "Spill" },
  location: { en: "Location", nb: "Posisjon" },
  activity: { en: "Activity", nb: "Aktivitet" },
  safety: { en: "Privacy and safety", nb: "Personvern og trygghet" },
  files: { en: "Photos, voice messages and drawings", nb: "Bilder, talemeldinger og tegninger" },
};

const GROUP_ORDER = Object.keys(EXPORT_GROUPS) as ExportGroup[];

function formatDate(iso: string, locale: ExportLocale): string {
  return new Date(iso).toLocaleDateString(locale === "nb" ? "nb-NO" : "en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

function fileList(input: ReadmeInput): string[] {
  const lines: string[] = [];
  for (const group of GROUP_ORDER) {
    const files = input.files.filter((file) => file.group === group);
    if (files.length === 0) continue;
    lines.push(`### ${GROUP_TITLES[group][input.locale]}`, "");
    for (const file of files.sort((a, b) => a.path.localeCompare(b.path))) {
      lines.push(`- \`${file.path}\` (${file.rows}): ${file.about}`);
    }
    lines.push("");
  }
  return lines;
}

function english(input: ReadmeInput): string {
  const multiple = input.partNames.length > 1;
  const lines: string[] = [
    "# Your Paeonia data",
    "",
    `Made on ${formatDate(input.generatedAt, "en")} for the account \`${input.userId}\`. Only you can download it. It is deleted from our servers ${EXPORT_VALID_DAYS} days after it was made.`,
    "",
    "## What is in this download",
    "",
    "This is a copy of the personal data Paeonia keeps about you. You can read it, keep it, or take it to another service. The data files are in JSON, a plain text format that programs and spreadsheets can open. The number after each file name is how many entries it has. Files with no entries are left out. A file that would be very big is split into numbered files, like `chat/thread_messages-001.json`, and together they hold all the entries.",
    "",
  ];
  if (multiple) {
    lines.push(
      `The download comes in ${input.partNames.length} zip files because it is big. Part 1 has this README. The data files and the photos, voice messages and drawings are spread over the parts, and \`manifest.json\` says which zip file holds each one. Unzip them all into the same folder.`,
      "",
      ...input.partNames.map((name, index) => `- Part ${index + 1}: ${name}`),
      "",
    );
  }
  lines.push(
    "`manifest.json` lists every file in this download in a form a program can read.",
    "",
    "## The files",
    "",
    ...fileList(input),
  );
  if (input.includeFiles) {
    lines.push(
      `You uploaded ${input.mediaCount + input.mediaSkippedCount} photos, voice messages and drawings. ${input.mediaCount} of them are in the \`files\` folder, in the original quality we store.${input.mediaSkippedCount > 0 ? ` ${input.mediaSkippedCount} could not be included because they were removed or are no longer stored.` : ""} \`files/media_assets.json\` says which file belongs to which entry, in the field \`file\`.`,
      "",
    );
  } else {
    lines.push(
      "You chose to leave out your photos, voice messages and drawings. The entries that point to them are still in the data files, and you can make a new download with them any time.",
      "",
    );
  }
  lines.push(
    "## How to read the data",
    "",
    "- Text is UTF-8. Dates and times are ISO 8601 in UTC, like `2026-10-21T08:30:00.000Z`. Dates without a time are `YYYY-MM-DD`.",
    "- Every entry has an `id` made of random letters and numbers. Other files point to it, for example an answer points to its question.",
    "- A field that is missing means we have nothing stored for it.",
    "",
    "## What is not in this download",
    "",
    "- **Your partner's own things.** What your partner wrote or uploaded, their photos and voice messages, their location, their settings and phones, and what they marked privately. This is their personal data, and the law asks us to protect it too (GDPR Art. 15(4) and 20(4)). In shared things, such as a story you wrote together, your own lines are in full and your partner's lines only show the number and time.",
    "- **Things you share with your partner as one.** These are included while you are together: the relationship, memories, countdowns, streaks, chats, and the scores and results of games. Secrets inside a game, such as a word or a spot your partner chose and you have not guessed yet, are left out.",
    "- **Reports about you.** If someone reported you, the report is not included, to protect the person who reported.",
    "- **Short-lived technical records.** For example copies of what your phone sent, which we keep for 30 days so nothing runs twice. What they contain is already in the files above.",
    "- **Usage statistics.** If you agreed to share them, PostHog keeps statistics about how you use the app, linked to your account id. They are not in this download. Write to contact@paeonia.no and we will fetch them for you.",
    "- **Sign-in details.** Apple, Google and Clerk hold your sign-in details, such as your email address. We only keep the parts they send us when you sign in.",
    "",
    "## Why we have your data, and who gets it",
    "",
    "- **Who is responsible.** Hjalmar Karlsen, Storgata 61, 0182 Oslo, Norway. Email contact@paeonia.no.",
    "- **What we use it for.** To make your account, connect you with your partner, run the shared features, show your subscription, send the notifications you allow, answer support, keep Paeonia safe, and follow the law. We use usage statistics and your location only if you agreed, and you can say no or change your mind any time.",
    "- **The legal reasons.** Mostly that we need it to give you Paeonia, which is our agreement with you (GDPR Art. 6(1)(b)). Usage statistics, location sharing and notifications rest on your consent (Art. 6(1)(a)). Keeping Paeonia safe and secure rests on our legitimate interest (Art. 6(1)(f)). Records we must keep, such as for accounting, rest on the law (Art. 6(1)(c)).",
    "- **Where it came from.** From you. From Apple or Google when you sign in. From Apple for your purchases. From your partner for the shared things.",
    "- **Who gets it.** These companies work for us and only to run Paeonia. Apple (Sign in with Apple, payments and subscriptions, notifications). Google (Sign in with Google). Clerk (sign-in and sessions). Cloudflare (stores your photos, voice messages and drawings in the EU, and passes live drawings between you and your partner without storing them). PostHog (usage statistics, only if you agreed, stored in Frankfurt). Our database and server run on a rented server in Leipzig, Germany. We do not sell data and we do not use it for advertising.",
    "- **Outside the EU.** PostHog, Inc. is a US company. Your data stays in Germany, and any access from the US is covered by the EU-US Data Privacy Framework and the EU standard contractual clauses. Email contact@paeonia.no for a copy of these.",
    "- **How long we keep it.** While your account is active. When a relationship ends, what you shared is hidden at once and deleted after about 30 days. Your latest shared location is deleted at once. Notifications and technical records are deleted after about 30 days. Deleted data can stay in backups for up to 14 days. Usage statistics are deleted after a year without use. Records about reports, subscriptions and safety can be kept longer when we need them for safety, accounting or the law.",
    "- **Decisions by a computer.** Nothing about you is decided only by a computer.",
    "",
    "## Your rights",
    "",
    "You can ask us to correct your data, delete it, limit how we use it, or stop using it. You can take back a consent you gave. You can open Us, then Privacy and safety, in the app to ask for a correction, to turn off usage statistics, and to delete your account. You can also write to contact@paeonia.no. We answer within a month.",
    "",
    "If you think we handle your data wrongly, you can complain to the Norwegian Data Protection Authority, Datatilsynet (www.datatilsynet.no), or to the authority in the country where you live.",
    "",
  );
  return lines.join("\n");
}

function norwegian(input: ReadmeInput): string {
  const multiple = input.partNames.length > 1;
  const lines: string[] = [
    "# Dine data fra Paeonia",
    "",
    `Laget ${formatDate(input.generatedAt, "nb")} for kontoen \`${input.userId}\`. Bare du kan laste den ned. Den slettes fra serverne våre ${EXPORT_VALID_DAYS} dager etter at den ble laget.`,
    "",
    "## Dette er med i nedlastingen",
    "",
    "Dette er en kopi av personopplysningene Paeonia har om deg. Du kan lese dem, ta vare på dem eller ta dem med til en annen tjeneste. Datafilene er i JSON, et tekstformat som programmer og regneark kan åpne. Tallet etter hvert filnavn er hvor mange oppføringer filen har. Filer uten oppføringer er utelatt. En fil som ville blitt veldig stor, er delt i nummererte filer, som `chat/thread_messages-001.json`, og til sammen har de alle oppføringene.",
    "",
  ];
  if (multiple) {
    lines.push(
      `Nedlastingen kommer i ${input.partNames.length} zip-filer fordi den er stor. Del 1 har denne README-filen. Datafilene og bildene, talemeldingene og tegningene er fordelt på delene, og \`manifest.json\` sier hvilken zip-fil som har hver enkelt. Pakk dem alle ut i samme mappe.`,
      "",
      ...input.partNames.map((name, index) => `- Del ${index + 1}: ${name}`),
      "",
    );
  }
  lines.push(
    "`manifest.json` lister alle filene i nedlastingen på en måte et program kan lese.",
    "",
    "## Filene",
    "",
    ...fileList(input),
  );
  if (input.includeFiles) {
    lines.push(
      `Du har lastet opp ${input.mediaCount + input.mediaSkippedCount} bilder, talemeldinger og tegninger. ${input.mediaCount} av dem ligger i mappen \`files\`, i originalkvaliteten vi har lagret.${input.mediaSkippedCount > 0 ? ` ${input.mediaSkippedCount} kunne ikke tas med fordi de er fjernet eller ikke lenger lagret.` : ""} \`files/media_assets.json\` viser hvilken fil som hører til hvilken oppføring, i feltet \`file\`.`,
      "",
    );
  } else {
    lines.push(
      "Du valgte å la bildene, talemeldingene og tegningene dine ligge utenfor. Oppføringene som peker til dem ligger fortsatt i datafilene, og du kan lage en ny nedlasting med dem når som helst.",
      "",
    );
  }
  lines.push(
    "## Slik leser du dataene",
    "",
    "- Tekst er UTF-8. Datoer og klokkeslett følger ISO 8601 i UTC, som `2026-10-21T08:30:00.000Z`. Datoer uten klokkeslett er `ÅÅÅÅ-MM-DD`.",
    "- Hver oppføring har en `id` av tilfeldige bokstaver og tall. Andre filer peker til den, for eksempel peker et svar til spørsmålet sitt.",
    "- Et felt som mangler betyr at vi ikke har lagret noe i det.",
    "",
    "## Dette er ikke med i nedlastingen",
    "",
    "- **Partnerens egne ting.** Det partneren din har skrevet eller lastet opp, bildene og talemeldingene deres, posisjonen deres, innstillingene og telefonene deres, og det de har merket privat. Dette er partnerens personopplysninger, og loven krever at vi beskytter dem også (GDPR art. 15(4) og 20(4)). I ting dere lager sammen, som en historie, er dine egne linjer med i sin helhet, og fra partnerens linjer vises bare nummer og tidspunkt.",
    "- **Ting dere deler som ett.** Disse er med så lenge dere er sammen: forholdet, minner, nedtellinger, rekker, samtaler og poeng og resultater i spill. Hemmeligheter i et spill, som et ord eller et punkt partneren din valgte og du ikke har gjettet ennå, er utelatt.",
    "- **Rapporter om deg.** Hvis noen har rapportert deg, er rapporten ikke med, for å beskytte den som rapporterte.",
    "- **Tekniske opplysninger som forsvinner fort.** For eksempel kopier av det telefonen din sendte, som vi har i 30 dager så ingenting kjøres to ganger. Innholdet er allerede med i filene over.",
    "- **Bruksstatistikk.** Hvis du har sagt ja til å dele den, har PostHog statistikk om hvordan du bruker appen, knyttet til konto-id-en din. Den er ikke med her. Skriv til contact@paeonia.no, så henter vi den for deg.",
    "- **Innloggingsopplysninger.** Apple, Google og Clerk har innloggingsopplysningene dine, som e-postadressen din. Vi har bare det de sender oss når du logger inn.",
    "",
    "## Hvorfor vi har dataene dine, og hvem som får dem",
    "",
    "- **Hvem som er ansvarlig.** Hjalmar Karlsen, Storgata 61, 0182 Oslo, Norge. E-post: contact@paeonia.no.",
    "- **Hva vi bruker dem til.** Å lage kontoen din, koble deg til partneren din, drive de delte funksjonene, vise abonnementet ditt, sende varslene du tillater, svare på henvendelser, holde Paeonia trygt og følge loven. Vi bruker bruksstatistikk og posisjonen din bare hvis du har sagt ja, og du kan si nei eller ombestemme deg når som helst.",
    "- **Det rettslige grunnlaget.** For det meste at vi trenger dem for å gi deg Paeonia, som er avtalen vår med deg (GDPR art. 6(1)(b)). Bruksstatistikk, deling av posisjon og varsler bygger på samtykket ditt (art. 6(1)(a)). Å holde Paeonia trygt og sikkert bygger på en berettiget interesse (art. 6(1)(f)). Opplysninger vi må ta vare på, for eksempel til regnskap, bygger på loven (art. 6(1)(c)).",
    "- **Hvor de kommer fra.** Fra deg. Fra Apple eller Google når du logger inn. Fra Apple for kjøpene dine. Fra partneren din for de delte tingene.",
    "- **Hvem som får dem.** Disse selskapene jobber for oss, og bare for å drive Paeonia. Apple (Logg inn med Apple, betaling og abonnement, varsler). Google (Logg inn med Google). Clerk (innlogging og økter). Cloudflare (lagrer bildene, talemeldingene og tegningene dine i EU, og sender levende tegninger mellom deg og partneren din uten å lagre dem). PostHog (bruksstatistikk, bare hvis du har sagt ja, lagret i Frankfurt). Databasen og serveren vår kjører på en leid server i Leipzig i Tyskland. Vi selger ikke data, og vi bruker dem ikke til reklame.",
    "- **Utenfor EU.** PostHog, Inc. er et amerikansk selskap. Dataene dine blir i Tyskland, og all tilgang fra USA dekkes av EU-USA-rammeverket for personvern (Data Privacy Framework) og EUs standardkontrakter. Send e-post til contact@paeonia.no for en kopi av dem.",
    "- **Hvor lenge vi har dem.** Så lenge kontoen din er aktiv. Når et forhold tar slutt, skjules det dere delte med en gang og slettes etter omtrent 30 dager. Siste delte posisjon slettes med en gang. Varsler og tekniske opplysninger slettes etter omtrent 30 dager. Slettede data kan ligge i sikkerhetskopier i opptil 14 dager. Bruksstatistikk slettes etter ett år uten bruk. Opplysninger om rapporter, abonnement og sikkerhet kan ligge lenger når vi trenger dem av hensyn til sikkerhet, regnskap eller loven.",
    "- **Avgjørelser fra en datamaskin.** Ingenting om deg avgjøres bare av en datamaskin.",
    "",
    "## Rettighetene dine",
    "",
    "Du kan be oss rette dataene dine, slette dem, begrense hvordan vi bruker dem eller slutte å bruke dem. Du kan trekke tilbake et samtykke du har gitt. I appen åpner du Oss og deretter Personvern og trygghet for å be om retting, slå av bruksstatistikk og slette kontoen. Du kan også skrive til contact@paeonia.no. Vi svarer innen en måned.",
    "",
    "Hvis du mener vi behandler dataene dine feil, kan du klage til Datatilsynet (www.datatilsynet.no) eller til tilsynet i landet du bor i.",
    "",
  );
  return lines.join("\n");
}

/** The README text of an export, in the person's language. */
export function renderReadme(input: ReadmeInput): string {
  return input.locale === "nb" ? norwegian(input) : english(input);
}
