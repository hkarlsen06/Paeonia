export const legalEn = {
  contactEmail: 'contact@paeonia.no',
  supportEmail: 'support@paeonia.no',
  privacy: {
    meta: {
      title: 'Privacy Policy',
      description: 'The full privacy policy is not ready yet.',
    },
    title: 'Privacy Policy',
    updated: 'Draft',
    sections: [
      {
        heading: 'What this page will cover',
        paragraphs: [
          'Paeonia is being built as a private app for couples.',
          'Before the app is ready, this page will be replaced with a clear privacy policy.',
        ],
      },
      {
        heading: 'Need help',
        paragraphs: ['If you have a privacy question, email contact@paeonia.no.'],
      },
    ],
  },
  terms: {
    meta: {
      title: 'Terms of Service',
      description: 'The full terms are not ready yet.',
    },
    title: 'Terms of Service',
    updated: 'Draft',
    sections: [
      {
        heading: 'What this page will cover',
        paragraphs: [
          'Paeonia is not open to the public yet.',
          'Before the app is ready, this page will be replaced with clear terms of service.',
        ],
      },
      {
        heading: 'Need help',
        paragraphs: ['If you have a question about Paeonia, email contact@paeonia.no.'],
      },
    ],
  },
} as const;
