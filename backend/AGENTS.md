# Backend agent guidance

Paeonia's backend is a self-hosted Convex deployment.

## Layout

Paths below are relative to `backend/`. Everything that more than one feature module needs lives in `convex/lib/` (plain helpers, no registered functions). `convex/*.test.ts` hold the `convex-test` tests next to their module.

- Keep the import graph of a query module small. Convex loads and evaluates every module a function imports on every call, and `import()` is not allowed in queries and mutations. On a local backend a function that imports about 400 KB of bundled code costs about 1 ms more per call than one that imports 100 KB, and the hosted server is about four times slower. A module with queries must not import `lib/gameRegistry.ts`, which pulls in every game. Put the code that needs it in its own module and call it with `ctx.runMutation`, as `games.ts` does with `gameHooks.ts` and `relationship.ts` does with `relationshipJobs.ts` (`lib/relationshipEnd.ts` reaches every game through `lib/badges.ts`). `lib/mediaOrphans.ts` also stays free of the game libraries and asks `lib/gameMediaReferences.ts` whether a game still shows a file.
- `convex/lib/gameWords.ts` imports `games/words/en.json` and `nb.json` into the bundle, so a word list change needs a deploy.

## iOS contract

The iOS app subscribes to reads over the ConvexMobile WebSocket client and writes the results into its local store, so partner changes show up live. Writes and one-shot reads go over the HTTP API (`POST /api/mutation`, `/api/query`, `/api/action` with `{"path","args","format":"json"}`) through the app's offline outbox, and the widget extension uses HTTP only. Both the HTTP calls and the socket use a token from the Clerk JWT template `convex` (claims `{"aud": "convex"}`, lifetime 15 minutes). The socket needs the long lifetime because every new token on a socket makes Convex re-run all of that phone's subscribed queries. With the 60-second session token, that happened about every 50 seconds per open app. `PaeoniaConvexAuthProvider` fetches the template token a minute before the old one expires. The HTTP client asks for the same token (`PaeoniaClerk.convexToken`), so the two share one fetch. Clerk keeps template tokens in memory only, so `ConvexTokenStore` (`ios/PaeoniaShared/`) saves the last one in the keychain with its Clerk session id, and a launch within its 15 minutes sends it without asking Clerk. Signing out clears it. `scripts/deploy-backend` runs `scripts/ensure-clerk-jwt-template` with the deployment's `CLERK_SECRET_KEY` on every deploy, which creates the template or corrects its claims and lifetime, so a new Clerk instance needs no dashboard setup.

The conventions below come from the functions ported from Supabase. Follow them for new functions so the code stays consistent. They are not a compatibility promise: rename a function, change its arguments, or reshape its result when that helps, and update the iOS caller in the same change.

- The export name is the Supabase function name, unchanged (`create_memory`). The path is `<module>:<name>`, for example `memories:create_memory`.
- Argument names are the SQL parameter names, unchanged, including the `p_` prefix. Optional SQL parameters with defaults become `v.optional(...)`; `null` must also be accepted where SQL accepted NULL (`v.optional(v.union(v.null(), ...))`).
- The return value is the JSON PostgREST returned: `jsonb` results keep their keys; `returns table`/`setof` become an array of row objects with the SQL column names; a scalar becomes the bare value; `void` becomes `null`.
- Reads are public `query` functions so the app can subscribe to them. A query must not depend on the clock for which rows it picks, because Convex re-runs it only when the data it read changes. Pass the day or cursor as an argument instead, and let a cron write time-based state changes (expired entitlements, broken streaks, expired invites) so subscribers update. Reads that must write (get-or-create, rate-limit bookkeeping) or that sign time-limited URLs (`get_media_signed_url`) stay mutations. The app calls an `ensure` mutation such as `get_or_create_widget_canvas` or `start_daily_challenge_snapshot` once, then subscribes to the matching query.
- Writes are public `mutation`s or `action`s. Service-role or operator-only SQL functions become `internalMutation`/`internalQuery`/`internalAction` and are run with `npx convex run`.
- Errors use `fail(code, message)` from `lib/errors.ts`, which throws `ConvexError({ code, message })`. Keep the exact SQL `raise exception` message and SQLSTATE code. The app matches substrings such as `stale location update`, `revision conflict`, `40001`, and `pairing_invite_secrets_code_hash_unique`.

## Data conventions

- Field names stay snake_case, matching the SQL columns.
- Tables with a uuid primary key keep it as a string field `id` (client-supplied where the RPC accepted one, otherwise `crypto.randomUUID()`), with an index `by_uuid` on `["id"]`. `by_id` is a reserved Convex index name. Look rows up through `lib/db.ts` helpers, never by scanning.
- Tables with composite or natural primary keys keep those columns and get a unique-by-convention index on them.
- Foreign keys are uuid strings. Convex does not enforce them: check existence where the SQL foreign key mattered, and perform `on delete cascade` and `set null` behavior explicitly in the deletion code.
- Unique constraints become an index lookup before the insert in the same mutation. Mutations are serializable, so this is race-free.
- Timestamps are ISO-8601 UTC strings from `nowIso()` (`Date.prototype.toISOString`, millisecond precision). Compare them as strings only when both came from `toISOString`. Dates are `YYYY-MM-DD` strings.
- `bytea` columns become lowercase hex strings (`sha256Hex` in `lib/crypto.ts`).
- `jsonb` columns use specific object validators when the shape is fixed, otherwise `v.any()`.
- Check constraints with a fixed value list become `v.union(v.literal(...))`. Length, range, and cross-column checks are enforced in write helpers with `fail("23514", ...)`.
- Do not store derived data that SQL computed in views. Compute it in the reading function.
- Nullable SQL columns are `v.optional(...)` and are omitted when the value is null. Nothing stores `null`. To clear a column, patch it to `undefined`. Reading code converts a missing field to `null` in API output (`orNull` in `lib/db.ts`). Argument validators still accept `null` where SQL did (see the iOS contract). Seed JSON files contain explicit `null`s, so loaders must drop them (`omitNulls` in `lib/db.ts`).
- Every uuid argument passes through `uuidArg` (or `optionalUuidArg`) from `lib/ids.ts` before use. iOS sends uppercase uuids, Postgres accepted any case, and Convex compares strings exactly. The helper lowercases and fails with `22P02 invalid input syntax for type uuid: "<value>"`. Stored uuids are always lowercase.
- Every timestamp argument passes through `timestampArg` (or `optionalTimestampArg`), which normalizes to `toISOString()` form and fails with `22007`. iOS sends ISO-8601 with fractional seconds, sometimes with a `+00:00` offset. Date arguments (`YYYY-MM-DD`) use `dateArg`.
- API output uses snake_case keys and `toISOString()` timestamps. iOS decodes them without key conversion.
- Index names are `by_<col>_<col>` and Convex limits them to 64 characters. Partial SQL indexes became full indexes: filter the rest in code. To match a missing optional field in an index, use `.eq("field", undefined)`.
- `app_runtime_secrets` has no table. Its values are environment variables. The `users` table also has `claim_display_name`, the last Clerk display name seen, used to detect provider name changes.
- `schema.ts` comments list the SQL foreign key delete behavior per table. Convex enforces none of it.

## Auth and authorization

- Clerk issues the JWT. `convex/auth.config.ts` trusts the Clerk issuer with `applicationID: "convex"`. Both the session token (Convex integration) and the `convex` JWT template carry `aud: convex`. A ban or deleted account takes effect on the next call whatever the token's lifetime, because every call looks the user up.
- `users` maps the Clerk `subject` to the Paeonia uuid that every other table references. `lib/auth.ts` exports `getCurrentUserId(ctx)` (returns null when signed out or not yet provisioned), `requireUserId(ctx)` (fails with `42501 authenticated user required`), and `ensureCurrentUser(ctx)` (mutations only). `ensureCurrentUser` replaces the `auth.users` triggers: it creates the `users` row and the profile from the Clerk identity claims on the first authenticated call.
- Convex has no row level security, so every public function performs the membership, entitlement, block, and ownership checks explicitly, using the helpers in `lib/access.ts`.
- Never trust a user id, couple id, or role from arguments for authorization. Derive them from the session.
- Access helpers take the user id explicitly, for example `canAccessCoupleContent(ctx, userId, coupleId)`. Get `userId` from `requireUserId` once per function and pass it down.
- `is_admin` was always false, so `isAdmin()` in `lib/access.ts` returns false. It is about content access, and no app user gets more of that. The admin area is separate: `admin.ts` checks the caller's Clerk user id against `PAEONIA_ADMIN_CLERK_USER_IDS` on every call, and only lets admins search users, ban, unban, and read the audit log (`admin_audit_log`). It never shows relationship content.
- Bans: `users.banned_at` is set by `banUser` in `lib/bans.ts`, which also ends the relationship and turns off push devices. `activeUserIdForSubject` treats a banned user as signed out, so every function refuses them without its own check. `get_access_snapshot` answers `account_status: "banned"`, and the app shows the closed-account screen. Account deletion still works for a banned user. Nobody can ban themselves or an admin.
- Clerk's default session token has no provider or name claims. `delete_account` asks the Clerk Backend API for linked Apple accounts, so Apple token revocation does not depend on a claim. An optional custom claim `auth_provider` (`apple` or `google`) and the standard name claims, if added to the session token, fill `users.auth_provider` and the initial profile name. One Clerk user can link both Apple and Google. `identity:sync_sign_in_methods` (called by the app after a link or unlink) reads Clerk's linked accounts and stores `apple` in `users.auth_provider` whenever Apple is linked, otherwise `google`. Apple wins everywhere because only Apple has a revocation duty. `delete_account` asks Clerk again, and `requestAccountDeletion` upgrades a stored job to Apple when Clerk shows Apple is linked. A Clerk lookup that fails is unknown, not "no Apple": when the app sent an Apple authorization code, `delete_account` treats the account as an Apple account and revokes without the subject check. The app keeps a note on the phone until `sync_sign_in_methods` succeeded and sends it again when the app opens (`SignInMethodsServerSync`).
- In both Clerk instances, turning on "Sign-in with email" also turns on "Sign-up with email". Ticket sign-in needs the user to have an identifier, such as an email, which is why the test couple has made-up verified emails.

## Write helpers

Convex has no triggers. A table with side effects on write gets write helpers in its owning `lib/` file or module, and other code calls them instead of `ctx.db.insert`, `patch` or `delete` directly.

- Patches that write `updated_at` go through `withUpdatedAt` or `withTouch` (which also bumps `revision`). Do not hand-write `updated_at`.
- Call `assertNoPendingAccountDeletion(ctx, userId)` before writing a table that a pending account deletion guards, and `tombstoneReportTargets` before deleting a reportable row.
- Postgres ran orphan media triggers at commit time. Call the `queue*IfOrphaned` helpers after the mutation's last write to the referencing rows.
- After writing `user_devices`, call `refreshStreakAfterDeviceTimeZoneChange`. After changing `profiles.time_zone_id`, call `refreshStreakAfterProfileTimeZoneChange`. Insert daily answers only through `insertDailyAnswer`, which records the streak activity and queues the partner push. After a memory insert, call `enqueueMemoryCreatedNotification`. After a story insert, call `enqueueStoryPostedNotification`. After a widget revision insert, call `enqueueWidgetUpdateAlert`.
- Insert outbox rows only through `insertNotificationOutbox` and `insertWidgetPushOutbox`. They apply the check constraints, dedupe keys and payload safety rule, and queue the send for the row's `scheduled_for`. The safety rule is an allowlist: `NOTIFICATION_PAYLOAD_FIELDS` in `lib/notifications.ts` names every field each kind may carry, and refuses any other field and any nested object. A new payload field needs an entry there, and must never hold something a person wrote. `prepare_notification` checks the payload again before the send.
- A day that ended stays what it was for the streak. Date every together day with `dayOf` on `streakClock`, write only today or later, and call `keepVisitDays` before any write that changes a visit's dates or deletes it.
- `readCoupleStreak` is the pure streak reader for queries. `getCoupleStreakForCouple` first persists a break with `detectStreakBreak`, so call it only from a mutation. The streak cron and `applyStreakRestore` persist breaks, so `restorable_count` is stored before a restore needs it.
- Time zone math uses `Intl.DateTimeFormat` and follows the Postgres rules at daylight saving changes: a local time in a spring-forward gap uses the offset from before the gap, and an ambiguous fall-back time resolves to standard time.
- `lib/rateLimits.ts` holds every rate limit. To add one, add an entry to `LIMITS` and call `consumeRateLimit(ctx, name, userId)` first thing inside the `runClientOperation` callback (`consumeGlobalRateLimit` for a limit with no user), so replays are free and a refusal rolls back. It fails with `53300`, which the app retries later instead of dropping the write. Set the capacity above the backlog an offline phone sends at once.
- Every read and serve of a media asset checks `isUsableMediaAsset` (`lib/mediaAssetState.ts`).
- A chat thread's subject has one case per `conversation_threads.kind` in `lib/threadSubjects.ts`. A new kind of chat adds a link table and one case in each function there.
- A reaction target kind has an access check in `REACTION_TARGETS` (`lib/reactions.ts`). Deleting a thing's reactions and its favorites (`deleteReactionsOf`, `deleteFavoritesOfTarget`) belong in the same places, and the couple cleanup uses `deleteCoupleReactions` and `deleteCoupleFavorites`.
- A topic question is a `daily_question_instances` row with `topic_collection_id` and no `couple_day_id`, so readers that start from answers must skip it (`isTopicInstance` in `dailyQuestions.ts`). Any other write to a topic's catalog tables calls `rebuildTopicCatalogs`, as `catalog:sync_catalog` does.
- A favorite kind is a name in `FAVORITE_KINDS` (`lib/validators.ts`) and one loader in `lib/favorites.ts`.
- `lib/dataExportRegistry.ts` needs an entry for every new table (see Data export).
- `lib/search.ts` holds the content search's text rules. Search indexes find candidates by word prefix, and code applies the access rules the app's own screens apply, so a new searchable thing needs both.

## Tests

The root [Testing](../AGENTS.md#testing) rules say when a change needs a test.

- Test helpers live in `convex/test.setup.ts`. The two dots in test file names keep Convex from bundling them.
- For time-dependent code use `vi.useFakeTimers({ toFake: ["Date"] })` and `vi.setSystemTime(...)`. End tests that queue a push with `await t.finishAllScheduledFunctions(vi.runAllTimers)`. Tests have no APNs keys, so queued pushes stay unsent. `deliverDuePushes(t)` in `push.testing.ts` runs the send-time checks on the due rows and marks the ones that pass as sent. `pushQueue.test.ts` mocks `sendWithEnvironmentFallback` to test real sends, retries included.
- A test that drives a workpool job uses `vi.useFakeTimers()` with every timer faked, then `await t.finishAllScheduledFunctions(vi.runAllTimers)`. The pool waits on timers between steps, and with only `Date` faked its loop keeps polling and never goes idle. Pass a higher `maxIterations` (the second argument) when a test runs out every retry.
- A test that waits for a presence timeout (a game screen or typing that stopped its heartbeats) calls `vi.useFakeTimers()` before the first heartbeat, then `await t.finishAllScheduledFunctions(vi.runAllTimers)`. The component's disconnect worker sleeps on a scheduled function, and one scheduled while only `Date` was faked waits on the real clock.

## Client operations

Local-first writes from iOS carry `p_client_operation_id`, `p_client_id`, `p_client_sequence`, and `p_local_created_at`. Wrap them with `runClientOperation` from `lib/clientOperations.ts`. Where a late retry must not overwrite a newer write from the same phone, also check `isSupersededClientOperation`. It returns the stored response when the same operation already succeeded, fails with `23505 client operation replay hash mismatch` when the request differs, and stores the new response otherwise. The request hash is the `sha256Hex` of a stable JSON encoding of the request fields the SQL function hashed.

## Media storage

- Files live in Convex file storage. `media_assets` keeps its SQL columns, and `storage_id` holds the `Id<"_storage">` once the upload finishes.
- `create_pending_media_upload` returns the SQL reservation fields plus `upload_url` from `ctx.storage.generateUploadUrl()`. The app POSTs the bytes there and passes the returned `storageId` to `finalize_media_upload` as `p_storage_id`. Finalize checks size and content type against `ctx.db.system.get(storageId)` before accepting.
- Convex storage URLs never expire, so do not hand them out. `get_media_signed_url` returns the SQL function's rows, each with an added `signed_url` string. The SQL version returned only the authorized bucket and path, and the app then asked Supabase Storage to sign it. `signed_url` points to the `GET /media` HTTP action with `asset`, `exp`, and an HMAC-SHA256 `sig` signed with the `PAEONIA_MEDIA_URL_SECRET` environment variable. The action verifies the signature and expiry, then streams the blob. Use the expiry the app asked for (`p_expires_in_seconds` or the SQL equivalent), capped at the old limit.
- Hosted origins: client API `https://api.paeonia.no` (`CONVEX_CLOUD_URL`), HTTP actions `https://actions.paeonia.no` (`CONVEX_SITE_URL`). Build signed URLs from `process.env.CONVEX_SITE_URL`.

## Partner names

A member can give their partner a nickname (`couple_members.partner_nickname`). It is private: only the member who set it reads it, and the partner is never told. A new field or function that names the partner must respect it.

- Any push title, push body, widget payload or API field that puts a partner's name in front of a viewer gets the name from `nameForViewer(ctx, viewerUserId, subjectUserId)` in `lib/partnerNames.ts`. It returns the viewer's nickname for the subject, otherwise the subject's own name, otherwise null. Use `nameAndSourceForViewer` when the client must know which one it got. `notificationAlertTitle` takes the recipient for this reason.
- Do not read `profiles.display_name` for this. `partnerNames.test.ts` reads the source of every file under `convex/` and fails when a file outside its `MAY_READ_DISPLAY_NAME` list mentions `display_name`. That list holds a reason for each file (the user's own profile, operator tools, the invite preview before a couple exists). Add a file there only when it never shows a partner's name to a partner.
- A name in an API result is a viewer-specific field, so name it for what it holds and keep the raw account name under another key (`partner_account_name`). Do not add a `display_name` key to a result for a partner.
- The nickname ends with the relationship. `endRelationshipForPair` clears it for both members, which covers leaving, blocking, reporting, bans and account deletion. The couple cleanup and purge clear it again.

## Data export

"Download my data" (`dataExport.ts`, `dataExportBuild.ts`) builds a zip of everything the signed-in person is entitled to, in the background, and tells them with a push. Read [privacy and data export](../docs/privacy-and-data-export.md) before changing it.

- `lib/dataExportRegistry.ts` is the one list of what is exported. Every table in `schema.ts` has an entry: `own` (rows with the person's id), `couple` (the couple's rows, or only the person's rows with `author`; `referencedBy` adds the partner's rows that the person's own rows point to, so an answer comes with its question), `child` (rows reached through an exported parent), or `excluded` with a reason. The type fails `npm run typecheck` for a table without an entry, and `lib/dataExportRegistry.test.ts` fails too. Add the entry in the same change as the table.
- Never put a new field or table into the export by hand. Rows are exported whole, minus `hide`. Hide secrets (tokens, hashes) and use `select` for a row that mixes the person's data with the partner's or holds a game secret.
- The export never contains what the partner wrote or uploaded. That rule is in the docs and in the README of every export (`lib/dataExportReadme.ts`), so change the three together.
- A download lives three days (`EXPORT_VALID_DAYS`). Its zip files are `_storage` blobs, so anything that sweeps storage must know `data_export_parts` and `data_export_chunks` (`media.ts` `sweepOrphanStorage` does). Account deletion deletes the person's downloads (`lib/dataExportFiles.ts`).
- Zip files are built in memory. `PAEONIA_EXPORT_PART_LIMIT_BYTES` lowers the 96 MiB limit on a server that is short of memory. Store a blob with `storeAndRecord`, so a failed record does not orphan it.

## Scheduling and push

- APNs delivery runs in Node actions (`"use node"`), because APNs requires HTTP/2. Each push has an outbox row (`notification_outbox`, `widget_push_outbox` or `live_activity_push_outbox`) that records `scheduled_for`, `sent_at`, `failed_at` and the dedupe keys. Each row is one `pushWorkpool` work item (`enqueuePush` in `lib/notifications.ts`) that runs `push:send_push` at `scheduled_for`. No cron polls the outbox.
- `send_push` re-checks the row right before it sends (`prepare_notification`, `prepare_widget_push` or `prepare_live_activity_push`), so a row queued for later is judged when it is due: the device, the notification preference, the reminder deadline, and for a payload with a `couple_id` that the recipient is still an active member. Game pushes ask `gamePushStillWanted` in `lib/gameRegistry.ts`, and a kind without an entry in `GAME_BACKENDS` is out of date. A dropped row fails with `notification target is no longer eligible` or `notification is out of date`.
- A dead APNs token (410, or `BadDeviceToken` on both hosts) is not retried and the device is retired. Other failures retry with backoff, and `pushQueue:push_finished` fails the row after the last try. Without APNs keys, `send_push` logs `push delivery is not configured` and leaves the row unsent.
- `backgroundWorkpool` (`lib/backgroundWorkpool.ts`) runs at most 5 jobs at once and retries a failed action after about 1, 2, 4 and 8 minutes. Two kinds of job use it, and no cron polls for either:
  - `enqueueReportSnapshotAssets` queues one `moderation:copy_report_snapshot_asset` per snapshot asset. After 5 failed tries, `report_snapshot_copy_finished` sets `copy_status` to `copy_failed` with `last_copy_error`.
  - `requestAccountDeletion` queues `accountDeletion:delete_auth_user` to start a minute later, after `delete_account` has tried the Clerk delete itself. It gets 10 tries over about 8.5 hours. Each failed try records `last_auth_delete_error_code` and an `auth_delete_failed` event. After the last one, `auth_delete_finished` sets the job to `attention_required`. `accountDeletion:retry_account_deletion_job` queues a fresh set of tries.
- Cron work that grows with the number of users or couples runs in pages. A page of 50 streaks (`detect_streak_breaks`, `enqueue_due_streak_reminders`, `enqueue_evening_streak_reminders`) or 50 users (`enqueue_question_time_reminders`) is one mutation, and a page that is not the last schedules the next with `ctx.scheduler.runAfter(0, ...)` and the `paginate` cursor. The relationship cleanup and purge crons change at most `ROWS_PER_CHUNK` rows of one couple per mutation and schedule themselves again while a couple is still due (`lib/relationshipCleanup.ts`). A purged couple keeps its row with `purged_at` set, which takes it out of the `by_status_purged_at_delete_after` range. Game rows are still deleted in one go. Account deletion removes the person's push rows the same way, 500 per mutation one second apart (`purge_push_history`), because an account that has been used for a while has thousands. The server allows 4 MiB of writes a second in total, so a job that chains large pages with no wait fails with `Too many writes per second` and slows every other function while it runs.
- Media blob deletes and expired report snapshot deletes stay on the `cleanup-media-storage` and `cleanup-report-snapshots` crons. They delete inside a mutation, next to the live-reference check, and the pool does not retry mutations.

## Environment variables

Set them with `npx convex env set`. The names are the `process.env` reads in `convex/`. Never commit values. Non-obvious ones:

- `CLERK_DEV_JWT_ISSUER_DOMAIN` and `CLERK_DEV_SECRET_KEY` are the development Clerk instance. `api.paeonia.no` does not use them. It stores them for `scripts/local-backend`, `scripts/test-couple` and `scripts/sim-sign-in`.
- `APPLE_SIGN_IN_*` is the Sign in with Apple key that account deletion uses to revoke Apple tokens. `INVITE_CODE_PEPPER` hashes invite codes.
- `CLOUDFLARE_TURN_KEY_ID` and `CLOUDFLARE_TURN_API_TOKEN` are the Cloudflare Realtime TURN key. While they are unset, `calls:get_call_ice_servers` returns no ICE servers, and a local backend leaves them unset.
- `POSTHOG_PERSONAL_API_KEY` has only the `person:write` and `query:read` scopes on project 309819. Account deletion and turning off usage statistics use it to delete the person's data, and fail and retry while it is unset. The monthly `delete-inactive-analytics-persons` cron uses it to find people inactive for a year.
- `PAEONIA_ADMIN_CLERK_USER_IDS` is the comma-separated Clerk user ids of the admins.
- `PAEONIA_DATA_EPOCH` is optional and reads as an empty string while unset. Change it only after a restore or a hand edit of game rows (see Hosted deployment).

## Function contract notes

`convex/<module>.ts` holds the registered functions, and the path is `<module>:<name>`. Grep the module for its function list. These notes cover what the code does not make obvious.

- Subscribe to `daily:get_daily_challenge_snapshot` (by `p_couple_day_id`), not the today variant, since its rows do not depend on the clock. `streaks:get_couple_streak` ignores `p_day_key`. A one-shot caller passes a fresh value so a result cached before midnight is never served.
- `identity:launch` is the cold-launch call: it provisions the user, then returns `{ profile, access }`. It refuses accounts with a pending or finished deletion and gives a banned account the `banned` access row.
- `identity:set_notification_preference` refuses `question_time_enabled`. `identity:set_question_time_reminder` saves it.
- Access and export are not privacy requests. `dataExport:request_data_export` answers both.
- `onboarding:record_welcome_step` is the only public function that reads no session. It stores a count per day and step and nothing else, behind a shared `welcomeStep` rate limit.
- `entitlementGrants` is the one way to give or take back access without a purchase. Run `create_entitlement_grant` and `revoke_entitlement_grant` with `npx convex run`. Every kind but `lifetime` needs a future `p_expires_at`, and creating a live grant again returns it with `created: false`.
- `admin:operator_ban_user` and `operator_unban_user` are the operator commands for bans.
- A pairing invite lasts 30 days. The server accepts an expiry up to 31 days out, so a phone clock that runs ahead still fits.
- The inviter's first-day drafts (`firstDay` module) become couple content in `accept_pairing_invite` through `materializeFirstDayDrafts`. The joining partner gets no visible pushes for it, and the inviter gets `partner_joined`.
- `accept_pairing_invite` with `p_restore` asks to bring back the pair's ended couple and returns null while the inviter decides with `answer_relationship_restore` (`lib/relationshipRestore.ts`). Only a couple that a partner left (`couples.end_reason` `user_left`) comes back, before `delete_after` and before `cleanup_started_at`. A reopened couple is `active` again, so the cleanup and purge crons never select it. A restored couple keeps its id, its members keep `first_day_finished_at`, and the inviter's first-day drafts go onto its next free days.
- `relationship.ts` holds the always-subscribed `get_relationship_sync_events`. Its jobs live in `relationshipJobs.ts` to keep that import graph small. `gameHooks.ts` and `dataExportStatus.ts` split off for the same reason.
- `get_memories` pages by the memory's `updated_at` and id. A note or photo change moves `updated_at` without a revision bump (`touchMemoryForSync`).
- Favorites are private to the user. `set_favorite` sets the given value, so a retry changes nothing, and taking a star back always works.
- The iOS app matches the purchase action errors `purchase_linked_to_another_account` and `no_streak_to_restore`, and treats every other failure as a payment that Apple took but the server has not confirmed yet.
- The three public actions `access:verify_purchase`, `access:redeem_streak_restore` and `identity:delete_account` use camelCase keys and typed `v` validators, and are not SQL ports. iOS calls them with `POST /api/action`. They fail with `fail(code, message)`, where the code names the reason. The Apple server notification webhook is `POST /apple/server-notifications` on the HTTP actions origin.
- Call errors the app reads: `calls` fails with `P0001 call_busy`, `P0002 call_not_ringing`, `P0002 call_not_live`, `P0003 turn_unavailable` and `P0003 turn_limit_reached`. The rules of calling are in `docs/calling-plan.md`.
- A VoIP ring is sent once per callee phone with a `voip_push_token`, with no outbox row and no retry. A token APNs calls dead is cleared from its device and the device stays on for its other pushes.
- Search (`search:search_couple_content`) takes its couple from the session and fails with `42501` without an entitled couple. A new chat thread kind adds one case to `messageTarget` in `search.ts`.

## Commands

Run from `backend/`: `npm run typecheck`, `npm test`, and `npx convex run <module>:<function> '<json args>'`. `npx convex dev` pushes to the deployment in `.env.local`. To test a branch on a simulator, use `scripts/local-backend` instead.

Commands against `api.paeonia.no` need `CONVEX_SELF_HOSTED_URL` and `CONVEX_SELF_HOSTED_ADMIN_KEY` in the shell environment, never in a committed file.

## Testing a branch on a local backend

A deploy replaces every function on `api.paeonia.no`, so a branch never deploys there, and only `main` does. Each worktree runs its own local backend instead. From the worktree root:

```sh
scripts/local-backend            # keep it running; Ctrl-C or kill stops it
scripts/local-backend --reseed   # copy api.paeonia.no's data again first
```

- It pushes this worktree's `backend/convex` on every change. The port comes from a hash of the worktree path.
- It uses the development Clerk instance, so a local backend never trusts production Clerk, and only accounts of that instance can sign in. It leaves out the APNs and Apple keys, so a local backend sends no pushes, verifies no purchases and revokes no Apple tokens.
- On the first run, or with `--reseed`, it replaces all local data with a read-only snapshot of `api.paeonia.no`, importing before it pushes the functions so the snapshot keeps the hosted table numbers. If the hosted data does not fit the branch's schema, the push fails and the script stops. Fix the schema or the data, then run it again.
- It writes the untracked `ios/local.xcconfig`, which `ios/debug.xcconfig` includes, so Debug builds of this worktree use the local backend. Delete the file to point Debug builds back at `api.paeonia.no`.
- It runs `scripts/test-couple`, which creates the test couple Shared and Panci, and `scripts/sim-sign-in` signs a simulator into them.

The data lives in `backend/.convex/` of the worktree and survives restarts. While the script runs, plain `npx convex run`, `data` and `import` from `backend/` go to the local backend, so edit local data freely. Do not set `CONVEX_SELF_HOSTED_URL` in that shell, because the CLI then targets the hosted deployment.

Live games still go through `relay.paeonia.no`. Its rooms are keyed by couple, so two worktrees that test live play with the same couple at the same time hear each other's strokes.

## Hosted deployment

There is no production yet. The hosted deployment at `api.paeonia.no` holds the developer's test data. Deploying `main` to it and editing its data for testing are pre-approved, so deploy after tests pass and say so in your summary. Deploy only from `main`, and test a branch on a local backend (see above). Schema changes do not need migrations or backfills. If old test rows block a deploy or no longer fit, delete or edit them.

The hosted Convex is self-hosted on the `one-s` server (`ssh one-s`). The stack lives in `/srv/paeonia/convex` and runs with docker compose: the Convex backend and the dashboard. Documents are SQLite in `./data`. Stored files, deployed modules, search indexes and snapshot exports and imports are in five Cloudflare R2 buckets in the EU jurisdiction, named `paeonia-convex-files`, `-modules`, `-search`, `-exports` and `-snapshot-imports`. The R2 key is in `.env` next to the compose file and can reach only those buckets. The compose file sets `STORAGE_MAX_INTERMEDIATE_PART_SIZE=5242880`. Keep it. R2 rejects a multipart upload whose parts before the last differ in size, and Convex otherwise doubles the part size from 5 MiB, so every file write or export over about 15 MiB fails with `InvalidPart`. The backend's `mem_limit` is 2560m. At 768m a burst of requests after pairing filled the cap, every request stalled for about 15 seconds while the kernel reclaimed memory, and the kernel then killed the backend. If requests stall or the backend restarts on its own, check `journalctl -k | grep oom-kill` and the container's `memory.events` before raising `APPLICATION_MAX_CONCURRENT_QUERIES`. Both containers bind to localhost, and Caddy terminates TLS.

Hosted runtime upgrades and rollback use the shared tools in `/srv/convex-runtime/source` on one-s, which Tidex shares. Its `README.md` gives the steps. The Tidex repo that tracked them is archived off the Mac, so edit the server copy and keep the previous copy as `source.<revision>`. To move to a newer Convex release, point `release.json` at the release's assets, at the startup scripts of its revision and at the official base image tagged with that revision. The hosted backend and dashboard use the pinned November 17, 2026 Convex release (`precompiled-2026-11-17-316a9b4`) with packaged jemalloc. Keep the image manifest, build source and allocator settings in recovery backups. Physical rollback must restore SQLite and its R2 objects together.

Paeonia stays self-hosted. Do not propose moving to hosted Convex unless the developer raises it or running the server clearly costs more than about 5% of revenue. Hosted Convex in the EU has no included usage and bills every call, so its cost grows with users, while the server costs a fixed $9 a month. When traffic needs more, first make reads fewer and cheaper, then move from SQLite to Postgres or MySQL in its own container. SQLite has one connection behind one lock, so raising `APPLICATION_MAX_CONCURRENT_QUERIES` does not help. The privacy policy (the marketing legal dictionaries) says the database runs in Leipzig, so any move must update it.

`/srv/backup/paeonia-backup.sh` backs up the deployment, with its settings in `/srv/backup/paeonia.conf`. A systemd timer runs it every night at 03:25 UTC. It takes a snapshot export with file storage, plus a config archive with the stack's `.env`, `admin-key`, compose file, the output of `convex env list`, and the shared runtime source and image manifests. Both go to `/srv/paeonia/backups` (14 kept) and to `r2:tidex-supabase-backups/paeonia/`, where copies older than 3 days are deleted to stay inside R2's free 10 GB (`OFFSITE_KEEP_DAYS`). Another timer runs it hourly with `db-only`, which writes an export without files and keeps it on the server only (48 kept). Self-hosted Convex does not delete old export and import zips from its R2 buckets, so `paeonia-convex-exports` and `paeonia-convex-snapshot-imports` have a lifecycle rule that deletes objects after 1 day. The script uses the Convex CLI pinned in `/srv/paeonia/cli`. When `backend/package.json` moves to a new major version, update that copy too. `/srv/backup/watchdog.sh` runs every 5 minutes. It emails an alert when `api.paeonia.no/version` fails, when `convex-backend-1` is unhealthy, or when the newest backup is too old. It also warns before the backend runs out of room: when the backend's working memory (excluding reclaimable inactive file cache) stays at or above 70% of `mem_limit` for at least 10 minutes, when it reached `mem_limit`, when the kernel killed it for memory, and when its log shows requests turned away (`Too many concurrent requests`) or timed out. A memory warning means check live working memory, allocator retention and query work before raising `mem_limit` or moving to a bigger server. jemalloc reduces retained freed memory; it does not make expensive queries cheaper. A turned-away warning without memory pressure means the concurrency limits (`APPLICATION_MAX_CONCURRENT_QUERIES` and the others) are too low.

To restore, stop the stack, move `./data` aside and start the stack again, so the backend starts empty with the same instance secret and admin key. Then run `convex env set --force --from-file convex.env` with the file from the config archive, deploy `main` with `scripts/deploy-backend`, and run `convex import --replace-all -y <export.zip>`. Last, run `convex env set PAEONIA_DATA_EPOCH "$(uuidgen)"`. Phones keep their own copy of a game when the server's copy has a lower version, so without a new epoch they hold on to games the restore rolled back. Run the CLI from `/srv/paeonia/cli` on the server, with `CONVEX_SELF_HOSTED_URL=http://127.0.0.1:3210` and the admin key. Switching between local and S3 storage follows the same steps.

Agents have docker access on `one-s` through passwordless `sudo`. The `administrator` user is not in the `docker` group, so plain `docker` fails with "permission denied". Use `sudo -n docker ...`. The containers are `convex-backend-1` and `convex-dashboard-1`. To read backend logs, for example to find the cause of a `Server Error` with a request id, run `ssh one-s 'sudo -n docker logs --since 30m convex-backend-1'`.

The origins (`api.`, `actions.`, `convex.paeonia.no`) are listed in the root `AGENTS.md`.

The admin key is in `/srv/paeonia/convex/admin-key` on `one-s` (owner-only). Never commit it, paste it into a file in the repository, or print it into logs.

Deploy with `scripts/deploy-backend` from the repository root of a clean checkout of local `main`. It deploys Convex to `api.paeonia.no` and then the relay (`relay/`) with `npx wrangler deploy`. It refuses any other commit and holds the hosted-backend lock from `scripts/lock` while it deploys.

`backend/.env.local` sets `CONVEX_DEPLOYMENT` for local development. The CLI refuses to run when that variable is set next to `CONVEX_SELF_HOSTED_URL`, so add `CONVEX_DEPLOYMENT=` (empty) to hosted commands when the file exists.

Operator functions (`internalMutation`/`internalQuery`/`internalAction`) run with the same two variables and `npx convex run <module>:<function> '<json args>'`. The App Review scripts `ios/Scripts/mint-review-codes.mjs` and `revoke-review-codes.mjs` use this path.

To run a public function as a user, add `--identity '{"subject":"<clerk user id>"}'` to `npx convex run`.

To hand-edit hosted rows for testing, export the table with `npx convex data <table> --format jsonLines`, keep that file as a backup, edit the rows, and load them back with `npx convex import --table <table> --replace -y <file>.jsonl`. The import keeps `_id` and `_creationTime`. `--replace` swaps out the whole table, so the file must hold every row. `npx convex run _system/frontend/patchDocumentsFields` fails with a server error on this deployment. After you delete game rows or roll them back, set a new `PAEONIA_DATA_EPOCH` the same way, or the phones keep showing the old games.

A deploy that adds a required field to an existing table fails when old rows lack it, and changes nothing. The old schema also rejects rows that already carry the field, so you can't fix the rows first. Find every affected table at once by diffing `schema.ts` for fields added without `v.optional`. Then, for each table:

1. Export a snapshot with `npx convex export` to `~/paeonia-backups/`.
2. Fill in the field in the table's `documents.jsonl`, without `_id` and `_creationTime`.
3. Empty the table with `npx convex import --table <table> --replace` from an empty file.
4. Deploy with `scripts/deploy-backend`.
5. Load the edited rows back with `--replace`.

A failed deploy regenerates `convex/_generated/api.d.ts`. Commit it before you retry, because `scripts/deploy-backend` refuses a dirty `backend/`.

The repo runs on the Node major in `.node-version`, and CI reads the same file. The scripts that call the Convex CLI put Homebrew's `/opt/homebrew/opt/node@<that major>/bin` first on PATH. A local backend runs `"use node"` actions with the `node` on PATH and accepts Node 22, 24 or 26.

Keep server access to what the task needs. Do not change the docker stack, Caddy, or the server itself unless the task asks for it.

PostHog usage statistics are in the EU project 309819. `posthog-cli` on this Mac is signed in to it. Run HogQL with `posthog-cli --host https://eu.posthog.com api call execute-sql '{"query":"...","context":"..."}'` and read settings with `project-get`. `project-settings-update` and `cdp-functions-partial-update` need `--confirm`, and project updates need `"id":"309819"`. The iOS SDK also obeys the project's server switches: it skips the crash handler unless `autocapture_exceptions_opt_in` is on. The app reads them from `https://eu-assets.i.posthog.com/array/<project key>/config`.

## Games

Each game's design is in `docs/games/<game>.md`, and `docs/games-plan.md` holds the Games tab plan. `GAME_KINDS` in `lib/validators.ts` lists the kinds, and the shared functions in `games.ts` accept every one. Function arguments and results are documented in the comments of `convex/games.ts` and `convex/drawAndGuess.ts`. `backend/scripts/<game>/play.mjs` plays the partner from the command line for the games that have one.

A new game adds its entries at these points and edits no other game:

- Its own `convex/<game>.ts` and `lib/<game>.ts`, with its tables in `schema.ts`. `lib/games.ts` holds what every game shares and never imports a game or the registry.
- `GAME_BACKENDS` in `lib/gameRegistry.ts`: `pushStillWanted`, `deleteCoupleRows`, and optionally `sendDueTurnReminders` and `onLanguageChanged`.
- `GAME_PUSH_COPY` in `lib/notificationCopy.ts`: the lock-screen name and wording of its pushes.
- `ALLOWED_CHANNELS` in `relay/src/ticket.ts` and `GameKind` in Swift: the same kinds as `GAME_KINDS` (the relay adds `call`). `scripts/check-repo-rules.mjs` checks both.

Rules every game follows:

- Every game function needs an active, entitled couple member (`canAccessCoupleContent`). Writes also refuse a user whose account deletion is pending.
- Functions the app may retry offline use `runClientOperation`. A game with a hidden secret (a word, a spot) returns it to the other partner only once the round is revealed or guessed.
- Games never write to `memories`. Favorites of game items are deleted with the couple's other favorites (`deleteCoupleFavorites`), not by `deleteCoupleGameRows`.
- Presence (who has the app, a game screen, the drawing or a chat open, and who is typing) lives in the presence component (`appRoom`, `gameRoom`, `drawingRoom`, `chatOpenRoom`, `chatTypingRoom` in `lib/presence.ts`). The app heartbeat (`set_app_presence`) also joins or leaves the drawing room, as `p_drawing` says. Chat rooms carry the chat's kind and then its game kind or subject id (`ChatPlace` in `lib/threadSubjects.ts`, the fields a thread row names its subject with), so `placesInApp` can read back where a partner is. `appPresence:get_partner_presence` returns nobody unless both partners have `profiles.shows_presence` on (missing means on). Game rooms are one per couple and kind. A game room marks a user offline 60 seconds after the last heartbeat and the app and drawing rooms 30 seconds after, so readers need no clock read or cron. Presence and chat typing callers check couple access first and build the room from the couple id, so a client never names a room or a user. `endRelationshipForPair` removes the couple's rooms, and account deletion removes whatever the user still has.
- Game pushes use the kinds `game_turn_ready`, `game_result`, `game_invite` and `game_turn_reminder`, all following `games_enabled`. The payload never carries the word, a drawing, or written content. `step` is a fixed token the game picks, never content. Turn and result pushes are skipped while the recipient has that game open (`isGamePresent`), and wait while the recipient's game Live Activity says "Your turn" for that game (`activitySaysYourTurn` in `lib/liveActivities.ts`). The title and body come from `GAME_PUSH_COPY`. A kind without an entry gets the title "Paeonia".
- A turn that counts for the streak is a `game_turn_completed` activity with a dedupe key naming the round (and the user, where both partners act).
- `get_games_overview` reads waits only from game backends with saved hidden keys, through `gameHooks:hidden_game_kinds`, so a game stays out of it unless the caller hid something.

Date reminders (`dateReminders.ts`, `lib/dateReminders.ts`) and the question time reminder (`questionTime.ts`) are cron-driven pushes. Both page 50 users per mutation, take the user's zone from `resolveMemberStreakTimeZone`, set `expires_at` to the end of the local date, and are not streak events. A calendar date has no zone, so each partner counts it on their own local date, and the two can get the push a day apart. `prepare_notification` asks `hasStartedToday` again before each send of a question time reminder, so a retry after an answer is dropped. Copy never carries a countdown title, because the words on a lock screen belong to the couple.

## Live drawing relay

`relay/` at the repository root is a Cloudflare Worker at `wss://relay.paeonia.no/canvas`. It forwards drawing and call messages between the two partners of one couple and stores nothing. The app gets a 60-second ticket from a Convex mutation that runs the usual couple access checks (`widget:create_widget_live_ticket`, `games:create_game_live_ticket` for a game channel, `calls:create_call_live_ticket` for the `call` channel), and `lib/liveTicket.ts` signs it. The Worker rejects a channel that is not in `ALLOWED_CHANNELS` in `relay/src/ticket.ts`. The connection rules (room size, socket expiry, message limit) are in `relay/src/room.ts`.

The ticket mutations return null while `PAEONIA_LIVE_RELAY_URL` or `PAEONIA_LIVE_RELAY_SECRET` is unset, and the app then draws without the relay. The Worker secret `RELAY_TICKET_SECRET` must equal `PAEONIA_LIVE_RELAY_SECRET`. To rotate it, generate one value and set it in both places (`npx wrangler secret put RELAY_TICKET_SECRET` from `relay/`, and `npx convex env set`). From `relay/`, run `npm test` and `npm run typecheck`. `scripts/deploy-backend` deploys the relay together with Convex.
