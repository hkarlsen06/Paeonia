-- Account deletion has two boundaries:
--
-- 1. The authenticated request is a single database transaction. It ends any
--    active relationship, removes access immediately, anonymizes the profile,
--    clears short-lived identity/location/notification rows, and records an
--    auditable privacy request.
-- 2. Provider revocation, global Auth sign-out, and Auth-user deletion happen
--    in the delete-account Edge Function. A private queue makes that second
--    boundary retryable if Apple or Supabase is temporarily unavailable.
--
-- Apple jobs start with the documented manual-revocation fallback. A fresh
-- authorization code can upgrade the job to automatic revocation immediately;
-- missing Apple credentials never delay deletion of Paeonia data or Auth state.

-- Newer identity-adjacent tables were added after the original Auth-delete FK
-- reconciliation. Short-lived rows cascade; audit ledgers retain UUID
-- snapshots and therefore must not depend on a live auth.users row.
alter table public.widget_push_devices
drop constraint if exists widget_push_devices_user_id_fkey,
add constraint widget_push_devices_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table internal.widget_push_outbox
drop constraint if exists widget_push_outbox_recipient_user_id_fkey,
add constraint widget_push_outbox_recipient_user_id_fkey
foreign key (recipient_user_id)
references auth.users (id)
on delete cascade;

alter table internal.widget_push_outbox
drop constraint if exists widget_push_outbox_target_widget_device_id_fkey,
add constraint widget_push_outbox_target_widget_device_id_fkey
foreign key (target_widget_device_id)
references public.widget_push_devices (id)
on delete cascade;

alter table internal.review_demo_partners
drop constraint if exists review_demo_partners_user_id_fkey,
add constraint review_demo_partners_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table internal.streak_restorations
drop constraint if exists streak_restorations_purchaser_user_id_fkey;

create table internal.account_deletion_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  request_id uuid not null unique references public.privacy_requests (id) on delete restrict,
  user_id uuid not null unique,
  auth_provider text not null,
  status text not null default 'ready_for_auth_delete',
  provider_revocation_status text not null,
  provider_revocation_attempted_at timestamptz,
  provider_revocation_error_code text,
  auth_delete_attempts integer not null default 0,
  next_attempt_at timestamptz,
  claimed_at timestamptz,
  last_auth_delete_error_code text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint account_deletion_jobs_auth_provider_check
    check (auth_provider in ('apple', 'google', 'unknown')),
  constraint account_deletion_jobs_status_check
    check (
      status in (
        'ready_for_auth_delete',
        'processing_auth_delete',
        'attention_required',
        'completed'
      )
    ),
  constraint account_deletion_jobs_provider_revocation_status_check
    check (
      provider_revocation_status in (
        'not_required',
        'succeeded',
        'manual_required'
      )
    ),
  constraint account_deletion_jobs_provider_error_check
    check (
      provider_revocation_error_code is null
      or char_length(provider_revocation_error_code) between 1 and 120
    ),
  constraint account_deletion_jobs_auth_delete_attempts_check
    check (auth_delete_attempts >= 0),
  constraint account_deletion_jobs_auth_error_check
    check (
      last_auth_delete_error_code is null
      or char_length(last_auth_delete_error_code) between 1 and 120
    ),
  constraint account_deletion_jobs_completed_state_check
    check (
      (status = 'completed' and completed_at is not null and next_attempt_at is null)
      or (status <> 'completed' and completed_at is null)
    )
);

create trigger set_account_deletion_jobs_updated_at
before update on internal.account_deletion_jobs
for each row
execute function internal.set_updated_at();

alter table internal.account_deletion_jobs enable row level security;

create policy account_deletion_jobs_service_role_all
on internal.account_deletion_jobs
for all
to service_role
using (true)
with check (true);

create index account_deletion_jobs_due_idx
on internal.account_deletion_jobs (next_attempt_at, id)
where status in ('ready_for_auth_delete', 'processing_auth_delete');

revoke all on internal.account_deletion_jobs from public, anon, authenticated;
grant all privileges on internal.account_deletion_jobs to service_role;

-- A request that started deletion is a permanent tombstone. An already-issued
-- access JWT can remain cryptographically valid until expiry even after the Auth
-- row is hard-deleted, so completion must not reopen writes. Most app mutations
-- pass through internal.client_operations; reject new work for a tombstoned user
-- at that shared boundary. Profile edits get an explicit RLS guard below.
create or replace function internal.reject_pending_account_client_operation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if exists (
    select 1
    from internal.account_deletion_jobs job
    where job.user_id = new.user_id
  ) then
    raise exception 'account deletion is in progress'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists reject_pending_account_client_operation
on internal.client_operations;
create trigger reject_pending_account_client_operation
before insert or update
on internal.client_operations
for each row
execute function internal.reject_pending_account_client_operation();

-- A few identity-adjacent writes intentionally bypass the client-operation
-- ledger. Apply the same tombstone at those direct write boundaries so another
-- device with an unexpired access JWT cannot recreate delivery or location
-- state before or after the final Auth delete.
drop trigger if exists reject_pending_account_user_device
on public.user_devices;
create trigger reject_pending_account_user_device
before insert or update on public.user_devices
for each row
execute function internal.reject_pending_account_client_operation();

drop trigger if exists reject_pending_account_widget_device
on public.widget_push_devices;
create trigger reject_pending_account_widget_device
before insert or update on public.widget_push_devices
for each row
execute function internal.reject_pending_account_client_operation();

drop trigger if exists reject_pending_account_notification_preference
on public.notification_preferences;
create trigger reject_pending_account_notification_preference
before insert or update on public.notification_preferences
for each row
execute function internal.reject_pending_account_client_operation();

drop trigger if exists reject_pending_account_location_preference
on public.location_sharing_preferences;
create trigger reject_pending_account_location_preference
before insert or update on public.location_sharing_preferences
for each row
execute function internal.reject_pending_account_client_operation();

drop trigger if exists reject_pending_account_latest_location
on public.latest_partner_locations;
create trigger reject_pending_account_latest_location
before insert or update on public.latest_partner_locations
for each row
execute function internal.reject_pending_account_client_operation();

-- Privacy requests are one of the few authenticated inserts that do not use
-- the client-operation ledger. The deletion transaction creates its request
-- before the tombstone job, so later inserts can be rejected permanently
-- without blocking the canonical deletion request itself.
drop trigger if exists reject_pending_account_privacy_request
on public.privacy_requests;
create trigger reject_pending_account_privacy_request
before insert on public.privacy_requests
for each row
execute function internal.reject_pending_account_client_operation();

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
on public.profiles
for update
to authenticated
using (
  user_id = (select auth.uid())
  and deleted_at is null
)
with check (
  user_id = (select auth.uid())
  and deleted_at is null
);

-- The existing RPC only recorded a privacy request. Replace it with the actual
-- first-stage deletion transaction. The return type changes, so both old
-- functions must be dropped before recreation.
drop function if exists public.request_account_deletion();
drop function if exists internal.request_account_deletion();

create or replace function internal.request_account_deletion()
returns table (
  id uuid,
  status text,
  requested_at timestamptz,
  deletion_job_id uuid,
  auth_provider text,
  provider_revocation_status text,
  auth_delete_status text
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_column
declare
  current_user_id uuid;
  request_row public.privacy_requests%rowtype;
  job_row internal.account_deletion_jobs%rowtype;
  created_request boolean := false;
  resolved_provider text;
  active_pair_id uuid;
  relationship_ended boolean := false;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  -- Serialize duplicate taps, multiple devices, and Edge Function retries for
  -- one account without holding locks for any external network work.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('account-deletion:' || current_user_id::text, 0)
  );

  -- Once the first-stage transaction has committed, every retry must return
  -- that durable tombstone instead of replaying destructive work or creating a
  -- second privacy request. This also closes the window where an already-issued
  -- access JWT can call this RPC after the Auth user has been hard-deleted.
  select job.*
  into job_row
  from internal.account_deletion_jobs job
  where job.user_id = current_user_id
  for update;

  if job_row.id is not null then
    select request.*
    into request_row
    from public.privacy_requests request
    where request.id = job_row.request_id;

    if request_row.id is null then
      raise exception 'account deletion request tombstone is missing';
    end if;

    return query
    select
      request_row.id,
      request_row.status,
      request_row.requested_at,
      job_row.id,
      job_row.auth_provider,
      job_row.provider_revocation_status,
      job_row.status;
    return;
  end if;

  resolved_provider = case
    -- Prefer Apple when identities are linked because its provider grant has a
    -- separate revocation obligation even if Google was used most recently.
    -- Read the canonical identity table as well as JWT metadata: a token issued
    -- on another device before identity linking can have a stale providers list.
    when exists (
      select 1
      from auth.identities identity
      where identity.user_id = current_user_id
        and identity.provider = 'apple'
    )
      or lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '')) = 'apple'
      or coalesce(auth.jwt() -> 'app_metadata' -> 'providers', '[]'::jsonb)
        @> '["apple"]'::jsonb
      then 'apple'
    when exists (
      select 1
      from auth.identities identity
      where identity.user_id = current_user_id
        and identity.provider = 'google'
    )
      or lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '')) = 'google'
      or coalesce(auth.jwt() -> 'app_metadata' -> 'providers', '[]'::jsonb)
        @> '["google"]'::jsonb
      then 'google'
    else 'unknown'
  end;

  select request.*
  into request_row
  from public.privacy_requests request
  where request.user_id = current_user_id
    and request.request_kind = 'deletion'
    and request.status in ('submitted', 'verifying', 'processing')
  order by request.requested_at desc, request.id
  limit 1
  for update;

  if request_row.id is null then
    insert into public.privacy_requests (
      user_id,
      request_kind,
      status,
      verified_at,
      visible_status_message
    ) values (
      current_user_id,
      'deletion',
      'processing',
      now(),
      'Your account deletion is in progress.'
    )
    on conflict (user_id)
      where request_kind = 'deletion'
        and status in ('submitted', 'verifying', 'processing')
    do nothing
    returning *
    into request_row;

    created_request = request_row.id is not null;
  end if;

  if request_row.id is null then
    select request.*
    into request_row
    from public.privacy_requests request
    where request.user_id = current_user_id
      and request.request_kind = 'deletion'
      and request.status in ('submitted', 'verifying', 'processing')
    order by request.requested_at desc, request.id
    limit 1
    for update;
  else
    update public.privacy_requests request
    set
      status = 'processing',
      verified_at = coalesce(request.verified_at, now()),
      visible_status_message = 'Your account deletion is in progress.'
    where request.id = request_row.id
    returning request.* into request_row;
  end if;

  if request_row.id is null then
    raise exception 'could not create account deletion request';
  end if;

  if created_request then
    insert into internal.privacy_request_events (
      request_id,
      actor_user_id,
      event_kind,
      metadata
    ) values (
      request_row.id,
      current_user_id,
      'deletion_requested',
      jsonb_build_object('source', 'ios_app')
    );
  end if;

  -- Reuse the canonical leave transition so the remaining partner receives the
  -- same ended notice and the same 30-day relationship cleanup schedule.
  select couple.pair_id
  into active_pair_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
  order by couple.created_at desc
  limit 1;

  if active_pair_id is not null then
    relationship_ended = internal.end_relationship_for_pair(
      active_pair_id,
      current_user_id,
      'account_deletion'
    );
  end if;

  -- An unaccepted invite must not let a deleted identity create a relationship
  -- later. Accepted/revoked history remains as an audit snapshot.
  update public.pairing_invites
  set
    status = 'revoked',
    revoked_at = coalesce(revoked_at, now())
  where created_by_user_id = current_user_id
    and status = 'pending';

  -- Remove every delivery and location path before the Auth job runs. Delete
  -- outbox rows first to keep this migration correct even on environments that
  -- have not yet replayed the FK cascade reconciliation above.
  delete from internal.widget_push_outbox outbox
  where outbox.recipient_user_id = current_user_id
     or outbox.target_widget_device_id in (
       select device.id
       from public.widget_push_devices device
       where device.user_id = current_user_id
     );

  delete from internal.notification_outbox outbox
  where outbox.recipient_user_id = current_user_id
     or outbox.target_device_id in (
       select device.id
       from public.user_devices device
       where device.user_id = current_user_id
     );

  delete from public.widget_push_devices
  where user_id = current_user_id;

  delete from public.user_devices
  where user_id = current_user_id;

  delete from public.notification_preferences
  where user_id = current_user_id;

  delete from public.latest_partner_locations
  where user_id = current_user_id;

  delete from public.location_sharing_preferences
  where user_id = current_user_id;

  -- Revocable test/review access should not outlive the account. StoreKit and
  -- streak-purchase ledgers remain as restricted audit records keyed by UUID.
  update internal.entitlement_grants grant_row
  set
    status = 'revoked',
    revoked_at = coalesce(grant_row.revoked_at, now()),
    revoked_reason = coalesce(grant_row.revoked_reason, 'account_deleted')
  where grant_row.user_id = current_user_id
    and grant_row.status = 'active';

  update internal.review_access_sessions review_session
  set completed_at = coalesce(review_session.completed_at, now())
  where review_session.user_id = current_user_id;

  -- Clearing the profile-photo reference invokes the existing orphan trigger,
  -- which queues the actual bytes for deletion through the Storage API.
  update public.profiles profile
  set
    display_name = null,
    profile_photo_asset_id = null,
    time_zone_id = null,
    time_zone_updated_at = null,
    onboarding_completed_at = null,
    moderation_status = 'hidden',
    deleted_at = coalesce(profile.deleted_at, now())
  where profile.user_id = current_user_id;

  -- Also queue abandoned uploads and every profile-photo object owned by this
  -- user. Finalized relationship media follows the normal ended-couple window;
  -- report snapshots follow their separate retention policy.
  update public.media_assets asset
  set
    deleted_at = coalesce(asset.deleted_at, now()),
    storage_delete_status = 'pending',
    storage_deleted_at = null,
    last_storage_delete_error = null
  where asset.owner_user_id = current_user_id
    and asset.storage_delete_status <> 'deleted'
    and asset.upload_purpose <> 'report_snapshot'
    and (
      asset.upload_purpose = 'profile_photo'
      or asset.upload_status <> 'finalized'
    );

  -- Supabase Auth refuses hard deletion while Storage objects still name the
  -- user as owner. Detach only ownership metadata here; do not delete bytes or
  -- object rows. Existing trusted Storage-API cleanup still performs physical
  -- deletion at the correct profile/relationship/report retention deadline.
  update storage.objects object_row
  set
    owner = null,
    owner_id = null
  where object_row.owner = current_user_id
     or object_row.owner_id = current_user_id::text;

  insert into internal.account_deletion_jobs (
    request_id,
    user_id,
    auth_provider,
    status,
    provider_revocation_status,
    next_attempt_at
  ) values (
    request_row.id,
    current_user_id,
    resolved_provider,
    'ready_for_auth_delete',
    case resolved_provider
      when 'apple' then 'manual_required'
      else 'not_required'
    end,
    -- Give the authenticated Edge request a short reservation window before
    -- the generic drain may claim the job. A targeted claim ignores this due
    -- time and still performs the normal deletion immediately.
    now() + interval '30 seconds'
  )
  on conflict (user_id) do update
  set
    request_id = excluded.request_id,
    auth_provider = excluded.auth_provider,
    provider_revocation_status = case
      when internal.account_deletion_jobs.provider_revocation_status = 'succeeded'
        then 'succeeded'
      else excluded.provider_revocation_status
    end,
    status = case
      when internal.account_deletion_jobs.status = 'completed' then 'completed'
      else internal.account_deletion_jobs.status
    end,
    next_attempt_at = case
      when internal.account_deletion_jobs.provider_revocation_status = 'succeeded'
        then least(internal.account_deletion_jobs.next_attempt_at, now())
      else internal.account_deletion_jobs.next_attempt_at
    end
  returning * into job_row;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  )
  select
    request_row.id,
    current_user_id,
    'account_data_removed',
    jsonb_build_object(
      'relationship_ended', relationship_ended,
      'auth_provider', resolved_provider,
      'provider_revocation_status', job_row.provider_revocation_status
    )
  where not exists (
    select 1
    from internal.privacy_request_events event
    where event.request_id = request_row.id
      and event.event_kind = 'account_data_removed'
  );

  return query
  select
    request_row.id,
    request_row.status,
    request_row.requested_at,
    job_row.id,
    job_row.auth_provider,
    job_row.provider_revocation_status,
    job_row.status;
end;
$$;

create or replace function public.request_account_deletion()
returns table (
  id uuid,
  status text,
  requested_at timestamptz,
  deletion_job_id uuid,
  auth_provider text,
  provider_revocation_status text,
  auth_delete_status text
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    deletion_request.id,
    deletion_request.status,
    deletion_request.requested_at,
    deletion_request.deletion_job_id,
    deletion_request.auth_provider,
    deletion_request.provider_revocation_status,
    deletion_request.auth_delete_status
  from internal.request_account_deletion() as deletion_request;
$$;

-- The Edge Function records only stable outcome/error categories. Apple
-- authorization codes, access tokens, refresh tokens, and client secrets never
-- enter Postgres or logs.
create or replace function internal.mark_account_deletion_provider_result(
  p_job_id uuid,
  p_status text,
  p_error_code text default null
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  job_row internal.account_deletion_jobs%rowtype;
  event_kind text;
begin
  if p_status not in ('succeeded', 'manual_required', 'not_required') then
    raise exception 'invalid provider revocation status'
      using errcode = '23514';
  end if;

  if p_error_code is not null
     and char_length(p_error_code) not between 1 and 120 then
    raise exception 'invalid provider revocation error code'
      using errcode = '23514';
  end if;

  update internal.account_deletion_jobs job
  set
    provider_revocation_status = p_status,
    provider_revocation_attempted_at = now(),
    provider_revocation_error_code = p_error_code,
    status = case
      when job.status = 'completed' then 'completed'
      when job.status = 'processing_auth_delete' then 'processing_auth_delete'
      else 'ready_for_auth_delete'
    end,
    next_attempt_at = case
      when job.status = 'completed' then null
      when p_status in ('succeeded', 'not_required') then now()
      else now()
    end,
    claimed_at = case
      when job.status = 'processing_auth_delete' then job.claimed_at
      else null
    end
  where job.id = p_job_id
  returning * into job_row;

  if not found then
    return false;
  end if;

  event_kind = case p_status
    when 'succeeded' then 'provider_revocation_succeeded'
    when 'not_required' then 'provider_revocation_not_required'
    else 'provider_revocation_manual_required'
  end;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  ) values (
    job_row.request_id,
    null,
    event_kind,
    jsonb_strip_nulls(
      jsonb_build_object(
        'provider', job_row.auth_provider,
        'error_code', p_error_code
      )
    )
  );

  return true;
end;
$$;

create or replace function internal.claim_account_deletion_jobs(
  p_now timestamptz default now(),
  p_limit integer default 10,
  p_retry_after interval default interval '5 minutes',
  p_max_attempts integer default 10,
  p_job_id uuid default null
)
returns table (
  job_id uuid,
  request_id uuid,
  user_id uuid,
  auth_provider text,
  provider_revocation_status text,
  auth_delete_attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_limit not between 1 and 100 then
    raise exception 'invalid account deletion claim limit'
      using errcode = '23514';
  end if;

  if p_retry_after < interval '30 seconds'
     or p_retry_after > interval '1 day' then
    raise exception 'invalid account deletion retry interval'
      using errcode = '23514';
  end if;

  if p_max_attempts not between 1 and 100 then
    raise exception 'invalid account deletion max attempts'
      using errcode = '23514';
  end if;

  return query
  with claimable as (
    select job.id
    from internal.account_deletion_jobs job
    where (p_job_id is null or job.id = p_job_id)
      and job.auth_delete_attempts < p_max_attempts
      and (
        (
          job.status = 'ready_for_auth_delete'
          and (
            p_job_id is not null
            or (
              job.next_attempt_at is not null
              and job.next_attempt_at <= p_now
            )
          )
        )
        or (
          job.status = 'processing_auth_delete'
          and job.claimed_at <= p_now - p_retry_after
        )
      )
    order by job.next_attempt_at nulls first, job.id
    limit p_limit
    for update skip locked
  )
  update internal.account_deletion_jobs job
  set
    status = 'processing_auth_delete',
    claimed_at = p_now,
    auth_delete_attempts = job.auth_delete_attempts + 1,
    last_auth_delete_error_code = null
  from claimable
  where job.id = claimable.id
  returning
    job.id,
    job.request_id,
    job.user_id,
    job.auth_provider,
    job.provider_revocation_status,
    job.auth_delete_attempts;
end;
$$;

create or replace function internal.mark_account_deletion_auth_failed(
  p_job_id uuid,
  p_error_code text,
  p_max_attempts integer default 10
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  job_row internal.account_deletion_jobs%rowtype;
begin
  if p_error_code is null
     or char_length(p_error_code) not between 1 and 120 then
    raise exception 'invalid Auth deletion error code'
      using errcode = '23514';
  end if;

  update internal.account_deletion_jobs job
  set
    status = case
      when job.auth_delete_attempts >= p_max_attempts then 'attention_required'
      else 'ready_for_auth_delete'
    end,
    next_attempt_at = case
      when job.auth_delete_attempts >= p_max_attempts then null
      else now() + least(
        interval '6 hours',
        interval '30 seconds' * power(2::numeric, least(job.auth_delete_attempts, 10))
      )
    end,
    claimed_at = null,
    last_auth_delete_error_code = p_error_code
  where job.id = p_job_id
    and job.status = 'processing_auth_delete'
  returning * into job_row;

  if not found then
    return false;
  end if;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  ) values (
    job_row.request_id,
    null,
    'auth_delete_failed',
    jsonb_build_object(
      'error_code', p_error_code,
      'attempt', job_row.auth_delete_attempts,
      'requires_attention', job_row.status = 'attention_required'
    )
  );

  return true;
end;
$$;

create or replace function internal.mark_account_deletion_completed(p_job_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  job_row internal.account_deletion_jobs%rowtype;
begin
  select job.*
  into job_row
  from internal.account_deletion_jobs job
  where job.id = p_job_id
  for update;

  if not found then
    return false;
  end if;

  if job_row.status = 'completed' then
    return true;
  end if;

  update internal.account_deletion_jobs job
  set
    status = 'completed',
    next_attempt_at = null,
    claimed_at = null,
    last_auth_delete_error_code = null,
    completed_at = now()
  where job.id = p_job_id
  returning * into job_row;

  update public.privacy_requests request
  set
    status = 'completed',
    completed_at = now(),
    cancelled_at = null,
    visible_status_message = 'Your Paeonia account has been deleted.'
  where request.id = job_row.request_id;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  ) values (
    job_row.request_id,
    null,
    'auth_user_deleted',
    jsonb_build_object(
      'attempts', job_row.auth_delete_attempts,
      'provider_revocation_status', job_row.provider_revocation_status
    )
  );

  return true;
end;
$$;

create or replace function internal.retry_account_deletion_job(p_job_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.account_deletion_jobs
  set
    status = 'ready_for_auth_delete',
    -- An attention-required job has exhausted the normal claim budget. Reset
    -- the per-run attempt counter so an explicit operator retry is claimable;
    -- prior failure events retain the audit history.
    auth_delete_attempts = 0,
    next_attempt_at = now(),
    claimed_at = null,
    last_auth_delete_error_code = null
  where id = p_job_id
    and status = 'attention_required';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function public.mark_account_deletion_provider_result(
  p_job_id uuid,
  p_status text,
  p_error_code text default null
)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_account_deletion_provider_result(
    p_job_id,
    p_status,
    p_error_code
  );
$$;

create or replace function public.claim_account_deletion_jobs(
  p_now timestamptz default now(),
  p_limit integer default 10,
  p_retry_after interval default interval '5 minutes',
  p_max_attempts integer default 10,
  p_job_id uuid default null
)
returns table (
  job_id uuid,
  request_id uuid,
  user_id uuid,
  auth_provider text,
  provider_revocation_status text,
  auth_delete_attempts integer
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.claim_account_deletion_jobs(
    p_now,
    p_limit,
    p_retry_after,
    p_max_attempts,
    p_job_id
  );
$$;

create or replace function public.mark_account_deletion_auth_failed(
  p_job_id uuid,
  p_error_code text,
  p_max_attempts integer default 10
)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_account_deletion_auth_failed(
    p_job_id,
    p_error_code,
    p_max_attempts
  );
$$;

create or replace function public.mark_account_deletion_completed(p_job_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_account_deletion_completed(p_job_id);
$$;

create or replace function public.retry_account_deletion_job(p_job_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.retry_account_deletion_job(p_job_id);
$$;

-- Wake the Edge Function after commit and periodically retry anything whose
-- lease/backoff has elapsed. Missing operational secrets leave the durable job
-- untouched for the next scheduled/manual attempt.
create extension if not exists pg_cron;

create or replace function internal.has_due_account_deletion_work(
  p_now timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from internal.account_deletion_jobs job
    where (
      job.status = 'ready_for_auth_delete'
      and job.next_attempt_at is not null
      and job.next_attempt_at <= p_now
    )
    or (
      job.status = 'processing_auth_delete'
      and job.claimed_at <= p_now - interval '5 minutes'
    )
  );
$$;

create or replace function internal.request_account_deletion_drain(
  p_source text default 'manual'
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.account_deletion_drain_queued', true) = '1' then
    return true;
  end if;

  if not internal.has_due_account_deletion_work(now()) then
    return false;
  end if;

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in (
    'account_deletion_drain_secret',
    'media_storage_cleanup_secret',
    'widget_drain_secret'
  )
  order by case name
    when 'account_deletion_drain_secret' then 0
    when 'media_storage_cleanup_secret' then 1
    else 2
  end
  limit 1;

  if coalesce(drain_secret, '') = '' then
    return false;
  end if;

  perform set_config('paeonia.account_deletion_drain_queued', '1', true);

  perform net.http_post(
    url := 'https://api.paeonia.no/functions/v1/delete-account',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-drain-secret', drain_secret
    ),
    body := jsonb_build_object(
      'source', coalesce(nullif(btrim(p_source), ''), 'manual'),
      'triggered_at', now()
    )
  );

  return true;
end;
$$;

create or replace function internal.invoke_account_deletion_drain()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.request_account_deletion_drain(
    tg_table_schema || '.' || tg_table_name
  );
  return null;
end;
$$;

drop trigger if exists invoke_account_deletion_drain_on_jobs
on internal.account_deletion_jobs;
create trigger invoke_account_deletion_drain_on_jobs
after insert or update of status, next_attempt_at
on internal.account_deletion_jobs
for each statement
execute function internal.invoke_account_deletion_drain();

select cron.schedule(
  'paeonia-account-deletion-drain',
  '* * * * *',
  $$select internal.request_account_deletion_drain('cron.account_deletion');$$
);

revoke all on function internal.request_account_deletion() from public, anon, authenticated;
grant execute on function internal.request_account_deletion() to service_role;

revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated, service_role;

revoke all on function internal.reject_pending_account_client_operation()
from public, anon, authenticated;
grant execute on function internal.reject_pending_account_client_operation()
to service_role;

revoke all on function internal.mark_account_deletion_provider_result(uuid, text, text)
from public, anon, authenticated;
revoke all on function internal.claim_account_deletion_jobs(timestamptz, integer, interval, integer, uuid)
from public, anon, authenticated;
revoke all on function internal.mark_account_deletion_auth_failed(uuid, text, integer)
from public, anon, authenticated;
revoke all on function internal.mark_account_deletion_completed(uuid)
from public, anon, authenticated;
revoke all on function internal.retry_account_deletion_job(uuid)
from public, anon, authenticated;
revoke all on function internal.has_due_account_deletion_work(timestamptz)
from public, anon, authenticated;
revoke all on function internal.request_account_deletion_drain(text)
from public, anon, authenticated;
revoke all on function internal.invoke_account_deletion_drain()
from public, anon, authenticated;

grant execute on function internal.mark_account_deletion_provider_result(uuid, text, text)
to service_role;
grant execute on function internal.claim_account_deletion_jobs(timestamptz, integer, interval, integer, uuid)
to service_role;
grant execute on function internal.mark_account_deletion_auth_failed(uuid, text, integer)
to service_role;
grant execute on function internal.mark_account_deletion_completed(uuid)
to service_role;
grant execute on function internal.retry_account_deletion_job(uuid)
to service_role;
grant execute on function internal.has_due_account_deletion_work(timestamptz)
to service_role;
grant execute on function internal.request_account_deletion_drain(text)
to service_role;
grant execute on function internal.invoke_account_deletion_drain()
to service_role;

revoke all on function public.mark_account_deletion_provider_result(uuid, text, text)
from public, anon, authenticated;
revoke all on function public.claim_account_deletion_jobs(timestamptz, integer, interval, integer, uuid)
from public, anon, authenticated;
revoke all on function public.mark_account_deletion_auth_failed(uuid, text, integer)
from public, anon, authenticated;
revoke all on function public.mark_account_deletion_completed(uuid)
from public, anon, authenticated;
revoke all on function public.retry_account_deletion_job(uuid)
from public, anon, authenticated;

grant execute on function public.mark_account_deletion_provider_result(uuid, text, text)
to service_role;
grant execute on function public.claim_account_deletion_jobs(timestamptz, integer, interval, integer, uuid)
to service_role;
grant execute on function public.mark_account_deletion_auth_failed(uuid, text, integer)
to service_role;
grant execute on function public.mark_account_deletion_completed(uuid)
to service_role;
grant execute on function public.retry_account_deletion_job(uuid)
to service_role;

notify pgrst, 'reload schema';
