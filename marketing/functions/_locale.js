const defaultLocale = 'en';

const localeAliases = {
  en: 'en',
  no: 'no',
  nb: 'no',
  nn: 'no',
};

export function redirectToPreferredLocale(request, path = '/') {
  const requestUrl = new URL(request.url);
  const locale = getPreferredLocale(request.headers.get('Accept-Language'));
  const localizedPath = path === '/' ? `/${locale}/` : `/${locale}${path}/`;

  requestUrl.pathname = localizedPath;

  return new Response(null, {
    status: 302,
    headers: {
      Location: requestUrl.toString(),
      Vary: 'Accept-Language',
      'Cache-Control': 'private, no-store',
    },
  });
}

function getPreferredLocale(acceptLanguage) {
  if (!acceptLanguage) {
    return defaultLocale;
  }

  const languages = acceptLanguage
    .split(',')
    .map((entry, index) => {
      const [rawLanguage, ...parameters] = entry.trim().split(';');
      const language = rawLanguage.toLowerCase();
      let quality = 1;

      for (const parameter of parameters) {
        const [key, value] = parameter.trim().split('=');

        if (key === 'q') {
          quality = Number.parseFloat(value);
        }
      }

      return { language, quality, index };
    })
    .filter(({ language, quality }) => language && language !== '*' && quality > 0)
    .sort((left, right) => right.quality - left.quality || left.index - right.index);

  for (const { language } of languages) {
    const primaryLanguage = language.split('-')[0];
    const locale = localeAliases[primaryLanguage];

    if (locale) {
      return locale;
    }
  }

  return defaultLocale;
}
