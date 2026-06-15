create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete restrict,
  display_name text,
  profile_photo_asset_id uuid,
  time_zone_id text,
  time_zone_updated_at timestamptz,
  onboarding_completed_at timestamptz,
  revision integer not null default 1,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid,
  moderation_report_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint profiles_display_name_check
    check (display_name is null or char_length(btrim(display_name)) between 1 and 80),
  constraint profiles_time_zone_id_check
    check (time_zone_id is null or char_length(btrim(time_zone_id)) between 1 and 128),
  constraint profiles_time_zone_updated_at_check
    check (time_zone_updated_at is null or time_zone_id is not null),
  constraint profiles_onboarding_completed_fields_check
    check (
      onboarding_completed_at is null
      or (
        display_name is not null
        and char_length(btrim(display_name)) between 1 and 80
        and time_zone_id is not null
        and char_length(btrim(time_zone_id)) between 1 and 128
        and time_zone_updated_at is not null
      )
    ),
  constraint profiles_revision_check
    check (revision > 0),
  constraint profiles_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger touch_profiles_updated_at_and_revision
before update on public.profiles
for each row
execute function internal.touch_updated_at_and_revision();

create table public.notification_preferences (
  user_id uuid primary key references auth.users (id) on delete restrict,
  streak_reminders_enabled boolean not null default true,
  daily_challenge_enabled boolean not null default true,
  partner_answered_enabled boolean not null default true,
  widget_updates_enabled boolean not null default true,
  location_updates_enabled boolean not null default false,
  lock_screen_detail_level text not null default 'private',
  revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint notification_preferences_lock_screen_detail_level_check
    check (lock_screen_detail_level in ('private', 'descriptive')),
  constraint notification_preferences_revision_check
    check (revision > 0)
);

create trigger touch_notification_preferences_updated_at_and_revision
before update on public.notification_preferences
for each row
execute function internal.touch_updated_at_and_revision();

create table public.user_devices (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete restrict,
  platform text not null,
  push_token text not null,
  push_token_hash bytea not null,
  apns_environment text not null,
  locale text,
  time_zone_id text,
  app_version text,
  last_seen_at timestamptz not null default now(),
  revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz,

  constraint user_devices_platform_check
    check (platform in ('ios', 'ipados')),
  constraint user_devices_push_token_check
    check (char_length(push_token) between 20 and 4096),
  constraint user_devices_push_token_hash_check
    check (octet_length(push_token_hash) = 32),
  constraint user_devices_apns_environment_check
    check (apns_environment in ('sandbox', 'production')),
  constraint user_devices_locale_check
    check (locale is null or char_length(btrim(locale)) between 2 and 64),
  constraint user_devices_time_zone_id_check
    check (time_zone_id is null or char_length(btrim(time_zone_id)) between 1 and 128),
  constraint user_devices_app_version_check
    check (app_version is null or char_length(btrim(app_version)) between 1 and 64),
  constraint user_devices_revision_check
    check (revision > 0)
);

create trigger touch_user_devices_updated_at_and_revision
before update on public.user_devices
for each row
execute function internal.touch_updated_at_and_revision();

create or replace function internal.register_user_device(
  p_platform text,
  p_push_token text,
  p_apns_environment text,
  p_locale text default null,
  p_time_zone_id text default null,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  token_hash bytea;
  registered_device_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_platform is null or p_platform not in ('ios', 'ipados') then
    raise exception 'unsupported device platform'
      using errcode = '23514';
  end if;

  if p_push_token is null or char_length(p_push_token) not between 20 and 4096 then
    raise exception 'invalid push token'
      using errcode = '23514';
  end if;

  if p_apns_environment is null or p_apns_environment not in ('sandbox', 'production') then
    raise exception 'unsupported APNs environment'
      using errcode = '23514';
  end if;

  token_hash = extensions.digest(p_push_token, 'sha256');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.encode(token_hash, 'hex') || ':' || p_apns_environment,
      0
    )
  );

  update public.user_devices
  set disabled_at = now()
  where push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and user_id <> current_user_id
    and disabled_at is null;

  select id
  into registered_device_id
  from public.user_devices
  where user_id = current_user_id
    and push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and disabled_at is null
  order by updated_at desc, id
  limit 1
  for update;

  if registered_device_id is null then
    insert into public.user_devices (
      user_id,
      platform,
      push_token,
      push_token_hash,
      apns_environment,
      locale,
      time_zone_id,
      app_version,
      last_seen_at
    ) values (
      current_user_id,
      p_platform,
      p_push_token,
      token_hash,
      p_apns_environment,
      nullif(btrim(p_locale), ''),
      nullif(btrim(p_time_zone_id), ''),
      nullif(btrim(p_app_version), ''),
      now()
    )
    returning id into registered_device_id;
  else
    update public.user_devices
    set
      platform = p_platform,
      push_token = p_push_token,
      push_token_hash = token_hash,
      apns_environment = p_apns_environment,
      locale = nullif(btrim(p_locale), ''),
      time_zone_id = nullif(btrim(p_time_zone_id), ''),
      app_version = nullif(btrim(p_app_version), ''),
      last_seen_at = now(),
      disabled_at = null
    where id = registered_device_id;
  end if;

  return registered_device_id;
end;
$$;

create or replace function internal.disable_user_device(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update public.user_devices
  set disabled_at = coalesce(disabled_at, now())
  where id = p_device_id
    and user_id = current_user_id;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function public.register_user_device(
  p_platform text,
  p_push_token text,
  p_apns_environment text,
  p_locale text default null,
  p_time_zone_id text default null,
  p_app_version text default null
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.register_user_device(
    p_platform,
    p_push_token,
    p_apns_environment,
    p_locale,
    p_time_zone_id,
    p_app_version
  );
$$;

create or replace function public.disable_user_device(p_device_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.disable_user_device(p_device_id);
$$;

create table public.privacy_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete restrict,
  request_kind text not null,
  status text not null default 'submitted',
  requested_at timestamptz not null default now(),
  verified_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  contact_email text,
  requester_note text,
  visible_status_message text,
  revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint privacy_requests_request_kind_check
    check (request_kind in ('access', 'export', 'deletion', 'correction')),
  constraint privacy_requests_status_check
    check (status in ('submitted', 'verifying', 'processing', 'completed', 'rejected', 'cancelled')),
  constraint privacy_requests_completed_status_check
    check (completed_at is null or status = 'completed'),
  constraint privacy_requests_cancelled_status_check
    check (cancelled_at is null or status = 'cancelled'),
  constraint privacy_requests_contact_email_check
    check (contact_email is null or char_length(btrim(contact_email)) between 3 and 320),
  constraint privacy_requests_requester_note_check
    check (requester_note is null or char_length(requester_note) <= 4000),
  constraint privacy_requests_visible_status_message_check
    check (visible_status_message is null or char_length(visible_status_message) <= 2000),
  constraint privacy_requests_revision_check
    check (revision > 0)
);

create trigger touch_privacy_requests_updated_at_and_revision
before update on public.privacy_requests
for each row
execute function internal.touch_updated_at_and_revision();

create table internal.privacy_request_events (
  id uuid primary key default extensions.gen_random_uuid(),
  request_id uuid not null references public.privacy_requests (id) on delete restrict,
  actor_user_id uuid,
  event_kind text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint privacy_request_events_event_kind_check
    check (char_length(event_kind) between 1 and 120),
  constraint privacy_request_events_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create or replace function internal.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  metadata_display_name text;
begin
  metadata_display_name = left(
    nullif(
      btrim(
        coalesce(
          new.raw_user_meta_data ->> 'full_name',
          new.raw_user_meta_data ->> 'name',
          ''
        )
      ),
      ''
    ),
    80
  );

  insert into public.profiles (user_id, display_name)
  values (new.id, metadata_display_name)
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger create_paeonia_profile_on_auth_user_created
after insert on auth.users
for each row
execute function internal.create_profile_for_new_user();

insert into public.profiles (user_id, display_name)
select
  id,
  left(
    nullif(
      btrim(
        coalesce(
          raw_user_meta_data ->> 'full_name',
          raw_user_meta_data ->> 'name',
          ''
        )
      ),
      ''
    ),
    80
  )
from auth.users
on conflict (user_id) do nothing;

insert into public.notification_preferences (user_id)
select id
from auth.users
on conflict (user_id) do nothing;

alter table public.profiles enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.user_devices enable row level security;
alter table public.privacy_requests enable row level security;
alter table internal.privacy_request_events enable row level security;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using (user_id = (select auth.uid()));

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy notification_preferences_select_own
on public.notification_preferences
for select
to authenticated
using (user_id = (select auth.uid()));

create policy notification_preferences_update_own
on public.notification_preferences
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy user_devices_select_own
on public.user_devices
for select
to authenticated
using (user_id = (select auth.uid()));

create policy user_devices_insert_own
on public.user_devices
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy user_devices_update_own
on public.user_devices
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy privacy_requests_select_own
on public.privacy_requests
for select
to authenticated
using (user_id = (select auth.uid()));

create policy privacy_requests_insert_own
on public.privacy_requests
for insert
to authenticated
with check (user_id = (select auth.uid()));

create index profiles_updated_at_user_id_idx
on public.profiles (updated_at, user_id);

create index user_devices_user_disabled_at_idx
on public.user_devices (user_id, disabled_at);

create unique index user_devices_active_token_hash_idx
on public.user_devices (push_token_hash, apns_environment)
where disabled_at is null;

create index user_devices_user_updated_at_id_idx
on public.user_devices (user_id, updated_at, id);

create index privacy_requests_user_requested_at_idx
on public.privacy_requests (user_id, requested_at desc);

create index privacy_requests_user_updated_at_id_idx
on public.privacy_requests (user_id, updated_at, id);

create index privacy_request_events_request_created_at_idx
on internal.privacy_request_events (request_id, created_at);

revoke all on public.profiles from public, anon, authenticated;
revoke all on public.notification_preferences from public, anon, authenticated;
revoke all on public.user_devices from public, anon, authenticated;
revoke all on public.privacy_requests from public, anon, authenticated;
revoke all on internal.privacy_request_events from public, anon, authenticated;

grant select (
  user_id,
  display_name,
  profile_photo_asset_id,
  time_zone_id,
  time_zone_updated_at,
  onboarding_completed_at,
  revision,
  moderation_status,
  created_at,
  updated_at,
  deleted_at
) on public.profiles to authenticated;

grant update (
  display_name,
  profile_photo_asset_id,
  time_zone_id,
  time_zone_updated_at,
  onboarding_completed_at
) on public.profiles to authenticated;

grant select (
  user_id,
  streak_reminders_enabled,
  daily_challenge_enabled,
  partner_answered_enabled,
  widget_updates_enabled,
  location_updates_enabled,
  lock_screen_detail_level,
  revision,
  created_at,
  updated_at
) on public.notification_preferences to authenticated;

grant update (
  streak_reminders_enabled,
  daily_challenge_enabled,
  partner_answered_enabled,
  widget_updates_enabled,
  location_updates_enabled,
  lock_screen_detail_level
) on public.notification_preferences to authenticated;

grant select (
  id,
  user_id,
  platform,
  apns_environment,
  locale,
  time_zone_id,
  app_version,
  last_seen_at,
  revision,
  created_at,
  updated_at,
  disabled_at
) on public.user_devices to authenticated;

grant select (
  id,
  user_id,
  request_kind,
  status,
  requested_at,
  verified_at,
  completed_at,
  cancelled_at,
  contact_email,
  requester_note,
  visible_status_message,
  revision,
  created_at,
  updated_at
) on public.privacy_requests to authenticated;

grant insert (
  id,
  user_id,
  request_kind,
  contact_email,
  requester_note
) on public.privacy_requests to authenticated;

grant all privileges on public.profiles to service_role;
grant all privileges on public.notification_preferences to service_role;
grant all privileges on public.user_devices to service_role;
grant all privileges on public.privacy_requests to service_role;
grant all privileges on internal.privacy_request_events to service_role;

grant usage on schema internal to authenticated;

revoke all on function internal.create_profile_for_new_user() from public, anon, authenticated;
grant execute on function internal.create_profile_for_new_user() to service_role;

revoke all on function internal.register_user_device(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function internal.register_user_device(text, text, text, text, text, text) to authenticated, service_role;

revoke all on function internal.disable_user_device(uuid) from public, anon, authenticated;
grant execute on function internal.disable_user_device(uuid) to authenticated, service_role;

revoke all on function public.register_user_device(text, text, text, text, text, text) from public, anon;
grant execute on function public.register_user_device(text, text, text, text, text, text) to authenticated, service_role;

revoke all on function public.disable_user_device(uuid) from public, anon;
grant execute on function public.disable_user_device(uuid) to authenticated, service_role;
