import { getMarketingDictionary } from '#lib/i18n/dictionaries/index.ts';

export function load({ params }) {
  return { locale: params.locale, dictionary: getMarketingDictionary(params.locale) };
}
