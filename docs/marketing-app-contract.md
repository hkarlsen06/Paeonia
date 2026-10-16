# Marketing App Contract

This document defines what `marketing/` must serve for the iOS app to work correctly.

Paeonia uses `paeonia.no` as the public marketing and Universal Link domain. The Convex backend lives separately at `api.paeonia.no`.

## Required Domains

### `paeonia.no`

Owned by the static marketing site on Cloudflare Pages.

Required for:

- public landing page
- App Store support, privacy, and terms links
- invite Universal Links
- fallback pages when the app is not installed

### `api.paeonia.no`

Owned by the self-hosted Convex backend (see `backend/AGENTS.md`).

Required for:

- Convex client API (mutations and actions called by the iOS app)
- Convex file storage upload URLs

`actions.paeonia.no` serves the Convex HTTP actions: signed media URLs (`GET /media`) and Apple App Store server notifications (`POST /apple/server-notifications`). Sign-in runs through Clerk, so the backend hosts no OAuth callback.

Do not route backend traffic through the marketing app.

## Implementation Structure

The marketing app is a static SvelteKit 3 site built with `@sveltejs/adapter-static` into `marketing/out/`:

- keep routes under `marketing/src/routes/`
- keep localized public pages under `marketing/src/routes/[locale=locale]/`. The `locale` matcher is in `marketing/src/params.ts`
- keep fallback app-link pages such as `/join` as explicit routes under `marketing/src/routes/`
- keep shared page components under `marketing/src/lib/components/`
- keep localization setup under `marketing/src/lib/i18n/`
- split dictionaries by domain and locale under `marketing/src/lib/i18n/dictionaries/`
- keep route/path helpers in `marketing/src/lib/`
- keep static deployment files in `marketing/static/`
- keep Cloudflare Pages Functions in `marketing/functions/`

Avoid reintroducing a single large dictionary file as the site grows. Add new marketing copy to the marketing dictionaries, legal copy to the legal dictionaries, and app-required static files to `public/`.

## Required Marketing Endpoints

### `/`

Purpose: public landing page.

Current behavior: `functions/index.js` sends the visitor to `/no/` when the browser prefers Norwegian (`nb`, `nn` or `no` in `Accept-Language`) and to `/en/` otherwise.

### `/en` and `/no`

Purpose: localized landing pages.

Current behavior: the marketing page, with games first, in English and Norwegian. The screenshots in `public/screens/` are real app screens from the Hjalmar and Elena test accounts, in English for both locales.

Production behavior: localized marketing pages.

### `/join`

Purpose: fallback page for invite links.

Current pre-launch behavior: preserve the invite code, offer an explicit `paeonia://join/<code>` button when Safari keeps the Universal Link in the browser, and tell private-beta users to install from their beta invitation before reopening the link.

Production behavior: if the app is installed, iOS should open Paeonia through Universal Links. If the app is not installed, the fallback page offers the canonical App Store listing at `https://apps.apple.com/us/app/paeonia/id6779833892` alongside the retained invite code.

Do not reveal invite details on the public web page. Invite preview and acceptance belong inside the app/backend flow.

### `/join/*`

Purpose: invite links with invite codes, for example:

```text
https://paeonia.no/join/ABCD1234
```

Static-export behavior: rewrite all `/join/*` paths to the static `/join/` page.

The path must stay covered by the Apple App Site Association file so iOS can open installed apps directly.

### `/privacy`

Purpose: stable App Store and in-app privacy URL.

Current behavior: redirect to `/no/privacy/` or `/en/privacy/` by browser language, through `functions/[path].js`.

Production behavior: final privacy policy.

The policy covers private relationship content, account deletion, precise location sharing if enabled, daily voice answers, photos, widget drawings, subscriptions, support/moderation access, reports, exports, retention, and the no-ad/no-tracking posture. Keep it aligned with shipped behavior and have the release owner arrange any required legal review before publication.

### `/terms`

Purpose: stable App Store and in-app terms URL.

Current behavior: redirect to `/no/terms/` or `/en/terms/` by browser language, through `functions/[path].js`.

Production behavior: final terms of service.

The terms cover subscriptions, one-partner-pays access, restore behavior, account deletion, leaving a relationship, acceptable use, moderation/reporting, and support limitations. Keep them aligned with shipped behavior and have the release owner arrange any required legal review before publication.

### `/support`

Purpose: stable App Store and in-app support URL.

Current behavior: redirect to `/no/support/` or `/en/support/` by browser language, through `functions/[path].js`.

Production behavior: support page with at least one reachable support channel.

Current support email:

```text
support@paeonia.no
```

## Required Well-Known Files

### `/.well-known/apple-app-site-association`

Purpose: Apple Associated Domains.

Required for:

- Universal Links for invite links

Serving requirements:

- HTTPS
- public, no authentication
- status `200`
- no redirect
- path exactly `/.well-known/apple-app-site-association`
- content type `application/json`
- valid JSON

Required contents for the current app:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "48ZSLD4RMP.no.paeonia.app",
        "paths": ["/join", "/join/*"]
      }
    ]
  }
}
```

If we add more Universal Link routes, this file must be updated in the same change as the iOS route handling.

### `/.well-known/security.txt`

Purpose: standard security contact file.

This is not required for the app to launch, but it is useful and should stay available once added.

## Required Cloudflare Pages Files

`marketing/wrangler.toml` pins the `paeonia` project, compatibility date, and `out/` deployment directory.

### `/_headers`

Purpose: static response headers.

Required behavior:

- `/.well-known/apple-app-site-association` must be served as `application/json`.
- basic security headers should apply globally.

Current important headers:

```text
/.well-known/apple-app-site-association
  Content-Type: application/json
  Cache-Control: public, max-age=3600
```

### `/_redirects`

Purpose: static routing for Cloudflare Pages.

Required behavior:

- `/privacy` redirects to the current privacy page.
- `/terms` redirects to the current terms page.
- `/support` redirects to the current support page.
- `/join/*` rewrites to `/join/` while keeping the public invite path valid for Universal Links.
- `/.well-known/*` passes through directly.

## Local Development

`bun run dev` serves the site at `http://localhost:3001` with Vite. The dev server does not read `_redirects` or run `functions/`, so `/join/<code>` and the unprefixed `/privacy`, `/terms` and `/support` only work on Cloudflare. To test those, build and run `npx wrangler pages dev out` from `marketing/`.

`bun run build` writes to `marketing/out/` and `.svelte-kit/`. It doesn't touch the dev server's files, so it is safe to build while `bun run dev` runs.

## Optional But Expected Static Files

These are not critical to app auth or pairing, but should remain present for a complete public site:

- `/robots.txt`
- `/sitemap.xml`
- `/site.webmanifest`

## Branding Assets

The canonical public mark, lockup, favicon SVG, Open Graph image, and web manifest are present under `marketing/static/` and referenced by `marketing/src/app.html` and `marketing/src/lib/components/PageHead.svelte`.

Before App Store launch, decide whether dedicated PNG favicon sizes and Apple touch icons are needed in addition to the canonical SVG:

- `/favicon-32x32.png`
- `/favicon-192x192.png`
- `/apple-touch-icon.png`

Keep `marketing/src/app.html` and `marketing/static/site.webmanifest` in sync with any added exports.

## Things The Marketing App Must Not Own

The marketing app must not contain:

- Convex admin keys or Clerk secret keys
- private API secrets
- authenticated app data
- invite lookup logic
- relationship state
- subscription state
- OAuth provider secrets
- sign-in callback handling

Google sign-in goes through Clerk, which handles the OAuth callback. The marketing app never receives it.

Native app callbacks use:

```text
paeonia://auth/*
paeonia://login-callback/*
```

## Verification

Run locally:

```bash
bun run build
jq empty marketing/static/.well-known/apple-app-site-association
```

Deploy the generated static site with Wrangler:

```bash
bun run pages:deploy:marketing
```

After deploy, verify:

```bash
curl -i https://paeonia.no/.well-known/apple-app-site-association
curl -I https://paeonia.no/join/test-code
curl -I https://paeonia.no/privacy
curl -I https://paeonia.no/terms
curl -I https://paeonia.no/support
```

Expected deployed result:

- `paeonia.no` resolves publicly.
- AASA returns `200` and `Content-Type: application/json`.
- `/join/test-code` resolves to a page, not a 404.
- privacy, terms, and support routes resolve.
- `curl -I -H 'Accept-Language: nb' https://paeonia.no/privacy` redirects to `/no/privacy/`.
- no app-required endpoint depends on a server runtime. The language redirects are Pages Functions in `marketing/functions/`, and the deploy script runs Wrangler from `marketing/` so it finds them. A deploy from the repository root silently leaves them out.
