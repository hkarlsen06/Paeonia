import { defineParams } from '@sveltejs/kit/params';
import { locales, type Locale } from '#lib/i18n/config.ts';

export const params = defineParams({
  locale: (param) => locales.find((locale): locale is Locale => locale === param),
});
