# Marketing agent guidance

Paths are relative to the repository root. Read `docs/marketing-app-contract.md` for routing or deployment changes.

## Marketing Site Guidelines

The `marketing/` app is a static SvelteKit 3 site. It moved off Next.js on 2026-10-16, so this is a deliberate difference from Tidex.

- Use SvelteKit with `@sveltejs/adapter-static`. Every page is prerendered, and only `/join/` ships client code (`csr = true` in `src/routes/join/+page.ts`).
- Configure SvelteKit through the `sveltekit()` plugin in `vite.config.ts`. SvelteKit 3 has no `svelte.config.js`.
- Import shared code through `#lib/...` with the file extension, for example `#lib/paths.ts`.
- Deploy to Cloudflare Pages.
- Keep public/legal/support pages in the marketing app.
- Use `paeonia.no` as the canonical domain.
- Use stable routes for App Store and in-app references:
  - `/`
  - `/privacy`
  - `/terms`
  - `/support`
  - `/join/[inviteCode]` or another universal-link route chosen before implementation
- Avoid server-only runtime dependencies unless the deployment target changes.
- Keep legal/version metadata structured once legal pages exist.

## App Store and marketing copy

- Before you change the App Store description, subtitle, keywords, promotional text, screenshot captions or other marketing copy, start two research agents in parallel: a teardown of competing couples apps' listings, and ASO evidence and case studies with measured results. Judge their reports, then write the copy from what they found.
- Screenshots are real captures from the app, never mockups. The test users have profile photos. Where two avatars sit side by side, the first account (Hjalmar, looking right) sits left of the second (Elena, looking left), so they face each other. The app puts the signed-in user first, so capture signed in as Hjalmar.
- Seed screenshot content through the app's own Convex mutations as each account, in English for the English set. Website screenshots live in `marketing/static/screens/` as 780 px WebP.
- App Store screenshots come from `scripts/capture-app-store-screenshots.py` and `scripts/render-3d-screenshots.mjs`. Captions never use gendered pronouns such as "her" or "his". Say "your partner".
- Show states that sell the app: a streak around 400 days (a short streak suggests the app is not for lasting relationships) and today's question ready, not done. A Home Screen shot shows Paeonia, not iOS: a dark calm wallpaper, only Paeonia in the dock, and the page filled with Paeonia widgets.
- Any drawing on screen is creative and cute, made by a skilled hand. Never a stick figure.
