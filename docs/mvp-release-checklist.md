# Paeonia MVP release checklist

What must be true before Paeonia ships. Only open items are listed, and finished items are deleted. Each open item says why it is open: it needs a device or a person, lives in App Store Connect, or is a gap in the source. A passing source or test item does not replace the device runs in Manual Happy Path QA and Failure Mode QA.

## Shipping Standard

Paeonia is ready for MVP when:

- a real couple can sign in, pay, pair, use the core features, and recover from ordinary failures without developer help
- one partner can pay and both partners receive access through server-enforced entitlement
- private relationship content is protected by explicit server-side access checks, signed media URLs, local cache clearing, and relationship access-loss handling
- App Review can verify the app without needing two physical devices
- every public claim, screenshot, legal page, and privacy label matches the shipped build
- no reachable surface contains test, placeholder, or "not ready" language

## Source Documents

- Implementation owners: `docs/implementation-map.md`
- Backend rules, contracts, and server access: `backend/AGENTS.md`
- Current data model: `backend/convex/schema.ts`
- Marketing/app contract: `docs/marketing-app-contract.md`
- Design and copy rules: `docs/phase-2-design/`
- Question authoring rules: `.agents/skills/paeonia-questions/`
- GDPR paperwork for the controller to sign (impact assessment, record of processing, breach routine): `docs/legal/`

## Release Blockers

These block TestFlight/App Review until resolved.

- [ ] App Review can access a paired demo state without needing two reviewer-controlled devices. On 2026-11-17 three demo partners (`review1-3@hkarlsen06.dev`, slots Alex, Sam, Nora) were registered on production, and a minted code paired a fresh email account on the developer's iPad with Alex and showed the paywall, as the review notes describe. Before submission, mint fresh codes (`bun run review-codes:mint`) and paste the notes into App Store Connect.

## Repository And Build Hygiene

- [ ] Worktree is clean before release candidate tagging. Do this when tagging.
- [ ] Local branch is pushed intentionally before remote deployment. Do this when tagging. Local `main` was ahead of `origin/main` on 2026-10-24.

## Verification Commands

Run these before a release candidate and record any skipped one with the reason: `swiftlint --quiet`, `./scripts/xcode-build-agent.sh --json`, `./scripts/xcode-test-agent.sh --json`, `bun run build`, and `npm run typecheck` and `npm test` in `backend/` on the Node version in `.node-version`.

## iOS App Configuration

- [ ] Widget target is embedded and visible in a release build. Needs a device. It is embedded (`project.pbxproj`) with 12 widgets in `PaeoniaWidgetBundle`. Check in a TestFlight build.

## Authentication And Onboarding

- [ ] Sign in with Apple works with Hide My Email. Needs a device. Nothing in the app reads the email address.
- [ ] Google Sign-In works (Clerk's OAuth sheet). Needs a device. The Google client lives in Google Cloud project `paeonia-hkarlsen06`, and its consent screen is published.

## Streaks

- [ ] Broken streak state is understandable. Needs a device.

## Lock Screen Widgets

- [ ] Days together, Next countdown, Their time, Distance apart, Streak, Today's question, and Your move can each be added to the Lock Screen. Needs a device.
- [ ] The countdown title stays hidden while the phone is locked and shows after Face ID. Needs a device. The view uses `.privacySensitive()`.
- [ ] A partner's answer, game move, countdown change, or start date change updates the other phone's widgets while Paeonia is closed. Needs a device. The server side is tested (`widget.test.ts`).
- [ ] Widget names and copy are audited in English and Norwegian. Needs a person. Both languages are complete.

## Home Screen Widgets

- [ ] Days together (small, medium), Countdown (small, medium), Streak (small), Today's question (small, medium) and the drawing widget in its new medium size can each be added to the Home Screen. Needs a device.
- [ ] Countdown titles stay hidden on a locked phone (StandBy). Needs a device.
- [ ] Widget names, settings and copy are audited in English and Norwegian. Needs a person.

## Countdown And Relationship Milestones

- [ ] A date reminder arrives at 09:00 local, opens the dates timeline, and arrives once per device. Needs a device. The time and dedupe are tested (`dateReminders.test.ts`).

## Partner Location

- [ ] On a real device: allow Always, close the app, move about 1 km, and confirm the partner sees the new location.
- [ ] On a real device: choose "Keep Only While Using" at the iOS question and confirm the "Choose Always in Settings" note appears.
- [ ] On a real device: pause for 1 hour with updates while closed on, close the app, wait for the pause to end, and confirm the partner sees the new location without opening the app.

## Notifications

- [ ] App still works if notifications are never enabled. Needs a device.

## Settings, Privacy, And Account Controls

- [ ] User can download all their data in the app (GDPR Art. 15 and 20): JSON files, original photos, voice messages and drawings, a README with the Art. 15 information, a push when it is ready, links that expire. Built on the backend and in the app, see `docs/privacy-and-data-export.md`. On 2026-11-17 a device download worked end to end with one 231 kB zip: the ready push, the share sheet, the README, and no partner content. Still needs a download with real photos and voice messages that splits into several zip files.

## Offline-First And Sync

- [ ] Slow network states are understandable. Needs a device.

## Convex Backend

Production is self-hosted Convex on `one-s` (see `backend/AGENTS.md`). The earlier Supabase checks (migrations, RLS, pgTAP, advisors, Edge Functions, Storage buckets) no longer apply.

- [ ] The catalog sync no longer moves existing daily questions to a new question version (the `ponytail:` step in `backend/convex/catalog.ts`), so answers keep the wording they were written for. Remove the step just before launch.
- [ ] `scripts/local-backend` no longer copies the data of `api.paeonia.no`. Today its first run and `--reseed` import every table and stored file of the hosted deployment into the worktree, which is fine while that is test data. Remove the import just before launch, so real couples' content never lands on a development machine, and seed local backends with the test couple only.
- [ ] A queued push reaches a real device as a widget update. Needs a device with a Paeonia widget on the Home Screen. Alerts reached both devices on 2026-11-17.
- [ ] A restore from a nightly backup has been tried. Hourly and nightly backups run (checked 2026-10-24). The storage move on 2026-10-14 used the restore steps, but no drill has used a nightly backup.
- [ ] The nightly backup fits once couples send videos. Each nightly export holds every stored file, a video is up to 80 MiB, and `one-s` keeps 14 exports, so total file storage times 14 must fit in the server's free disk (120 GB on 2026-11-16, when an export was 72 MB). The offsite copy in R2 keeps 3 days inside the free 10 GB. Exports that leave out files, with the files copied once to R2, would remove the limit.

## Localization And Copy

- [ ] English strings are clear enough for a 16-year-old user. Needs a person. No technical words were found.
- [ ] Norwegian Bokmal strings are natural, not technical database-sounding translations. Needs a native speaker.
- [ ] Daily answer reveal copy is audited in English and Norwegian. Needs a person.
- [ ] Widget drawing save/clear copy is audited in English and Norwegian. Needs a person.

## Accessibility And Device QA

- [ ] Small iPhone layout pass.
- [ ] Video call on a real iPhone Duo, unfolded and closed, held upright and on its side. Needs a device. The call must stand upright on both phones and use the camera beside the screen in use. The open question in [the calling plan](calling-plan.md#open-questions) says what the simulator showed.
- [ ] Latest supported iOS version pass.
- [ ] Minimum supported iOS version pass.
- [ ] Complete the device-specific release gate in [the accessibility report](accessibility-report.md), including real VoiceOver and Voice Control journeys. A smoke check or automated audit does not close this gate.
- [ ] Color contrast is acceptable against plum surfaces.
- [ ] Touch targets are large enough.
- [ ] Sheet dismissal and keyboard behavior are sane.
- [ ] Invite code entry works with paste and accessibility.
- [ ] Daily answer composer works with keyboard, camera/photo picker, microphone, and VoiceOver.
- [ ] Widget drawing controls are reachable and understandable.
- [ ] Map is not the only way location state is communicated.

## Manual Happy Path QA

Run these on real devices where possible.

- [ ] Fresh install -> Apple sign-in -> onboarding -> paywall.
- [ ] Fresh install -> Google sign-in -> onboarding -> paywall.
- [ ] Payer subscribes -> creates invite.
- [ ] One user answers a question the partner answered on an earlier day -> reveal works.
- [ ] User enables location; map waits for partner.
- [ ] Partner enables location; distance/location appears.
- [ ] User disables location; map hides or updates as expected.

## Failure Mode QA

- [ ] No network during location update.
- [ ] StoreKit product loading fails.
- [ ] Purchase is cancelled.
- [ ] Purchase fails.
- [ ] Restore finds no subscription.
- [ ] Media upload fails.
- [ ] Voice recording permission denied.
- [ ] Camera/photo permission denied.
- [ ] Location permission denied.
- [ ] Invite code expired.

## App Store Connect

The text metadata lives in `ios/Scripts/appstore-metadata-source.json`, and `ios/Scripts/generate-appstore-metadata.mjs` writes native ASC JSON to `ios/app-store/metadata/`. The upload workflow is in `ios/app-store/README.md`.

- [ ] Subtitle, promotional text, description and keywords describe the current app. Rewritten on 2026-10-24 from competitor and App Store search research, with a new en-GB locale for a second Norwegian keyword field. In App Store Connect: plan them with `bun run app-store metadata`, then upload with `--apply`.
- [ ] Copyright filled.
- [ ] Support URL set.
- [ ] Marketing URL set if desired.
- [ ] App Review contact information filled.
- [ ] App Review notes are pasted into App Store Connect. `ios/Scripts/mint-review-codes.mjs` prints them from `ios/Scripts/app-review-notes.txt` with fresh review codes.
- [ ] In-app purchases submitted with the build.
- [ ] Subscription screenshot/metadata completed.
- [ ] Content rights answered.

## App Store Screenshots

The proposed v1 iPhone and iPad sets are in `ios/ASConnectScreenshots/1.0.0/3d/` (git-ignored), in English and Norwegian. They were uploaded to version 1.0.0 in App Store Connect on 2026-10-25 with `bundle exec fastlane ios upload_screenshots`. The scripts that make it are listed in `marketing/AGENTS.md`.

- [ ] Screenshots match final app icon, colors, and layout. Recapture before submission if the UI changes. The scripts rerun the whole set.

## TestFlight

- [ ] Internal TestFlight build uploaded.
- [ ] TestFlight install launches.
- [ ] App icon and display name are correct in TestFlight.
- [ ] Production-like push notifications work in TestFlight.
- [ ] StoreKit sandbox/subscription works in TestFlight.
- [ ] App Review beta notes explain login, pairing, subscription, and demo path.
- [ ] External TestFlight review passes before broad beta.
- [ ] Small beta group has enough couples to test paired behavior.
- [ ] Feedback collection path exists.
- [ ] Crash reports are monitored.

## Explicit Non-MVP Items

These should not delay 1.0 unless the product decision changes.

- AI
- public profiles
- searchable users
- multiple couples
- prompt marketplace
- advanced photo editing
- Android
- web companion app
- public social feed
- ads
- external media scanning vendor
- custom admin/moderation UI
- end-to-end encryption
