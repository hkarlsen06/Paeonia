export const legalNo = {
  contactEmail: 'contact@paeonia.no',
  supportEmail: 'support@paeonia.no',
  privacy: {
    meta: {
      title: 'Personvern',
      description: 'Den fullstendige personvernteksten er ikke klar ennå.',
    },
    title: 'Personvern',
    updated: 'Utkast',
    sections: [
      {
        heading: 'Hva denne siden vil forklare',
        paragraphs: [
          'Paeonia bygges som en privat app for par.',
          'Før appen er klar, blir denne siden erstattet med en tydelig personverntekst.',
        ],
      },
      {
        heading: 'Trenger du hjelp',
        paragraphs: ['Hvis du har et spørsmål om personvern, send e-post til contact@paeonia.no.'],
      },
    ],
  },
  terms: {
    meta: {
      title: 'Vilkår',
      description: 'De fullstendige vilkårene er ikke klare ennå.',
    },
    title: 'Vilkår',
    updated: 'Utkast',
    sections: [
      {
        heading: 'Hva denne siden vil forklare',
        paragraphs: [
          'Paeonia er ikke åpen for alle ennå.',
          'Før appen er klar, blir denne siden erstattet med tydelige vilkår.',
        ],
      },
      {
        heading: 'Trenger du hjelp',
        paragraphs: ['Hvis du har spørsmål om Paeonia, send e-post til contact@paeonia.no.'],
      },
    ],
  },
} as const;
