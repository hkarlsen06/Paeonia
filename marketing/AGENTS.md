# Marketing agent guidance

Paths are relative to the repository root. Read `docs/marketing-app-contract.md` for routing or deployment changes.

## Marketing Site Guidelines

The `marketing/` app should follow Tidex's simple static-site pattern:

- Use Next.js with static export.
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
