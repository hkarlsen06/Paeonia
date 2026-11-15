# Marketing app contract

What `marketing/` must serve for the iOS app to work. Paeonia uses `paeonia.no` for the public site and Universal Links. The Convex backend lives at `api.paeonia.no` and `actions.paeonia.no` (see `backend/AGENTS.md`). Do not route backend traffic through the marketing app. Sign-in runs through Clerk, so neither host serves an OAuth callback.

## Routes the app depends on

- `/privacy`, `/terms`, `/support`: stable App Store and in-app URLs. `functions/[path].js` redirects each to `/no/<page>/` or `/en/<page>/` by browser language. Support email is `support@paeonia.no`. The policy and terms must match shipped behavior, and the release owner arranges any legal review before publication.
- `/accessibility`: the static page describes current native app support and known barriers. Review it with `docs/accessibility-report.md` before publishing accessibility metadata.
- `/join/*`: invite links such as `https://paeonia.no/join/ABCD1234`. `_redirects` rewrites every `/join/*` to the static `/join/` page, which keeps the code and offers a `paeonia://join/<code>` button. The page never reveals invite details, because preview and acceptance belong in the app and backend. When the app is not installed, its App Store button copies `https://paeonia.no/join/<code>` to the clipboard, because iOS has no way to carry a link through an App Store install. On first launch the welcome screen sees the link on the clipboard and offers the system Paste button in place of "I was invited" (`WelcomeView`), which reads it without a permission prompt. The App Store listing is `https://apps.apple.com/us/app/paeonia/id6779833892`.

## Apple App Site Association

`/.well-known/apple-app-site-association` must be served over HTTPS without authentication or redirect, with status 200 and `Content-Type: application/json` (set in `marketing/static/_headers`). Its `details` entry holds `appID` `48ZSLD4RMP.no.paeonia.app` and paths `/join` and `/join/*`. Update the file in the same change as any new Universal Link route in the app.

## Cloudflare Pages

The root `wrangler.toml` pins the `paeonia` project, compatibility date and `marketing/out/` output directory. The Pages Git build runs from the repository root and reads this file, so it overrides the dashboard. Change the output directory there, not in the dashboard.

Keep the root `functions/` a real directory, because Wrangler resolves generated bundle paths incorrectly through a symlink. Deploy from the repository root with `bun run pages:deploy:marketing`, so Wrangler finds `functions/` and the routing rules in `marketing/static/_routes.json`. No app-required endpoint may depend on a server runtime other than those Pages Functions.

The dev server (`bun run dev`, port 3001) does not read `_redirects` or run `functions/`, so `/join/<code>` and the unprefixed `/privacy`, `/terms` and `/support` only work on Cloudflare. To test them, build and run `bunx wrangler pages dev` from the repository root.

## Must not live in the marketing app

Convex admin keys, Clerk or OAuth secrets, authenticated app data, invite lookup, and relationship or subscription state.

## After a deploy

```bash
curl -i https://paeonia.no/.well-known/apple-app-site-association
curl -I https://paeonia.no/join/test-code
curl -I -H 'Accept-Language: nb' https://paeonia.no/privacy
```

The first returns 200 with `application/json`. The second resolves to a page, not a 404. The third redirects to `/no/privacy/`.
