# Backend agent guidance

Paeonia's backend is a self-hosted Convex deployment. This folder replaced the Supabase backend (`supabase/`, removed after the port). Paths below are relative to `backend/` unless they start with the repository root.

## Layout

- `convex/schema.ts`: every table and index.
- `convex/lib/`: shared plain TypeScript helpers (no registered functions). Everything that more than one feature module needs lives here.
- `convex/<module>.ts`: registered functions for one feature area. See the module map below.
- `convex/http.ts`: the single HTTP router. Feature modules export `httpAction`s and `http.ts` mounts them.
- `convex/crons.ts`: every scheduled job.
- `convex/*.test.ts`: `convex-test` + `vitest` tests next to the module they cover.
- `questions/`: source-controlled question catalog markdown, uploaded with `scripts/sync-question-catalog` (see `questions/README.md`).
- `games/words/en.json` and `nb.json`: the Draw & Guess word lists. `convex/lib/gameWords.ts` imports them into the bundle, so a list change needs a deploy. `lib/gameWords.test.ts` checks both files against the rules in `docs/games/draw-and-guess.md`.
- `seed/subscription_products.json`: subscription product reference data, loaded by `internal.catalog.seed_subscription_products`.

## iOS contract

The iOS app subscribes to reads over the ConvexMobile WebSocket client and writes the results into its local store, so partner changes show up live. Writes and one-shot reads go over the HTTP API (`POST /api/mutation`, `/api/query`, `/api/action` with `{"path","args","format":"json"}`) through the app's offline outbox. Both use the Clerk session token. The widget extension uses HTTP only.

Functions ported from Supabase kept their RPC shapes, which gives the conventions below. Follow them for new functions so the code stays consistent. They are not a compatibility promise. No shipped app depends on them, so rename a function, change its arguments, or reshape its result when that helps, and update the iOS caller in the same change.

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

- Clerk issues the JWT. `convex/auth.config.ts` trusts the Clerk issuer with `applicationID: "convex"`.
- `users` maps the Clerk `subject` to the Paeonia uuid that every other table references. `lib/auth.ts` exports `getCurrentUserId(ctx)` (returns null when signed out or not yet provisioned), `requireUserId(ctx)` (fails with `42501 authenticated user required`), and `ensureCurrentUser(ctx)` (mutations only). `ensureCurrentUser` replaces the `auth.users` triggers: it creates the `users` row and the profile from the Clerk identity claims on the first authenticated call.
- Supabase used row level security plus `auth.uid()` checks inside `internal.*` functions. Convex has neither, so every public function must perform the same membership, entitlement, block, and ownership checks explicitly, using the helpers in `lib/access.ts`. When porting, read the RLS policies on every table the function touches and preserve their effect.
- Never trust a user id, couple id, or role from arguments for authorization. Derive them from the session.
- Access helpers take the user id explicitly, for example `canAccessCoupleContent(ctx, userId, coupleId)`. The SQL read `auth.uid()` inside. Get `userId` from `requireUserId` once per function and pass it down.
- `is_admin` was always false, so `isAdmin()` returns false. App users are never admins. Operator work runs through internal functions.
- Clerk's default session token has no provider or name claims. `delete_account` asks the Clerk Backend API for linked Apple accounts, so Apple token revocation does not depend on a claim. An optional custom claim `auth_provider` (`apple` or `google`) and the standard name claims, if added to the session token, fill `users.auth_provider` and the initial profile name.

## Triggers

Postgres triggers do not exist in Convex. Each trigger becomes explicit code that runs at every write site for that table. Tables with trigger behavior get write helpers in the owning `lib/` file or module, and other code must call those helpers instead of `ctx.db.insert`/`patch`/`delete` directly.

- `set_updated_at`: set `updated_at: nowIso()` on every patch.
- `touch_updated_at_and_revision`: also increment `revision`.
- `reject_pending_account_client_operation`: call `assertNoPendingAccountDeletion(ctx, userId)` before writing the guarded tables.
- `tombstone_content_report_target`: call `tombstoneReportTargets` before deleting a reportable row.
- `invoke_*_drain` and outbox `AFTER INSERT` triggers: schedule the drain with `ctx.scheduler.runAfter(0, ...)`. The push outbox inserts queue a `pushWorkpool` work item instead (see Scheduling and push).
- `assert_*_allowed` validation triggers: call the matching assert helper inside the write helper.
- Other `AFTER` triggers (notifications, streak refreshes, location deletion): call the side-effect helper from the write helper.

## Shared helpers (`convex/lib/`)

Import these instead of re-porting the SQL.

| File | Contents |
|---|---|
| `errors.ts` | `fail`, `assertCheck`, `checkViolation`, `uniqueViolation` |
| `ids.ts` | `newUuid`, `uuidArg`, `optionalUuidArg`, `timestampArg`, `optionalTimestampArg`, `dateArg`, `optionalDateArg` |
| `time.ts` | `nowIso`, `addMs`, `addHours`, `addDaysToInstant`, `addDaysToDate`, `isValidTimeZone`, `validTimeZoneOrUtc`, `localDateOf`, `startOfLocalDay`, `endOfLocalDay`, `localMidnightAfter`, `zonedLocalToUtcMs` |
| `crypto.ts` | `sha256Hex`, `hmacSha256Hex`, `randomHex`, `randomToken`, `timingSafeEqual`, `requestHash` |
| `json.ts` | `stableStringify`, `jsonbText`, `jsonbByteLength` (for the SQL `octet_length(x::text)` checks), `isJsonObject` |
| `db.ts` | `getByUuid`, `requireByUuid`, `omitNulls`, `orNull`, `withUpdatedAt`, `withTouch`, `withRevisionBump` |
| `validators.ts` | `literals` and the shared literal unions (`moderationStatus`, `authProvider`, ...) |
| `auth.ts` | `getCurrentUserId`, `requireUserId`, `ensureCurrentUser` |
| `clientOperations.ts` | `runClientOperation` |
| `backgroundWorkpool.ts` | `backgroundWorkpool`, the `@convex-dev/workpool` pool for report snapshot copies and Clerk account deletes |
| `rateLimits.ts` | every rate limit in one `RateLimiter` (`@convex-dev/rate-limiter`), and `consumeRateLimit`. To add a limit, add an entry to `LIMITS` and call `consumeRateLimit(ctx, name, userId)` first thing inside the `runClientOperation` callback, so replays are free and a refusal rolls back. It fails with `53300`, which the app retries later instead of dropping the write. Set the capacity above the backlog an offline phone sends at once |
| `accountDeletion.ts` | `assertNoPendingAccountDeletion` |
| `entitlements.ts`, `access.ts` | membership, entitlement, block, and pair helpers |
| `coupleDays.ts` | couple day anchors, `getOrCreateCoupleDayAt`, `userLocalDate` |
| `syncEvents.ts` | `createRelationshipSyncEvent` |
| `hearts.ts` | `MAX_HEARTS_PER_SEND`, `seenTotalAfterMark`, `deleteHeartsForCouple` for the `couple_hearts` table (one row per couple and sender, with `sent_total` and `seen_total`). The relationship end and the couple cleanup and purge delete a couple's rows |
| `relationshipEnd.ts` | `endRelationshipForPair` (used by leave, block, report, and account deletion), `deleteLatestLocationsForCouple` |
| `dailyQuestionRounds.ts` | a couple has one chat per question and each day the question came back is a round: `loadCoupleRounds`, `isSharedRound`, `dailyQuestionThreadLink`, and `addRoundInfo` (the round fields on question rows) |
| `streaks.ts`, `streakDeadlines.ts` | streak core, restore, and the zone-change refreshes |
| `notifications.ts`, `notificationCopy.ts` | outbox inserts, enqueue helpers, notification copy |
| `reports.ts` | `tombstoneReportTargets` |
| `mediaOrphans.ts` | live-reference check and orphan queueing |
| `games.ts` | what every game shares: `GameKind`, settings, `isGamePresent`, `enqueueGamePush`, `gameDeepLink`, `settingsJson`. It never imports a game or the registry |
| `presence.ts` | game presence and chat typing on `@convex-dev/presence`: `gameRoom`, `chatTypingRoom`, `setPresent`, `onlineUserIds`, `removePresenceRooms`. Callers check couple access first and build the room from the couple id, so a client never names a room or a user |
| `drawAndGuess.ts` | Draw & Guess tables: turn start, word choices, scoring, json shapes, and `drawAndGuessBackend` |
| `storyChain.ts` | Story Chain rules (line, title and dare word checks, end rules), the opening and dare word lists, seeded choices, story json, and `storyChainBackend` |
| `mindMeld.ts` | Mind Meld tables (`mindMeldTables`), word rules and match keys, and `mindMeldBackend` |
| `boardGames.ts`, `boardGameRules.ts`, `connectFour.ts`, `dotsAndBoxes.ts`, `ultimateTicTacToe.ts` | the board games' pure rules (`BOARD_RULES`, `replay`, `movers`) |
| `boardGameStore.ts`, `boardGameBackend.ts` | the board game row helpers, the view projection, the hidden photo pick, the turn token, and `boardGameBackend` |
| `gameRegistry.ts` | `GAME_BACKENDS` and the dispatchers `gamePushStillWanted`, `deleteCoupleGameRows`, `sendDueGameTurnReminders`, `gameLanguageChanged` |
| `gameWords.ts` | Draw & Guess word lists, custom word and guess normalization |
| `liveTicket.ts` | `signLiveTicket`, the relay ticket for the widget canvas and for game channels |

Rules that come with them:

- Patches that write `updated_at` go through `withUpdatedAt` or `withTouch`. Do not hand-write `updated_at`.
- Postgres ran orphan media triggers at commit time (deferred). Call the `queue*IfOrphaned` helpers after the mutation's last write to the referencing rows.
- After writing `user_devices`, call `refreshStreakAfterDeviceTimeZoneChange`. After changing `profiles.time_zone_id`, call `refreshStreakAfterProfileTimeZoneChange`. After a daily answer insert, call `enqueuePartnerAnsweredNotification`. After a memory insert, call `enqueueMemoryCreatedNotification`. After a widget revision insert, call `enqueueWidgetUpdateAlert`.
- Insert outbox rows only through `insertNotificationOutbox` and `insertWidgetPushOutbox`. They apply the check constraints, dedupe keys, and payload safety rule, and queue the send for the row's `scheduled_for`.
- `readCoupleStreak` is the pure streak reader for queries. A just-broken streak shows as broken with its restore offer, without writing. `getCoupleStreakForCouple` first persists the break with `detectStreakBreak`, so call it only from a mutation. The streak cron and `applyStreakRestore` persist breaks, so `restorable_count` is stored before a restore needs it.
- Time zone math uses `Intl.DateTimeFormat`. It follows the Postgres rules at daylight saving changes: a local time in a spring-forward gap uses the offset from before the gap, and an ambiguous fall-back time resolves to standard time.

## Tests

- `vitest.config.ts` runs tests in the `edge-runtime` environment. Test files are `convex/**/*.test.ts`. The two dots keep Convex from bundling them.
- `convex/test.setup.ts` (also two dots) has the shared helpers: `newTest()`, `createSignedInUser(t, { name, timeZone, claims })`, `createCouple(t, { timeZones, entitled })`, `setTimeZone`, `addDevice`, `grantLifetime`. Run helpers as a user with `user.as.run(...)` or `user.as.mutation(...)`.
- For time-dependent code use `vi.useFakeTimers({ toFake: ["Date"] })` and `vi.setSystemTime(...)`. End tests that queue a push with `await t.finishAllScheduledFunctions(vi.runAllTimers)`. Tests have no APNs keys, so queued pushes stay unsent. `deliverDuePushes(t)` in `push.testing.ts` runs the send-time checks on the due rows and marks the ones that pass as sent. `pushQueue.test.ts` mocks `sendWithEnvironmentFallback` to test real sends, retries included.
- A test that drives a workpool job uses `vi.useFakeTimers()` with every timer faked, then `await t.finishAllScheduledFunctions(vi.runAllTimers)`. The pool waits on timers between steps, and with only `Date` faked its loop keeps polling and never goes idle. Pass a higher `maxIterations` (the second argument) when a test runs out every retry.
- A test that waits for a presence timeout (a game screen or typing that stopped its heartbeats) calls `vi.useFakeTimers()` before the first heartbeat, then `await t.finishAllScheduledFunctions(vi.runAllTimers)`. The component's disconnect worker sleeps on a scheduled function, and one scheduled while only `Date` was faked waits on the real clock.
- `tsconfig.json` lists `types: ["node", "vite/client"]` because TypeScript 7 no longer loads `@types/*` packages on its own.

## Client operations

Local-first writes from iOS carry `p_client_operation_id`, `p_client_id`, `p_client_sequence`, and `p_local_created_at`. Wrap them with `runClientOperation` from `lib/clientOperations.ts`. It returns the stored response when the same operation already succeeded, fails with `23505 client operation replay hash mismatch` when the request differs, and stores the new response otherwise. The request hash is the `sha256Hex` of a stable JSON encoding of the request fields the SQL function hashed.

## Media storage

- Files live in Convex file storage. `media_assets` keeps its SQL columns, and `storage_id` holds the `Id<"_storage">` once the upload finishes.
- `create_pending_media_upload` returns the SQL reservation fields plus `upload_url` from `ctx.storage.generateUploadUrl()`. The app POSTs the bytes there and passes the returned `storageId` to `finalize_media_upload` as `p_storage_id`. Finalize checks size and content type against `ctx.db.system.get(storageId)` before accepting.
- Convex storage URLs never expire, so do not hand them out. `get_media_signed_url` returns the SQL function's rows, each with an added `signed_url` string. The SQL version returned only the authorized bucket and path, and the app then asked Supabase Storage to sign it. `signed_url` points to the `GET /media` HTTP action with `asset`, `exp`, and an HMAC-SHA256 `sig` signed with the `PAEONIA_MEDIA_URL_SECRET` environment variable. The action verifies the signature and expiry, then streams the blob. Use the expiry the app asked for (`p_expires_in_seconds` or the SQL equivalent), capped at the old limit.
- Hosted origins: client API `https://api.paeonia.no` (`CONVEX_CLOUD_URL`), HTTP actions `https://actions.paeonia.no` (`CONVEX_SITE_URL`). Build signed URLs from `process.env.CONVEX_SITE_URL`.

## Scheduling and push

- pg_cron jobs live in `convex/crons.ts`.
- APNs delivery runs in Node actions (`"use node"`), because APNs requires HTTP/2. The outbox tables keep the record of each push: `scheduled_for`, `sent_at`, `failed_at`, `last_error`, `provider_message_id`, and the dedupe keys.
- Each outbox row is one `pushWorkpool` work item (`enqueuePush` in `lib/notifications.ts`), which runs `push:send_push` at the row's `scheduled_for`. No cron polls the outbox. At most 10 sends run at once. A network error or an APNs failure other than a dead token retries after about 10, 20, 40 and 80 seconds, and then `pushQueue:push_finished` fails the row. A dead token (410, or `BadDeviceToken` on both hosts) is not retried, and the device is retired. `push_finished` runs after every send and records the outcome in one mutation: sent, failed, the retired device, and the APNs host that answered. Without APNs keys, `send_push` logs `push delivery is not configured`, leaves the row unsent, and does not retry.
- `send_push` calls `prepare_notification` (or `prepare_widget_push`) right before it sends, so a row queued for later is checked when it is due. It checks the device, the notification preference, and the reminder deadline. A row whose payload has a `couple_id` needs the recipient to still be an active member of that couple. Game pushes go through `gamePushStillWanted` in `lib/gameRegistry.ts`. It checks couple access, keeps invites, and asks the entry of the pushed game in `GAME_BACKENDS` whether the round or turn still waits for the recipient. A kind without an entry is out of date. A dropped row is failed with `notification target is no longer eligible` or `notification is out of date`.
- `backgroundWorkpool` (`lib/backgroundWorkpool.ts`) runs at most 5 jobs at once and retries a failed action after about 1, 2, 4 and 8 minutes. Two kinds of job use it, and no cron polls for either:
  - `enqueueReportSnapshotAssets` queues one `moderation:copy_report_snapshot_asset` per snapshot asset. After 5 failed tries, `report_snapshot_copy_finished` sets `copy_status` to `copy_failed` with `last_copy_error`.
  - `requestAccountDeletion` queues `accountDeletion:delete_auth_user` to start a minute later, after `delete_account` has tried the Clerk delete itself. It gets 10 tries over about 8.5 hours. Each failed try records `last_auth_delete_error_code` and an `auth_delete_failed` event. After the last one, `auth_delete_finished` sets the job to `attention_required`. `accountDeletion:retry_account_deletion_job` queues a fresh set of tries.
- Media blob deletes and expired report snapshot deletes stay on the `cleanup-media-storage` and `cleanup-report-snapshots` crons. They delete inside a mutation, next to the live-reference check, and the pool does not retry mutations.

## Environment variables

Set these with `npx convex env set`: `CLERK_JWT_ISSUER_DOMAIN`, `CLERK_SECRET_KEY`, `PAEONIA_MEDIA_URL_SECRET`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`, `APPLE_BUNDLE_ID`, `APPLE_APP_APPLE_ID`, `PAEONIA_LIVE_RELAY_URL`, `PAEONIA_LIVE_RELAY_SECRET`. Never commit values. `PAEONIA_DATA_EPOCH` is optional and reads as an empty string while unset. Change it only after a restore or a hand edit of game rows (see the hosted deployment section).

## Module map

| Module | App-callable functions |
|---|---|
| `identity` | `ensure_current_user`, `complete_profile_onboarding`, `update_own_profile`, `set_own_provider_profile_photo`, `register_user_device`, `disable_user_device`, `get_notification_preferences`, `set_notification_preference`, `get_privacy_requests`, `create_privacy_request`, `request_account_deletion`, `delete_account` (action) |
| `pairing` | `create_pairing_invite`, `preview_pairing_invite`, `validate_my_pairing_invite`, `accept_pairing_invite`, `revoke_pairing_invite`, `rotate_pairing_invite` |
| `relationship` | `get_relationship_sync_events`, `leave_relationship`, `mark_relationship_ended_notice_seen`, `set_couple_started_on` |
| `access` | `get_access_snapshot`, `get_or_create_app_account_token`, `verify_purchase` (action), `redeem_streak_restore` (action) |
| `daily` | `start_daily_challenge_snapshot`, `get_today_daily_challenge_snapshot`, `get_daily_challenge_snapshot` (query by `p_couple_day_id`; subscribe to this one, since its rows do not depend on the clock), `shuffle_daily_question_snapshot`, `submit_daily_answer`, `update_daily_answer_text`, `update_daily_answer_partner_choice`, `get_daily_answer_details`, `get_daily_questions_history`, `get_daily_answer_history_details` |
| `streaks` | `get_couple_streak` |
| `dailyQuestionChat` | `get_daily_question_chat` (by `p_couple_id` and `p_question_id`: a question's rounds with the reveal rule applied per round, plus the chat's `thread_id`) |
| `chatPresence` | `set_daily_chat_typing`, `get_daily_chat_presence` (both by `p_couple_id` and `p_question_id`), `mark_thread_read`, `mark_daily_answer_seen` (by `p_instance_id`) |
| `threads` | `get_conversation_threads`, `get_thread_messages`, `send_thread_message`, `edit_thread_message`, `create_daily_question_thread_with_message`, `create_memory_thread_with_message` |
| `memories` | `create_memory`, `update_memory`, `hide_memory`, `get_memories`, `upsert_memory_note`, `attach_memory_media`, `remove_memory_media` |
| `media` | `create_pending_media_upload`, `finalize_media_upload`, `get_media_signed_url`, `mark_media_for_deletion` |
| `games` | `set_game_settings`, `get_games_overview`, `send_game_invite`, `set_game_presence`, `create_game_live_ticket` (shared by all games, each takes a `p_kind` from `GAME_KINDS`) |
| `storyChain` | `ensure_story_chain_game`, `get_story_chain`, `get_story_chain_story`, `start_story`, `add_story_line`, `name_story`, `mark_story_seen`, `set_story_star`, `get_story_chain_history` |
| `drawAndGuess` | `ensure_draw_and_guess_game`, `get_draw_and_guess`, `get_draw_and_guess_round`, `pick_draw_word`, `submit_drawing`, `mark_round_seen`, `submit_guess`, `give_up_round`, `mark_round_result_seen`, `set_round_reaction`, `set_round_star`, `get_draw_and_guess_history`, `get_draw_and_guess_records` |
| `mindMeld` | `get_mind_meld`, `start_mind_meld_game`, `lock_mind_meld_word`, `count_mind_meld_round`, `mark_mind_meld_reveal_seen`, `mark_mind_meld_end_seen`, `restart_mind_meld`, `get_mind_meld_history` |
| `boardGames` | `get_board_games`, `get_board_game_marks`, `ensure_board_game`, `make_move`, `start_rematch`, `set_board_game_mark` (Connect Four, Dots and Boxes and Ultimate Tic-Tac-Toe, each by `p_kind`) |
| `widget` | `get_or_create_widget_canvas`, `get_widget_canvas`, `get_widget_drawing_revisions`, `submit_widget_drawing_revision`, `register_widget_push_device`, `create_widget_live_ticket` |
| `location` | `update_latest_partner_location`, `update_location_sharing_preference`, `get_partner_location_visibility` |
| `hearts` | `send_hearts`, `mark_hearts_seen`, `get_hearts` (the Home map hearts) |

| `reports` | `submit_leave_and_report` |

These functions replace direct PostgREST table access from iOS. They return full rows with SQL column names and apply the old RLS rules:

- `identity:complete_profile_onboarding` `{p_time_zone_id, p_profile_photo_asset_id?}` sets `time_zone_id`, `time_zone_updated_at`, `onboarding_completed_at`, and optionally `profile_photo_asset_id`, then returns the profile row.
- `identity:get_notification_preferences` `{}` returns the caller's `notification_preferences` row. `identity:set_notification_preference` `{p_column, p_enabled}` updates one boolean column (`streak_reminders_enabled`, `daily_challenge_enabled`, `partner_answered_enabled`, `messages_enabled`, `widget_updates_enabled`, `memories_enabled`, `games_enabled`). `identity:set_question_time_reminder` `{p_enabled, p_minutes}` saves the opt-in question time reminder (`question_time_enabled`, off by default, and `question_time_minutes`, minutes after local midnight, 0 to 1439, default 1200) and returns the row. The generic switch endpoint refuses `question_time_enabled`.
- `identity:get_privacy_requests` `{}` returns the caller's `privacy_requests`, newest `requested_at` first, at most 100. `identity:create_privacy_request` `{p_id, p_kind, p_requester_note?}` inserts one and returns the row.
- `relationship:get_relationship_sync_events` `{p_after_created_at?, p_after_id?, p_limit}` returns the caller's events ordered by `created_at`, then `id`, strictly after the cursor.

Three public actions replace the old Supabase Edge Functions. They are not SQL ports, so they use camelCase keys, typed `v` validators, and no `http_<status>` codes. iOS calls them with `POST /api/action`. Each returns its result object directly and fails with `fail(code, message)`. The code names the reason, and the message is the text the app shows or logs.

- `access:verify_purchase` takes `{ jws, transactionId, originalTransactionId, productId, environment, priceDisplay? }`. `environment` is `xcode`, `sandbox`, or `production`. It checks the transaction with Apple, records it, and returns `{ entitled, subscription: { status, productId, expiresAt, environment, originalTransactionId, transactionId } }`.
- `access:redeem_streak_restore` takes the same arguments without `priceDisplay`. It returns `{ restoredCount }`.
- `identity:delete_account` takes `{ appleAuthorizationCode? }` and returns `{ requestId, authDeleteStatus, appleRevocation, requiresManualAppleRevocation, revocationErrorCode? }`. `authDeleteStatus` is `completed` or `queued`. A queued deletion finishes in the background.

Error codes for the two purchase actions: `not_signed_in`, `invalid_request` (bad or local-only transaction), `transaction_mismatch` (the upload differs from what Apple returned, or the bundle is wrong), `invalid_transaction` (unsupported product or type), `app_account_token_missing`, `purchase_linked_to_another_account` (the purchase belongs to another account), `apple_verification_failed`, `service_not_ready`, `purchase_not_saved`, `unexpected`. Streak restore adds `no_entitled_couple` and `no_streak_to_restore`. The iOS app matches `purchase_linked_to_another_account` and `no_streak_to_restore` and treats every other failure as a payment that Apple took but the server has not confirmed yet. `delete_account` fails with `not_signed_in` or `account_deletion_failed`. The Apple server notification webhook is `POST /apple/server-notifications` on the HTTP actions origin.

## Commands

Run from `backend/`:

- `npm run typecheck`
- `npm test`
- `npx convex dev`: pushes to the deployment in `.env.local`. Without one, `CONVEX_AGENT_MODE=anonymous npx convex dev` starts a local backend on the first free ports from `127.0.0.1:3210`. To test a branch on a simulator, use `scripts/local-backend` instead (see below).
- `npx convex run <module>:<function> '<json args>'`

Commands against `api.paeonia.no` need `CONVEX_SELF_HOSTED_URL` and `CONVEX_SELF_HOSTED_ADMIN_KEY` in the shell environment, never in a committed file.

## Testing a branch on a local backend

A deploy replaces every function on `api.paeonia.no`, so a branch never deploys there. Each worktree runs its own local backend instead, and only `main` is deployed. From the repository root of the worktree:

```sh
scripts/local-backend            # keep it running; Ctrl-C or kill stops it
scripts/local-backend --reseed   # copy api.paeonia.no's data again first
```

The script does the following:

- It runs `convex dev` against a local backend at `http://127.0.0.1:<port>`, with HTTP actions on the next port. It pushes this worktree's `backend/convex` and pushes again on every change. The port comes from a hash of the worktree path, so it is different per worktree and the same across restarts.
- It copies `CLERK_JWT_ISSUER_DOMAIN`, `CLERK_SECRET_KEY`, `INVITE_CODE_PEPPER`, `PAEONIA_MEDIA_URL_SECRET`, `PAEONIA_LIVE_RELAY_URL` and `PAEONIA_LIVE_RELAY_SECRET` from `api.paeonia.no` on every run. It leaves out the APNs and Apple keys, so a local backend sends no pushes, verifies no purchases and revokes no Apple tokens. Push sends log `push delivery is not configured` and leave the rows unsent.
- On the first run, or with `--reseed`, it replaces all local data with a snapshot of `api.paeonia.no` (`npx convex export --include-file-storage`, then `npx convex import --replace-all`). The two test accounts are then paired, entitled and have their media. It only reads the hosted deployment. If the hosted data does not fit the branch's schema, the import fails. Fix the schema or the data, then run it again with `--reseed`.
- It writes the untracked `ios/local.xcconfig`, which `ios/debug.xcconfig` includes, so Debug builds of this worktree use the local backend. Release builds ignore it. Delete the file to point Debug builds back at `api.paeonia.no`.

The data lives in `backend/.convex/` of the worktree and survives restarts. While the script runs, plain `npx convex run`, `npx convex data` and `npx convex import` from `backend/` go to the local backend (through `backend/.env.local`), so edit local data freely there. Do not set `CONVEX_SELF_HOSTED_URL` in that shell, because the CLI then targets the hosted deployment instead. Clerk session tokens of the test accounts work on the local backend, since it trusts the same Clerk issuer.

Live games still go through `relay.paeonia.no`. Its rooms are keyed by couple, so two worktrees that test live play with the same couple at the same time hear each other's strokes.

## Hosted deployment

There is no production yet. The hosted deployment at `api.paeonia.no` holds only the developer's two test accounts. Deploying `main` to it and editing its data for testing are pre-approved, so deploy after tests pass and say so in your summary. Deploy only from `main`, and test a branch on a local backend (see above). Schema changes do not need migrations or backfills. If old test rows block a deploy or no longer fit, delete or edit them.

The hosted Convex is self-hosted on the `one-s` server (`ssh one-s`). The stack lives in `/srv/paeonia/convex` and runs with docker compose: the Convex backend and the dashboard. Documents are SQLite in `./data`. Stored files, deployed modules, search indexes and snapshot exports and imports are in five Cloudflare R2 buckets in the EU jurisdiction, named `paeonia-convex-files`, `-modules`, `-search`, `-exports` and `-snapshot-imports`. The R2 key is in `.env` next to the compose file and can reach only those buckets. Both containers bind to localhost, and Caddy terminates TLS.

`/srv/backup/paeonia-backup.sh` backs up the deployment, with its settings in `/srv/backup/paeonia.conf`. A systemd timer runs it every night at 03:25 UTC. It takes a snapshot export with file storage, plus a config archive with the stack's `.env`, `admin-key`, compose file and the output of `convex env list`. Both go to `/srv/paeonia/backups` (14 kept) and to `r2:tidex-supabase-backups/paeonia/`, where copies older than 3 days are deleted to stay inside R2's free 10 GB (`OFFSITE_KEEP_DAYS`). Another timer runs it hourly with `db-only`, which writes an export without files and keeps it on the server only (48 kept). Self-hosted Convex does not delete old export and import zips from its R2 buckets, so `paeonia-convex-exports` and `paeonia-convex-snapshot-imports` have a lifecycle rule that deletes objects after 1 day. The script uses the Convex CLI pinned in `/srv/paeonia/cli`. When `backend/package.json` moves to a new major version, update that copy too. `/srv/backup/watchdog.sh` emails an alert when `api.paeonia.no/version` fails, when `convex-backend-1` is unhealthy, or when the newest backup is too old.

To restore, stop the stack, move `./data` aside and start the stack again, so the backend starts empty with the same instance secret and admin key. Then run `convex env set --force --from-file convex.env` with the file from the config archive, deploy `main` with `scripts/deploy-backend`, and run `convex import --replace-all -y <export.zip>`. Last, run `convex env set PAEONIA_DATA_EPOCH "$(uuidgen)"`. Phones keep their own copy of a game when the server's copy has a lower version, so without a new epoch they hold on to games the restore rolled back. Run the CLI from `/srv/paeonia/cli` on the server, with `CONVEX_SELF_HOSTED_URL=http://127.0.0.1:3210` and the admin key. Switching between local and S3 storage follows the same steps.

Agents have docker access on `one-s` through passwordless `sudo`. The `administrator` user is not in the `docker` group, so plain `docker` fails with "permission denied". Use `sudo -n docker ...`. The containers are `convex-backend-1` and `convex-dashboard-1`. To read backend logs, for example to find the cause of a `Server Error` with a request id, run `ssh one-s 'sudo -n docker logs --since 30m convex-backend-1'`.

| Origin | Purpose |
|---|---|
| `https://api.paeonia.no` | Client API. Use it for the iOS app, `npx convex deploy`, and `npx convex run`. |
| `https://actions.paeonia.no` | HTTP actions: `GET /media` (signed media URLs) and `POST /apple/server-notifications`. |
| `https://convex.paeonia.no` | Dashboard. Reachable on the tailnet only. |

The admin key is in `/srv/paeonia/convex/admin-key` on `one-s` (owner-only). Never commit it, paste it into a file in the repository, or print it into logs.

Deploy with `scripts/deploy-backend` from the repository root of a clean checkout of local `main`. It refuses any other commit and holds the hosted-backend lock from `scripts/lock` while it deploys.

`backend/.env.local` sets `CONVEX_DEPLOYMENT` for local development. The CLI refuses to run when that variable is set next to `CONVEX_SELF_HOSTED_URL`, so add `CONVEX_DEPLOYMENT=` (empty) to hosted commands when the file exists.

Operator functions (`internalMutation`/`internalQuery`/`internalAction`) run with the same two variables and `npx convex run <module>:<function> '<json args>'`. The App Review scripts `ios/Scripts/mint-review-codes.mjs` and `revoke-review-codes.mjs` use this path.

To hand-edit hosted rows for testing, export the table with `npx convex data <table> --format jsonLines`, keep that file as a backup, edit the rows, and load them back with `npx convex import --table <table> --replace -y <file>.jsonl`. The import keeps `_id` and `_creationTime`. `--replace` swaps out the whole table, so the file must hold every row. `npx convex run _system/frontend/patchDocumentsFields` fails with a server error on this deployment. After you delete game rows or roll them back, set a new `PAEONIA_DATA_EPOCH` the same way, or the phones keep showing the old games.

Use Node 20, 22, or 24 for `convex dev` and `convex deploy`, because Convex Node actions fail on Node 26. On macOS, Homebrew's `node@22` is at `/opt/homebrew/opt/node@22/bin`. The `mdr` server no longer hosts Paeonia, so ignore older notes that mention `mdr`, `api.paeonia.no/auth/v1/callback`, or Supabase publishable keys.

Keep server access to what the task needs. Do not change the docker stack, Caddy, or the server itself unless the task asks for it.

## Games

Draw & Guess, Story Chain and the board games (Connect Four, Dots and Boxes, Ultimate Tic-Tac-Toe) are built. Story Chain's design is in `docs/games/story-chain.md`, its opening lines and dare words are in `backend/games/story-chain/`, and `backend/scripts/story-chain/play.mjs` plays the partner from the command line. `GAME_KINDS` in `lib/validators.ts` lists all seven planned kinds, and the shared functions in `games.ts` accept every one of them. The design is in `docs/games/draw-and-guess.md`, `docs/games/board-games.md` and `docs/games-plan.md`. Function arguments and results are documented in the comments of `convex/games.ts` and `convex/drawAndGuess.ts`.

A new game adds its entries at these points and edits no other game:

- Its own `convex/<game>.ts` and `lib/<game>.ts`, with its tables in `schema.ts`.
- `GAME_BACKENDS` in `lib/gameRegistry.ts`: `pushStillWanted`, `deleteCoupleRows`, and optionally `sendDueTurnReminders` and `onLanguageChanged`.
- `GAME_PUSH_COPY` in `lib/notificationCopy.ts`: the lock-screen name and wording of its pushes.
- The kind is in `ALLOWED_CHANNELS` in `relay/src/ticket.ts` already. Keep that list the same as `GAME_KINDS`.

- Every game function needs an active, entitled couple member (`canAccessCoupleContent`). Writes also refuse a user whose account deletion is pending.
- Game tables: `game_settings` and `game_invites` are shared by all games. `games` (one per couple), `game_moves` (one row per round), `game_guesses`, `game_round_stars`, and `game_used_words` belong to Draw & Guess. Each has a `couple_id` index. `deleteCoupleGameRows` in `lib/gameRegistry.ts` deletes the shared rows and then calls each game's `deleteCoupleRows`, when the relationship content is cleaned up or purged.
- Presence (who has a game screen open) lives in the presence component, one room per couple and kind (`gameRoom` in `lib/presence.ts`). `set_game_presence` true is a heartbeat, false leaves the room. The component marks a user offline 60 seconds after the last heartbeat (`GAME_PRESENCE_TIMEOUT_MS`), so readers get a yes or no without a clock read or a cron. `endRelationshipForPair` removes the couple's rooms, and account deletion removes whatever the user still has.
- `get_games_overview` (a query, no clock reads) returns `{ user_id, partner_user_id, couple_id, settings, presence }`. `settings` is null until the couple sets them. `presence` has one `{ kind, my_present, partner_present, last_invite_at }` entry per kind, in `GAME_KINDS` order, for each kind that either partner has open or the caller sent an invite for. `get_draw_and_guess` has the same three fields for Draw & Guess. Other kinds are left out. `last_invite_at` is the caller's own last invite.
- `pick_draw_word`, `submit_drawing`, `submit_guess`, and `give_up_round` use `runClientOperation`, because the app may retry them offline. The client supplies the round id in `pick_draw_word`, so a queued drawing upload can name its round before the server has seen it. `pick_draw_word` also takes the `word_id` of the offered choice the drawer saw, and refuses it once the choices changed. Only the round's drawer can reserve its drawing upload, and the round must already exist, so the app sends `pick_draw_word` before the upload.
- The drawing is a `pkdrawing` asset in the `game-drawings` bucket (purpose `game_drawing_payload`, parent kind `game_move`, parent id = the round id, path context `{ game_id }`). Only members of the couple can read it, through `get_media_signed_url`, once a round holds it.
- Scores are always kept three ways. A solve adds the word points to `games.shared_points`, adds the word points to the drawer, and adds the word points plus the speed bonus plus the first-try bonus to the guesser. The play style in `game_settings` only decides which numbers the app shows.
- Bonuses. The speed bonus is 2 within 15 seconds of the guesser first seeing the drawing, 1 within 30 seconds, and 0 after that. `submit_guess` takes optional `p_speed_bonus` (0, 1 or 2), `p_solve_ms` (finite and 0 or more, stored capped at 30 days) and `p_hints_used` (a whole number from 0 up to the word's letters minus 1, spaces not counted). They are what the guesser's phone showed on its own clock, and the server stores them when present, so a guess that waited offline or reached the server before `mark_round_seen` keeps the bonus on screen. `scoreSolve` in `lib/drawAndGuess.ts` decides only when a claim is missing. Any hint sets the speed bonus and the first-try bonus to 0. The server decides the first-try bonus itself: 1 when the correct guess is the round's first stored attempt and no hint was used. All three claims are in the request hash. A wrong guess ignores them. A hint-free solve with a solve time that beats every earlier hint-free solve by the same guesser, with at least one earlier, is stored as `personal_best`. `mark_round_seen` still records `guesser_first_seen_at` for the live display and the fallback.
- After a round. `set_round_reaction` (the guesser only, `love`, `laugh`, `wow` or null), `set_round_star` (either partner, private) and `mark_round_result_seen` (the drawer or the guesser, keeps the first time) work on finished rounds only. They are plain idempotent writes without `runClientOperation`, and none of them sends a push. `get_draw_and_guess_history` pages the couple's finished rounds that hold a drawing (limit capped at 50, cursor `p_before_round_number`), and `get_draw_and_guess_records` scans the couple's rounds with the `by_couple_id` index. Both are queries that do not read the clock. The round projection (`roundJson`: `current_round`, `recent_rounds`, and `get_draw_and_guess_round`) carries the caller's own `starred_by_me`, one `by_move_id_user_id` lookup per round, and never the partner's star.
- Games never write to `memories`. `deleteCoupleGameRows` deletes the stars with the other game rows, and account deletion reaches them through the relationship cleanup.
- A sent drawing counts as the `game_turn_completed` streak activity (dedupe key `game_turn_completed:<round id>`).
- Pushes use the kinds `game_turn_ready`, `game_result`, `game_invite`, and `game_turn_reminder`. `game_result` means the partner finished something you wait to see, such as a solved drawing. All four follow `games_enabled`. The payload carries `type`, `game_kind`, `couple_id`, `game_id` and `round_id` when the game passes them (never on invites), `step` when the game passes one, `actor_user_id`, `route: "games"`, and `deeplink: "paeonia://games/<kind with dashes>"`, for example `paeonia://games/draw-and-guess`. It never carries the word, a drawing, or written content. The turn and result pushes are skipped while the recipient has that game open (`isGamePresent`). The title and body come from `GAME_PUSH_COPY` in `lib/notificationCopy.ts` by `payload.game_kind`, or from the entry's `steps` when `payload.step` names one. `step` is a fixed token the game picks, never content. A kind without an entry gets the title "Paeonia".
- Mind Meld (`docs/games/mind-meld.md`) has its own tables `mind_meld_games`, `mind_meld_rounds` and `mind_meld_words`. `get_mind_meld` returns the partner's word only for a revealed round, so a word stays hidden until both partners locked in. `lock_mind_meld_word` uses `runClientOperation`, and the second lock-in reveals the round in the same mutation. Each lock-in counts as `game_turn_completed` with the dedupe key `game_turn_completed:<round id>:<user id>`. Every write bumps the version of the game it touches and of the couple's newest game, so the app can tell an older read from a newer one.
- Board games (`docs/games/board-games.md`) keep one `board_games` row per couple and kind with the move list, and `board_game_marks` with each partner's drawn mark. `make_move` and `start_rematch` check the version, so a stale move fails with 40001. `backend/scripts/boardGames/play.mjs` plays either account from the command line.
- Question time reminder: `enqueue-question-time-reminders` (every 5 minutes, `questionTime.ts`) reads the users with `question_time_enabled` through the `by_question_time_enabled` index and queues a `question_time_reminder` push when the chosen time came in the last 15 minutes of the user's current local date (`questionTimeDue` in `lib/questionTime.ts`; a window never crosses local midnight). The time zone is the one the streak reminders use (`resolveMemberStreakTimeZone`). It skips users without an entitled couple, with an answer on any question of the running couple day or a completed day, and without a device. The dedupe key is user, local date, and device. `prepare_notification` asks `hasStartedToday` (`lib/questionTimeStatus.ts`) again before every send attempt, so a retry after an answer is dropped. The payload carries `expires_at` (the end of the local date), which `notificationStaleAt` turns into `apns-expiration`. The push is not a streak event. Its tap opens `paeonia://daily/today`.
- Crons: `send-due-game-turn-reminders` (one reminder per turn after 72 hours). The reminder cron calls `sendDueTurnReminders` of every game in `GAME_BACKENDS` that has turns. Changing the game language calls `onLanguageChanged` of every game that has it.

## Live drawing relay

`relay/` at the repository root is a Cloudflare Worker at `wss://relay.paeonia.no/canvas`. It forwards drawing messages between the two partners of one couple and stores nothing. Sockets of the same user, such as the Home tab and the canvas on one phone, never hear each other. The app gets a 60-second ticket from `widget:create_widget_live_ticket`, which runs the usual couple access checks, and sends it as `Authorization: Bearer <ticket>`. The relay checks the HMAC and puts the socket in the couple's Durable Object room. Sockets close after 10 minutes and reconnect with a new ticket. That holds for a socket that only listens too: the room closes an expired socket instead of forwarding to it, and a Durable Object alarm closes expired sockets in a quiet room. The rule lives in `relay/src/room.ts`.

Game sockets use their own room. `games:create_game_live_ticket` adds a channel claim `ch` (the game kind, for example `draw_and_guess`) to the ticket, and the Worker puts the socket in the room `<couple id>:<channel>`. A ticket without `ch` still joins the couple's widget canvas room. The Worker rejects a channel that is not in `ALLOWED_CHANNELS` in `relay/src/ticket.ts`, and it lists every kind in `GAME_KINDS`. Convex issues a ticket for any of them. `lib/liveTicket.ts` signs both kinds of ticket.

The ticket mutations return null while `PAEONIA_LIVE_RELAY_URL` or `PAEONIA_LIVE_RELAY_SECRET` is unset, and the app then draws without the relay. The Worker secret `RELAY_TICKET_SECRET` must equal `PAEONIA_LIVE_RELAY_SECRET`. To rotate it, generate one value and set it in both places (`npx wrangler secret put RELAY_TICKET_SECRET` from `relay/`, and `npx convex env set`).

From `relay/`: `npm test`, `npm run typecheck`, and `npx wrangler deploy`.
