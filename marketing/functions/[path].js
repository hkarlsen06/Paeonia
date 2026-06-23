import { redirectToPreferredLocale } from './_locale.js';

const localizedEntryPaths = new Set(['privacy', 'terms', 'support']);

export function onRequest({ request, params }) {
  const path = params.path;

  if (!localizedEntryPaths.has(path)) {
    return new Response('Not found', { status: 404 });
  }

  return redirectToPreferredLocale(request, `/${path}`);
}
