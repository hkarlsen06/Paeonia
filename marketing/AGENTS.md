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
