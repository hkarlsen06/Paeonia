import type { Locale } from './i18n/config.ts';

/** A path inside one locale, with the trailing slash the static export uses: `/en/privacy/`. */
export function buildLocalizedPath(locale: Locale, path = '') {
  const trimmed = path.replace(/^\/+|\/+$/g, '');
  return trimmed ? `/${locale}/${trimmed}/` : `/${locale}/`;
}
