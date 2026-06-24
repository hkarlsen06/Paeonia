# Marketing App Contract

This document defines what `marketing/` must serve for the iOS app to work correctly.

Paeonia uses `paeonia.no` as the public marketing and Universal Link domain. Supabase lives separately at `api.paeonia.no`.

## Required Domains

### `paeonia.no`

Owned by the static marketing site on Cloudflare Pages.

Required for:

- public landing page
- App Store support, privacy, and terms links
- invite Universal Links
- fallback pages when the app is not installed

### `api.paeonia.no`

Owned by Supabase.

Required for:

- Supabase API
- Supabase Auth
- Supabase Storage
- Supabase Realtime
- Supabase Edge Functions
- OAuth provider callback URL: `https://api.paeonia.no/auth/v1/callback`

Do not route Supabase traffic through the marketing app.

## Implementation Structure

Keep the marketing app structurally close to Tidex's modern marketing app:

- use the Next.js App Router under `marketing/app/`
- keep localized public pages under `marketing/app/[locale]/`
- keep fallback app-link pages such as `/join` as explicit routes under `marketing/app/`
- keep shared page components under `marketing/components/`
- keep localization setup under `marketing/lib/i18n/`
- split dictionaries by domain and locale under `marketing/lib/i18n/dictionaries/`
- keep route/path helpers in `marketing/lib/`
- keep static deployment files in `marketing/public/`

Avoid reintroducing a single large dictionary file as the site grows. Add new marketing copy to the marketing dictionaries, legal copy to the legal dictionaries, and app-required static files to `public/`.

## Required Marketing Endpoints

### `/`

Purpose: public landing page.

Temporary behavior: show an under-construction page that says Paeonia is being built and links to support, privacy, and terms.

Production behavior: real marketing page.

### `/en` and `/no`

Purpose: localized landing pages.

Temporary behavior: same under-construction message in English and Norwegian.

Production behavior: localized marketing pages.

### `/join`

Purpose: fallback page for invite links.

Temporary behavior: explain that Paeonia is not ready yet and that this link will open the app later.

Production behavior: if the app is installed, iOS should open Paeonia through Universal Links. If the app is not installed, the page should explain how to get the app.

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

Temporary behavior: redirect to `/en/privacy/`.

Production behavior: final privacy policy.

The final policy must cover private relationship content, account deletion, precise location sharing if enabled, voice notes, photos, widget drawings, subscriptions, support/admin access, reports, exports, retention, and no-ad/no-tracking posture.

### `/terms`

Purpose: stable App Store and in-app terms URL.

Temporary behavior: redirect to `/en/terms/`.

Production behavior: final terms of service.

The final terms must cover subscriptions, one-partner-pays access, restore behavior, account deletion, leaving a relationship, acceptable use, moderation/reporting, and support limitations.

### `/support`

Purpose: stable App Store and in-app support URL.

Temporary behavior: redirect to `/en/support/`.

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

`marketing/next.config.js` keeps `output: 'export'` enabled for production builds only.

`marketing/lib/i18n/static-params.ts` also returns no locale static params in local development, while returning every locale for production builds.

Reason: with the Next.js 16 dev server, static-export behavior around dynamic locale routes can corrupt or briefly read incomplete generated dev JSON manifests when several routes are requested at the same time. Production `next build` still exports a static Cloudflare-compatible site with every supported locale.

## Optional But Expected Static Files

These are not critical to app auth or pairing, but should remain present for a complete public site:

- `/robots.txt`
- `/sitemap.xml`
- `/site.webmanifest`

## Branding TODO

The current marketing icons are temporary placeholders only:

- `/favicon.ico`
- `/favicon.svg`
- `/favicon-32x32.png`
- `/favicon-192x192.png`
- `/apple-touch-icon.png`
- `/apple-touch-icon-precomposed.png`

Replace these after the real Paeonia brand/icon work is ready. Keep `marketing/app/layout.tsx` metadata and `marketing/public/site.webmanifest` in sync with the final exported assets.

## Things The Marketing App Must Not Own

The marketing app must not contain:

- Supabase service-role keys
- private API secrets
- authenticated app data
- invite lookup logic
- relationship state
- subscription state
- OAuth provider secrets
- Supabase Auth callback handling

OAuth provider callback handling belongs to:

```text
https://api.paeonia.no/auth/v1/callback
```

Native app callbacks use:

```text
paeonia://auth/*
paeonia://login-callback/*
```

## Verification

Run locally:

```bash
pnpm --filter marketing build
jq empty marketing/public/.well-known/apple-app-site-association
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
- no app-required endpoint depends on a server runtime.

## Current Temporary Site Goal

Until the real marketing site is ready, the static site only needs to:

- tell visitors that Paeonia is being built
- keep legal/support routes alive
- keep invite-link fallback routes alive
- serve Apple Associated Domains correctly
- avoid misleading launch or availability claims
