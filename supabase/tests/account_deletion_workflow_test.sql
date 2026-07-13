-- Regression coverage for the two-stage, retryable account-deletion workflow.

begin;
select plan(26);

insert into auth.users (id, email, raw_app_meta_data)
values
  (
    '20000000-0000-0000-0000-0000000000a1',
    'deleting-user@test.local',
    '{"provider":"apple","providers":["apple"]}'::jsonb
  ),
  (
    '20000000-0000-0000-0000-0000000000a2',
    'remaining-partner@test.local',
    '{"provider":"google","providers":["google"]}'::jsonb
  );

insert into public.relationship_pairs (id, user_low_id, user_high_id)
values (
  '20000000-0000-0000-0000-0000000000b1',
  '20000000-0000-0000-0000-0000000000a1',
  '20000000-0000-0000-0000-0000000000a2'
);

insert into public.couples (id, pair_id, started_on, created_by_user_id)
values (
  '20000000-0000-0000-0000-0000000000c1',
  '20000000-0000-0000-0000-0000000000b1',
  current_date,
  '20000000-0000-0000-0000-0000000000a1'
);

insert into public.couple_members (couple_id, user_id, role)
values
  (
    '20000000-0000-0000-0000-0000000000c1',
    '20000000-0000-0000-0000-0000000000a1',
    'creator'
  ),
  (
    '20000000-0000-0000-0000-0000000000c1',
    '20000000-0000-0000-0000-0000000000a2',
    'partner'
  );

insert into public.media_assets (
  id,
  owner_user_id,
  reserved_parent_kind,
  reserved_parent_id,
  reserved_by_client_operation_id,
  bucket,
  storage_path,
  media_type,
  upload_purpose,
  expected_media_type,
  expected_bucket,
  mime_type,
  byte_size,
  sha256,
  upload_status,
  upload_expires_at,
  upload_finalized_at
)
values (
  '20000000-0000-0000-0000-0000000000d1',
  '20000000-0000-0000-0000-0000000000a1',
  'profile_photo',
  '20000000-0000-0000-0000-0000000000a1',
  '20000000-0000-0000-0000-0000000000e1',
  'profile-photos',
  '20000000-0000-0000-0000-0000000000a1/profile.jpg',
  'image',
  'profile_photo',
  'image',
  'profile-photos',
  'image/jpeg',
  128,
  decode(repeat('2', 64), 'hex'),
  'finalized',
  now() + interval '1 day',
  now()
);

update public.profiles
set
  display_name = 'Delete Me',
  profile_photo_asset_id = '20000000-0000-0000-0000-0000000000d1',
  time_zone_id = 'Europe/Oslo',
  time_zone_updated_at = now(),
  onboarding_completed_at = now()
where user_id = '20000000-0000-0000-0000-0000000000a1';

insert into public.user_devices (
  id,
  user_id,
  platform,
  push_token,
  push_token_hash,
  apns_environment
)
values (
  '20000000-0000-0000-0000-0000000000f1',
  '20000000-0000-0000-0000-0000000000a1',
  'ios',
  'account-deletion-test-push-token',
  extensions.digest('account-deletion-test-push-token', 'sha256'),
  'sandbox'
);

insert into public.widget_push_devices (
  id,
  user_id,
  widget_kind,
  widget_push_token,
  widget_push_token_hash,
  apns_environment
)
values (
  '20000000-0000-0000-0000-0000000000f2',
  '20000000-0000-0000-0000-0000000000a1',
  'PaeoniaWidget',
  'account-deletion-widget-push-token',
  extensions.digest('account-deletion-widget-push-token', 'sha256'),
  'sandbox'
);

insert into public.location_sharing_preferences (
  couple_id,
  user_id,
  is_enabled,
  enabled_at,
  disabled_at,
  consent_version,
  source
)
values (
  '20000000-0000-0000-0000-0000000000c1',
  '20000000-0000-0000-0000-0000000000a1',
  true,
  now(),
  null,
  'test-v1',
  'settings_toggle'
);

insert into public.latest_partner_locations (
  couple_id,
  user_id,
  latitude,
  longitude,
  captured_at,
  source,
  client_operation_id,
  client_id,
  client_sequence
)
values (
  '20000000-0000-0000-0000-0000000000c1',
  '20000000-0000-0000-0000-0000000000a1',
  59.91,
  10.75,
  now(),
  'foreground_open',
  '20000000-0000-0000-0000-000000000101',
  '20000000-0000-0000-0000-000000000102',
  1
);

do $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '20000000-0000-0000-0000-0000000000a1',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"20000000-0000-0000-0000-0000000000a1","role":"authenticated","app_metadata":{"provider":"apple"}}',
    true
  );
end;
$$;

create temp table deletion_result as
select * from public.request_account_deletion();

select ok(
  (
    select auth_provider = 'apple'
      and provider_revocation_status = 'manual_required'
      and auth_delete_status = 'ready_for_auth_delete'
    from deletion_result
  ),
  'Apple deletion starts with an immediate manual fallback and a retryable Auth job'
);

select ok(
  (
    select status = 'ended'
      and ended_at is not null
      and delete_after > ended_at
    from public.couples
    where id = '20000000-0000-0000-0000-0000000000c1'
  ),
  'account deletion uses the canonical ended relationship state and cleanup window'
);

select is(
  (
    select status
    from public.couple_members
    where couple_id = '20000000-0000-0000-0000-0000000000c1'
      and user_id = '20000000-0000-0000-0000-0000000000a1'
  ),
  'left',
  'deleting member is recorded as the relationship initiator who left'
);

select is(
  (
    select status
    from public.couple_members
    where couple_id = '20000000-0000-0000-0000-0000000000c1'
      and user_id = '20000000-0000-0000-0000-0000000000a2'
  ),
  'ended_notice_pending',
  'remaining partner receives the normal ended notice'
);

select ok(
  exists (
    select 1
    from public.relationship_sync_events
    where user_id = '20000000-0000-0000-0000-0000000000a2'
      and event_kind = 'relationship_ended'
      and reason = 'account_deletion'
  ),
  'relationship leave audit/event records account deletion as the reason'
);

select ok(
  (
    select display_name is null
      and profile_photo_asset_id is null
      and time_zone_id is null
      and onboarding_completed_at is null
      and deleted_at is not null
      and moderation_status = 'hidden'
    from public.profiles
    where user_id = '20000000-0000-0000-0000-0000000000a1'
  ),
  'profile is anonymized and tombstoned immediately'
);

select is(
  (
    select count(*)::integer
    from public.user_devices
    where user_id = '20000000-0000-0000-0000-0000000000a1'
  ) + (
    select count(*)::integer
    from public.widget_push_devices
    where user_id = '20000000-0000-0000-0000-0000000000a1'
  ) + (
    select count(*)::integer
    from public.notification_preferences
    where user_id = '20000000-0000-0000-0000-0000000000a1'
  ),
  0,
  'device tokens and notification preferences are removed immediately'
);

select is(
  (
    select count(*)::integer
    from public.location_sharing_preferences
    where user_id = '20000000-0000-0000-0000-0000000000a1'
  ) + (
    select count(*)::integer
    from public.latest_partner_locations
    where user_id = '20000000-0000-0000-0000-0000000000a1'
  ),
  0,
  'location consent and precise location are removed immediately'
);

select ok(
  (
    select deleted_at is not null and storage_delete_status = 'pending'
    from public.media_assets
    where id = '20000000-0000-0000-0000-0000000000d1'
  ),
  'profile-photo bytes are queued for trusted Storage API deletion'
);

select ok(
  (
    select next_attempt_at <= now() + interval '30 seconds'
    from internal.account_deletion_jobs
    where id = (select deletion_job_id from deletion_result)
  ),
  'manual Apple fallback schedules Supabase Auth deletion without a provider gate'
);

select throws_ok(
  $$
    insert into internal.client_operations (
      user_id,
      client_operation_id,
      client_id,
      client_sequence,
      local_created_at,
      operation_kind,
      idempotency_scope,
      request_hash
    ) values (
      '20000000-0000-0000-0000-0000000000a1',
      '20000000-0000-0000-0000-000000000201',
      '20000000-0000-0000-0000-000000000202',
      1,
      now(),
      'test_after_deletion',
      'account_deletion_test',
      extensions.digest('blocked', 'sha256')
    )
  $$,
  '42501',
  'account deletion is in progress',
  'a still-valid access JWT cannot enqueue new app mutations'
);

select throws_ok(
  $$
    insert into public.user_devices (
      id,
      user_id,
      platform,
      push_token,
      push_token_hash,
      apns_environment
    ) values (
      '20000000-0000-0000-0000-000000000203',
      '20000000-0000-0000-0000-0000000000a1',
      'ios',
      'account-deletion-recreated-push-token',
      extensions.digest('account-deletion-recreated-push-token', 'sha256'),
      'sandbox'
    )
  $$,
  '42501',
  'account deletion is in progress',
  'a still-valid access JWT cannot recreate direct device or delivery state'
);

select is(
  (
    select count(*)::integer
    from internal.privacy_request_events event
    where event.request_id = (select id from deletion_result)
      and event.event_kind in ('deletion_requested', 'account_data_removed')
  ),
  2,
  'privacy audit records both request and completed data-removal stage'
);

select ok(
  internal.mark_account_deletion_provider_result(
    (select deletion_job_id from deletion_result),
    'succeeded',
    null
  ),
  'service worker can record automatic Apple revocation without token material'
);

create temp table claimed_deletion as
select *
from internal.claim_account_deletion_jobs(
  now(),
  1,
  interval '5 minutes',
  10,
  (select deletion_job_id from deletion_result)
);

select is(
  (select count(*)::integer from claimed_deletion),
  1,
  'due Auth deletion job is atomically claimed'
);

select ok(
  internal.mark_account_deletion_auth_failed(
    (select deletion_job_id from deletion_result),
    'auth_test_failure',
    1
  ),
  'an exhausted Auth deletion job records its failed attempt'
);

select ok(
  (
    select status = 'attention_required'
      and auth_delete_attempts = 1
    from internal.account_deletion_jobs
    where id = (select deletion_job_id from deletion_result)
  ),
  'an exhausted Auth deletion job moves to operator attention'
);

select ok(
  internal.retry_account_deletion_job(
    (select deletion_job_id from deletion_result)
  ),
  'operator can retry an exhausted Auth deletion job'
);

select ok(
  (
    select status = 'ready_for_auth_delete'
      and auth_delete_attempts = 0
      and next_attempt_at <= now()
    from internal.account_deletion_jobs
    where id = (select deletion_job_id from deletion_result)
  ),
  'operator retry resets the exhausted claim budget'
);

create temp table reclaimed_deletion as
select *
from internal.claim_account_deletion_jobs(
  now(),
  1,
  interval '5 minutes',
  10,
  (select deletion_job_id from deletion_result)
);

select is(
  (select count(*)::integer from reclaimed_deletion),
  1,
  'an operator-retried Auth deletion job can be claimed again'
);

select ok(
  internal.mark_account_deletion_completed(
    (select deletion_job_id from deletion_result)
  ),
  'worker can complete a claimed Auth deletion job'
);

select ok(
  (
    select status = 'completed' and completed_at is not null
    from public.privacy_requests
    where id = (select id from deletion_result)
  ),
  'successful Auth deletion completes both job and privacy request'
);

select ok(
  (
    select repeat_result.id = original_result.id
      and repeat_result.deletion_job_id = original_result.deletion_job_id
      and repeat_result.status = 'completed'
      and repeat_result.auth_delete_status = 'completed'
    from public.request_account_deletion() repeat_result
    cross join deletion_result original_result
  ) and (
    select count(*) = 1
    from public.privacy_requests request
    where request.user_id = '20000000-0000-0000-0000-0000000000a1'
      and request.request_kind = 'deletion'
  ),
  'a still-valid JWT reuses the completed deletion tombstone'
);

select throws_ok(
  $$
    insert into internal.client_operations (
      user_id,
      client_operation_id,
      client_id,
      client_sequence,
      local_created_at,
      operation_kind,
      idempotency_scope,
      request_hash
    ) values (
      '20000000-0000-0000-0000-0000000000a1',
      '20000000-0000-0000-0000-000000000301',
      '20000000-0000-0000-0000-000000000302',
      1,
      now(),
      'test_after_auth_delete',
      'account_deletion_test',
      extensions.digest('still-blocked', 'sha256')
    )
  $$,
  '42501',
  'account deletion is in progress',
  'completed tombstone still blocks an unexpired access JWT'
);

select throws_ok(
  $$
    insert into public.privacy_requests (
      id,
      user_id,
      request_kind,
      requester_note
    ) values (
      '20000000-0000-0000-0000-000000000303',
      '20000000-0000-0000-0000-0000000000a1',
      'export',
      'stale JWT request'
    )
  $$,
  '42501',
  'account deletion is in progress',
  'completed tombstone blocks new privacy requests from an unexpired JWT'
);

select lives_ok(
  $$
    delete from auth.users
    where id = '20000000-0000-0000-0000-0000000000a1'
  $$,
  'hard Auth deletion is not blocked by a remaining foreign key'
);

select * from finish();
rollback;
