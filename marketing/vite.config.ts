import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  // A build writes to out/. Without this, every build would reload pages open in the dev server.
  server: { watch: { ignored: ['**/out/**'] } },
  plugins: [
    tailwindcss(),
    sveltekit({
      compilerOptions: {
        runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true),
      },
      // Cloudflare Pages serves `out`, and functions/ sits next to it (wrangler.toml).
      adapter: adapter({ pages: 'out', assets: 'out' }),
      paths: { origin: 'https://paeonia.no' },
      prerender: { entries: ['*', '/en/', '/no/'] },
    }),
  ],
});
