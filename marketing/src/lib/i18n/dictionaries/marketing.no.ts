export const marketingNo = {
  meta: {
    title: 'Paeonia - Spill sammen mellom besøk',
    description:
      'Paeonia er en privat app for par. Spill Ludo, Tegn og gjett og andre spill laget for to, svar på noen spørsmål hver dag og ta vare på minnene på ett sted.',
    ogTitle: 'Paeonia - Spill sammen mellom besøk',
    ogDescription: 'Spill, daglige spørsmål, tegninger og minner for dere to.',
    ogImageAlt: 'Paeonia, et privat sted for dere to',
  },
  hero: {
    brandName: 'Paeonia',
    title: 'Spill sammen mellom besøk',
    titleEmphasis: 'Spill sammen',
    description:
      'En privat app for dere to. Kast terningen i Ludo, gjett hverandres tegninger, svar på noen spørsmål hver dag og tell ned til neste gang dere ses.',
    primaryCta: 'Jeg er interessert',
    secondaryCta: 'Se spillene',
    note: 'Kommer snart til iPhone og iPad',
    screenshots: [
      {
        src: 'home',
        alt: 'Hjemskjermen i Paeonia med bildene og notatene til begge, nedtelling til neste besøk, en felles tegning og et kart.',
      },
      {
        src: 'ludo',
        alt: 'Et parti Ludo på et trebord med croissanter, en liten plante og en kopp kakao til hver av dem. Brikkene til hver av dem har merket de tegnet selv.',
      },
    ],
  },
  games: {
    title: 'Spillkveld for to, hvilken kveld som helst',
    description:
      'Spill laget for par. Spill samtidig, eller ta turen din når det passer. Alle spillene er med.',
    screens: [
      {
        src: 'games',
        alt: 'Spill-fanen med Ludo øverst. En grønn merkelapp sier at Elena er her nå, og at det er din tur.',
      },
      {
        src: 'draw-guess-solved',
        alt: 'Tegn og gjett etter et riktig svar. Elena tegnet hytta deres, og begge fikk poeng.',
      },
      {
        src: 'connect-four',
        alt: 'Et parti Fire på rad der brikkene til den ene har en håndtegnet stjerne og den andres et hjerte.',
      },
      {
        src: 'mind-meld',
        alt: 'Tenk likt etter at begge skrev det samme ordet, cafe, i tredje runde.',
      },
    ],
    points: [
      {
        title: 'Deres egne brikker',
        description: 'Tegn et merke én gang. Det vises på brikkene dine i alle brettspillene.',
      },
      {
        title: 'Ingen hast',
        description: 'En tur venter så lenge den må. Ingen taper et parti fordi de svarte sent.',
      },
      {
        title: 'Poeng som varer',
        description: 'Seire og poeng fortsetter å telle, så rivaliseringen starter aldri på nytt.',
      },
    ],
    listHeading: 'Alle spillene',
    list: [
      { name: 'Ludo', art: 'ludo', description: 'Kast terningen og få alle brikkene dine hjem først.' },
      { name: 'Tegn og gjett', art: 'draw-and-guess', description: 'Bytt på å tegne et ord. Den andre gjetter hva det er.' },
      { name: 'Fire på rad', art: 'connect-four', description: 'Slipp brikker og få fire på linje først.' },
      { name: 'Tenk likt', art: 'mind-meld', description: 'Skriv et ord samtidig, og finn ordet som binder dem sammen.' },
      { name: 'Prikker og streker', art: 'dots-and-boxes', description: 'Tegn streker på tur. Den som lukker flest ruter, vinner.' },
      { name: 'Ultimat bondesjakk', art: 'ultimate-tic-tac-toe', description: 'Bondesjakk inni bondesjakk. Vinn tre brett på rad.' },
      { name: 'Skrivestafett', art: 'story-chain', description: 'Skriv en historie sammen, én linje om gangen.' },
      { name: 'Rare skapninger', art: 'odd-creatures', description: 'Tegn hver deres del uten å kikke. Brett så ut skapningen.' },
    ],
  },
  moment: {
    title: 'For nettene dere sovner i hver deres by',
    description: 'Kast terningen før leggetid, finn en tegning om morgenen og tell dagene til dere ses igjen.',
  },
  live: {
    title: 'Alt skjer med en gang',
    description:
      'Når partneren din gjør noe i Paeonia, dukker det opp på telefonen din med en gang. Du trenger aldri å oppdatere.',
    screenshot: {
      src: 'home-live',
      alt: 'Hjemskjermen mens Elena har Ludo åpent. Et kort sier at Elena er her nå, og at det er din tur.',
    },
    events: ['Elena er her nå', 'Elena kastet en sekser', 'Elena gjettet tegningen din', 'Elena sendte deg et notat'],
    now: 'nå',
    items: [
      {
        title: 'Se hvem som er her',
        description: 'En grønn merkelapp viser når partneren din har et spill åpent, og Hjem viser hvilket.',
      },
      {
        title: 'Trekk kommer med en gang',
        description: 'Et terningkast, en gjetning eller et ord dukker opp på den andre telefonen mens du ser på.',
      },
      {
        title: 'Tegninger strek for strek',
        description: 'Tegn sammen, og hver strek dukker opp på den andre skjermen mens den tegnes.',
      },
      {
        title: 'Fungerer når dere er fra hverandre',
        description: 'Er partneren din ikke på nett, venter trekket ditt til de åpner appen.',
      },
    ],
  },
  features: {
    items: [
      {
        title: 'Noen små spørsmål hver dag',
        description:
          'Paeonia velger spørsmål til dere to hver dag. Skriv et svar, send en talemelding eller legg ved et bilde.',
        points: [
          'Svaret til partneren din åpnes når du har svart selv',
          'Snakk om et svar i en egen chat',
          'Se tilbake på alle svarene dere har delt',
        ],
        screens: [
          {
            src: 'questions',
            alt: 'Dagens spørsmål. Begge har svart, og svarene fra Elena er nye.',
          },
          {
            src: 'question-chat',
            alt: 'En chat om hvor dere skal på helgetur. Begge svarte København og planlegger turen.',
          },
        ],
      },
      {
        title: 'Ta vare på dagene dere vil huske',
        description:
          'Lagre en dag med bilder og dato. Dere skriver hvert deres notat, så hvert minne har begge sider.',
        points: [
          'Begge kan legge til bilder',
          'Del et bilde som en historie i 24 timer',
          'Gamle historier blir liggende i Minner',
        ],
        screens: [
          {
            src: 'memories',
            alt: 'En tidslinje med felles minner og bilder fra en hyttehelg og en tur til Bergen.',
          },
          {
            src: 'memory',
            alt: 'Minnet fra hyttehelgen med et bilde av en hytte ved et vann og et notat fra hver av dem.',
          },
        ],
      },
    ],
  },
  extras: {
    heading: 'Også i Paeonia',
    items: [
      {
        title: 'Nedtelling',
        description: 'Se hvor mange dager det er til dere ses, og hvor lenge dere har vært sammen.',
      },
      {
        title: 'Felles tegning',
        description: 'Tegn noe lite. Det dukker opp i widgeten på hjemskjermen til partneren din.',
      },
      {
        title: 'Avstand',
        description: 'Når dere begge deler posisjon, ser dere hvor langt det er mellom dere.',
      },
      {
        title: 'En snill streak',
        description: 'Gjør én liten ting hver dag. Går en dag tapt, holder en streak-frys flammen i gang.',
      },
    ],
  },
  privacy: {
    heading: 'Bare dere to',
    description: 'Paeonia er laget rundt ett forhold. Andre kan ikke finne dere i appen.',
    items: [
      {
        title: 'Ingen offentlige profiler',
        description: 'Det finnes ingen følgere, ikke personsøk og ingen foreslåtte personer.',
      },
      {
        title: 'Koblet sammen med én invitasjon',
        description: 'Én av dere sender en invitasjonslenke til den andre. Lenken brukes bare til å koble dere sammen.',
      },
      {
        title: 'Ingen reklame',
        description: 'Paeonia har ingen reklame og sporer deg ikke på tvers av andre apper.',
      },
    ],
    link: 'Les personvernerklæringen',
  },
  faq: {
    heading: 'Spørsmål og svar',
    description: 'Korte svar om hva Paeonia er, hvordan spillene fungerer og hva det koster.',
    contactLink: 'Spør oss om noe annet',
    items: [
      {
        question: 'Kan vi bruke Paeonia nå?',
        answers: [
          'Den første versjonen gjøres klar nå.',
          'Når den er klar, viser denne siden hvordan dere kommer i gang.',
        ],
      },
      {
        question: 'Må vi begge være på nett for å spille?',
        answers: [
          'Nei. Alle spillene fungerer når dere tar tur, så dere kan spille på tvers av tidssoner.',
          'Når dere er i samme spill, ser dere hverandres trekk mens de skjer.',
        ],
      },
      {
        question: 'Må begge betale?',
        answers: [
          'Nei. Ett abonnement dekker dere begge. Den som blir med gjennom en invitasjon, betaler ikke.',
          'Alle spill og funksjoner er med. Det eneste ekstra kjøpet er frivillig. Hvis rekken deres tar slutt, kan dere betale én gang for å hente den tilbake.',
        ],
      },
      {
        question: 'Er Paeonia privat?',
        answers: [
          'Ja. Hvert felles rom tilhører ett par.',
          'Det finnes ingen følgere, offentlige profiler eller måter å lete etter folk inne i appen.',
        ],
      },
      {
        question: 'Hvordan fungerer invitasjoner?',
        answers: [
          'En invitasjon brukes bare for å koble deg sammen med partneren din.',
          'Én av dere lager det felles rommet og inviterer den andre. Paeonia har ikke personsøk, offentlige profiler eller foreslåtte personer.',
        ],
      },
      {
        question: 'Finnes Paeonia for Android?',
        answers: ['Nei. Foreløpig finnes Paeonia bare for iPhone og iPad.'],
      },
    ],
  },
  contact: {
    heading: 'Interessert i Paeonia?',
    description: 'Send oss en melding hvis du vil vite når appen kommer, eller hvis du har et spørsmål.',
    button: 'Send en melding',
    emailSubject: 'Interessert i Paeonia',
    emailBody: 'Hei!\n\nJeg er interessert i Paeonia og vil gjerne vite mer.',
  },
  footer: {
    copyright: '© 2026 Paeonia',
    logoAlt: 'Paeonia, et privat sted for dere to.',
    tagline: 'Et privat sted for to mellom besøk.',
    note: 'Laget med omtanke for private forhold.',
    headerNavigationLabel: 'Hovednavigasjon',
    footerNavigationLabel: 'Bunnavigasjon',
    privacy: 'Personvern',
    terms: 'Vilkår',
    support: 'Hjelp',
  },
  join: {
    title: 'Du er invitert til Paeonia',
    message: 'Åpne Paeonia for å se hvem som inviterte deg, og velg om du vil bli med.',
    invalidTitle: 'Denne invitasjonslenken ser ikke riktig ut',
    invalidMessage: 'Be partneren din dele en ny invitasjon fra Paeonia.',
    missingMessage: 'Åpne hele invitasjonslenken partneren din delte med deg.',
    code: 'Invitasjonskode',
    open: 'Åpne Paeonia',
    install: 'Last ned Paeonia fra App Store',
    installNote: 'Har du ikke Paeonia ennå? Vi kopierer invitasjonen når du trykker på App Store-knappen. Åpne Paeonia når appen er lastet ned, og trykk på Lim inn.',
    help: 'Trenger du hjelp?',
    opening: 'Åpner invitasjonen din …',
  },
} as const;
