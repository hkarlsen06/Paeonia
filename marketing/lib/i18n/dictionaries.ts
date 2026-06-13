import type { Locale } from './config';

interface LegalSection {
  title: string;
  body: string[];
}

interface LegalContent {
  title: string;
  description: string;
  updated: string;
  sections: LegalSection[];
}

export interface Dictionary {
  meta: {
    title: string;
    description: string;
  };
  home: {
    kicker: string;
    title: string;
    lede: string;
    primaryAction: string;
    secondaryAction: string;
    previewLabel: string;
    previewQuestion: string;
    previewPartner: string;
    previewAnswerOne: string;
    previewAnswerTwo: string;
    sectionsLabel: string;
    sections: Array<{
      title: string;
      body: string;
    }>;
  };
  privacy: LegalContent;
  terms: LegalContent;
  support: {
    title: string;
    description: string;
    kicker: string;
    back: string;
  };
}

const english: Dictionary = {
  meta: {
    title: 'Paeonia',
    description: 'A private place for the two of you.',
  },
  home: {
    kicker: 'Private by design',
    title: 'A private place for the two of you.',
    lede:
      'Paeonia helps couples stay close through daily check-ins, shared memories, voice notes, milestone countdowns, and a widget that feels alive.',
    primaryAction: 'Contact support',
    secondaryAction: 'Privacy',
    previewLabel: 'Paeonia check-in preview',
    previewQuestion: 'What made you think of us today?',
    previewPartner: 'Partner answer',
    previewAnswerOne: 'Saved privately. Reveals when both have answered.',
    previewAnswerTwo: 'Waiting for the app.',
    sectionsLabel: 'Paeonia product pillars',
    sections: [
      {
        title: 'Small rituals',
        body: 'Daily questions and streak reminders should feel supportive, not punishing.',
      },
      {
        title: 'Shared memory',
        body: 'A timeline for notes, images, and voice that stays private to the relationship.',
      },
      {
        title: 'Built to last',
        body: 'Local-first storage and careful sync should make the app feel fast and reliable.',
      },
    ],
  },
  privacy: {
    title: 'Privacy Policy',
    description:
      'This placeholder explains the privacy surface that must be completed before App Store submission.',
    updated: 'Draft',
    sections: [
      {
        title: 'Private relationship content',
        body: [
          'Paeonia is expected to store relationship content such as answers, notes, photos, drawings, voice notes, and milestones.',
          'The final policy must explain what is collected, why it is collected, how long it is retained, and how users can delete it.',
        ],
      },
      {
        title: 'No ads or tracking',
        body: [
          'The MVP plan does not include advertising, IDFA access, or third-party tracking.',
          'Functional database state needed to run the app is separate from ad tracking.',
        ],
      },
    ],
  },
  terms: {
    title: 'Terms of Service',
    description:
      'This placeholder marks the terms route needed for App Store and in-app links.',
    updated: 'Draft',
    sections: [
      {
        title: 'Private couple space',
        body: [
          'Paeonia is planned as a private one-to-one app for couples with invite-and-accept pairing.',
          'The final terms should cover acceptable use, account deletion, subscriptions, and relationship disconnection.',
        ],
      },
      {
        title: 'Subscriptions',
        body: [
          'The MVP plan uses a paid subscription where one paying partner grants access to the couple.',
          'The final terms must describe billing, renewal, cancellation, trials, and restore behavior.',
        ],
      },
    ],
  },
  support: {
    title: 'Support',
    description:
      'For now, use email for product questions, privacy requests, and account support.',
    kicker: 'Support',
    back: 'Back to Paeonia',
  },
};

const norwegian: Dictionary = {
  meta: {
    title: 'Paeonia',
    description: 'Et privat sted for dere to.',
  },
  home: {
    kicker: 'Privat fra starten',
    title: 'Et privat sted for dere to.',
    lede:
      'Paeonia hjelper par med å holde nærheten gjennom daglige innsjekker, minner, stemmenotater, milepæler og en widget som føles levende.',
    primaryAction: 'Kontakt support',
    secondaryAction: 'Personvern',
    previewLabel: 'Forhåndsvisning av Paeonia-innsjekk',
    previewQuestion: 'Hva fikk deg til å tenke på oss i dag?',
    previewPartner: 'Partnersvar',
    previewAnswerOne: 'Lagret privat. Vises når begge har svart.',
    previewAnswerTwo: 'Venter på appen.',
    sectionsLabel: 'Paeonia produktpilarer',
    sections: [
      {
        title: 'Små ritualer',
        body: 'Daglige spørsmål og streak-påminnelser skal føles støttende, ikke straffende.',
      },
      {
        title: 'Felles minner',
        body: 'En tidslinje for notater, bilder og stemme som er privat for forholdet.',
      },
      {
        title: 'Bygget for å vare',
        body: 'Lokal lagring først og ryddig synk skal gjøre appen rask og pålitelig.',
      },
    ],
  },
  privacy: {
    title: 'Personvernerklaering',
    description:
      'Denne plassholderen viser personvernflaten som må ferdigstilles før App Store-innsending.',
    updated: 'Utkast',
    sections: [
      {
        title: 'Privat forholdsinnhold',
        body: [
          'Paeonia forventes å lagre forholdsinnhold som svar, notater, bilder, tegninger, stemmenotater og milepæler.',
          'Den endelige erklæringen må forklare hva som samles inn, hvorfor, hvor lenge det lagres og hvordan brukere kan slette det.',
        ],
      },
      {
        title: 'Ingen annonser eller sporing',
        body: [
          'MVP-planen inkluderer ikke annonser, IDFA-tilgang eller tredjepartssporing.',
          'Funksjonell databasetilstand som trengs for å drive appen er adskilt fra annonsesporing.',
        ],
      },
    ],
  },
  terms: {
    title: 'Vilkår',
    description:
      'Denne plassholderen markerer vilkårsruten som trengs for App Store og lenker i appen.',
    updated: 'Utkast',
    sections: [
      {
        title: 'Privat parrom',
        body: [
          'Paeonia planlegges som en privat en-til-en-app for par med invitasjon og aksept.',
          'De endelige vilkårene bør dekke akseptabel bruk, kontosletting, abonnementer og frakobling av forhold.',
        ],
      },
      {
        title: 'Abonnementer',
        body: [
          'MVP-planen bruker et betalt abonnement der én betalende partner gir paret tilgang.',
          'De endelige vilkårene må beskrive betaling, fornyelse, kansellering, prøveperiode og gjenoppretting.',
        ],
      },
    ],
  },
  support: {
    title: 'Support',
    description:
      'Foreløpig brukes e-post til produktspørsmål, personvernforespørsler og kontohjelp.',
    kicker: 'Support',
    back: 'Tilbake til Paeonia',
  },
};

const dictionaries: Record<Locale, Dictionary> = {
  en: english,
  no: norwegian,
};

export function getDictionary(locale: Locale) {
  return dictionaries[locale];
}
