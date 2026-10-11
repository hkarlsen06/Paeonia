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
- `seed/subscription_products.json`: subscription product reference data, loaded by `internal.catalog.seed_subscription_products`.

## iOS contract

The iOS app subscribes to reads over the ConvexMobile WebSocket client and writes the results into its local store, so partner changes show up live. Writes and one-shot reads go over the HTTP API (`POST /api/mutation`, `/api/query`, `/api/action` with `{"path","args","format":"json"}`) through the app's offline outbox. Both use the Clerk session token. The widget extension uses HTTP only.

Every Convex function ported from a Supabase RPC keeps that RPC's contract:

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
- `invoke_*_drain` and outbox `AFTER INSERT` triggers: schedule the drain with `ctx.scheduler.runAfter(0, ...)`.
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
| `accountDeletion.ts` | `assertNoPendingAccountDeletion` |
| `entitlements.ts`, `access.ts` | membership, entitlement, block, and pair helpers |
| `coupleDays.ts` | couple day anchors, `getOrCreateCoupleDayAt`, `userLocalDate` |
| `syncEvents.ts` | `createRelationshipSyncEvent` |
| `relationshipEnd.ts` | `endRelationshipForPair` (used by leave, block, report, and account deletion), `deleteLatestLocationsForCouple` |
| `streaks.ts`, `streakDeadlines.ts` | streak core, restore, and the zone-change refreshes |
| `notifications.ts`, `notificationCopy.ts` | outbox inserts, enqueue helpers, notification copy |
| `reports.ts` | `tombstoneReportTargets` |
| `mediaOrphans.ts` | live-reference check and orphan queueing |

Rules that come with them:

- Patches that write `updated_at` go through `withUpdatedAt` or `withTouch`. Do not hand-write `updated_at`.
- Postgres ran orphan media triggers at commit time (deferred). Call the `queue*IfOrphaned` helpers after the mutation's last write to the referencing rows.
- After writing `user_devices`, call `refreshStreakAfterDeviceTimeZoneChange`. After changing `profiles.time_zone_id`, call `refreshStreakAfterProfileTimeZoneChange`. After a daily answer insert, call `enqueuePartnerAnsweredNotification`. After a memory insert, call `enqueueMemoryCreatedNotification`. After a widget revision insert, call `enqueueWidgetUpdateAlert`.
- Insert outbox rows only through `insertNotificationOutbox` and `insertWidgetPushOutbox`. They apply the check constraints, dedupe keys, and payload safety rule. Callers then call `scheduleNotificationDrain` or `scheduleWidgetPushDrain`. The `enqueue*` helpers do this already.
- `readCoupleStreak` is the pure streak reader for queries. A just-broken streak shows as broken with its restore offer, without writing. `getCoupleStreakForCouple` first persists the break with `detectStreakBreak`, so call it only from a mutation. The streak cron and `applyStreakRestore` persist breaks, so `restorable_count` is stored before a restore needs it.
- Time zone math uses `Intl.DateTimeFormat`. It follows the Postgres rules at daylight saving changes: a local time in a spring-forward gap uses the offset from before the gap, and an ambiguous fall-back time resolves to standard time.

## Tests

- `vitest.config.ts` runs tests in the `edge-runtime` environment. Test files are `convex/**/*.test.ts`. The two dots keep Convex from bundling them.
- `convex/test.setup.ts` (also two dots) has the shared helpers: `newTest()`, `createSignedInUser(t, { name, timeZone, claims })`, `createCouple(t, { timeZones, entitled })`, `setTimeZone`, `addDevice`, `grantLifetime`. Run helpers as a user with `user.as.run(...)` or `user.as.mutation(...)`.
- For time-dependent code use `vi.useFakeTimers({ toFake: ["Date"] })` and `vi.setSystemTime(...)`. End tests that schedule a push drain with `await t.finishAllScheduledFunctions(vi.runAllTimers)`.
- `tsconfig.json` lists `types: ["node", "vite/client"]` because TypeScript 7 no longer loads `@types/*` packages on its own.

## Client operations

Local-first writes from iOS carry `p_client_operation_id`, `p_client_id`, `p_client_sequence`, and `p_local_created_at`. Wrap them with `runClientOperation` from `lib/clientOperations.ts`. It returns the stored response when the same operation already succeeded, fails with `23505 client operation replay hash mismatch` when the request differs, and stores the new response otherwise. The request hash is the `sha256Hex` of a stable JSON encoding of the request fields the SQL function hashed.

## Media storage

- Files live in Convex file storage. `media_assets` keeps its SQL columns, and `storage_id` holds the `Id<"_storage">` once the upload finishes.
- `create_pending_media_upload` returns the SQL reservation fields plus `upload_url` from `ctx.storage.generateUploadUrl()`. The app POSTs the bytes there and passes the returned `storageId` to `finalize_media_upload` as `p_storage_id`. Finalize checks size and content type against `ctx.db.system.get(storageId)` before accepting.
- Convex storage URLs never expire, so do not hand them out. `get_media_signed_url` returns the SQL function's rows, each with an added `signed_url` string. The SQL version returned only the authorized bucket and path, and the app then asked Supabase Storage to sign it. `signed_url` points to the `GET /media` HTTP action with `asset`, `exp`, and an HMAC-SHA256 `sig` signed with the `PAEONIA_MEDIA_URL_SECRET` environment variable. The action verifies the signature and expiry, then streams the blob. Use the expiry the app asked for (`p_expires_in_seconds` or the SQL equivalent), capped at the old limit.
- Production origins: client API `https://api.paeonia.no` (`CONVEX_CLOUD_URL`), HTTP actions `https://actions.paeonia.no` (`CONVEX_SITE_URL`). Build signed URLs from `process.env.CONVEX_SITE_URL`.

## Scheduling and push

- pg_cron jobs live in `convex/crons.ts`.
- APNs delivery runs in Node actions (`"use node"`), because APNs requires HTTP/2. Outbox tables keep their SQL shape. Inserting outbox rows schedules a drain right away, and a cron drains anything left over.

## Environment variables

Set these with `npx convex env set`: `CLERK_JWT_ISSUER_DOMAIN`, `CLERK_SECRET_KEY`, `PAEONIA_MEDIA_URL_SECRET`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`, `APPLE_BUNDLE_ID`, `APPLE_APP_APPLE_ID`, `PAEONIA_LIVE_RELAY_URL`, `PAEONIA_LIVE_RELAY_SECRET`. Never commit values.

## Module map

| Module | App-callable functions |
|---|---|
| `identity` | `ensure_current_user`, `get_own_profile`, `complete_profile_onboarding`, `update_own_profile`, `set_own_provider_profile_photo`, `register_user_device`, `disable_user_device`, `get_notification_preferences`, `set_notification_preference`, `get_privacy_requests`, `create_privacy_request`, `request_account_deletion`, `delete_account` (action) |
| `pairing` | `create_pairing_invite`, `preview_pairing_invite`, `validate_my_pairing_invite`, `accept_pairing_invite`, `revoke_pairing_invite`, `rotate_pairing_invite` |
| `relationship` | `get_current_relationship_state`, `get_relationship_sync_events`, `leave_relationship`, `block_relationship`, `unblock_pair`, `mark_relationship_ended_notice_seen`, `set_couple_started_on` |
| `access` | `get_access_snapshot`, `get_my_entitlement`, `get_my_couple_entitlement`, `get_or_create_app_account_token`, `complete_review_access_session`, `verify_purchase` (action), `redeem_streak_restore` (action) |
| `daily` | `get_active_question_catalog`, `start_daily_challenge`, `start_daily_challenge_snapshot`, `get_today_daily_challenge_snapshot`, `get_daily_challenge_snapshot` (query by `p_couple_day_id`; subscribe to this one, since its rows do not depend on the clock), `get_today_daily_questions`, `shuffle_daily_question`, `shuffle_daily_question_snapshot`, `submit_daily_answer`, `update_daily_answer_text`, `update_daily_answer_partner_choice`, `get_daily_answer_details`, `get_daily_answer_details_for_couple_days`, `get_daily_answer_reveal_state`, `get_daily_questions_history`, `get_daily_answer_history_details`, `get_question_answer_history` |
| `streaks` | `get_couple_streak` |
| `threads` | `get_conversation_threads`, `get_thread_messages`, `send_thread_message`, `create_daily_question_thread_with_message`, `create_memory_thread_with_message` |
| `memories` | `create_memory`, `update_memory`, `hide_memory`, `get_memories`, `upsert_memory_note`, `attach_memory_media`, `remove_memory_media` |
| `media` | `create_pending_media_upload`, `finalize_media_upload`, `get_media_signed_url`, `mark_media_for_deletion` |
| `widget` | `get_or_create_widget_canvas`, `get_widget_canvas`, `get_widget_drawing_revisions`, `submit_widget_drawing_revision`, `register_widget_push_device`, `create_widget_live_ticket` |
| `location` | `update_latest_partner_location`, `update_location_sharing_preference`, `get_partner_location_visibility` |
| `reports` | `submit_content_report`, `submit_leave_and_report` |

These functions replace direct PostgREST table access from iOS. They return full rows with SQL column names and apply the old RLS rules:

- `identity:get_own_profile` `{}` returns the caller's `profiles` row.
- `identity:complete_profile_onboarding` `{p_time_zone_id, p_profile_photo_asset_id?}` sets `time_zone_id`, `time_zone_updated_at`, `onboarding_completed_at`, and optionally `profile_photo_asset_id`, then returns the profile row.
- `identity:get_notification_preferences` `{}` returns the caller's `notification_preferences` row. `identity:set_notification_preference` `{p_column, p_enabled}` updates one boolean column (`streak_reminders_enabled`, `daily_challenge_enabled`, `partner_answered_enabled`, `messages_enabled`, `widget_updates_enabled`, `memories_enabled`).
- `identity:get_privacy_requests` `{}` returns the caller's `privacy_requests`, newest `requested_at` first, at most 100. `identity:create_privacy_request` `{p_id, p_kind, p_requester_note?}` inserts one and returns the row.
- `relationship:get_relationship_sync_events` `{p_after_created_at?, p_after_id?, p_limit}` returns the caller's events ordered by `created_at`, then `id`, strictly after the cursor.

The three Supabase Edge Functions the app called become public actions: `apple-verify-purchase` is `access:verify_purchase`, `apple-redeem-streak-restore` is `access:redeem_streak_restore`, and `delete-account` is `identity:delete_account`. iOS calls them with `POST /api/action`. Their arguments are the Edge Function's JSON request body keys, unchanged. A 2xx Edge Function response body becomes the return value. A non-2xx response becomes `fail("http_<status>", <the body's error string>)`, so the app still sees the same reason text. The Apple server notification webhook is `POST /apple/server-notifications` on the HTTP actions origin.

## Commands

Run from `backend/`:

- `npm run typecheck`
- `npm test`
- `npx convex dev`: pushes to the deployment in `.env.local`. Without one, `CONVEX_AGENT_MODE=anonymous npx convex dev` starts a local backend on `127.0.0.1:3210` (HTTP actions on `3211`).
- `npx convex run <module>:<function> '<json args>'`

Production deploys need `CONVEX_SELF_HOSTED_URL` and `CONVEX_SELF_HOSTED_ADMIN_KEY` in the shell environment, never in a committed file.

## Production

Production Convex is self-hosted on the `one-s` server (`ssh one-s`). The stack lives in `/srv/paeonia/convex` and runs with docker compose: the Convex backend and the dashboard. Data is SQLite in `./data`. Both containers bind to localhost, and Caddy terminates TLS.

Agents have docker access on `one-s` through passwordless `sudo`. The `administrator` user is not in the `docker` group, so plain `docker` fails with "permission denied". Use `sudo -n docker ...`. The containers are `convex-backend-1` and `convex-dashboard-1`. To read backend logs, for example to find the cause of a `Server Error` with a request id, run `ssh one-s 'sudo -n docker logs --since 30m convex-backend-1'`.

| Origin | Purpose |
|---|---|
| `https://api.paeonia.no` | Client API. Use it for the iOS app, `npx convex deploy`, and `npx convex run`. |
| `https://actions.paeonia.no` | HTTP actions: `GET /media` (signed media URLs) and `POST /apple/server-notifications`. |
| `https://convex.paeonia.no` | Dashboard. Reachable on the tailnet only. |

The admin key is in `/srv/paeonia/convex/admin-key` on `one-s` (owner-only). Never commit it, paste it into a file in the repository, or print it into logs.

Deploy from `backend/`:

```sh
CONVEX_SELF_HOSTED_URL=https://api.paeonia.no \
CONVEX_SELF_HOSTED_ADMIN_KEY="$(ssh one-s cat /srv/paeonia/convex/admin-key)" \
npx convex deploy
```

`backend/.env.local` sets `CONVEX_DEPLOYMENT` for local development. The CLI refuses to run when that variable is set next to `CONVEX_SELF_HOSTED_URL`, so add `CONVEX_DEPLOYMENT=` (empty) to the command when the file exists.

Operator functions (`internalMutation`/`internalQuery`/`internalAction`) run with the same two variables and `npx convex run <module>:<function> '<json args>'`. The App Review scripts `ios/Scripts/mint-review-codes.mjs` and `revoke-review-codes.mjs` use this path.

To hand-edit production rows for testing, export the table with `npx convex data <table> --format jsonLines`, keep that file as a backup, edit the rows, and load them back with `npx convex import --table <table> --replace -y <file>.jsonl`. The import keeps `_id` and `_creationTime`. `--replace` swaps out the whole table, so the file must hold every row. `npx convex run _system/frontend/patchDocumentsFields` fails with a server error on this deployment.

Use Node 20, 22, or 24 for `convex dev` and `convex deploy`, because Convex Node actions fail on Node 26. On macOS, Homebrew's `node@22` is at `/opt/homebrew/opt/node@22/bin`. The `mdr` server no longer hosts Paeonia, so ignore older notes that mention `mdr`, `api.paeonia.no/auth/v1/callback`, or Supabase publishable keys.

Limit production access to the operation the task authorizes.

## Live drawing relay

`relay/` at the repository root is a Cloudflare Worker at `wss://relay.paeonia.no/canvas`. It forwards drawing messages between the two partners of one couple and stores nothing. Sockets of the same user, such as the Home tab and the canvas on one phone, never hear each other. The app gets a 60-second ticket from `widget:create_widget_live_ticket`, which runs the usual couple access checks, and sends it as `Authorization: Bearer <ticket>`. The relay checks the HMAC and puts the socket in the couple's Durable Object room. Sockets close after 10 minutes and reconnect with a new ticket.

The mutation returns null while `PAEONIA_LIVE_RELAY_URL` or `PAEONIA_LIVE_RELAY_SECRET` is unset, and the app then draws without the relay. The Worker secret `RELAY_TICKET_SECRET` must equal `PAEONIA_LIVE_RELAY_SECRET`. To rotate it, generate one value and set it in both places (`npx wrangler secret put RELAY_TICKET_SECRET` from `relay/`, and `npx convex env set`).

From `relay/`: `npm test`, `npm run typecheck`, and `npx wrangler deploy`.
