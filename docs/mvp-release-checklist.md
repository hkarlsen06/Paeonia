# Paeonia MVP Release Checklist

This is the active execution checklist for getting Paeonia to a review-ready MVP.

Use this instead of a phase roadmap. Paeonia is now past early planning: the important question is not "what phase are we in?", but "what must be true before we can ship?"

Checklist status was reconciled against repository source and public endpoint availability on 2026-07-11. Checked source/configuration items are not substitutes for device or production-flow QA; those stay unchecked until they are exercised in the environment named by the item.

## Shipping Standard

Paeonia is ready for MVP when:

- a real couple can sign in, pay, pair, use the core features, and recover from ordinary failures without developer help
- one partner can pay and both partners receive access through server-enforced entitlement
- private relationship content is protected by RLS, private Storage, local cache clearing, and relationship access-loss handling
- App Review can verify the app without needing two physical devices
- every public claim, screenshot, legal page, and privacy label matches the shipped build
- no reachable surface contains test, placeholder, or "not ready" language

## Source Documents

- Implementation owners: `docs/implementation-map.md`
- Product/data contract: `docs/phase-3-data-contract.md`
- Migration and RLS checklist: `docs/phase-3-migration-checklist.md`
- Marketing/app contract: `docs/marketing-app-contract.md`
- Design and copy rules: `docs/phase-2-design/`
- Historical UX audit with a current status summary: `docs/ux-friction-report.md`
- Question authoring rules: `docs/couple-question-guidelines.md`

## Release Blockers

These block TestFlight/App Review until resolved.

- [x] No active docs, scripts, or agent instructions point at the removed phase roadmap.
- [x] `docs/implementation-map.md` accurately reflects the current feature ownership.
- [x] No reachable app screen says "test account", "not ready", "still building", or similar placeholder copy.
- [x] App and widget privacy manifests declare their required-reason API usage.
- [x] Public privacy policy is final and live at `https://paeonia.no/privacy`.
- [x] Public terms are final and live at `https://paeonia.no/terms`.
- [x] Support page is final and live at `https://paeonia.no/support`.
- [x] In-app legal/support links open the production URLs.
- [x] Account deletion works end-to-end from the app.
- [x] Relationship leave/disconnect hides shared content after sync.
- [x] App Review can access a paired demo state without needing two reviewer-controlled devices.
- [x] In-app purchase products are configured in App Store Connect.
- [x] StoreKit sandbox monthly and annual purchases and entitlement refresh are tested on device.
- [x] StoreKit sandbox restore is tested on device.
- [x] One paying partner unlocks both partners through backend entitlement.
- [x] Subscription terms are clear before purchase.
- [ ] App icon is final in the app target, widget target, and App Store assets.
- [ ] App Store privacy labels match the actual data collected by the build.

## Repository And Build Hygiene

- [ ] Worktree is clean before release candidate tagging.
- [ ] Local branch is pushed intentionally before remote deployment.
- [x] No secrets, service-role keys, APNs keys, StoreKit secrets, or review access codes are committed.
- [x] `.gitignore` excludes generated build output, Xcode derived data, local Supabase temp files, and local environment files.
- [x] `AGENTS.md` points agents to `docs/mvp-release-checklist.md` and `docs/implementation-map.md` as the active planning/navigation docs.
- [x] CI smoke checks run on pushes.
- [ ] The committed project opens cleanly in Xcode.
- [ ] The committed SwiftPM/package state is portable for a fresh checkout.
- [x] Local-only/debug-only surfaces are either removed or hidden behind debug configuration.
- [x] Generated assets are committed only when they are canonical source or required runtime assets.

## Verification Commands

Run these before a release candidate.

- [x] `swiftlint --quiet` (exit 0; advisory warnings remain).
- [x] `./scripts/xcode-build-agent.sh --json` (Xcode 27 beta; succeeded).
- [x] `./scripts/xcode-test-agent.sh --json` (468 tests, 0 failures).
- [x] `bun run build`
- [x] `DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase db lint --local --schema public,internal --fail-on error`
- [x] `DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase db reset --local --no-seed`
- [x] `DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase test db` (168 pgTAP tests, 0 failures).

Record any skipped command with the reason.

## iOS App Configuration

- [x] Bundle identifier is final: `no.paeonia.app`.
- [x] Display name is final: `Paeonia`.
- [x] Minimum supported iOS version is intentional.
- [x] App Group entitlement is present for app and widget.
- [x] Associated Domains include `applinks:paeonia.no`.
- [x] Push notification capability is configured.
- [x] Sign in with Apple capability is configured.
- [x] Location usage descriptions are present and plain-language.
- [x] Microphone usage description is present for voice notes.
- [x] Photo library/camera usage descriptions are present for media answers and memories.
- [ ] Widget target is embedded and visible in a release build.
- [x] Notification Service Extension is configured if required by the shipped notification behavior.
- [x] App icon asset is linked correctly in all relevant targets.
- [x] Launch screen uses final brand treatment or an intentionally minimal native launch.
- [x] Release build configuration points at production Supabase and production marketing URLs.
- [x] Debug/test account shortcuts are unavailable in release builds.

## Authentication And Onboarding

- [ ] Sign in with Apple works with normal Apple ID.
- [ ] Sign in with Apple works with private relay email.
- [ ] Google Sign-In works.
- [x] No email/password, magic-link, or passkey sign-up surface is reachable in MVP.
- [ ] Auth errors are understandable to a normal user.
- [x] OAuth profile name is used when available.
- [x] Name fallback flow works when OAuth does not provide a usable name.
- [x] Display name can be changed later.
- [x] Profile photo upload and replacement have a tested source path.
- [x] A private OAuth profile-photo fallback appears when the user-uploaded override is missing and cannot itself be removed.
- [x] Relationship start date is collected contextually from the milestone card, not during onboarding.
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
- [x] The trial timeline's two-days-left promise is backed by an idempotent localized push queued from verified Apple trial data.
- [x] Primary CTA says what happens next, including App Store confirmation.
- [x] Restore purchases works when signed into the paying account.
- [ ] Restore does not grant access to unrelated accounts.
- [x] Backend records verified StoreKit transactions.
- [ ] StoreKit server notifications endpoint is deployed and configured.
- [ ] Apple server notification shared secret/key configuration is correct.
- [ ] Grace period behavior preserves access when Apple reports grace state.
- [x] Expired subscription removes entitlement when neither partner has active access.
- [ ] Lifetime/test/review grants are scoped, auditable, revocable, and intentional.
- [ ] App checks whether the current couple already has active entitlement before starting purchase.
- [ ] Simultaneous purchase attempts cannot create conflicting active entitlements.
- [x] Manage subscription link is available in settings or paywall footer.
- [x] Subscription sharing is explained clearly: one subscription unlocks Paeonia for both partners.
- [x] Paywall does not imply free access if the product is paid.
- [x] Paywall invite-code entry does not confuse joining with purchasing.

## Pairing And Relationship Lifecycle

- [ ] Invite creation works for an unpaired entitled user.
- [ ] Invite code is short enough to share manually.
- [ ] Invite link opens the app through Universal Links.
- [x] `/join/*` fallback route explains what to do if the app is not installed.
- [x] Accepting an invite previews who invited the user before pairing.
- [x] Accepting an invite requires explicit confirmation.
- [x] Expired invite handling is clear.
- [ ] Already-paired user cannot accidentally join another relationship.
- [ ] Pending invites do not create empty couples.
- [ ] Couple row is created only after acceptance.
- [x] Pairing celebration works without blocking access if animation fails.
- [x] Relationship ended notice is a real screen/state, not an unavailable placeholder.
- [x] Leaving a relationship is clearly warned.
- [x] Leaving immediately removes local access to shared relationship content.
- [x] Leaving schedules backend cleanup according to retention policy.
- [x] Account deletion while paired has the same relationship effect as leaving.
- [x] Prior report/block safety warnings behave as documented if re-pairing is attempted.
- [x] No public discovery, user search, or profile lookup is reachable.

## Daily Challenge

- [ ] Today’s challenge loads from database-backed question content.
- [ ] A user receives up to three own daily questions.
- [ ] A user must answer three own daily questions to complete the challenge.
- [ ] Partners may receive different questions.
- [ ] A partner’s answered questions appear in the history/answered screen for the other partner to answer.
- [ ] Partner answers remain hidden until the current user answers that same question.
- [ ] Locked/revealed answer states are clear without relying only on icons.
- [ ] Answer kinds are respected per question version.
- [ ] Text answers work.
- [ ] Photo answers work.
- [ ] Voice answers work.
- [ ] Partner-choice answers work.
- [ ] Combined answer-kind behavior follows `docs/couple-question-guidelines.md`.
- [ ] Staged drafts survive closing/reopening the answer composer.
- [ ] Offline answers queue and show local-first reassurance.
- [ ] Queued answers upload later without duplication.
- [ ] Media/voice upload failure does not drop user content.
- [ ] Answer reveal works after both partners answer.
- [ ] Only fully revealed question cards open their private question chat.
- [ ] The first follow-up message creates the thread lazily; opening chat never creates an empty thread.
- [ ] Offline chat messages appear immediately and later send without duplication.
- [ ] Question-chat notifications route to the right question without exposing message content on the lock screen.
- [ ] Question-chat UI and notification settings are localized in English and Norwegian Bokmal.
- [ ] Partner-answer notification does not expose answer content.
- [ ] Challenge completion notification copy explains that the recipient must answer to see partner content.
- [ ] Daily challenge history groups questions by effective latest-answer day.
- [ ] Carried-over partner questions remain answerable without disappearing unexpectedly.
- [ ] Shuffle works.
- [ ] Shuffled questions are excluded for the intended window.
- [ ] Shuffle undo works if implemented in the UI.
- [ ] Resurfaceable questions can reappear after the configured period and show prior answer dates.
- [ ] Non-resurfaceable answered questions do not repeat.
- [ ] Question content has English and Norwegian Bokmal localizations.
- [ ] No question prompt assumes gender, public sharing, or unsafe relationship behavior.

## Streaks

- [ ] Couple-level streak is calculated from qualifying activity.
- [ ] Completing daily challenge keeps the streak alive.
- [ ] Updating the shared widget keeps the streak alive.
- [ ] Streak does not expire before midnight in the latest partner timezone.
- [ ] Started couple-day timezone window is frozen as documented.
- [ ] Streak reminder can be scheduled before expiry.
- [ ] Streak reminder copy is privacy-safe.
- [ ] Broken streak state is understandable.
- [ ] Streak restore flow works.
- [ ] Streak restore purchase cannot be confused with subscription entitlement.
- [ ] Streak restore window is intentional and tested.

## Memories

- [ ] Memory timeline loads local-first.
- [ ] Empty state has a clear create action.
- [ ] Memory requires title and date.
- [ ] Memory can be created with note-only content.
- [ ] Memory can be created with photo-only content.
- [ ] Memory supports up to 5 photos per partner.
- [ ] Partner can add their own note later.
- [ ] Both partners can edit title/date as intended.
- [ ] A user can edit their own note.
- [ ] A user can add/remove their own photos.
- [ ] Photo compression follows the intended space-saving approach.
- [ ] Photo upload failure leaves the draft intact.
- [ ] Memory photos are loaded through private signed URLs.
- [ ] Memory media cache clears on relationship access loss.
- [ ] Memory deletion/hide behavior matches product decision and RLS.
- [ ] Memory thread-message write path is either surfaced in UI or intentionally deferred.
- [x] Memory voice notes are cut from MVP; active product copy and App Store materials must not imply that memories include voice.

## Widget Drawing

- [x] Widget can be added to Home Screen.
- [x] Widget shows a safe placeholder before first drawing.
- [x] Tapping widget opens the app drawing flow.
- [x] Drawing uses PencilKit.
- [ ] Canonical drawing payload is stored as `PKDrawing`/vector data, not PNG.
- [ ] Raster output is derived for display/network efficiency only.
- [x] Saving a drawing updates local app preview.
- [x] Saving a drawing updates widget payload through App Group storage.
- [x] Saving a drawing uploads private drawing payload.
- [ ] Partner receives update notification for new drawing.
- [x] Silent/widget refresh behavior works as far as iOS allows.
- [ ] Drawing history preserves prior revisions.
- [ ] Drawing history shows author and timestamp.
- [ ] Clearing canvas is local until a new revision is saved.
- [ ] Drawing save failure keeps the drawing recoverable.
- [x] Widget privacy setting exists or the shipped behavior is explicitly privacy-safe by default.
- [x] Widget does not expose sensitive private text on the lock screen.
- [x] App Group data clears on sign-out, account deletion, and permanent relationship access loss; temporary entitlement loss uses a privacy-safe hide.

## Countdown And Relationship Milestones

- [x] Relationship start date flows from the milestone setup/server state to home.
- [x] Countdown defaults to next monthly milestone under one year.
- [x] Countdown defaults to next anniversary after one year.
- [x] Round day milestones behave intentionally.
- [x] Missing/invalid start date shows honest setup copy, not fake data.
- [x] Countdown date formatting localizes correctly.
- [x] Countdown card has no hardcoded sample milestone in release.
- [x] Custom countdowns are absent from active product claims/screenshots.
- [ ] Countdown reminders are either implemented or absent from notification settings/copy.

## Partner Location

- [x] Location map is hidden unless both partners opt in.
- [x] Location permission is requested at the right moment.
- [x] Permission copy explains latest location only, foreground updates only, and no location history.
- [x] Foreground location update has a tested source path.
- [x] Offline stale location retries cannot overwrite newer location.
- [x] Latest partner location displays with last-updated relative time.
- [x] Stale marker behavior after 24 hours is implemented or intentionally deferred from UI claims.
- [x] Disabling sharing deletes/hides latest location as documented.
- [x] Relationship end/account deletion removes location visibility.
- [ ] App Store privacy labels include precise location.
- [x] Privacy policy explains opt-in latest-location sharing, no history, stale timestamps, and deletion behavior clearly.

## Notifications

- [ ] APNs auth key/certificate is configured.
- [ ] Push registration works on device.
- [ ] Device token is stored with environment and user relationship context.
- [ ] Notification preferences are available in settings.
- [ ] User can disable streak reminders.
- [ ] User can disable partner-answer notifications.
- [ ] User can disable widget drawing notifications.
- [ ] New drawing notification works.
- [ ] Partner-answer notification works.
- [ ] Partner-completed-daily-challenge notification works if shipped.
- [ ] Streak-expiry reminder works if shipped.
- [ ] Notification payloads do not include answer text, note text, media URLs, invite codes, precise location, or report details.
- [ ] Notification outbox records delivery attempts and failures.
- [ ] Permission-denied state is graceful.
- [ ] App still works if notifications are never enabled.

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
- [x] User can create a privacy/data request or contact support for data access/export.
- [x] Delete account copy explains account, relationship, and content consequences.
- [x] Destructive actions require confirmation.
- [x] Support email is `support@paeonia.no`.
- [x] Contact email is `contact@paeonia.no`.
- [ ] Reported content remains visible/hidden according to product decision until admin action.
- [x] Admin/moderation runbook exists for reports, even without admin UI.

## Offline-First And Sync

- [ ] App launches offline with cached relationship state.
- [ ] Paired home renders cached content before network refresh where safe.
- [ ] Daily challenge snapshot cache works.
- [ ] Memory cache works.
- [ ] Widget payload cache works.
- [x] Location visibility cache does not leak after relationship access loss.
- [ ] Pending operations are idempotent.
- [ ] Pending operation retries do not duplicate answers, memories, drawings, or locations.
- [ ] Sync cursors persist only after successful page/application.
- [x] Relationship access-loss events clear or privacy-hide private local caches according to whether loss is permanent.
- [x] Sign-out clears private local caches.
- [x] Account deletion clears private local caches.
- [x] Media draft stores do not leak content across users.
- [ ] Slow network states are understandable.
- [ ] Recoverable sync errors route through the shared banner or local status, not raw technical messages.
- [ ] No private content is written to logs.

## Supabase Schema, RLS, And Storage

Remote baseline checked on 2026-07-10: all 74 committed migrations are present and the five expected Edge Functions are active. Advisors have no blocking findings. The security advisor reports 64 warnings for authenticated `security definer` public wrappers; these are intentional thin wrappers over authorized `internal.*` implementations required by Paeonia's schema boundary. The performance advisor reports 67 unused-index informational findings on the pre-launch dataset; retain the relationship, RLS, cleanup, and foreign-key indexes until representative production usage exists.

- [x] All migrations apply cleanly to a fresh local database.
- [x] Supabase lint has no blocking findings.
- [x] RLS is enabled on all client-facing tables.
- [x] Public app RPC wrappers that call `internal.*` are thin `security definer` wrappers with fixed `search_path`; service-only invoker wrappers remain restricted.
- [x] Internal app functions perform `auth.uid()` authorization checks where user context is required.
- [x] Foreign keys and indexes exist for relationship/user/couple access paths.
- [x] `internal` schema is not broadly exposed to ordinary clients.
- [x] Storage buckets are private.
- [x] Profile photo bucket policy covers custom and private provider-fallback assets.
- [x] Couple media bucket policy is covered by the security surface tests.
- [x] Widget drawing payload bucket policy is covered by the security surface tests.
- [x] Report snapshot bucket policy is covered by the security surface tests.
- [x] Media reservation/finalize flow prevents path spoofing.
- [x] Orphaned media cleanup behavior is covered by pgTAP.
- [ ] Relationship cleanup job works.
- [x] StoreKit notification endpoint is deployed.
- [x] Widget push endpoint is deployed.
- [x] Cleanup media endpoint is deployed.
- [ ] Edge Function environment variables are configured in production.
- [x] `api.paeonia.no` custom domain works for Supabase.
- [x] Advisors are checked and intentional findings are documented.
- [x] No service-role credential/path is reachable from the client source.

## Marketing Site

- [x] `bun run build` succeeds with static export (verified 2026-07-11).
- [x] Cloudflare Pages deploy succeeds.
- [x] `https://paeonia.no/` loads.
- [x] `https://www.paeonia.no/` redirects or resolves correctly.
- [x] `https://paeonia.no/privacy` loads.
- [x] `https://paeonia.no/terms` loads.
- [x] `https://paeonia.no/support` loads.
- [x] `https://paeonia.no/join/<code>` fallback loads.
- [x] `/.well-known/apple-app-site-association` is served with the correct content type and no redirect problem.
- [x] Marketing logo assets load in production.
- [x] Favicon uses the mark, not a broken app-icon asset.
- [ ] Header/footer links are not duplicated or noisy.
- [ ] Landing page language matches shipped app state: private beta, TestFlight, or launched.
- [ ] Landing page does not promise unshipped features.
- [x] Legal pages are published with production-oriented English and Norwegian privacy and terms text, including final operator details approved by the release owner.
- [x] Support page lists current support/contact emails.
- [ ] Open Graph metadata uses final brand assets.

## Localization And Copy

- [ ] All user-facing iOS strings are in String Catalogs.
- [ ] Swift code uses generated localization symbols, not raw keys.
- [ ] English strings are clear enough for a 16-year-old user.
- [ ] Norwegian Bokmal strings are natural, not technical database-sounding translations.
- [x] All new keys have English, Norwegian Bokmal, and translator comments.
- [ ] No stale placeholder localization keys are reachable.
- [x] Paywall copy is audited in English and Norwegian.
- [x] Account deletion copy is audited in English and Norwegian.
- [x] Location sharing copy is audited in English and Norwegian.
- [ ] Daily answer reveal copy is audited in English and Norwegian.
- [ ] Widget drawing save/clear copy is audited in English and Norwegian.
- [ ] App Store metadata copy matches in-app language.

## Accessibility And Device QA

- [ ] Small iPhone layout pass.
- [ ] Large iPhone layout pass.
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
- [ ] Both users answer daily questions -> reveal works.
- [ ] One user answers partner question -> reveal works.
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
- [ ] User deletes account; state and backend behavior are correct.

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

- [x] App name: `Paeonia`.
- [x] Subtitle written.
- [x] Promotional text written.
- [x] Description written.
- [x] Keywords selected.
- [ ] Category selected.
- [ ] Age rating questionnaire completed honestly.
- [ ] Copyright filled.
- [ ] Support URL set.
- [ ] Privacy Policy URL set.
- [ ] Marketing URL set if desired.
- [ ] App Review contact information filled.
- [ ] App Review notes explain:
  - [ ] what Paeonia does
  - [ ] why login is required
  - [ ] how to use demo/review access
  - [ ] how subscription sharing works
  - [ ] how pairing normally works
  - [ ] widget behavior
  - [ ] location behavior
- [ ] In-app purchases submitted with the build.
- [ ] Subscription screenshot/metadata completed.
- [ ] Privacy Nutrition Labels completed.
- [ ] Encryption/export compliance answered.
- [ ] Content rights answered.

## App Store Screenshots

- [ ] Screenshots use realistic fake couple content, not real private content.
- [ ] Screenshot 1 shows the private couple home.
- [ ] Screenshot 2 shows daily question/reveal.
- [ ] Screenshot 3 shows shared widget drawing.
- [ ] Screenshot 4 shows memories.
- [ ] Screenshot 5 shows countdown/location or settings/privacy.
- [ ] Screenshots do not imply unshipped features.
- [ ] Screenshots match final app icon, colors, and layout.
- [ ] Required device sizes are generated.

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
