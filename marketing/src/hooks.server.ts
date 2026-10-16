import type { Handle } from '@sveltejs/kit/hooks';

// Every prerendered page gets the lang of its locale. Pages outside /no/ are English.
export const handle: Handle = ({ event, resolve }) => {
  const lang = event.url.pathname.startsWith('/no/') || event.url.pathname === '/no' ? 'no' : 'en';
  return resolve(event, { transformPageChunk: ({ html }) => html.replace('%paeonia.lang%', lang) });
};
