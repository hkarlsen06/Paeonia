export const marketingEn = {
  meta: {
    title: 'Paeonia - Feel close between visits',
    description: 'Paeonia is a private app for couples who want to feel close between visits.',
    ogTitle: 'Paeonia - Feel close between visits',
    ogDescription: 'Daily questions, shared memories, drawings, and countdowns in one private place.',
    ogImageAlt: 'Paeonia, a private place for the two of you',
  },
  hero: {
    brandName: 'Paeonia',
    title: 'Feel close between visits',
    titleEmphasis: 'close',
    description:
      'A private app for the two of you. Answer a few questions a day, keep your memories, and count down to the next time you meet.',
    primaryCta: "I'm interested",
    secondaryCta: 'See inside',
    note: 'Coming soon to iPhone',
    screenshotAlt:
      'The Paeonia home screen with a map of where you both are, today\'s questions, a countdown to the next visit, and a shared drawing.',
  },
  features: {
    eyebrow: 'Inside the app',
    items: [
      {
        label: 'Questions',
        title: 'Two small questions a day',
        description:
          'Paeonia picks two questions for you every day. Write your answer, record a voice note, or add a photo.',
        points: [
          'Your partner\'s answer opens once you have answered too',
          'Talk about an answer in its own chat',
          'Look back at every answer you have shared',
        ],
        screens: [
          {
            src: 'questions',
            alt: 'Today\'s questions in Paeonia, with both partners\' answers to a question about the sounds around them.',
          },
        ],
      },
      {
        label: 'Memories',
        title: 'Keep the visits you want to remember',
        description:
          'Save a day with photos and a date. You each write your own note, so every memory has both sides.',
        points: ['Both of you can add photos', 'Sorted by month, newest first'],
        screens: [
          {
            src: 'memories',
            alt: 'A timeline of shared memories with photos from a weekend away, a café, and a concert.',
          },
          {
            src: 'memory',
            alt: 'One memory with a photo of a fjord and a note from each partner.',
          },
        ],
      },
    ],
  },
  extras: {
    heading: 'Also in Paeonia',
    items: [
      {
        title: 'Countdown',
        description: 'See how many days are left until you meet, and how long you have been together.',
      },
      {
        title: 'Shared drawing',
        description: 'Draw something small. It shows up in the widget on your partner\'s Home Screen.',
      },
      {
        title: 'Distance',
        description: 'When you both share your location, you can see how far apart you are.',
      },
    ],
  },
  privacy: {
    eyebrow: 'Privacy',
    heading: 'Just the two of you',
    description: 'Paeonia is built around one relationship. Other people cannot find you in the app.',
    items: [
      {
        title: 'No public profiles',
        description: 'There are no followers, no people search, and no suggested people.',
      },
      {
        title: 'Paired with one invite',
        description: 'One of you sends an invite link to the other. The link is only for pairing.',
      },
      {
        title: 'One subscription for both',
        description: 'The plan is that one paying partner unlocks Paeonia for both of you.',
      },
    ],
    link: 'Read the privacy policy',
  },
  faq: {
    eyebrow: 'FAQ',
    heading: 'Questions and answers',
    description: 'Short answers about what Paeonia is, how pairing works, and what it costs.',
    contactLink: 'Ask us something else',
    items: [
      {
        question: 'Can we use Paeonia now?',
        answers: [
          'The first release is being prepared now.',
          'When it is ready, this page will show you how to get started.',
        ],
      },
      {
        question: 'Is Paeonia private?',
        answers: [
          'Yes. Each shared space belongs to one couple.',
          'There are no followers, public profiles, or ways to browse for people inside the app.',
        ],
      },
      {
        question: 'How do invites work?',
        answers: [
          'An invite is only for pairing with your partner.',
          'One person creates the shared space, then invites the other. Paeonia does not have people search, public profiles, or suggested people.',
        ],
      },
      {
        question: 'Do both people need to pay?',
        answers: [
          'The plan is that one paying partner unlocks Paeonia for both of you.',
          'So you only need one subscription between the two of you.',
        ],
      },
      {
        question: 'Who is Paeonia for?',
        answers: [
          'Couples who want a shared place to feel close, especially when they spend time apart.',
        ],
      },
      {
        question: 'Is there an Android version?',
        answers: ['No. Paeonia is only for iPhone for now.'],
      },
    ],
  },
  contact: {
    heading: 'Interested in Paeonia?',
    description: 'Send us a note if you want to hear when it launches, or if you have a question.',
    button: 'Send a note',
    emailSubject: 'Interested in Paeonia',
    emailBody: 'Hi!\n\nI am interested in Paeonia and would like to know more.',
  },
  footer: {
    copyright: '© 2026 Paeonia',
    logoAlt: 'Paeonia, a private place for the two of you.',
    tagline: 'A private place for two people between visits.',
    note: 'Made with care for private relationships.',
    headerNavigationLabel: 'Main navigation',
    footerNavigationLabel: 'Footer navigation',
    privacy: 'Privacy',
    terms: 'Terms',
    support: 'Support',
  },
  support: {
    title: 'Support',
    description: 'For help with Paeonia, your account, or a partner invite, email us and we will help.',
    emailLabel: 'Email',
    back: 'Back to Paeonia',
  },
  join: {
    title: "You've been invited to Paeonia",
    message: 'Open Paeonia to see who invited you and choose whether to join.',
    invalidTitle: "This invite link doesn't look right",
    invalidMessage: 'Ask your partner to share a new Paeonia invite.',
    missingMessage: 'Open the full invite link your partner shared with you.',
    code: 'Invite code',
    open: 'Open Paeonia',
    install: 'Get Paeonia on the App Store',
    help: 'Need help?',
    opening: 'Opening your invite…',
  },
} as const;
