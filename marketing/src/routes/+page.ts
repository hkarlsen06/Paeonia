import { redirect } from '@sveltejs/kit';

// functions/index.js normally picks the visitor's language before this page is reached.
export function load() {
  redirect(307, '/en/');
}
