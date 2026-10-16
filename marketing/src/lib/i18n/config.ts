export const locales = ['no', 'en'] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = 'en';

export const localeNames: Record<Locale, string> = {
  no: 'Norsk',
  en: 'English',
};
