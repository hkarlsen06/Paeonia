import { locales } from './config';

export function generateLocaleStaticParams() {
  if (process.env.NODE_ENV === 'development') {
    return [];
  }

  return locales.map((locale) => ({ locale }));
}
