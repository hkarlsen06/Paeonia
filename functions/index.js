import { redirectToPreferredLocale } from './_locale.js';

export function onRequest({ request }) {
  return redirectToPreferredLocale(request);
}
