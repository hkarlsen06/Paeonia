# Phase 3 Migration Checklist

This checklist records the design and audit criteria used to turn `docs/phase-3-data-contract.md` into the first Supabase migration slices.

Status: implemented as a migration series. This document is now a historical schema/security audit reference, not the active progress tracker. Use `docs/mvp-release-checklist.md` for release readiness and inspect `supabase/migrations/` for the applied source history. Unchecked boxes below are review criteria retained for traceability; they do not mean that no SQL exists.

Rules:

- Create migration files with `supabase migration new <name>` when SQL work starts.
- Do not apply remote migrations until a Supabase project is intentionally linked.
- Keep each migration reviewable. If a migration becomes hard to audit, split it.
- Enable RLS on every table in exposed schemas.
- Keep privileged helpers in `internal` by default. Public RPC wrappers may be
  `security definer` only when they are approved client/service entry points,
  use a fixed `search_path`, have narrow `EXECUTE` grants, and avoid exposing
  broad table-shaped access.
- Use `security_invoker = true` for exposed views that should respect RLS.
- Revoke broad privileges before granting narrow client access.
- Use `TO authenticated` on ordinary user policies.
- Wrap stable auth helper calls in policies, for example `(select auth.uid())`, to avoid per-row auth helper execution.
- Add indexes for every FK, every RLS lookup column, every sync cursor, and every cleanup predicate.

Current Supabase docs checked while writing this plan:

- RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- RLS performance: https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv
- Storage access control: https://supabase.com/docs/guides/storage/security/access-control
- Storage helper functions: https://supabase.com/docs/guides/storage/schema/helper-functions
- Security-invoker views: https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0010_security_definer_view

## Implementation Gates

Before writing SQL for a slice:

- [ ] Confirm every table is classified as direct-sync, RPC/read-model, or internal-only.
- [ ] Confirm every status/source/kind column uses an enum or constrained text.
- [ ] Confirm PKs, FKs, unique constraints, `ON DELETE` behavior, and check constraints.
- [ ] Confirm supporting indexes exist before RLS policies that depend on them are enabled.
- [ ] Confirm every RLS helper lookup has supporting indexes.
- [ ] Confirm ordinary users cannot call privileged internals directly.
- [ ] Confirm upload-backed content uses `media_assets`, not duplicate lifecycle columns.
- [x] Required question catalog data is versioned in `supabase/questions/` and applied through catalog migrations; non-MVP seed data is not required.
- [ ] Confirm cleanup/retry behavior for rows that can outlive the user or relationship.
- [ ] Confirm the slice can be tested locally with SQL assertions or focused app-level smoke tests.

## Schema Boundaries

Use these schemas from the first migration:

- `public`: client-visible tables, client-callable RPC wrappers, and safe read models.
- `internal`: privileged tables, security-definer helpers, StoreKit raw data, review-code data, notification outbox, rate limits, cleanup state, and admin audit data.

Default grants:

- `anon`: no direct table access.
- `authenticated`: execute only on approved public RPC wrappers and direct table access only where this checklist explicitly allows it.
- `service_role`: internal operations, webhooks, cron, cleanup, review access, StoreKit reconciliation, report snapshots, and moderation runbooks.

## Common Columns

Use these defaults unless a slice explains otherwise:

- `id uuid primary key default gen_random_uuid()`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()` on mutable rows
- `revision integer not null default 1` on mutable directly synced rows
- `deleted_at timestamptz` on soft-deletable client-visible rows
- `moderation_status moderation_status not null default 'visible'` on reportable content
- `moderated_at timestamptz`
- `moderated_by uuid`
- `moderation_report_id uuid`
- `client_operation_id uuid` or operation linkage on queued user writes

Trigger helpers:

- `internal.set_updated_at()` updates `updated_at`.
- `internal.bump_revision()` increments `revision` when mutable synced rows change.
- `internal.touch_updated_at_and_revision()` can combine both for direct-sync rows.
- `internal.assert_not_user_editable_moderation_fields()` or column grants/RPC-only writes must prevent clients from setting moderation fields.

Avoid `ON DELETE CASCADE` from `auth.users` to relationship content, reports, StoreKit audit rows, or privacy audit rows. Account deletion must be an explicit server workflow.

## Constrained Values

Prefer Postgres enums for stable values used across many tables or RLS helpers. Use constrained text/check constraints for volatile operational/admin values that may need removal, renaming, or semantic reshaping.

Create each enum or constrained value in the same migration as its first consuming table unless the value is truly foundational. Do not create every value below in migration 001 just because it is listed here.

| Name | Values |
| --- | --- |
| `couple_status` | `active`, `ended`, `deleted` |
| `couple_member_status` | `active`, `left`, `ended_notice_pending`, `ended_notice_seen` |
| `pairing_invite_status` | `pending`, `accepted`, `revoked`, `expired` |
| `relationship_sync_event_kind` | `relationship_ended`, `relationship_deleted`, `entitlement_lost`, `entitlement_restored`, `content_hidden`, `account_deletion_started`, `account_deleted` |
| `relationship_block_revoke_reason` | `user_unblocked`, `moderation_unblocked`, `admin_correction` |
| `subscription_product_kind` | `couple_subscription` |
| `billing_period` | `monthly`, `yearly` |
| `storekit_environment` | `xcode`, `sandbox`, `production` |
| `storekit_payload_kind` | `transaction`, `renewal_info`, `server_notification`, `server_api_response` |
| `entitlement_source` | `storekit`, `lifetime_grant`, `review_grant`, `test_grant` |
| `entitlement_status` | `active`, `grace`, `billing_retry`, `expired`, `revoked`, `refunded`, `lifetime` |
| `entitlement_grant_kind` | `lifetime`, `review`, `test`, `beta` |
| `entitlement_grant_status` | `active`, `expired`, `revoked` |
| `review_access_scenario` | `pre_paired_entitled`, `purchase_flow_unentitled` |
| `review_access_code_status` | `active`, `revoked`, `expired` |
| `question_collection_kind` | `system`, `custom`, `mini_game` |
| `catalog_status` | `draft`, `active`, `inactive`, `retired`, `archived` |
| `question_answer_kind` | `text`, `photo`, `voice`, `partner_choice` |
| `daily_question_instance_status` | `active`, `shuffled`, `answered` |
| `conversation_thread_kind` | `daily_question`, `memory` |
| `media_type` | `image`, `voice`, `drawing_payload`, `report_snapshot` |
| `upload_purpose` | `profile_photo`, `memory_photo`, `voice_note`, `daily_answer_media`, `thread_media`, `widget_drawing_payload`, `report_snapshot` |
| `reserved_parent_kind` | `profile_photo`, `memory_media`, `daily_answer_media`, `thread_message_media`, `widget_drawing_revision`, `report_snapshot` |
| `upload_status` | `pending`, `finalized`, `failed`, `expired` |
| `storage_delete_status` | `none`, `pending`, `retrying`, `deleted`, `failed` |
| `moderation_status` | `pending_review`, `visible`, `hidden`, `removed`, `rejected` |
| `notification_kind` | `streak_reminder`, `daily_challenge_completed`, `partner_answered`, `widget_updated`, `location_updated`, `relationship_ended`, `entitlement_changed` |
| `notification_redaction_level` | `private`, `generic`, `content_allowed` |
| `lock_screen_detail_level` | `private`, `descriptive` |
| `apns_environment` | `sandbox`, `production` |
| `location_source` | `foreground_open`, `manual_refresh`, `settings_toggle` |
| `activity_kind` | `daily_challenge_completed`, `widget_drawing_saved`, `memory_created`, `memory_updated`, `thread_message_sent` |
| `report_reason` | `harassment`, `abuse`, `threat`, `sexual_content`, `hate`, `privacy`, `impersonation`, `self_harm`, `spam`, `other` |
| `content_report_status` | `submitted`, `under_review`, `action_taken`, `rejected`, `closed` |
| `moderation_action_kind` | `hide`, `remove`, `restore`, `reject_upload`, `delete_storage`, `create_pair_warning`, `clear_pair_warning`, `block_pair`, `unblock_pair` |
| `moderation_action_status` | `started`, `applied`, `partially_applied`, `failed` |
| `moderation_operator_kind` | `service_role`, `sql_runbook`, `edge_function`, `admin_user` |
| `privacy_request_kind` | `access`, `export`, `deletion`, `correction` |
| `privacy_request_status` | `submitted`, `verifying`, `processing`, `completed`, `rejected`, `cancelled` |
| `device_platform` | `ios`, `ipados` |
| `drawing_format` | `pkdrawing` |
| `drawing_compression` | `none`, `gzip` |

Product note: supporting both monthly and yearly product rows does not mean both must launch. Seed only the actual products before TestFlight or App Review.

## Data Surface Classification

| Surface | Classification | Notes |
| --- | --- | --- |
| `profiles` | direct-sync with limited partner read model | Self-owned fields can sync directly; partner profile should be shaped through a view/RPC to avoid user search. |
| `relationship_pairs` | RPC/read-model | No broad direct listing. |
| `couples` | RPC/read-model | Minimal ended-notice metadata remains readable after relationship end. |
| `couple_members` | RPC/read-model | Used by access helpers and relationship routing. |
| `pairing_invites` | RPC/read-model | Creator sees own pending invite metadata; acceptor resolves through preview/accept RPC. |
| `relationship_blocks` | internal/RPC-read | Ordinary clients learn block effects only through pairing/current-relationship RPCs. |
| `relationship_sync_events` | direct-sync/read-model | Needed for local access-loss, cleanup deadlines, and support debugging. |
| `subscription_products` | read-model | Authenticated clients can read active products. |
| `public.user_entitlements` | RPC-only view | Revoke direct client read. Use `get_my_entitlement()` and `get_my_couple_entitlement()`. |
| StoreKit internal tables | internal-only | Service/Edge Function only. |
| Review access internal tables | internal-only | Edge Function only after normal user JWT. |
| Question catalog tables | read-model | Active system rows can be read through views/RPCs; writes are seed/admin SQL only. |
| Daily challenge tables | RPC/read-model | Start/shuffle/submit through RPCs; read models enforce reveal rules. |
| Answer detail tables | RPC/read-model | Never rely on client filtering for partner answer body/media. |
| Threads/messages | RPC/read-model | Message send through RPC; reads require active entitled couple. |
| `media_assets` | RPC/read-model | Reservation/finalize/delete through RPC; signed URL flows validate media state. |
| Memories | direct-sync via RPC-backed writes | Reads can be synced after access checks; title/date updates use revision checks. |
| Widget drawings | RPC/read-model | Canonical payloads in Storage; rows store metadata/history. |
| Streak/activity | read-model/system-write | Activity events are append-only enough to audit. |
| Notification preferences | direct self-owned | Low-risk direct sync after RLS. |
| Devices | RPC/direct self-owned | Registration/update can be RPC to normalize tokens and hashes. |
| Location tables | RPC/read-model | Updates through RPC; map read model reports visibility state. |
| Reports | RPC/read-model | Reporter sees status only; admin review is internal/service-controlled. |
| Privacy requests | RPC/read-model | User sees request status; processing is internal. |
| `internal.*` | internal-only | Not exposed through Data API. |

## RLS Helper Checklist

Create helpers in `internal` after their referenced tables exist:

- [ ] `internal.current_user_id() returns uuid`
- [ ] `internal.is_active_couple_member(couple_id uuid) returns boolean`
- [ ] `internal.is_active_entitled_couple_member(couple_id uuid) returns boolean`
- [ ] `internal.is_couple_pair_member(pair_id uuid) returns boolean`
- [ ] `internal.can_access_couple_content(content_couple_id uuid) returns boolean`
- [ ] `internal.can_view_daily_answer(answer_id uuid) returns boolean`
- [ ] `internal.is_admin() returns boolean`

Helper rules:

- `security definer`
- fixed `search_path`
- fully qualified table names
- no user-editable metadata
- no email-based authorization
- no broad `authenticated` execute unless a helper is explicitly safe to expose
- RLS policies call helpers with `(select internal.helper(...))` when result is stable for the statement

Required helper indexes:

- `profiles(user_id)`
- `couple_members(user_id, status, couple_id)`
- partial unique active membership on `couple_members(user_id) where status = 'active'`
- `couple_members(couple_id, user_id, status)`
- `couples(id, status)`
- `couples(pair_id, status)`
- entitlement resolver indexes on active StoreKit transactions and active grants
- `relationship_pairs(user_low_id, user_high_id)`
- `daily_question_answers(instance_id, user_id)`
- `daily_question_instances(id, couple_day_id, question_version_id)`
- `couple_days(id, couple_id)`
- `media_assets(couple_id, upload_status, moderation_status, deleted_at)`

## Storage Buckets

Create private buckets:

- `profile-photos`
- `couple-media`
- `widget-drawings`
- `report-snapshots`

Object paths:

- `profile-photos/{user_id}/{asset_id}.{ext}`
- `couple-media/{couple_id}/{media_type}/{asset_id}.{ext}`
- `widget-drawings/{couple_id}/{canvas_id}/revisions/{revision_id}/drawing.pkdrawing`
- `report-snapshots/{report_id}/{asset_id}.{ext}`

Storage policy requirements:

- [ ] No public buckets for private app content.
- [ ] Uploads must match an existing pending `media_assets` reservation.
- [ ] Downloads must require finalized, non-deleted, visible media and the correct ownership/couple access.
- [ ] No overwrites for finalized objects.
- [ ] Upsert should not be part of normal app uploads.
- [ ] `report-snapshots` is service/admin only.
- [ ] Signed URL RPCs must deny hidden, removed, rejected, pending, expired, or relationship-ended media.
- [ ] Storage cleanup jobs delete objects first or mark retries before deleting metadata.

## Migration Slices

### 001 Foundation: Schemas, Extensions, Client Operations, Utilities

Purpose: create the base database language that every later migration relies on.

Tables/functions:

- `internal.client_operations`
- common trigger functions
- optional RLS auto-enable event trigger for `public` tables, if we decide to use it

Checklist:

- [ ] Enable required extensions with explicit SQL. Start with `pgcrypto` if `gen_random_uuid()` is not already available locally.
- [ ] Create `internal` schema.
- [ ] Revoke schema/table/function defaults from `public`, `anon`, and `authenticated` for `internal`.
- [ ] Set default privileges in `internal` so future tables, sequences, and functions are not available to ordinary client roles by accident.
- [ ] Do not create feature-specific enums in this slice. Create enums/check constraints beside their first consuming table.
- [ ] Create `internal.client_operations` with unique `(user_id, client_operation_id)`.
- [ ] Add `client_id`, `client_sequence`, `local_created_at`, `operation_kind`, `idempotency_scope`, `request_hash`, `response_hash`, `stored_response`, `status`, `locked_until`, `attempt_count`, `last_attempt_at`, `completed_at`, `failed_at`, and `failure_code` to `internal.client_operations`.
- [ ] Use constrained text for `internal.client_operations.status`: `started`, `succeeded`, `failed_retryable`, `failed_terminal`.
- [ ] Prefer `bytea` SHA-256 hashes for `request_hash` and `response_hash`, with `octet_length(...) = 32`.
- [ ] RPCs using `internal.client_operations` reject a retry when the same `(user_id, client_operation_id)` arrives with a different `request_hash`, even if the idempotency scope differs.
- [ ] RPCs using `internal.client_operations` replay the stored successful response for exact duplicate retries instead of applying side effects again.
- [ ] RPCs using `internal.client_operations` mark in-progress operations in a way that concurrent duplicate retries either wait, return a retryable response, or safely return the stored response once available.
- [ ] Create timestamp/revision trigger helpers.
- [ ] Use `security invoker` by default for helper functions. Use `security definer` only for helpers that need elevated access, and always set a fixed `search_path`.
- [ ] Public RPC wrappers that call private `internal.*` functions are approved `security definer` exceptions only when they are thin wrappers and the internal function performs `auth.uid()` authorization.
- [ ] Create `internal.current_user_id()` only if useful; it can be `security invoker` because it only wraps `auth.uid()`.
- [ ] If adding an RLS auto-enable event trigger, keep it as a narrow guardrail for future `public` tables only. Each migration must still explicitly enable RLS on public tables.

Indexes:

- `internal.client_operations(user_id, client_operation_id)` unique
- `internal.client_operations(user_id, idempotency_scope, created_at desc)`
- `internal.client_operations(user_id, created_at desc)`
- `internal.client_operations(status, locked_until)` for stale started operations
- stale operation cleanup index on `(status, created_at)`

Verification:

- [ ] New tables have RLS enabled or are internal-only with client grants revoked.
- [ ] `anon` cannot select any foundation table.
- [ ] `authenticated` cannot select, insert, update, delete, or execute internal objects unless explicitly granted.
- [ ] Security-definer functions, if any, have fixed `search_path`.
- [ ] No broad default function execute remains for future internal functions.

### 002 Identity, Profile, Devices, Notifications, Privacy Requests

Purpose: establish user-owned rows before relationship or entitlement flows.

Tables:

- `public.profiles`
- `public.notification_preferences`
- `public.user_devices`
- `public.privacy_requests`
- optional `internal.privacy_request_events`

Checklist:

- [ ] `profiles.user_id` is PK and FK to `auth.users(id)`.
- [ ] Profile photo uses nullable FK to `media_assets` only after media slice; add FK later if needed.
- [ ] `profiles.display_name` has length constraints.
- [ ] `profiles.time_zone_id` is nullable during early onboarding but required before full product routing.
- [ ] Profile moderation fields exist from first profile migration.
- [ ] Notification preferences default to private lock-screen details.
- [ ] Devices store token hash, APNs environment, app version, locale, timezone, and disabled timestamp.
- [ ] Privacy requests are user-visible by owner only; internal processing fields stay internal where possible.

RLS/RPC:

- [ ] Self can read and update own profile fields.
- [x] Partner profile reads are exposed through the current-relationship read model; no profile listing/search policy exists.
- [x] No profile listing/search policy exists.
- [ ] Self can read/update notification preferences.
- [ ] Device register/update/disable should be RPC-backed or tightly self-owned.
- [ ] Self can create/read privacy requests; service/admin updates status.

Indexes:

- `profiles(user_id)`
- `profiles(updated_at, user_id)` for sync cursor
- `user_devices(user_id, disabled_at)`
- unique active token hash if practical: `(push_token_hash, apns_environment) where disabled_at is null`
- `notification_preferences(user_id)`
- `privacy_requests(user_id, requested_at desc)`

Verification:

- [ ] A signed-in user cannot list all profiles.
- [ ] A signed-in user cannot update moderation fields.

### 003 Relationship Lifecycle, Pairing, Blocks, Sync Events

Purpose: model exactly two-person private relationship spaces and invite-only pairing.

Tables:

- `public.relationship_pairs`
- `public.couples`
- `public.couple_members`
- `public.pairing_invites`
- `internal.pairing_invite_secrets`
- `internal.pairing_invite_attempts`
- `public.relationship_blocks`
- `public.relationship_sync_events`
- `internal.pair_safety_warning_flags`

Checklist:

- [ ] `relationship_pairs.user_low_id < user_high_id`.
- [ ] unique `(user_low_id, user_high_id)`.
- [ ] `couples.pair_id` FK to `relationship_pairs`.
- [ ] `couples.started_on` is required on accepted pairing.
- [ ] `couple_members` has exactly two members per active couple, enforced by accept RPC and supporting constraints/triggers where practical.
- [ ] Partial unique active membership on `couple_members(user_id)` where status is `active`.
- [ ] Invites do not create couple rows before acceptance.
- [ ] Invite code hashes live in `internal`, not public rows.
- [ ] Active blocks reject invite creation and acceptance.
- [ ] Prior reports create pair safety warnings surfaced by invite preview/accept RPC responses.
- [ ] Relationship end inserts `relationship_sync_events` and sets `couples.delete_after`.
- [ ] Relationship lifecycle RPCs insert per-user `relationship_sync_events` when clients must purge or reroute local caches, including relationship start, relationship end, entitlement loss, entitlement restoration, content hide, account deletion start, and final cleanup where applicable.
- [ ] Account deletion reuses relationship end flow before profile anonymization.

RPCs:

- `create_pairing_invite(client_operation)`
- `preview_pairing_invite(code)`
- `accept_pairing_invite(code, started_on, client_operation)`
- `revoke_pairing_invite(invite_id)`
- `leave_relationship(client_operation)`
- `leave_and_report_relationship(...)`
- `block_relationship(...)`
- `unblock_pair(pair_id)`
- `mark_relationship_ended_notice_seen(couple_id)`
- `get_current_relationship_state()`

Indexes:

- `relationship_pairs(user_low_id, user_high_id)` unique
- `couples(pair_id, status)`
- `couples(status, delete_after)` for cleanup
- `couple_members(user_id, status, couple_id)`
- `couple_members(couple_id, user_id, status)`
- `pairing_invites(created_by_user_id, status, expires_at)`
- `relationship_blocks(pair_id, revoked_at)`
- unique active block on `(pair_id, blocked_by_user_id, blocked_user_id) where revoked_at is null`
- `relationship_sync_events(couple_id, created_at, id)`
- `relationship_sync_events(user_id, created_at, id)` if events are user-scoped

Verification:

- [ ] A user cannot accept their own invite.
- [ ] A user cannot enter two active couples.
- [ ] Ending a relationship hides ordinary couple content once content tables exist.
- [ ] Active blocks prevent pairing in either direction.

### 004 Entitlements, StoreKit, Review Access

Purpose: make database-side access depend on user-owned entitlement that covers the active couple.

Tables/views:

- `public.subscription_products`
- `internal.storekit_payloads`
- `internal.storekit_transactions`
- `internal.storekit_notification_events`
- `internal.entitlement_grants`
- `internal.review_access_codes`
- `internal.review_access_attempts`
- `internal.review_access_sessions`
- `public.user_entitlements` resolver view

Checklist:

- [ ] Store raw StoreKit payloads only in `internal`.
- [ ] Unique `(environment, transaction_id)` on transactions.
- [ ] Unique notification UUID.
- [ ] Unique payload SHA where present.
- [ ] Grants can represent lifetime, review, test, and beta access.
- [ ] Lifetime grants may have `expires_at is null`.
- [ ] Review/test grants normally have `expires_at`.
- [ ] Review grants link to `internal.review_access_sessions`.
- [ ] `public.user_entitlements` is a resolver view with direct client `SELECT` revoked.
- [ ] Use typed RPC return rows for entitlement responses.
- [ ] `get_my_couple_entitlement()` checks both active members of the current couple.
- [ ] Before StoreKit launch, client asks backend if current couple is already covered.
- [ ] Valid duplicate Apple transactions are recorded, not discarded.

RPCs/Edge Functions:

- `get_my_entitlement()`
- `get_my_couple_entitlement()`
- StoreKit transaction verification Edge Function
- App Store Server Notification Edge Function
- `redeem-review-access` Edge Function with user JWT
- optional `complete_review_access_session(review_session_id)`

Indexes:

- `subscription_products(apple_product_id)` unique
- `subscription_products(is_active, kind)`
- `internal.storekit_transactions(user_id, status, expires_at)`
- `internal.storekit_transactions(environment, transaction_id)` unique
- `internal.storekit_transactions(environment, original_transaction_id)`
- `internal.entitlement_grants(user_id, status, expires_at)`
- partial unique active grant per `(user_id, grant_kind, product_id) where revoked_at is null`
- `internal.review_access_attempts(user_id, attempted_at desc)`
- `internal.review_access_attempts(code_hash_prefix, attempted_at desc)`

Verification:

- [ ] Ordinary clients cannot read raw transactions, grants, review codes, or payloads.
- [ ] Couple access is true when either active member has `active`, `grace`, or `lifetime`.
- [ ] `billing_retry`, `expired`, `revoked`, and `refunded` deny access.

### 005 Media Assets And Storage Policies

Purpose: centralize upload reservation, finalize, signed URL, and delete retry behavior before any feature stores media.

Tables:

- `public.media_assets`
- Storage bucket rows for `profile-photos`, `couple-media`, `widget-drawings`, `report-snapshots`

Checklist:

- [ ] `media_assets.storage_path` unique within bucket.
- [ ] Pending rows include owner, couple, parent kind/id, client operation id, upload purpose, expected bucket, expected media type, expiry, and status.
- [ ] Finalize stores byte size, MIME type, dimensions/duration where applicable, SHA-256, and finalized timestamp.
- [ ] Hidden/rejected/removed media cannot receive signed URLs.
- [ ] Relationship media deletion is queued through `storage_delete_status`.
- [ ] Report snapshot media retention is separate from relationship cleanup.
- [ ] Storage policies require matching pending reservation for upload.
- [ ] Use short-lived signed URLs by default, starting at 15 minutes.

RPCs:

- `create_pending_media_upload(...)`
- `finalize_media_upload(...)`
- `mark_media_for_deletion(media_asset_id)`
- `get_media_signed_url(media_asset_id)`

Indexes:

- `media_assets(owner_user_id, created_at desc)`
- `media_assets(couple_id, created_at desc)`
- `media_assets(bucket, storage_path)` unique
- `media_assets(upload_status, upload_expires_at)` for stale pending cleanup
- `media_assets(storage_delete_status, storage_delete_attempts, updated_at)` for delete retry
- `media_assets(reserved_parent_kind, reserved_parent_id)`
- `media_assets(sha256)` non-unique unless dedupe requires unique per bucket/type

Verification:

- [ ] User cannot finalize another user's reservation.
- [ ] User cannot finalize a path reserved for another parent or purpose.
- [ ] Upserting an existing finalized object is denied by policy/path design.

### 006 Question Catalog And Seed Data

Purpose: create normalized localized question storage before daily challenge logic.

Tables:

- `public.question_collections`
- `public.questions`
- `public.question_versions`
- `public.question_version_localizations`
- `public.question_answer_kinds`

Checklist:

- [ ] `questions.key` unique within collection.
- [ ] `question_versions` unique on `(question_id, version_number)`.
- [ ] `question_version_localizations` PK `(question_version_id, locale)`.
- [ ] `question_answer_kinds` PK `(question_version_id, answer_kind)`.
- [ ] Enforce at most two answer kinds per version in MVP.
- [ ] Do not add `question_options` for MVP.
- [ ] Active system questions require `en` and `nb` localization rows.
- [ ] Retire/version historical wording instead of editing in place once answered.

Seed data:

- [ ] One active `system` question collection.
- [ ] Initial active question set.
- [ ] English and Norwegian Bokmal localizations for every active version.
- [ ] One or two answer kinds for every active version.

Indexes:

- `question_collections(kind, status)`
- `questions(collection_id, status)`
- `questions(collection_id, key)` unique
- `question_versions(question_id, status)`
- `question_version_localizations(locale)`

Verification:

- [ ] Active question read model returns only versions with required localizations and answer kinds.

### 007 Daily Challenge, Answers, Reveal Rules

Purpose: enforce random daily challenge composition, shuffles, answer submission, and reveal behavior server-side.

Tables:

- `public.couple_days`
- `public.daily_challenges`
- `public.daily_question_instances`
- `public.daily_question_shuffles`
- `public.daily_question_answers`
- `public.daily_answer_text`
- `public.daily_answer_partner_choice`
- `public.daily_answer_media`

Checklist:

- [ ] `couple_days` unique on `(couple_id, local_date)`.
- [ ] `daily_challenges` PK `(couple_day_id, user_id)`.
- [ ] Only one active instance per `(couple_day_id, seeded_for_user_id, slot_number)`.
- [ ] Shuffle limit is 5 total per `(couple_day_id, user_id)`.
- [ ] Shuffle suppression lasts 14 days per user/question identity.
- [ ] Non-resurfaceable questions are excluded after that user answered them once.
- [ ] Resurfaceable questions can return after `resurface_after_months`, default 6.
- [ ] Answer uniqueness on `(instance_id, user_id)`.
- [ ] Answer detail rows must match allowed `question_answer_kinds`.
- [ ] Partner-choice selected user must be one of the two members of the instance's couple.
- [ ] Partner answer content is hidden until current user answered the same instance.
- [ ] Partner answered metadata can be visible before reveal.

RPCs/read models:

- `start_daily_challenge(client_operation)`
- `shuffle_daily_question(slot_number, client_operation)`
- `submit_daily_answer(instance_id, payload, client_operation)`
- `get_today_daily_questions()`
- `get_daily_answer_reveal_state(couple_day_id)`

Indexes:

- `couple_days(couple_id, local_date)` unique
- `daily_challenges(couple_day_id, user_id)` PK
- partial unique active slot on `daily_question_instances(couple_day_id, seeded_for_user_id, slot_number) where status = 'active'`
- `daily_question_instances(couple_day_id, question_version_id)`
- `daily_question_shuffles(user_id, question_id, exclude_until)`
- `daily_question_shuffles(couple_day_id, user_id)`
- `daily_question_answers(instance_id, user_id)` unique
- `daily_question_answers(user_id, created_at desc)`
- `daily_answer_media(answer_id, sort_order)` unique

Verification:

- [ ] Concurrent start/shuffle retries do not duplicate slots.
- [ ] A user can answer partner-seeded instances without completing their own challenge.
- [ ] Answering all three own slots sets challenge completion and queues partner notification.

### 008 Conversation Threads And Messages

Purpose: support follow-up conversation on daily questions and memories.

Tables:

- `public.conversation_threads`
- `public.daily_question_threads`
- `public.memory_threads`
- `public.thread_messages`
- `public.thread_message_media`

Checklist:

- [ ] Thread kind constrained to `daily_question` or `memory`.
- [ ] `daily_question_threads.instance_id` PK.
- [ ] `daily_question_threads.thread_id` unique.
- [ ] `memory_threads.memory_id` PK.
- [ ] `memory_threads.thread_id` unique.
- [ ] First follow-up message creates thread and first message in one RPC.
- [ ] Message media uses finalized `media_assets`.
- [ ] Moderation fields exist on thread/message rows.

RPCs:

- `create_daily_question_thread_with_message(...)`
- `create_memory_thread_with_message(...)`
- `send_thread_message(thread_id, body, media_asset_ids, client_operation)`

Indexes:

- `conversation_threads(couple_id, created_at desc)`
- `thread_messages(thread_id, created_at, id)`
- `thread_messages(sender_user_id, created_at desc)`
- `thread_message_media(media_asset_id)`

Verification:

- [ ] No empty thread is created before first follow-up message.
- [ ] Ended/unentitled couples cannot read or send messages.

### 009 Memories

Purpose: create editable couple memories with title/date, partner notes, photos, and optional conversation.

Tables:

- `public.memories`
- `public.memory_notes`
- `public.memory_media`
- `public.memory_threads`

Checklist:

- [ ] Memory requires `title`, `memory_date`, and at least one supported content item at creation.
- [ ] Both partners can edit memory title/date through revision-checked RPC.
- [ ] One `memory_notes` row per `(memory_id, user_id)`.
- [ ] Notes are author-owned and revision-checked.
- [ ] `memory_media` unique `(memory_id, media_asset_id)`.
- [ ] Each partner can add up to 5 photos per memory.
- Memory voice notes are deferred beyond MVP. The existing generic media schema may support them later, but release UI and copy must not claim them.
- [ ] No ordinary user hard delete in MVP; hiding/removal is RPC/admin/cleanup controlled.
- [ ] Relationship end hides memories immediately and cleanup deletes after `delete_after`.

RPCs/read models:

- `create_memory(...)`
- `update_memory(...)`
- `upsert_memory_note(...)`
- `attach_memory_media(...)`
- `remove_memory_media(...)` if allowed for owner before admin deletion rules are finalized

Indexes:

- `memories(couple_id, memory_date desc, id)`
- `memories(couple_id, updated_at, id)` for sync
- `memory_notes(memory_id, user_id)` unique
- `memory_notes(user_id, updated_at desc)`
- `memory_media(memory_id, sort_order)`
- `memory_media(owner_user_id, memory_id)`

Verification:

- [ ] Offline conflicting title/date edits return conflict instead of silent overwrite.
- [ ] Notes from both partners can coexist.
- [ ] Media count limit is enforced server-side.

### 010 Widget Drawing History

Purpose: store shared canvas history as immutable PencilKit payload revisions with local raster caches.

Tables:

- `public.widget_canvases`
- `public.widget_drawing_revisions`

Checklist:

- [ ] `widget_canvases.couple_id` unique.
- [ ] `active_revision_id` FK points to latest visible revision.
- [ ] Drawing revision payload points to finalized `media_assets` in `widget-drawings`.
- [ ] `format = 'pkdrawing'`, `format_version = 1`.
- [ ] Payload path follows `widget-drawings/{couple_id}/{canvas_id}/revisions/{revision_id}/drawing.pkdrawing`.
- [ ] Server validates ownership, reserved path, byte limit, SHA, metadata limits, and finalize state.
- [ ] iOS validates `PKDrawing` decode before upload/finalize.
- [ ] Stroke limit 5,000; point limit 200,000.
- [ ] Normal payload hard limit 2 MB; 5 MB admin/debug escape hatch only if explicitly added.
- [ ] Continuing or clearing canvas creates a new full drawing revision only when saved.
- [ ] No server-side raster table or bucket in MVP.
- [ ] Silent push is queued on saved revision so partner app can refresh local widget cache.

RPCs:

- `get_or_create_widget_canvas(couple_id)`
- `submit_widget_drawing_revision(canvas_id, media_asset_id, metadata, client_operation)`

Indexes:

- `widget_canvases(couple_id)` unique
- `widget_drawing_revisions(canvas_id, created_at desc)`
- `widget_drawing_revisions(author_user_id, created_at desc)`
- `widget_drawing_revisions(payload_media_asset_id)` unique

Verification:

- [ ] User cannot reuse another media asset as drawing payload.
- [ ] Admin-hidden active revision is not returned to widget read model.

### 011 Location, Streaks, Activity, Notification Outbox

Purpose: add relationship presence features and operational push fanout.

Tables:

- `public.location_sharing_preferences`
- `public.latest_partner_locations`
- `public.streak_states`
- `public.couple_activity_events`
- `internal.notification_outbox`

Checklist:

- [ ] Location preferences PK `(couple_id, user_id)`.
- [ ] Latest locations PK `(couple_id, user_id)`.
- [ ] Latitude/longitude range checks.
- [ ] Map read model only shows map when both users enabled sharing.
- [ ] Disabling location deletes latest location row.
- [ ] Relationship end deletes both latest location rows.
- [ ] Reject stale offline location retry when `captured_at` is older than stored row.
- [ ] Streak next activity deadline falls after midnight in the latest partner timezone.
- [ ] Activity events include qualifying actions and couple_day linkage.
- [ ] Notification outbox stores one row per target device.
- [ ] Push payloads use IDs/routing hints, not sensitive content.

RPCs/jobs:

- `update_location_sharing_preference(...)`
- `update_latest_partner_location(...)`
- `get_partner_location_visibility()`
- Location RPC public wrappers must stay `security definer` with fixed `search_path` because the implementation lives in private `internal`.
- `record_couple_activity(...)`
- notification fanout job/function
- streak reminder scheduler

Streak behavior:

- [ ] A couple day advances the shared streak only after both active partners contribute.
- [ ] The qualification timestamp is the later partner's first event; repeat actions do not extend it.
- [ ] Reminder fanout targets only the partner or partners still missing a current-day contribution.

Indexes:

- `location_sharing_preferences(couple_id, user_id)` PK
- `latest_partner_locations(couple_id, user_id)` PK
- `couple_activity_events(couple_id, couple_day_id, activity_kind)`
- `streak_states(couple_id)` PK
- `internal.notification_outbox(scheduled_for, sent_at, failed_at)`
- `internal.notification_outbox(recipient_user_id, created_at desc)`
- unique/dedupe index on `internal.notification_outbox(dedupe_key)` where appropriate

Verification:

- [ ] Map read model returns explicit `not_sharing`, `disabled`, `relationship_ended`, or visible state.
- [ ] Push payload fixtures contain no answer body, media URL, precise coordinate, invite code, or report detail.

### 012 Reports, Moderation, Admin Runbooks

Purpose: make UGC reportable and moderation auditable from MVP without building a custom admin UI yet.

Tables:

- `public.content_reports`
- `public.content_report_targets`
- `internal.report_snapshots`
- `internal.report_snapshot_assets`
- `internal.moderation_actions`
- `internal.pair_safety_warning_flags`

Checklist:

- [ ] One `content_report_targets` row per report.
- [ ] Target table enforces exactly one target group.
- [ ] Every target column/group has a real FK.
- [ ] `submit-report` infers `reported_user_id`; client cannot choose it.
- [ ] Users can report only connected current or recently ended relationship content/conduct.
- [ ] Reporter can see own report status; reported user cannot see report row.
- [ ] Reports can create pair safety warning flags.
- [ ] Block/report path creates active relationship block when selected.
- [ ] Snapshot reported text/metadata into internal report snapshot.
- [ ] Binary snapshots use `report-snapshots` bucket and internal asset rows.
- [ ] Report snapshots retained while open and 180 days after resolution.
- [ ] Moderation action updates target moderation fields and writes audit action in one transaction.
- [ ] Ordinary clients cannot set moderation fields.

RPCs/runbooks:

- `submit_content_report(...)`
- `submit_leave_and_report(...)`
- service-role moderation runbook functions for hide/remove/restore/block/unblock
- report snapshot cleanup job

Indexes:

- `content_reports(reporter_user_id, created_at desc)`
- `content_reports(reported_user_id, created_at desc)` internal/admin use
- `content_reports(couple_id, created_at desc)`
- `content_reports(status, created_at)`
- `content_report_targets(report_id)` PK
- target indexes for each FK column or target group
- `internal.report_snapshots(report_id)` PK
- `internal.report_snapshot_assets(delete_after, storage_delete_status)`
- `internal.moderation_actions(report_id, created_at desc)`
- `internal.pair_safety_warning_flags(pair_id, created_at desc)`

Verification:

- [ ] Reported user cannot infer report existence.
- [ ] Report snapshot cleanup skips ordinary relationship cleanup timing.
- [ ] Pair safety warning appears through invite accept/preview RPC only.

### 013 Cleanup Jobs, Seeds, Local Verification

Purpose: close the loop so the schema can be operated safely during development and TestFlight.

Jobs/functions:

- relationship content cleanup after `couples.delete_after`
- expired pending upload cleanup
- storage delete retry
- invite/review attempt retention cleanup
- report snapshot retention cleanup
- notification outbox delivery/retry
- StoreKit reconciliation

Seed data:

- [ ] Subscription products for actual StoreKit product IDs.
- [ ] System question collection and initial questions.
- [ ] English and Norwegian Bokmal localizations.
- [ ] Review access codes for App Review windows, created by secure runbook, not committed as plaintext.
- [ ] Seeded demo partner account and review-only pre-paired scenario setup.
- [ ] Seeded demo partner Auth user creation is handled by an operational Supabase Auth/service-role runbook, not assumed to be plain SQL inserted into `auth.users`.

Verification commands/checks:

- [ ] `supabase db reset` succeeds locally once migrations exist.
- [ ] `supabase db lint` or advisors are run if available.
- [ ] RLS smoke tests cover user A/user B/stranger for relationship content.
- [ ] RLS smoke tests prove ended relationship content stays hidden after the same pair re-pairs.
- [ ] Daily answer tests prove answer bodies/media stay hidden until the current user answers the same instance.
- [ ] Storage policy smoke tests cover upload/finalize/read/delete denial paths.
- [ ] Storage tests prove finalized object paths cannot be reused or overwritten by ordinary clients.
- [ ] RPC idempotency tests retry the same `client_operation_id`.
- [ ] RPC idempotency tests retry the same `client_operation_id` with a different request body and get a mismatch rejection.
- [ ] Cleanup jobs are safe to run twice.
- [ ] Cleanup tests prove relationship cleanup skips `report-snapshots`.
- [ ] Sync cursor tests prove pagination is stable when multiple rows have identical `updated_at` values.
- [ ] Views exposed to clients are `security_invoker` or direct grants are revoked.
- [ ] No ordinary client grant exists on `internal`.

## First SQL Work Order

Start implementation with these exact migration slices:

1. `foundation_schemas_client_operations`
2. `identity_profiles_devices_privacy`
3. `relationship_pairing_blocks_sync_events`
4. `entitlements_storekit_review_access`
5. `media_assets_storage_buckets`

Stop after slice 5 for review before implementing product-content tables. At that point the backend can express account state, pairing, entitlement, media reservation, and access helpers, which are the hardest foundations to correct later.

Then continue:

6. `question_catalog_seed`
7. `daily_challenges_answers_reveal`
8. `conversation_threads_messages`
9. `memories`
10. `widget_drawings`
11. `location_streaks_notifications`
12. `reports_moderation`
13. `cleanup_jobs_and_verification`

## Open Implementation Checks

These do not block the first migration, but they must be answered before App Store submission:

- Exact StoreKit product IDs and whether launch has monthly only, yearly only, or both.
- Final App Review code issuance runbook and expiration window.
- Exact initial daily question seed set.
- Final legal/privacy text for precise location, private UGC reports, subscription sharing, account deletion, and trusted server-side moderation.
- Apple Sign in account deletion token revocation behavior after Supabase Auth implementation is verified.
