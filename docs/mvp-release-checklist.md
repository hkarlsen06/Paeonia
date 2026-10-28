# Paeonia MVP Release Checklist

This is the active execution checklist for getting Paeonia to a review-ready MVP.

Use this instead of a phase roadmap. Paeonia is now past early planning: the important question is not "what phase are we in?", but "what must be true before we can ship?"

## How to read the boxes

The checklist was last reconciled on 2026-10-24, against the source, the tests, and the hosted deployment at `api.paeonia.no`.

- A box is checked when an automated test in the repository covers the item, when the source or configuration proves it, or when it was measured on the hosted deployment or a public URL. The note says which.
- An unchecked item ends with a note that says why it is open:
  - **Needs a device.** Only a real phone, a real Apple or Google account, or real push delivery can prove it. The code exists unless the note says otherwise.
  - **In App Store Connect.** Or another outside dashboard that the repository cannot show.
  - **Gap.** The source is missing the behavior, contradicts the item, or has a bug.
  - **Built, untested.** The source implements it, but no test covers it and it is one of the kinds of logic that `AGENTS.md` says keeps tests.
  - **Your call.** A product or design decision.
- A checked source or test item does not replace the device runs in Manual Happy Path QA and Failure Mode QA.

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
- Original product/data decisions (retired Supabase schema): `docs/phase-3-data-contract.md`
- Marketing/app contract: `docs/marketing-app-contract.md`
- Design and copy rules: `docs/phase-2-design/`
- Historical UX audit with a current status summary: `docs/ux-friction-report.md`
- Question authoring rules: `.agents/skills/paeonia-questions/`

## Release Blockers

These block TestFlight/App Review until resolved.

- [x] No active docs, scripts, or agent instructions point at the removed phase roadmap.
- [x] `docs/implementation-map.md` accurately reflects the current feature ownership.
- [x] No reachable app screen says "test account", "not ready", "still building", or similar placeholder copy.
- [x] App and widget privacy manifests declare their required-reason API usage.
- [x] Public privacy policy is final and live at `https://paeonia.no/privacy`. The location pause paragraph was fixed on 2026-10-24, including the one location sent when a pause ends while the app is closed. It is live once `main` is pushed.
- [x] Public terms are final and live at `https://paeonia.no/terms`.
- [x] Support page is final and live at `https://paeonia.no/support`.
- [x] In-app legal/support links open the production URLs.
- [ ] Account deletion works end-to-end from the app. Needs a device: the backend (`accountDeletion.test.ts`) and app (`RootViewModelFlowTests`) are tested, but the Clerk user removal and Apple token revocation need a real account.
- [x] Relationship leave/disconnect hides shared content after sync. `relationship.test.ts`, `LocalPrivacyPurgeTests`, `RelationshipEventsLiveFeedTests`.
- [ ] App Review can access a paired demo state without needing two reviewer-controlled devices. The backend is tested (`review.test.ts`). Next, sign in three demo partner accounts on the production Clerk instance and run `mint-review-codes.mjs`.
- [x] In-app purchase products are configured in App Store Connect.
- [x] StoreKit sandbox monthly and annual purchases and entitlement refresh are tested on device. Measured on 2026-10-24: `api.paeonia.no` holds 15 monthly and 5 yearly verified sandbox transactions, with renewal, expiry and plan-change notifications.
- [ ] StoreKit sandbox restore is tested on device. Needs a device.
- [x] One paying partner unlocks both partners through backend entitlement. `storekit.test.ts` "one paying partner unlocks the couple for both".
- [x] Subscription terms are clear before purchase.
- [x] App icon is final in the app target and App Store assets. The app uses `paeonia_app.icon`. A widget extension has no icon of its own.
- [x] App Store privacy labels match the actual data collected by the build.
- [x] App Store privacy labels include the PostHog data: product interaction, device ID and crash data, linked to the user, used for analytics, not for tracking. There are no screen recordings.
- [ ] Confirm in App Store Connect that the declared Product Interaction for Analytics also covers the signed-out welcome step counts (`onboarding:record_welcome_step`): a step name only, kept as daily totals, with no user, phone or install identifier. In App Store Connect.
- [x] `POSTHOG_PERSONAL_API_KEY` is set on the hosted backend, so account deletion and turning off usage statistics delete the person's PostHog data.
- [x] That key also has the `query:read` scope, so the monthly `delete-inactive-analytics-persons` cron can find people inactive for a year.
- [x] The Mac that archives has `posthog-cli` installed and signed in (`posthog-cli login`, EU), so the Upload dSYMs to PostHog phase can send symbols. An archive fails without it.
- [x] The PostHog data processing agreement is signed.
- [x] A record of processing and a short DPIA for usage statistics and crash reports are written down. They are kept outside the repo with the signed PostHog DPA.
- [ ] On a device: the usage question appears once after pairing, nothing reaches PostHog before a yes, and turning off Share usage statistics stops sending at once. Needs a device.

## Repository And Build Hygiene

- [ ] Worktree is clean before release candidate tagging. Do this when tagging.
- [ ] Local branch is pushed intentionally before remote deployment. Do this when tagging. Local `main` was ahead of `origin/main` on 2026-10-24.
- [x] No secrets, Convex admin keys, Clerk secret keys, APNs keys, StoreKit secrets, or review access codes are committed. On 2026-10-24 gitleaks scanned all 2358 commits and found only publishable keys, UserDefaults key names and a question file. The repository is public, so scan again before release.
- [x] `.gitignore` excludes generated build output, Xcode derived data, local Convex state, and local environment files.
- [x] `AGENTS.md` points agents to `docs/mvp-release-checklist.md` and `docs/implementation-map.md` as the active planning/navigation docs.
- [x] CI smoke checks run on pushes.
- [x] Backend CI (`.github/workflows/backend.yml`: typecheck and tests) passes on GitHub. Green on 2026-10-24.
- [x] The committed project builds from a fresh checkout. The iOS workflow runs `build-for-testing` with warnings as errors, green on 2026-10-24.
- [x] The committed SwiftPM/package state is portable for a fresh checkout. `Package.resolved` is tracked. The `Chat` package tracks `branch = main` of a public fork, pinned by revision.
- [x] Local-only/debug-only surfaces are either removed or hidden behind debug configuration.
- [x] Generated assets are committed only when they are canonical source or required runtime assets.

## Verification Commands

Run these before a release candidate.

- [x] `swiftlint --quiet` (exit 0; advisory warnings remain).
- [x] `./scripts/xcode-build-agent.sh --json` (Xcode 27 beta; succeeded).
- [x] `./scripts/xcode-test-agent.sh --json` (468 tests, 0 failures).
- [x] `bun run build`
- [x] `cd backend && npm run typecheck` (Node 20, 22, or 24; Convex Node actions fail on Node 26). Passed on Node 22, 2026-10-24.
- [x] `cd backend && npm test`. 2288 tests passed, 2026-10-24.

Record any skipped command with the reason. Run all six again for the release candidate.

## iOS App Configuration

- [x] Bundle identifier is final: `no.paeonia.app`.
- [x] Display name is final: `Paeonia`.
- [x] Minimum supported iOS version is intentional.
- [x] Supported devices are intentional. Paeonia supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- [x] App Group entitlement is present for app and widget.
- [x] Associated Domains include `applinks:paeonia.no`.
- [x] Push notification capability is configured.
- [x] Sign in with Apple capability is configured.
- [x] Location usage descriptions are present and plain-language.
- [x] Microphone usage description is present for voice notes.
- [x] Photo library/camera usage descriptions are present for media answers and memories.
- [ ] Widget target is embedded and visible in a release build. Needs a device. It is embedded (`project.pbxproj`) with 12 widgets in `PaeoniaWidgetBundle`. Check in a TestFlight build.
- [x] Notification Service Extension is configured if required by the shipped notification behavior.
- [x] App icon asset is linked correctly in all relevant targets.
- [x] Launch screen uses final brand treatment or an intentionally minimal native launch.
- [x] Release build configuration points at the production Convex URL (`https://api.paeonia.no`), a `pk_live_` Clerk key from the production Clerk instance (`clerk.paeonia.no`), and production marketing URLs. Switched on 2026-10-24.
- [x] Debug/test account shortcuts are unavailable in release builds.

## Authentication And Onboarding

- [ ] Sign in with Apple works with normal Apple ID (native ID token exchanged through Clerk). Needs a device.
- [ ] Sign in with Apple works with Hide My Email. Needs a device. Nothing in the app reads the email address.
- [ ] Google Sign-In works (Clerk's OAuth sheet). Needs a device. The Google client lives in Google Cloud project `paeonia-hkarlsen06`, and its consent screen is published.
- [x] No email/password, magic-link, or passkey sign-up surface is reachable in MVP.
- [x] Auth errors are understandable to a normal user. Sign-in, account deletion and the relationship-ended notice say to check the connection only when `PaeoniaFailure` is `.offline`, and otherwise say something went wrong (`RootNoticeLocalization.swift`). Cancelling sign-in shows nothing.
- [x] A production Clerk instance exists at `clerk.paeonia.no`. Its issuer is `CLERK_JWT_ISSUER_DOMAIN` on `api.paeonia.no`, which accepts its tokens and refuses the development instance's (checked 2026-10-24). Apple uses Services ID `no.paeonia.app.clerk` and the iOS app `48ZSLD4RMP` / `no.paeonia.app`. Google uses its own client. `scripts/deploy-backend` creates the `convex` JWT template on each deploy.
- [x] The Google client secret and the Sign in with Apple key `7HMG8DVAK4` are rotated. On 2026-10-24 the Google client got a new secret and the old one was deleted. Apple key `Q6X2689WV2`, with push and Sign in with Apple, replaced `7HMG8DVAK4`, which is revoked. Production Clerk and the `APNS_*` and `APPLE_SIGN_IN_*` variables on `api.paeonia.no` use the new values. The old secret and key now fail with `invalid_client` and `InvalidProviderToken`.
- [x] OAuth profile name is used when available. `ClerkAuthServiceSignInTests`, `lib/auth.test.ts`.
- [x] Name fallback flow works when OAuth does not provide a usable name. Onboarding refuses a blank name, `identity.test.ts` refuses it on the server, and the UI test types a name.
- [x] Display name can be changed later.
- [x] Profile photo upload and replacement have a tested source path. `ClerkAuthServiceProfileTests`, `identity.test.ts`.
- [x] A private OAuth profile-photo fallback appears when the user-uploaded override is missing and cannot itself be removed. `identity.test.ts`, `ClerkAuthServiceProfileTests` "updateProfileRemovingCustomPhotoRevealsProviderFallback".
- [x] The relationship start date is asked once before sign-in and can be skipped. The milestone card asks again.
- [x] Relationship start date validation is clear.
- [x] The user sees paywall after account creation and before pairing, per product decision.
- [x] A user can sign out from post-auth onboarding/paywall states.
- [x] A user can delete the account from post-auth onboarding/paywall states.
- [x] Account deletion copy states real consequences, not test-device language.

## Paywall, StoreKit, And Entitlements

- [x] Subscription group exists in App Store Connect.
- [x] Product IDs in App Store Connect match `subscription_products`.
- [x] Product prices and periods load correctly.
- [x] Intro offer/trial copy is derived from the loaded StoreKit product.
- [x] The trial timeline's two-days-left promise is backed by an idempotent localized push queued from verified Apple trial data. `storekit.test.ts` "queues verified free trials per device, in bounded batches, once".
- [x] Primary CTA says what happens next, including App Store confirmation.
- [x] Restore purchases works when signed into the paying account.
- [x] Restore does not grant access to unrelated accounts. `storekit.test.ts` "rejects another user's token" and "rejects a transaction id already owned by another user".
- [x] Backend records verified StoreKit transactions. `access.test.ts`, and 20 sandbox transactions on `api.paeonia.no` (2026-10-24).
- [x] Sandbox server notifications reach `https://actions.paeonia.no/apple/server-notifications`. An Apple test notification was stored on 2026-10-24.
- [ ] The production server notification URL in App Store Connect is `https://actions.paeonia.no/apple/server-notifications`. In App Store Connect. Apple's production test-notification request returned 401 on 2026-10-24, probably because the app has no production release yet.
- [x] Apple server notification and in-app purchase key configuration is correct (`APPLE_IAP_*`, `APPLE_BUNDLE_ID` and `APPLE_APP_APPLE_ID` on `api.paeonia.no`). Sandbox purchases verify on the hosted backend.
- [ ] Billing Grace Period is turned on in App Store Connect, and a subscription in grace keeps access for both partners until the grace period ends. In App Store Connect. The backend half is tested (`storekitWebhook.test.ts`) and deployed on 2026-10-24.
- [x] Expired subscription removes entitlement when neither partner has active access. `storekit.test.ts` "expires lapsed transactions and grants".
- [x] Lifetime/test/review grants are scoped, auditable, revocable, and intentional. `entitlementGrants:create_entitlement_grant` and `revoke_entitlement_grant` are the only writers, run with `npx convex run`. A grant needs a reason and who gave it, and a user has at most one live grant per kind and product (`entitlementGrants.test.ts`).
- [x] A partner does not buy a second subscription for a couple that already has access. The live access feed closes the paywall for both partners as soon as one purchase verifies, so `PaywallViewModel` needs no check of its own. Two partners who confirm the purchase sheet within the same few seconds can both be billed. That is accepted (decided 2026-10-24).
- [x] Manage subscription link is available in settings or paywall footer.
- [x] Subscription sharing is explained clearly: one subscription unlocks Paeonia for both partners.
- [x] Paywall does not imply free access if the product is paid.
- [x] Paywall invite-code entry does not confuse joining with purchasing.

## Pairing And Relationship Lifecycle

- [x] Invite creation works for an unpaired entitled user. `pairing.test.ts`.
- [x] Invite code is short enough to share manually. Six characters (`pairing.ts`).
- [ ] Invite link opens the app through Universal Links. Needs a device. The association file and `/join/<code>` are served correctly.
- [x] `/join/*` fallback route explains what to do if the app is not installed.
- [x] Accepting an invite previews who invited the user before pairing.
- [x] Accepting an invite requires explicit confirmation.
- [x] Expired invite handling is clear.
- [x] Already-paired user cannot accidentally join another relationship. `pairing.test.ts`.
- [x] Pending invites do not create empty couples. Only invite acceptance and App Review code redemption insert a couple.
- [x] Couple row is created only after acceptance. `pairing.test.ts`.
- [x] Pairing celebration works without blocking access if animation fails.
- [x] Relationship ended notice is a real screen/state, not an unavailable placeholder.
- [x] Leaving a relationship is clearly warned.
- [x] Leaving immediately removes local access to shared relationship content.
- [x] Leaving schedules backend cleanup according to retention policy. `relationship.test.ts`, crons in `crons.ts`.
- [x] Account deletion while paired has the same relationship effect as leaving. `accountDeletion.test.ts`.
- [x] Prior report/block safety warnings behave as documented if re-pairing is attempted.
- [x] No public discovery, user search, or profile lookup is reachable.

## Daily Challenge

- [x] Today's challenge loads from database-backed question content.
- [x] Both partners get the same single question each couple day.
- [x] Each partner answers it once, in either order.
- [x] A question only one partner answered carries over, and the other can answer it late.
- [x] A question the partner answered on an earlier day shows as a locked row on the daily card and in the Questions list, and the user can answer it.
- [x] Partner answers remain hidden until the current user answers that same question.
- [x] Locked/revealed answer states are clear without relying only on icons.
- [x] Answer kinds are respected per question version.
- [x] Text answers work.
- [x] Photo answers work.
- [ ] Voice answers work. Needs a device for recording and playback. The app side is tested. No backend test submits a daily voice answer.
- [x] Partner-choice answers work.
- [x] Combined answer-kind behavior follows `.agents/skills/paeonia-questions/SKILL.md`.
- [x] Staged drafts survive closing/reopening the answer composer.
- [x] Offline answers queue and show local-first reassurance.
- [x] Queued answers upload later without duplication.
- [x] Media/voice upload failure does not drop user content. `MediaUploadFlowTests` "aDailyVoiceAnswerWhoseUploadFailsStaysQueuedAndSendsOnTheRetry" keeps the staged file and the queued answer after a failed upload, then sends both on the retry.
- [x] Answer reveal works after both partners answer, with the chime and petal moment, and offers Open chat and Done.
- [x] Only fully revealed question cards open their private question chat.
- [x] The first follow-up message creates the thread lazily; opening chat never creates an empty thread.
- [x] Offline chat messages appear immediately and later send without duplication.
- [ ] Question-chat notifications route to the right question without exposing message content on the lock screen. Needs a device. The push copy and deep link are tested (`threads.test.ts`).
- [x] Question-chat UI and notification settings are localized in English and Norwegian Bokmal.
- [x] Partner-answer notification does not expose answer content.
- [x] The "answered today's question" notification copy explains that the recipient must answer to see the partner's answer.
- [x] Daily challenge history groups questions by effective latest-answer day.
- [x] Carried-over questions the partner answered remain answerable for 30 days.
- [x] Skip works, up to 30 a day.
- [x] Skipped questions stay away for 14 days. `daily.test.ts` "a skipped question stays away on later days and comes back once 14 days have passed".
- [x] Resurfaceable questions can reappear after the configured period and show prior answer dates. `daily.test.ts` "a question that can resurface stays away for its months, then comes back with the day it was answered".
- [x] When a couple has seen every active question, the picker repeats the one the couple had longest ago instead of failing.
- [x] Question content has English and Norwegian Bokmal localizations.
- [x] No question prompt assumes gender, public sharing, or unsafe relationship behavior.

## Streaks

- [x] Couple-level streak is calculated from qualifying activity.
- [x] Answering the daily question keeps the streak alive.
- [x] Updating the shared widget keeps the streak alive.
- [ ] Creating or editing a memory keeps the streak alive. Creating one records `memory_created` (`lib/streaks.test.ts`). No memory edit records `memory_updated` yet.
- [x] Streak does not expire before midnight in the latest partner timezone.
- [x] Started couple-day timezone window is frozen as documented. `daily.test.ts` "a partner who changes time zone mid-day does not move the day that already started".
- [x] Streak reminder can be scheduled before expiry.
- [x] Streak reminder copy is privacy-safe.
- [ ] Broken streak state is understandable. Needs a device.
- [x] Streak restore flow works.
- [x] Streak restore purchase cannot be confused with subscription entitlement.
- [x] Streak restore window is intentional and tested. A streak of 3 or more that breaks comes back for free when both partners show up on the next couple day. The paid restore is offered only on the second and third couple days after the missed one, and after that the streak is gone. `lib/streaks.test.ts` "after a break: one free save day, then two restore days" and "save and restore days across time zones".

## Memories

- [x] Memory timeline loads local-first.
- [x] Empty state has a clear create action.
- [x] Memory requires title and date.
- [x] Memory can be created with note-only content.
- [x] Memory can be created with photo-only content.
- [x] Memory supports up to 5 photos per partner.
- [x] Partner can add their own note later.
- [x] Both partners can edit title/date as intended.
- [x] A user can edit their own note.
- [x] A user can add/remove their own photos.
- [x] Photo compression follows the intended space-saving approach.
- [x] Photo upload failure leaves the draft intact.
- [x] Memory photos are loaded through private signed URLs.
- [x] Memory media cache clears on relationship access loss. `LocalPrivacyPurgeTests` "everyPurgeRemovesCachedMemoryPhotos" runs the real purger for every purge scope.
- [x] Memory deletion/hide behavior matches product decision and the access checks in `backend/convex/memories.ts`.
- [x] Memory comments are in the UI (`MemoryCommentsSection`).
- [x] Memory voice notes are cut from MVP; active product copy and App Store materials must not imply that memories include voice. The backend and `MemoryMediaPurpose.voice` still accept memory voice, which can be deleted.

## Widget Drawing

- [x] Widget can be added to Home Screen.
- [x] Widget shows a safe placeholder before first drawing.
- [x] Tapping widget opens the app drawing flow.
- [x] Drawing uses PencilKit.
- [x] Canonical drawing payload is stored as `PKDrawing`/vector data, not PNG.
- [x] The upload is the PKDrawing. PNG previews are made on the phone for the widget and history thumbnails only.
- [x] Saving a drawing updates local app preview.
- [x] Saving a drawing updates widget payload through App Group storage.
- [x] Saving a drawing uploads private drawing payload.
- [x] Partner receives update notification for new drawing. `widget.test.ts`. Delivery is part of Manual Happy Path QA.
- [x] Silent/widget refresh behavior works as far as iOS allows.
- [x] Drawing history preserves prior revisions.
- [x] Drawing history shows author and timestamp.
- [x] Clearing canvas is local until a new revision is saved.
- [x] Drawing save failure keeps the drawing recoverable.
- [x] Widget privacy setting exists or the shipped behavior is explicitly privacy-safe by default.
- [x] Widget does not expose sensitive private text on the lock screen.
- [x] App Group data clears on sign-out, account deletion, and permanent relationship access loss; temporary entitlement loss uses a privacy-safe hide.

## Lock Screen Widgets

- [ ] Days together, Next countdown, Their time, Distance apart, Streak, Today's question, and Your move can each be added to the Lock Screen. Needs a device.
- [x] Each widget shows a neutral state when signed out, unpaired, or before its first refresh, never sample numbers.
- [ ] The countdown title stays hidden while the phone is locked and shows after Face ID. Needs a device. The view uses `.privacySensitive()`.
- [x] Distance apart shows nothing about either partner's location except the distance, and only while both share location.
- [x] Streak halves and Today's question reset when the couple's day ends, without opening the app.
- [ ] A partner's answer, game move, countdown change, or start date change updates the other phone's widgets while Paeonia is closed. Needs a device. The server side is tested (`widget.test.ts`).
- [x] Their time stays correct across a daylight saving change in either time zone.
- [x] Tapping each widget opens the matching screen. Their time and Distance apart open the app on purpose.
- [x] The lock screen widget cache clears on sign-out, account deletion, and relationship access loss. `LocalPrivacyPurgeTests` "everyPurgeRemovesWhatTheLockScreenAndHomeScreenWidgetsShow" covers every purge scope.
- [ ] Widget names and copy are audited in English and Norwegian. Needs a person. Both languages are complete.

## Home Screen Widgets

- [ ] Days together (small, medium), Countdown (small, medium), Streak (small), Today's question (small, medium) and the drawing widget in its new medium size can each be added to the Home Screen. Needs a device.
- [x] Each shows a neutral state when signed out, unpaired, or before its first refresh, never sample numbers.
- [x] A couple with no start date, no countdowns, or no streak sees an invitation in the matching widget, and tapping it opens the right screen.
- [x] The Countdown widget's settings list "Next one", every countdown and both birthdays. A deleted countdown falls back to the next date.
- [x] A yearly countdown and a birthday that passed yesterday show next year's day in the Countdown widget without opening the app.
- [x] Today's question never shows question or answer text, and its status changes when the partner answers while Paeonia is closed.
- [ ] Countdown titles stay hidden on a locked phone (StandBy). Needs a device.
- [x] Tapping each widget opens the matching screen: dates timeline, streak, today's question, drawing.
- [x] The widgets clear on sign-out, account deletion, and relationship access loss. Covered by the same test as the lock screen widgets, which also checks that the widgets reload.
- [ ] Widget names, settings and copy are audited in English and Norwegian. Needs a person.

## Countdown And Relationship Milestones

- [x] Relationship start date flows from the milestone setup/server state to home.
- [x] In the first year, the countdown shows the soonest of the next monthly milestone and the 100-day mark.
- [x] After one year, the countdown shows the soonest of the next anniversary and the next round day count (500, then every 1,000).
- [x] Round day milestones behave intentionally.
- [x] Missing/invalid start date shows honest setup copy, not fake data.
- [x] Countdown date formatting localizes correctly.
- [x] Countdown card has no hardcoded sample milestone in release.
- [x] Custom countdowns and birthdays sync between partners, work offline, and show on the Home tile when they come first.
- [x] Reminders for birthdays, the anniversary, milestones and countdowns are a notification switch ("Dates that matter") that is on by default, and the push copy names no countdown.
- [x] A countdown can repeat every year, and the Home tile, the timeline and the widgets show its next occurrence, 29 February included.
- [ ] A date reminder arrives at 09:00 local, opens the dates timeline, and arrives once per device. Needs a device. The time and dedupe are tested (`dateReminders.test.ts`).

## Partner Location

- [x] Location map is hidden unless both partners opt in.
- [x] Location permission is requested at the right moment.
- [x] Permission copy explains latest location only and no location history.
- [x] Updates while the app is open come from a live feed that sends only after a 250 m move or 5 minutes.
- [x] Updates while the app is closed are a separate choice. Turning sharing on from the map card or the location primer asks iOS for Always right away, so the person decides then. The Settings switch changes it later, shows only while sharing is on, and turns off when sharing is turned off.
- [x] Updates while closed use the significant-change service with Always access. The app does not declare the `location` background mode.
- [x] `NSLocationAlwaysAndWhenInUseUsageDescription` says when the location is sent and how to turn it off, in English and Norwegian.
- [x] Backend with the `background` location source is deployed before a build with updates while closed ships. Deployed to `api.paeonia.no` on 2026-10-24.
- [ ] On a real device: allow Always, close the app, move about 1 km, and confirm the partner sees the new location.
- [ ] On a real device: choose "Keep Only While Using" at the iOS question and confirm the "Choose Always in Settings" note appears.
- [x] Pausing location sharing for 1 hour, 4 hours or until morning keeps sharing on, hides the partner's position from the person who paused, and ends by itself. The partner is not told and sees the last position and its age.
- [ ] On a real device: pause for 1 hour with updates while closed on, close the app, wait for the pause to end, and confirm the partner sees the new location without opening the app.
- [x] Foreground location update has a tested source path.
- [x] Offline stale location retries cannot overwrite newer location.
- [x] Latest partner location displays with last-updated relative time.
- [x] Stale marker behavior after 24 hours is implemented or intentionally deferred from UI claims.
- [x] Disabling sharing deletes/hides latest location as documented.
- [x] Relationship end/account deletion removes location visibility.
- [x] App Store privacy labels include precise location.
- [x] Privacy policy explains opt-in latest-location sharing, no history, stale timestamps, pausing, and deletion behavior clearly.

## Notifications

- [x] APNs auth key is configured (`APNS_*` Convex environment variables). Set on `api.paeonia.no`, and `push:send_push` succeeds in the hosted logs (2026-10-24).
- [x] Push registration works on device. The developer's phones receive pushes from `api.paeonia.no`.
- [x] Device tokens are stored per user with their APNs environment. The couple is checked when the push is sent.
- [x] Notification preferences are available in settings.
- [x] User can disable streak reminders.
- [x] User can disable partner-answer notifications. `daily.test.ts` covers the setting when the push is queued and when it is due.
- [x] User can disable widget drawing notifications.
- [x] New drawing notification works.
- [x] Partner-answer notification works.
- [x] Partner-completed-daily-challenge notification works if shipped.
- [x] Streak-expiry reminder works if shipped.
- [x] Notification payloads do not include answer text, note text, media URLs, invite codes, precise location, or report details. `NOTIFICATION_PAYLOAD_FIELDS` in `lib/notifications.ts` lists the only fields each kind may carry, and `prepare_notification` checks again before the send. `lib/notifications.test.ts` covers all six kinds of content across every notification kind.
- [x] Notification outbox records delivery attempts and failures.
- [ ] Permission-denied state is graceful. Needs a device.
- [ ] App still works if notifications are never enabled. Needs a device.

## Settings, Privacy, And Account Controls

- [x] Settings tab/screen exposes profile, relationship, subscription, notification, location, legal, support, sign-out, and deletion paths as appropriate.
- [x] User can update display name.
- [x] User can update a custom profile photo; the OAuth fallback remains available.
- [x] User can sign out.
- [x] User can restore purchases through StoreKit and refresh access.
- [x] User can manage subscription.
- [x] User can leave relationship.
- [x] User can report and leave relationship.
- [x] User can initiate account deletion.
- [x] User can ask for a correction, or delete the account, from Privacy and safety.
- [ ] User can download all their data in the app (GDPR Art. 15 and 20): JSON files, original photos, voice messages and drawings, a README with the Art. 15 information, a push when it is ready, links that expire. Built on the backend and in the app, see `docs/privacy-and-data-export.md`. Needs a device: a download with real photos, several zip files, and the share sheet.
- [x] Delete account copy explains account, relationship, and content consequences.
- [x] Destructive actions require confirmation.
- [x] Support email is `support@paeonia.no`.
- [x] Contact email is `contact@paeonia.no`.
- [x] Reported content stays visible until an admin acts. `moderation.test.ts`.
- [x] Admin/moderation steps are written down. The operator functions are listed in `backend/AGENTS.md`.

## Offline-First And Sync

- [x] App launches offline with cached relationship state.
- [x] Paired home renders cached content before network refresh where safe.
- [x] Daily challenge snapshot cache works.
- [x] Memory cache works.
- [x] Widget payload cache works.
- [x] Location visibility cache does not leak after relationship access loss.
- [x] Pending operations are idempotent.
- [x] Pending operation retries do not duplicate answers, memories, drawings, or locations.
- [x] Live feed cursors move only after the events were applied.
- [x] Relationship access-loss events clear or privacy-hide private local caches according to whether loss is permanent.
- [x] Sign-out clears private local caches.
- [x] Account deletion clears private local caches.
- [x] Media draft stores do not leak content across users.
- [ ] Slow network states are understandable. Needs a device.
- [x] Recoverable errors show plain copy. Every message that tells people to check their connection is shown only when `PaeoniaFailure` is `.offline`, including StoreKit's network error (`PaeoniaFailureTests`). Checked on 2026-10-24 by scanning all 78 such strings. Some "saved on this phone" lines still say "when you're online" after a server error on a working connection, because those features' sending states don't tell the two apart.
- [x] No private content is written to logs.

## Convex Backend

Production is self-hosted Convex on `one-s` (see `backend/AGENTS.md`). The earlier Supabase checks (migrations, RLS, pgTAP, advisors, Edge Functions, Storage buckets) no longer apply.

- [x] `scripts/deploy-backend` succeeds against `https://api.paeonia.no`. Deployed `9a6d88d4` on 2026-10-24.
- [x] Every environment variable the backend reads is set on `api.paeonia.no` (checked 2026-10-24). Clerk points at the production instance.
- [x] `https://api.paeonia.no` and `https://actions.paeonia.no` serve over TLS. `https://convex.paeonia.no` is reachable on the tailnet only.
- [x] Every app-callable function checks membership, entitlement, block state, and ownership from the session. 175 of 183 public functions call an auth helper. The other 8 need none. Convex has no row level security, so the tests in `backend/convex/*.test.ts` are the safety net.
- [x] Media uploads reject a mismatched size or content type, and signed media URLs (`GET /media`) expire and reject a bad signature.
- [x] Orphaned media cleanup crons run (`cleanup-media-storage`, `sweep-orphan-media-storage`).
- [x] Relationship cleanup crons run (`paeonia-cleanup-expired-relationship-content`, `paeonia-purge-deleted-relationship-content`).
- [x] The question catalog on `api.paeonia.no` matches the repository, and subscription products are seeded. `scripts/deploy-backend` seeds the products on every deploy.
- [ ] The catalog sync no longer moves existing daily questions to a new question version (the `ponytail:` step in `backend/convex/catalog.ts`), so answers keep the wording they were written for. Remove the step just before launch.
- [ ] A queued push reaches a real device as an alert and as a widget update. Needs a device.
- [ ] A restore from a nightly backup has been tried. Hourly and nightly backups run (checked 2026-10-24). The storage move on 2026-10-14 used the restore steps, but no drill has used a nightly backup.
- [x] No Convex admin key or Clerk secret key is reachable from the client source or the marketing app.
- [ ] `ios/Scripts/mint-review-codes.mjs` works against production, including registered demo partners. Needs three demo partner accounts on the production Clerk instance.

## Marketing Site

- [x] `bun run build` succeeds with static export.
- [x] Cloudflare Pages deploy succeeds.
- [x] `https://paeonia.no/` loads.
- [x] `https://www.paeonia.no/` redirects or resolves correctly. Added as a Pages custom domain on 2026-10-24. It had returned 522.
- [x] `https://paeonia.no/privacy` loads.
- [x] `https://paeonia.no/terms` loads.
- [x] `https://paeonia.no/support` loads.
- [x] `https://paeonia.no/join/<code>` fallback loads.
- [x] `/.well-known/apple-app-site-association` is served with the correct content type and no redirect problem.
- [x] Marketing logo assets load in production.
- [x] Favicon uses the mark, not a broken app-icon asset.
- [x] Header/footer links are not duplicated or noisy.
- [x] Landing page language matches shipped app state: private beta, TestFlight, or launched.
- [x] The site says Paeonia runs on iPhone and iPad. The hero, the FAQ and the join page say so in both languages. It is live once `main` is pushed.
- [x] Landing page does not promise unshipped features. The FAQ says the streak restore is the only extra purchase, and that it is optional.
- [x] Legal pages are published with production-oriented English and Norwegian privacy and terms text, including final operator details approved by the release owner.
- [x] Support page lists current support/contact emails.
- [x] Open Graph metadata uses final brand assets. Fixed on 2026-10-24.

## Localization And Copy

- [x] All user-facing iOS strings are in String Catalogs.
- [x] Swift code uses generated localization symbols, not raw keys. App Intents metadata is the exception, because the build rejects generated symbols there. `docs/agent-guides/ios-localization.md` records it.
- [ ] English strings are clear enough for a 16-year-old user. Needs a person. No technical words were found.
- [ ] Norwegian Bokmal strings are natural, not technical database-sounding translations. Needs a native speaker.
- [x] All new keys have English, Norwegian Bokmal, and translator comments.
- [x] No stale placeholder localization keys are reachable. The four unused keys were deleted on 2026-10-24.
- [x] Paywall copy is audited in English and Norwegian.
- [x] Account deletion copy is audited in English and Norwegian.
- [x] Location sharing copy is audited in English and Norwegian.
- [ ] Daily answer reveal copy is audited in English and Norwegian. Needs a person.
- [ ] Widget drawing save/clear copy is audited in English and Norwegian. Needs a person.
- [x] App Store metadata copy matches in-app language. The listing uses the in-app game names in both languages (2026-10-24).

## Accessibility And Device QA

- [ ] Small iPhone layout pass.
- [ ] Large iPhone layout pass.
- [ ] iPad layout pass, in portrait, landscape and split view.
- [ ] Latest supported iOS version pass.
- [ ] Minimum supported iOS version pass.
- [ ] Dynamic Type pass.
- [ ] VoiceOver smoke pass.
- [ ] Reduce Motion pass.
- [ ] Increased Contrast pass.
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
- [ ] Partner signs in -> accepts invite -> paired home.
- [ ] Non-paying partner receives entitlement after pairing.
- [ ] Both users answer today's question -> reveal works for the one who answers second.
- [ ] One user answers a question the partner answered on an earlier day -> reveal works.
- [ ] One user records voice answer -> partner can play it after reveal.
- [ ] One user sends photo answer -> partner can view it after reveal.
- [ ] One user creates memory with note.
- [ ] One user creates memory with photos.
- [ ] Partner adds note/photo to memory.
- [ ] User draws and saves widget update.
- [ ] Partner receives drawing notification/update.
- [ ] User enables location; map waits for partner.
- [ ] Partner enables location; distance/location appears.
- [ ] User disables location; map hides or updates as expected.
- [ ] User leaves relationship; private content disappears after sync.
- [ ] User signs out and signs back in; state restores correctly.
- [ ] User deletes account; state and backend behavior are correct (Clerk user removed, Sign in with Apple token revoked).

## Failure Mode QA

- [ ] No network during launch.
- [ ] No network during daily answer submit.
- [ ] No network during memory note-only create.
- [ ] No network during memory photo create.
- [ ] No network during widget save.
- [ ] No network during location update.
- [ ] StoreKit product loading fails.
- [ ] Purchase is cancelled.
- [ ] Purchase fails.
- [ ] Restore finds no subscription.
- [ ] Media upload fails.
- [ ] Voice recording permission denied.
- [ ] Camera/photo permission denied.
- [ ] Location permission denied.
- [ ] Push permission denied.
- [ ] Invite code invalid.
- [ ] Invite code expired.
- [ ] Partner leaves relationship while app is open.
- [ ] Relationship entitlement expires while app is open.
- [ ] App is killed during pending upload and reopened.

## App Store Connect

The text metadata lives in `ios/Scripts/appstore-metadata-source.json`, and `ios/Scripts/generate-appstore-metadata.mjs` writes it to `ios/fastlane/metadata/`.

- [x] App name: `Paeonia`.
- [ ] Subtitle, promotional text, description and keywords describe the current app. Rewritten on 2026-10-24 from competitor and App Store search research, with a new en-GB locale for a second Norwegian keyword field. In App Store Connect: upload them with `fastlane metadata`.
- [ ] Category selected.
- [ ] Age rating questionnaire completed honestly. The terms say 16+.
- [ ] Copyright filled.
- [ ] Support URL set.
- [ ] Privacy Policy URL set.
- [ ] Marketing URL set if desired.
- [ ] App Review contact information filled.
- [ ] App Review notes are pasted into App Store Connect. `ios/Scripts/mint-review-codes.mjs` prints them from `ios/Scripts/app-review-notes.txt` with fresh review codes. They explain:
  - [x] what Paeonia does
  - [x] why login is required
  - [x] how to use demo/review access
  - [x] how subscription sharing works, and that the invite code only links two accounts and unlocks nothing by itself
  - [x] how pairing normally works
  - [x] widget behavior
  - [x] location behavior, including that sharing while closed is optional, asked about right after sharing is turned on, needs Always, and sends the latest location only after a significant move
- [ ] In-app purchases submitted with the build.
- [ ] Subscription screenshot/metadata completed.
- [x] Privacy Nutrition Labels completed.
- [x] Encryption/export compliance answered. `Info.plist` sets `ITSAppUsesNonExemptEncryption` to false.
- [ ] Content rights answered.

## App Store Screenshots

The proposed v1 iPhone and iPad sets are in `ios/ASConnectScreenshots/1.0.0/3d/` (git-ignored), in English and Norwegian. They were uploaded to version 1.0.0 in App Store Connect on 2026-10-25 with `bundle exec fastlane ios upload_screenshots`. The scripts that make it are listed in `marketing/AGENTS.md`.

- [x] Screenshots use realistic fake couple content, not real private content. The test couple has fictional content seeded by `scripts/app-store-content`, with Unsplash photos listed in `scripts/assets/app-store/photos/SOURCES.md`.
- [x] Screenshots show Home, a game such as Ludo or Draw & Guess, the daily questions and chat, Memories, and the drawing widget or distance. The six panels are the drawing widget, the question chat, Ludo, Home with the countdown, Memories and Draw & Guess.
- [x] Screenshots do not imply unshipped features. Every panel is a real capture of the current app.
- [ ] Screenshots match final app icon, colors, and layout. Recapture before submission if the UI changes. The scripts rerun the whole set.
- [x] Required device sizes are generated, iPad included. The set has 6.9" iPhone (1320x2868) and 13" iPad (2064x2752) screenshots.

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

## Launch Cut Line

Do not ship 1.0 unless all of these are true:

- [ ] Two real users can pair reliably.
- [ ] One real subscription unlocks both partners.
- [ ] Daily challenge is usable with text, photo, voice, and partner-choice where configured.
- [ ] Answer reveal behavior is correct and understandable.
- [ ] Memories can be created, edited, synced, and recovered.
- [ ] Widget drawing works and does not leak private content unexpectedly.
- [ ] Partner location works only after both users opt in.
- [x] Relationship leave/account deletion removes access and starts cleanup.
- [ ] Legal, support, privacy labels, and App Store metadata are accurate.
- [ ] The app feels polished in its intentionally narrow scope.

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
