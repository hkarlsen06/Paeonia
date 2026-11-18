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
  /** How many photos, videos, voice messages and drawings are in the download, and how many could not be included. */
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
  letters: { en: "Letters", nb: "Brev" },
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
    `Made on ${formatDate(input.generatedAt, "en")} for the account \`${input.userId}\`. Only your account can make a download link, and each link works for an hour. The download is deleted from our servers ${EXPORT_VALID_DAYS} days after it was made.`,
    "",
    "## What is in this download",
    "",
    "This is a copy of the personal data Paeonia keeps about you. You can read it, keep it, or take it to another service. The data files are in JSON, a plain text format that programs and spreadsheets can open. The number after each file name is how many entries it has. Files with no entries are left out. A file that would be very big is split into numbered files, like `chat/thread_messages-001.json`, and together they hold all the entries.",
    "",
  ];
  if (multiple) {
    lines.push(
      `The download comes in ${input.partNames.length} zip files because it is big. Part 1 has this README. The data files and the photos, videos, voice messages and drawings are spread over the parts, and \`manifest.json\` says which zip file holds each one. Unzip them all into the same folder.`,
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
      `You uploaded ${input.mediaCount + input.mediaSkippedCount} photos, videos, voice messages and drawings. ${input.mediaCount} of them are in the \`files\` folder, in the original quality we store.${input.mediaSkippedCount > 0 ? ` ${input.mediaSkippedCount} could not be included because they were removed or are no longer stored.` : ""} \`files/media_assets.json\` says which file belongs to which entry, in the field \`file\`.`,
      "",
    );
  } else {
    lines.push(
      "You chose to leave out your photos, videos, voice messages and drawings. The entries that point to them are still in the data files, and you can make a new download with them any time.",
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
    "- **Your partner's own things.** What your partner wrote or uploaded, their photos, videos and voice messages, their location, their settings and phones, and what they marked privately. This is their personal data, and the law asks us to protect it too (GDPR Art. 15(4) and 20(4)). In shared things, such as a story you wrote together, your own lines are in full and your partner's lines only show the number and time.",
    "- **Things you share with your partner as one.** These are included while you are together: the relationship, memories, countdowns, streaks, chats, and the scores and results of games. Secrets inside a game, such as a word or a spot your partner chose and you have not guessed yet, are left out.",
    "- **Reports about you.** If someone reported you, the report is not included, to protect the person who reported.",
    "- **Short-lived technical records.** For example copies of what your phone sent, which we keep for 30 days so nothing runs twice. What they contain is already in the files above.",
    "- **Usage statistics.** If you agreed to share them, PostHog keeps statistics about how you use the app, linked to your account id. They are not in this download. Write to contact@paeonia.no and we will fetch them for you.",
    "- **Sign-in details.** Apple, Google and Clerk hold your sign-in details, such as your email address and the codes Clerk emails you. We only keep the parts they send us when you sign in.",
    "",
    "## Why we have your data, and who gets it",
    "",
    "- **Who is responsible.** Hjalmar Karlsen, Storgata 61, 0182 Oslo, Norway. Email contact@paeonia.no.",
    "- **What we use it for.** To make your account, connect you with your partner, run the shared features, show your subscription, send the notifications you allow, answer support, keep Paeonia safe, and follow the law. We use usage statistics, your location and your Flirt answers only if you agreed, and you can say no or change your mind any time.",
    "- **The legal reasons.** Your account, pairing, the shared features, calls, subscriptions and support rest on our agreement with you (GDPR Art. 6(1)(b)). Location sharing, usage statistics, Flirt and notifications rest on your consent, which you take back by turning them off (Art. 6(1)(a), and Art. 9(2)(a) for Flirt). Call connection reports, protection against misuse, reports and blocks rest on our legitimate interest in a service that works and is safe (Art. 6(1)(f)). You can object to these. Purchase records rest on the accounting law (Art. 6(1)(c)).",
    "- **Where it came from.** From you. From Apple or Google when you sign in with them. From Apple for your purchases. From your partner for the shared things.",
    "- **Who gets it.** Clerk, Cloudflare, PostHog and our server host work on our instructions and only to run Paeonia. Clerk (sign-in and sessions, and the sign-in code sent to your email). Cloudflare (stores your photos, videos, voice messages and drawings in the EU, keeps a backup of the database and the files in the EU, and passes calls and live drawings between you and your partner without storing them). PostHog (usage statistics, only if you agreed, stored in Frankfurt). Our database and server run on a rented server in Leipzig, Germany. Apple (Sign in with Apple, payments and subscriptions, notifications) and Google (Sign in with Google) decide for themselves how they handle these, under their own privacy policies. We do not sell data and we do not use it for advertising.",
    "- **Outside the EU.** Everything you share in Paeonia is stored in the EU. Three of our providers are American: Clerk, Cloudflare and PostHog. Clerk, Inc. keeps your sign-in details in the USA: your email address, your name, which sign-in method you use, and your sessions. Cloudflare stores your files and our backup in the EU. PostHog, Inc. stores usage statistics in Germany, if you agreed to share them. All three are certified under the EU-US Data Privacy Framework, and our agreements with them include the EU standard contractual clauses. Email contact@paeonia.no for a copy.",
    "- **How long we keep it.** While your account is active. When a relationship ends, what you shared is hidden at once and deleted after about 30 days. Your latest shared location is deleted at once. Notifications and technical records are deleted after about 30 days. Deleted data can stay in backups for up to 14 days. Usage statistics are deleted after a year without use. Reports, what we did about them, safety warnings and records of data requests are kept for three years after the case is closed. Purchase records are kept for five years after the year of the purchase, as the Norwegian accounting law requires. A block stays until the person who made it asks us to remove it, or until one of the two deletes their account. An invite that was used or ran out is deleted about 60 days after it was made. The record of who was paired with whom is deleted with the relationship content, unless a report or a block about that relationship is still kept. Access we gave without a purchase is deleted from our records one year after it ended. Our log of what our team did with an account or a case is kept for three years.",
    "- **Decisions by a computer.** Nothing about you is decided only by a computer.",
    "",
    "## Your rights",
    "",
    "You can ask us to correct your data, delete it, limit how we use it, or stop using it. You can take back a consent you gave. You can open the More tab, then Privacy and safety, in the app to ask for a correction, to turn off usage statistics, and to delete your account. You can also write to contact@paeonia.no. We answer within a month.",
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
    `Laget ${formatDate(input.generatedAt, "nb")} for kontoen \`${input.userId}\`. Bare kontoen din kan lage en nedlastingslenke, og hver lenke virker i en time. Nedlastingen slettes fra serverne våre ${EXPORT_VALID_DAYS} dager etter at den ble laget.`,
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
    "- **Innloggingsopplysninger.** Apple, Google og Clerk har innloggingsopplysningene dine, som e-postadressen din og kodene Clerk sender deg på e-post. Vi har bare det de sender oss når du logger inn.",
    "",
    "## Hvorfor vi har dataene dine, og hvem som får dem",
    "",
    "- **Hvem som er ansvarlig.** Hjalmar Karlsen, Storgata 61, 0182 Oslo, Norge. E-post: contact@paeonia.no.",
    "- **Hva vi bruker dem til.** Å lage kontoen din, koble deg til partneren din, drive de delte funksjonene, vise abonnementet ditt, sende varslene du tillater, svare på henvendelser, holde Paeonia trygt og følge loven. Vi bruker bruksstatistikk, posisjonen din og Flørt-svarene dine bare hvis du har sagt ja, og du kan si nei eller ombestemme deg når som helst.",
    "- **Det rettslige grunnlaget.** Kontoen din, sammenkoblingen, fellesfunksjonene, samtaler, abonnement og brukerstøtte bygger på avtalen vi har med deg (GDPR art. 6(1)(b)). Posisjonsdeling, bruksstatistikk, Flørt og varsler bygger på samtykket ditt, som du trekker tilbake ved å slå dem av (art. 6(1)(a), og art. 9(2)(a) for Flørt). Rapporter om samtaleforbindelsen, vern mot misbruk, rapporter og blokkeringer bygger på vår berettigede interesse i en tjeneste som virker og er trygg (art. 6(1)(f)). Du kan protestere mot dette. Kjøpsopplysninger bygger på bokføringsloven (art. 6(1)(c)).",
    "- **Hvor de kommer fra.** Fra deg. Fra Apple eller Google når du logger inn med dem. Fra Apple for kjøpene dine. Fra partneren din for de delte tingene.",
    "- **Hvem som får dem.** Clerk, Cloudflare, PostHog og serverleverandøren vår arbeider etter våre instrukser og bare for å drive Paeonia. Clerk (innlogging og økter, og innloggingskoden som sendes til e-postadressen din). Cloudflare (lagrer bildene, videoene, talemeldingene og tegningene dine i EU, har en sikkerhetskopi av databasen og filene i EU, og sender samtaler og live-tegninger mellom deg og partneren din uten å lagre dem). PostHog (bruksstatistikk, bare hvis du har sagt ja, lagret i Frankfurt). Databasen og serveren vår kjører på en leid server i Leipzig i Tyskland. Apple (Logg inn med Apple, betaling og abonnement, varsler) og Google (Logg inn med Google) bestemmer selv hvordan de håndterer dette, etter sine egne personvernregler. Vi selger ikke data, og vi bruker dem ikke til reklame.",
    "- **Utenfor EU.** Alt du deler i Paeonia, lagres i EU. Tre av leverandørene våre er amerikanske: Clerk, Cloudflare og PostHog. Clerk, Inc. oppbevarer innloggingsopplysningene dine i USA: e-postadressen din, navnet ditt, hvilken innloggingsmetode du bruker, og øktene dine. Cloudflare lagrer filene dine og sikkerhetskopien vår i EU. PostHog, Inc. lagrer bruksstatistikk i Tyskland, hvis du har sagt ja til å dele den. Alle tre er sertifisert under EU-US Data Privacy Framework, og avtalene våre med dem inneholder EUs standard personvernbestemmelser. Send e-post til contact@paeonia.no for å få en kopi.",
    "- **Hvor lenge vi har dem.** Så lenge kontoen din er aktiv. Når et forhold tar slutt, skjules det dere delte med en gang og slettes etter omtrent 30 dager. Siste delte posisjon slettes med en gang. Varsler og tekniske opplysninger slettes etter omtrent 30 dager. Slettede data kan ligge i sikkerhetskopier i opptil 14 dager. Bruksstatistikk slettes etter ett år uten bruk. Rapporter, det vi gjorde med dem, sikkerhetsvarsler og opplysninger om personvernforespørsler beholdes i tre år etter at saken er avsluttet. Kjøpsopplysninger beholdes i fem år etter utløpet av året kjøpet ble gjort, slik bokføringsloven krever. En blokkering blir stående til personen som blokkerte, ber oss om å fjerne den, eller til en av de to sletter kontoen sin. En invitasjon som er brukt eller utløpt, slettes omtrent 60 dager etter at den ble laget. Oversikten over hvem som var koblet sammen med hvem, slettes sammen med innholdet i forholdet, med mindre en rapport eller en blokkering som gjelder forholdet, fortsatt beholdes. Tilgang vi har gitt uten kjøp, slettes fra oversiktene våre ett år etter at den tok slutt. Loggen vår over hva teamet vårt har gjort med en konto eller en sak, beholdes i tre år.",
    "- **Avgjørelser fra en datamaskin.** Ingenting om deg avgjøres bare av en datamaskin.",
    "",
    "## Rettighetene dine",
    "",
    "Du kan be oss rette dataene dine, slette dem, begrense hvordan vi bruker dem eller slutte å bruke dem. Du kan trekke tilbake et samtykke du har gitt. I appen åpner du Mer-fanen og deretter Personvern og trygghet for å be om retting, slå av bruksstatistikk og slette kontoen. Du kan også skrive til contact@paeonia.no. Vi svarer innen en måned.",
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
