create table public.location_sharing_preferences (
  couple_id uuid not null references public.couples (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  is_enabled boolean not null default false,
  enabled_at timestamptz,
  disabled_at timestamptz default now(),
  consent_version text,
  source text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint location_sharing_preferences_primary_key
    primary key (couple_id, user_id),
  constraint location_sharing_preferences_source_check
    check (source in ('foreground_open', 'manual_refresh', 'settings_toggle')),
  constraint location_sharing_preferences_consent_version_check
    check (consent_version is null or char_length(btrim(consent_version)) between 1 and 80),
  constraint location_sharing_preferences_state_check
    check (
      (is_enabled and enabled_at is not null and disabled_at is null and consent_version is not null)
      or (not is_enabled and disabled_at is not null)
    )
);

create trigger set_location_sharing_preferences_updated_at
before update on public.location_sharing_preferences
for each row
execute function internal.set_updated_at();

create table public.latest_partner_locations (
  couple_id uuid not null references public.couples (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  accuracy_m numeric(10,2),
  captured_at timestamptz not null,
  received_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  source text not null,
  client_operation_id uuid not null,
  client_id uuid not null,
  client_sequence bigint not null,

  constraint latest_partner_locations_primary_key
    primary key (couple_id, user_id),
  constraint latest_partner_locations_latitude_check
    check (latitude between -90 and 90),
  constraint latest_partner_locations_longitude_check
    check (longitude between -180 and 180),
  constraint latest_partner_locations_accuracy_check
    check (accuracy_m is null or accuracy_m between 0 and 100000),
  constraint latest_partner_locations_captured_at_check
    check (captured_at <= now() + interval '5 minutes'),
  constraint latest_partner_locations_source_check
    check (source in ('foreground_open', 'manual_refresh', 'settings_toggle')),
  constraint latest_partner_locations_client_sequence_check
    check (client_sequence > 0)
);

create trigger set_latest_partner_locations_updated_at
before update on public.latest_partner_locations
for each row
execute function internal.set_updated_at();

create table public.streak_states (
  couple_id uuid primary key references public.couples (id) on delete restrict,
  current_count integer not null default 0,
  longest_count integer not null default 0,
  last_qualified_date date,
  last_qualified_couple_day_id uuid references public.couple_days (id) on delete restrict,
  restore_available boolean not null default false,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),

  constraint streak_states_counts_check
    check (current_count >= 0 and longest_count >= current_count),
  constraint streak_states_last_qualified_check
    check (
      (current_count = 0 and last_qualified_date is null and last_qualified_couple_day_id is null and expires_at is null)
      or (current_count > 0 and last_qualified_date is not null and last_qualified_couple_day_id is not null and expires_at is not null)
    )
);

create trigger set_streak_states_updated_at
before update on public.streak_states
for each row
execute function internal.set_updated_at();

create table public.couple_activity_events (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  couple_day_id uuid not null references public.couple_days (id) on delete restrict,
  activity_kind text not null,
  occurred_at timestamptz not null,
  dedupe_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint couple_activity_events_dedupe_key_unique
    unique (dedupe_key),
  constraint couple_activity_events_activity_kind_check
    check (activity_kind in ('daily_challenge_completed', 'widget_drawing_saved', 'memory_created', 'memory_updated', 'thread_message_sent')),
  constraint couple_activity_events_dedupe_key_check
    check (char_length(btrim(dedupe_key)) between 1 and 240),
  constraint couple_activity_events_metadata_check
    check (jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 2048)
);

create table internal.notification_outbox (
  id uuid primary key default extensions.gen_random_uuid(),
  recipient_user_id uuid not null references auth.users (id) on delete restrict,
  target_device_id uuid not null references public.user_devices (id) on delete restrict,
  push_token_hash bytea not null,
  apns_environment text not null,
  kind text not null,
  payload_version integer not null default 1,
  redaction_level text not null default 'private',
  payload jsonb not null,
  dedupe_key text,
  apns_push_type text not null default 'alert',
  apns_collapse_id text,
  provider_message_id text,
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_error text,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now(),

  constraint notification_outbox_push_token_hash_check
    check (octet_length(push_token_hash) = 32),
  constraint notification_outbox_apns_environment_check
    check (apns_environment in ('sandbox', 'production')),
  constraint notification_outbox_kind_check
    check (kind in ('streak_reminder', 'daily_challenge_completed', 'partner_answered', 'widget_updated', 'location_updated', 'relationship_ended', 'entitlement_changed')),
  constraint notification_outbox_payload_version_check
    check (payload_version = 1),
  constraint notification_outbox_redaction_level_check
    check (redaction_level in ('private', 'generic', 'content_allowed')),
  constraint notification_outbox_payload_check
    check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 4096),
  constraint notification_outbox_dedupe_key_check
    check (dedupe_key is null or char_length(btrim(dedupe_key)) between 1 and 320),
  constraint notification_outbox_apns_push_type_check
    check (apns_push_type in ('alert', 'background')),
  constraint notification_outbox_apns_collapse_id_check
    check (apns_collapse_id is null or char_length(btrim(apns_collapse_id)) between 1 and 64),
  constraint notification_outbox_provider_message_id_check
    check (provider_message_id is null or char_length(btrim(provider_message_id)) <= 255),
  constraint notification_outbox_attempt_count_check
    check (attempt_count >= 0),
  constraint notification_outbox_last_error_check
    check (last_error is null or char_length(last_error) <= 2000),
  constraint notification_outbox_terminal_state_check
    check (not (sent_at is not null and failed_at is not null))
);

create or replace function internal.notification_payload_is_safe(p_payload jsonb)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select p_payload is not null
    and jsonb_typeof(p_payload) = 'object'
    and octet_length(p_payload::text) <= 4096
    and p_payload::text !~* '"(answer_body|note_body|message_body|body_text|voice_transcript|media_url|signed_url|latitude|longitude|coordinate|invite_code|report_detail|precise_location)"';
$$;

create or replace function internal.assert_notification_payload_safe()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not internal.notification_payload_is_safe(new.payload) then
    raise exception 'notification payload contains sensitive or unsupported fields'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_notification_outbox_payload_safe
before insert or update of payload on internal.notification_outbox
for each row
execute function internal.assert_notification_payload_safe();

create or replace function internal.enqueue_notification_for_user(
  p_recipient_user_id uuid,
  p_kind text,
  p_payload jsonb,
  p_dedupe_key text default null,
  p_redaction_level text default 'private',
  p_apns_push_type text default 'alert',
  p_apns_collapse_id text default null,
  p_scheduled_for timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer;
begin
  if p_recipient_user_id is null then
    raise exception 'notification recipient is required'
      using errcode = '23514';
  end if;

  if p_kind not in ('streak_reminder', 'daily_challenge_completed', 'partner_answered', 'widget_updated', 'location_updated', 'relationship_ended', 'entitlement_changed') then
    raise exception 'notification kind is not supported'
      using errcode = '23514';
  end if;

  if p_redaction_level <> 'private' then
    raise exception 'only private notification payloads are supported for MVP'
      using errcode = '23514';
  end if;

  if not internal.notification_payload_is_safe(p_payload) then
    raise exception 'notification payload contains sensitive or unsupported fields'
      using errcode = '23514';
  end if;

  insert into internal.notification_outbox (
    recipient_user_id,
    target_device_id,
    push_token_hash,
    apns_environment,
    kind,
    redaction_level,
    payload,
    dedupe_key,
    apns_push_type,
    apns_collapse_id,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.push_token_hash,
    device.apns_environment,
    p_kind,
    p_redaction_level,
    p_payload,
    case
      when nullif(btrim(coalesce(p_dedupe_key, '')), '') is null then null
      else btrim(p_dedupe_key) || ':' || device.id::text
    end,
    p_apns_push_type,
    nullif(btrim(coalesce(p_apns_collapse_id, '')), ''),
    coalesce(p_scheduled_for, now())
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = p_recipient_user_id
    and device.disabled_at is null
    and (
      case p_kind
        when 'streak_reminder' then preference.streak_reminders_enabled
        when 'daily_challenge_completed' then preference.daily_challenge_enabled
        when 'partner_answered' then preference.partner_answered_enabled
        when 'widget_updated' then preference.widget_updates_enabled
        when 'location_updated' then preference.location_updates_enabled
        else true
      end
    )
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;

create or replace function internal.enqueue_partner_notification(
  p_couple_id uuid,
  p_actor_user_id uuid,
  p_kind text,
  p_payload jsonb,
  p_dedupe_key text default null,
  p_redaction_level text default 'private',
  p_apns_push_type text default 'alert',
  p_apns_collapse_id text default null,
  p_scheduled_for timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer := 0;
  partner_row record;
begin
  for partner_row in
    select member.user_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id <> p_actor_user_id
      and member.status = 'active'
      and couple.status = 'active'
  loop
    queued_rows = queued_rows + internal.enqueue_notification_for_user(
      partner_row.user_id,
      p_kind,
      p_payload,
      p_dedupe_key,
      p_redaction_level,
      p_apns_push_type,
      p_apns_collapse_id,
      p_scheduled_for
    );
  end loop;

  return queued_rows;
end;
$$;

create or replace function internal.resolve_streak_expires_at(
  p_couple_id uuid,
  p_observed_at timestamptz
)
returns timestamptz
language sql
security definer
set search_path = pg_catalog
as $$
  select max(
    (((p_observed_at at time zone coalesce(timezone_name.name, 'UTC'))::date + 1)::timestamp)
      at time zone coalesce(timezone_name.name, 'UTC')
  )
  from public.couple_members member
  left join public.profiles profile
    on profile.user_id = member.user_id
  left join pg_timezone_names timezone_name
    on timezone_name.name = profile.time_zone_id
  where member.couple_id = p_couple_id
    and member.status = 'active';
$$;

create or replace function internal.apply_couple_activity(
  p_couple_id uuid,
  p_user_id uuid,
  p_couple_day_id uuid,
  p_activity_kind text,
  p_occurred_at timestamptz,
  p_dedupe_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_day_row public.couple_days%rowtype;
  inserted_event_id uuid;
  existing_state public.streak_states%rowtype;
  next_current_count integer;
  next_longest_count integer;
  next_restore_available boolean;
  next_expires_at timestamptz;
begin
  if p_activity_kind not in ('daily_challenge_completed', 'widget_drawing_saved', 'memory_created', 'memory_updated', 'thread_message_sent') then
    raise exception 'couple activity kind is not supported'
      using errcode = '23514';
  end if;

  if p_occurred_at is null then
    p_occurred_at = now();
  end if;

  if p_dedupe_key is null or char_length(btrim(p_dedupe_key)) not between 1 and 240 then
    raise exception 'couple activity dedupe key is required'
      using errcode = '23514';
  end if;

  if p_metadata is null then
    p_metadata = '{}'::jsonb;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = p_couple_day_id;

  if not found
    or couple_day_row.couple_id <> p_couple_id then
    raise exception 'couple activity day is invalid'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = p_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'couple activity user must be an active couple member'
      using errcode = '23514';
  end if;

  insert into public.couple_activity_events (
    couple_id,
    user_id,
    couple_day_id,
    activity_kind,
    occurred_at,
    dedupe_key,
    metadata
  ) values (
    p_couple_id,
    p_user_id,
    p_couple_day_id,
    p_activity_kind,
    p_occurred_at,
    btrim(p_dedupe_key),
    p_metadata
  )
  on conflict (dedupe_key) do nothing
  returning id into inserted_event_id;

  if inserted_event_id is null then
    select event.id
    into inserted_event_id
    from public.couple_activity_events event
    where event.dedupe_key = btrim(p_dedupe_key);

    return inserted_event_id;
  end if;

  next_expires_at = internal.resolve_streak_expires_at(p_couple_id, p_occurred_at);

  select *
  into existing_state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  if not found then
    insert into public.streak_states (
      couple_id,
      current_count,
      longest_count,
      last_qualified_date,
      last_qualified_couple_day_id,
      restore_available,
      expires_at
    ) values (
      p_couple_id,
      1,
      1,
      couple_day_row.local_date,
      couple_day_row.id,
      false,
      next_expires_at
    );
  elsif existing_state.last_qualified_date is null
    or couple_day_row.local_date > existing_state.last_qualified_date then
    if existing_state.last_qualified_date is null then
      next_current_count = 1;
      next_restore_available = false;
    elsif couple_day_row.local_date = existing_state.last_qualified_date + 1 then
      next_current_count = existing_state.current_count + 1;
      next_restore_available = existing_state.restore_available;
    else
      next_current_count = 1;
      next_restore_available = true;
    end if;

    next_longest_count = greatest(existing_state.longest_count, next_current_count);

    update public.streak_states
    set
      current_count = next_current_count,
      longest_count = next_longest_count,
      last_qualified_date = couple_day_row.local_date,
      last_qualified_couple_day_id = couple_day_row.id,
      restore_available = next_restore_available,
      expires_at = next_expires_at
    where couple_id = p_couple_id;
  elsif couple_day_row.local_date = existing_state.last_qualified_date then
    update public.streak_states
    set
      last_qualified_couple_day_id = couple_day_row.id,
      expires_at = greatest(existing_state.expires_at, next_expires_at)
    where couple_id = p_couple_id;
  end if;

  return inserted_event_id;
end;
$$;

create or replace function internal.record_couple_activity(
  p_activity_kind text,
  p_couple_day_id uuid,
  p_occurred_at timestamptz,
  p_dedupe_key text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  resolved_couple_day_id uuid;
  resolved_occurred_at timestamptz;
  event_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  resolved_occurred_at = coalesce(p_occurred_at, now());
  resolved_couple_id = internal.get_current_entitled_couple_id();
  resolved_couple_day_id = coalesce(
    p_couple_day_id,
    internal.get_or_create_couple_day_at(resolved_couple_id, resolved_occurred_at)
  );

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'record_couple_activity',
      resolved_couple_id::text,
      current_user_id::text,
      resolved_couple_day_id::text,
      p_activity_kind,
      resolved_occurred_at::text,
      p_dedupe_key
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'record_couple_activity',
    'activity',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'activity_event_id')::uuid;
  end if;

  event_id = internal.apply_couple_activity(
    resolved_couple_id,
    current_user_id,
    resolved_couple_day_id,
    p_activity_kind,
    resolved_occurred_at,
    p_dedupe_key,
    '{}'::jsonb
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('activity_event_id', event_id)
  );

  return event_id;
end;
$$;

create or replace function internal.update_location_sharing_preference(
  p_couple_id uuid,
  p_is_enabled boolean,
  p_consent_version text,
  p_source text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_id uuid,
  user_id uuid,
  is_enabled boolean,
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_source text;
  normalized_consent_version text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_is_enabled is null then
    raise exception 'location sharing state is required'
      using errcode = '23514';
  end if;

  resolved_source = lower(btrim(coalesce(p_source, 'settings_toggle')));

  if resolved_source not in ('foreground_open', 'manual_refresh', 'settings_toggle') then
    raise exception 'location source is not supported'
      using errcode = '23514';
  end if;

  normalized_consent_version = nullif(btrim(coalesce(p_consent_version, '')), '');

  if p_is_enabled
    and (
      normalized_consent_version is null
      or char_length(normalized_consent_version) > 80
    ) then
    raise exception 'location sharing consent version is required'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(p_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_location_sharing_preference',
      p_couple_id::text,
      current_user_id::text,
      p_is_enabled::text,
      coalesce(normalized_consent_version, ''),
      resolved_source
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_location_sharing_preference',
    'location',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'couple_id')::uuid,
      (replayed_response ->> 'user_id')::uuid,
      (replayed_response ->> 'is_enabled')::boolean,
      (replayed_response ->> 'enabled_at')::timestamptz,
      (replayed_response ->> 'disabled_at')::timestamptz,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  insert into public.location_sharing_preferences (
    couple_id,
    user_id,
    is_enabled,
    enabled_at,
    disabled_at,
    consent_version,
    source
  ) values (
    p_couple_id,
    current_user_id,
    p_is_enabled,
    case when p_is_enabled then now() else null end,
    case when p_is_enabled then null else now() end,
    case when p_is_enabled then normalized_consent_version else null end,
    resolved_source
  )
  on conflict on constraint location_sharing_preferences_primary_key do update
  set
    is_enabled = excluded.is_enabled,
    enabled_at = case when excluded.is_enabled then now() else location_sharing_preferences.enabled_at end,
    disabled_at = case when excluded.is_enabled then null else now() end,
    consent_version = case when excluded.is_enabled then excluded.consent_version else location_sharing_preferences.consent_version end,
    source = excluded.source
  returning
    public.location_sharing_preferences.couple_id,
    public.location_sharing_preferences.user_id,
    public.location_sharing_preferences.is_enabled,
    public.location_sharing_preferences.enabled_at,
    public.location_sharing_preferences.disabled_at,
    public.location_sharing_preferences.updated_at
  into
    couple_id,
    user_id,
    is_enabled,
    enabled_at,
    disabled_at,
    updated_at;

  if not p_is_enabled then
    delete from public.latest_partner_locations latest
    where latest.couple_id = p_couple_id
      and latest.user_id = current_user_id;
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'couple_id', couple_id,
      'user_id', user_id,
      'is_enabled', is_enabled,
      'enabled_at', enabled_at,
      'disabled_at', disabled_at,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;

create or replace function internal.update_latest_partner_location(
  p_couple_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric,
  p_captured_at timestamptz,
  p_source text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_id uuid,
  user_id uuid,
  latitude numeric,
  longitude numeric,
  accuracy_m numeric,
  captured_at timestamptz,
  received_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_source text;
  existing_location public.latest_partner_locations%rowtype;
  changed_rows integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if not internal.can_access_couple_content(p_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  resolved_source = lower(btrim(coalesce(p_source, 'foreground_open')));

  if resolved_source not in ('foreground_open', 'manual_refresh', 'settings_toggle') then
    raise exception 'location source is not supported'
      using errcode = '23514';
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90
    or p_longitude is null or p_longitude < -180 or p_longitude > 180
    or p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 100000)
    or p_captured_at is null
    or p_captured_at > now() + interval '5 minutes' then
    raise exception 'location payload is out of range'
      using errcode = '23514';
  end if;

  perform 1
    from public.location_sharing_preferences preference
    where preference.couple_id = p_couple_id
      and preference.user_id = current_user_id
      and preference.is_enabled
    for update;

  if not found then
    raise exception 'location sharing must be enabled before updating location'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_latest_partner_location',
      p_couple_id::text,
      current_user_id::text,
      p_latitude::text,
      p_longitude::text,
      coalesce(p_accuracy_m::text, ''),
      p_captured_at::text,
      resolved_source
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_latest_partner_location',
    'location',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'couple_id')::uuid,
      (replayed_response ->> 'user_id')::uuid,
      (replayed_response ->> 'latitude')::numeric,
      (replayed_response ->> 'longitude')::numeric,
      (replayed_response ->> 'accuracy_m')::numeric,
      (replayed_response ->> 'captured_at')::timestamptz,
      (replayed_response ->> 'received_at')::timestamptz,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into existing_location
  from public.latest_partner_locations latest
  where latest.couple_id = p_couple_id
    and latest.user_id = current_user_id
  for update;

  if found and existing_location.captured_at > p_captured_at then
    raise exception 'stale location update was rejected'
      using errcode = '40001';
  end if;

  insert into public.latest_partner_locations (
    couple_id,
    user_id,
    latitude,
    longitude,
    accuracy_m,
    captured_at,
    received_at,
    source,
    client_operation_id,
    client_id,
    client_sequence
  ) values (
    p_couple_id,
    current_user_id,
    p_latitude,
    p_longitude,
    p_accuracy_m,
    p_captured_at,
    now(),
    resolved_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence
  )
  on conflict on constraint latest_partner_locations_primary_key do update
  set
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy_m = excluded.accuracy_m,
    captured_at = excluded.captured_at,
    received_at = excluded.received_at,
    source = excluded.source,
    client_operation_id = excluded.client_operation_id,
    client_id = excluded.client_id,
    client_sequence = excluded.client_sequence
  where public.latest_partner_locations.captured_at <= excluded.captured_at
  returning
    public.latest_partner_locations.couple_id,
    public.latest_partner_locations.user_id,
    public.latest_partner_locations.latitude,
    public.latest_partner_locations.longitude,
    public.latest_partner_locations.accuracy_m,
    public.latest_partner_locations.captured_at,
    public.latest_partner_locations.received_at,
    public.latest_partner_locations.updated_at
  into
    couple_id,
    user_id,
    latitude,
    longitude,
    accuracy_m,
    captured_at,
    received_at,
    updated_at;

  get diagnostics changed_rows = row_count;

  if changed_rows = 0 then
    raise exception 'stale location update was rejected'
      using errcode = '40001';
  end if;

  if exists (
    select 1
    from public.couple_members partner_member
    join public.location_sharing_preferences partner_preference
      on partner_preference.couple_id = partner_member.couple_id
      and partner_preference.user_id = partner_member.user_id
    where partner_member.couple_id = p_couple_id
      and partner_member.user_id <> current_user_id
      and partner_member.status = 'active'
      and partner_preference.is_enabled
  ) then
    perform internal.enqueue_partner_notification(
      p_couple_id,
      current_user_id,
      'location_updated',
      jsonb_build_object(
        'type', 'location_updated',
        'couple_id', p_couple_id,
        'actor_user_id', current_user_id,
        'captured_at', captured_at,
        'route', 'location'
      ),
      'location_updated:' || p_couple_id::text || ':' || current_user_id::text || ':' || captured_at::text,
      'private',
      'background',
      'location:' || p_couple_id::text,
      now()
    );
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'couple_id', couple_id,
      'user_id', user_id,
      'latitude', latitude,
      'longitude', longitude,
      'accuracy_m', accuracy_m,
      'captured_at', captured_at,
      'received_at', received_at,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;

create or replace function internal.get_partner_location_visibility(p_couple_id uuid default null)
returns table (
  couple_id uuid,
  viewer_user_id uuid,
  partner_user_id uuid,
  visibility_state text,
  viewer_sharing_enabled boolean,
  partner_sharing_enabled boolean,
  partner_location_latitude numeric,
  partner_location_longitude numeric,
  partner_location_accuracy_m numeric,
  partner_location_captured_at timestamptz,
  partner_location_is_stale boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  couple_status text;
  viewer_member_status text;
  partner_member_user_id uuid;
  viewer_enabled boolean := false;
  partner_enabled boolean := false;
  partner_location public.latest_partner_locations%rowtype;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_couple_id is null then
    resolved_couple_id = internal.get_current_entitled_couple_id();
  else
    resolved_couple_id = p_couple_id;
  end if;

  select couple.status, member.status
  into couple_status, viewer_member_status
  from public.couples couple
  join public.couple_members member
    on member.couple_id = couple.id
  where couple.id = resolved_couple_id
    and member.user_id = current_user_id
    and member.status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen');

  if not found then
    raise exception 'relationship was not found'
      using errcode = '42501';
  end if;

  select member.user_id
  into partner_member_user_id
  from public.couple_members member
  where member.couple_id = resolved_couple_id
    and member.user_id <> current_user_id
    and member.status = 'active'
  order by member.joined_at desc, member.user_id
  limit 1;

  if couple_status <> 'active'
    or viewer_member_status <> 'active'
    or partner_member_user_id is null then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'relationship_ended'::text,
      false,
      false,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  if not internal.can_access_couple_content(resolved_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  select coalesce(preference.is_enabled, false)
  into viewer_enabled
  from public.location_sharing_preferences preference
  where preference.couple_id = resolved_couple_id
    and preference.user_id = current_user_id;

  viewer_enabled = coalesce(viewer_enabled, false);

  select coalesce(preference.is_enabled, false)
  into partner_enabled
  from public.location_sharing_preferences preference
  where preference.couple_id = resolved_couple_id
    and preference.user_id = partner_member_user_id;

  partner_enabled = coalesce(partner_enabled, false);

  if not viewer_enabled then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'disabled'::text,
      false,
      partner_enabled,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  if not partner_enabled then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'not_sharing'::text,
      true,
      false,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  select *
  into partner_location
  from public.latest_partner_locations latest
  where latest.couple_id = resolved_couple_id
    and latest.user_id = partner_member_user_id;

  if not found then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'not_sharing'::text,
      true,
      true,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  return query
  select
    resolved_couple_id,
    current_user_id,
    partner_member_user_id,
    'visible'::text,
    true,
    true,
    partner_location.latitude,
    partner_location.longitude,
    partner_location.accuracy_m,
    partner_location.captured_at,
    partner_location.captured_at < now() - interval '24 hours',
    partner_location.updated_at;
end;
$$;

create or replace function internal.claim_due_notifications(
  p_limit integer default 100
)
returns table (
  outbox_id uuid,
  recipient_user_id uuid,
  target_device_id uuid,
  push_token text,
  push_token_hash bytea,
  apns_environment text,
  kind text,
  payload_version integer,
  redaction_level text,
  payload jsonb,
  apns_push_type text,
  apns_collapse_id text,
  attempt_count integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'notification claim limit is out of range'
      using errcode = '23514';
  end if;

  update internal.notification_outbox outbox
  set
    failed_at = now(),
    last_attempt_at = now(),
    last_error = 'notification target is no longer eligible'
  from public.user_devices device
  left join public.notification_preferences preference
    on preference.user_id = device.user_id
  where outbox.target_device_id = device.id
    and outbox.scheduled_for <= now()
    and outbox.sent_at is null
    and outbox.failed_at is null
    and (
      device.disabled_at is not null
      or not coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then preference.widget_updates_enabled
          when 'location_updated' then preference.location_updates_enabled
          else true
        end,
        false
      )
    );

  return query
  with picked as (
    select outbox.id
    from internal.notification_outbox outbox
    join public.user_devices device
      on device.id = outbox.target_device_id
    left join public.notification_preferences preference
      on preference.user_id = device.user_id
    where outbox.scheduled_for <= now()
      and outbox.sent_at is null
      and outbox.failed_at is null
      and device.disabled_at is null
      and coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then preference.widget_updates_enabled
          when 'location_updated' then preference.location_updates_enabled
          else true
        end,
        false
      )
    order by outbox.scheduled_for, outbox.created_at, outbox.id
    for update of outbox skip locked
    limit p_limit
  ),
  claimed as (
    update internal.notification_outbox outbox
    set
      attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now(),
      last_error = null
    from picked
    where outbox.id = picked.id
    returning outbox.*
  )
  select
    claimed.id,
    claimed.recipient_user_id,
    claimed.target_device_id,
    device.push_token,
    claimed.push_token_hash,
    claimed.apns_environment,
    claimed.kind,
    claimed.payload_version,
    claimed.redaction_level,
    claimed.payload,
    claimed.apns_push_type,
    claimed.apns_collapse_id,
    claimed.attempt_count
  from claimed
  join public.user_devices device
    on device.id = claimed.target_device_id
  where device.disabled_at is null;
end;
$$;

create or replace function internal.mark_notification_sent(
  p_outbox_id uuid,
  p_provider_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.notification_outbox
  set
    provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
    sent_at = now(),
    failed_at = null,
    last_error = null
  where id = p_outbox_id
    and sent_at is null;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.mark_notification_failed(
  p_outbox_id uuid,
  p_error text,
  p_terminal boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.notification_outbox
  set
    last_error = left(nullif(btrim(coalesce(p_error, '')), ''), 2000),
    failed_at = case when coalesce(p_terminal, false) then now() else null end
  where id = p_outbox_id
    and sent_at is null;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.enqueue_due_streak_reminders(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer := 0;
  reminder_row record;
begin
  for reminder_row in
    select
      streak.couple_id,
      streak.current_count,
      streak.last_qualified_date,
      streak.expires_at,
      member.user_id
    from public.streak_states streak
    join public.couple_members member
      on member.couple_id = streak.couple_id
    join public.couples couple
      on couple.id = streak.couple_id
    where couple.status = 'active'
      and member.status = 'active'
      and streak.expires_at > p_now
      and streak.expires_at <= p_now + interval '1 hour'
  loop
    queued_rows = queued_rows + internal.enqueue_notification_for_user(
      reminder_row.user_id,
      'streak_reminder',
      jsonb_build_object(
        'type', 'streak_reminder',
        'couple_id', reminder_row.couple_id,
        'current_count', reminder_row.current_count,
        'last_qualified_date', reminder_row.last_qualified_date,
        'expires_at', reminder_row.expires_at,
        'route', 'streak'
      ),
      'streak_reminder:' || reminder_row.couple_id::text || ':' || reminder_row.last_qualified_date::text,
      'private',
      'alert',
      'streak:' || reminder_row.couple_id::text,
      p_now
    );
  end loop;

  return queued_rows;
end;
$$;

create or replace function internal.handle_daily_challenge_completed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_day_row public.couple_days%rowtype;
begin
  if new.completed_at is null
    or old.completed_at is not null then
    return new;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = new.couple_day_id;

  if found then
    perform internal.apply_couple_activity(
      couple_day_row.couple_id,
      new.user_id,
      new.couple_day_id,
      'daily_challenge_completed',
      new.completed_at,
      'daily_challenge_completed:' || new.couple_day_id::text || ':' || new.user_id::text,
      jsonb_build_object('source', 'daily_challenge')
    );

    perform internal.enqueue_partner_notification(
      couple_day_row.couple_id,
      new.user_id,
      'daily_challenge_completed',
      jsonb_build_object(
        'type', 'daily_challenge_completed',
        'couple_id', couple_day_row.couple_id,
        'couple_day_id', new.couple_day_id,
        'actor_user_id', new.user_id,
        'route', 'daily'
      ),
      'daily_challenge_completed:' || new.couple_day_id::text || ':' || new.user_id::text,
      'private',
      'alert',
      'daily:' || couple_day_row.couple_id::text,
      now()
    );

    new.partner_notified_at = coalesce(new.partner_notified_at, now());
  end if;

  return new;
end;
$$;

create trigger handle_daily_challenge_completed
before update of completed_at on public.daily_challenges
for each row
execute function internal.handle_daily_challenge_completed();

create or replace function internal.handle_widget_drawing_revision_created()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canvas_row public.widget_canvases%rowtype;
  couple_day_id uuid;
begin
  select *
  into canvas_row
  from public.widget_canvases
  where id = new.canvas_id;

  if not found then
    return new;
  end if;

  couple_day_id = internal.get_or_create_couple_day_at(canvas_row.couple_id, new.created_at);

  perform internal.apply_couple_activity(
    canvas_row.couple_id,
    new.author_user_id,
    couple_day_id,
    'widget_drawing_saved',
    new.created_at,
    'widget_drawing_saved:' || new.id::text,
    jsonb_build_object('canvas_id', new.canvas_id)
  );

  perform internal.enqueue_partner_notification(
    canvas_row.couple_id,
    new.author_user_id,
    'widget_updated',
    jsonb_build_object(
      'type', 'widget_updated',
      'couple_id', canvas_row.couple_id,
      'canvas_id', new.canvas_id,
      'revision_id', new.id,
      'actor_user_id', new.author_user_id,
      'route', 'widget'
    ),
    'widget_updated:' || new.id::text,
    'private',
    'background',
    'widget:' || canvas_row.couple_id::text,
    now()
  );

  return new;
end;
$$;

create trigger handle_widget_drawing_revision_created
after insert on public.widget_drawing_revisions
for each row
execute function internal.handle_widget_drawing_revision_created();

create or replace function internal.delete_latest_locations_on_preference_disable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not new.is_enabled then
    delete from public.latest_partner_locations latest
    where latest.couple_id = new.couple_id
      and latest.user_id = new.user_id;
  end if;

  return new;
end;
$$;

create trigger delete_latest_locations_on_preference_disable
after insert or update of is_enabled on public.location_sharing_preferences
for each row
execute function internal.delete_latest_locations_on_preference_disable();

create or replace function internal.delete_latest_locations_on_relationship_end()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.status = 'active' and new.status <> 'active' then
    delete from public.latest_partner_locations latest
    where latest.couple_id = new.id;
  end if;

  return new;
end;
$$;

create trigger delete_latest_locations_on_relationship_end
after update of status on public.couples
for each row
execute function internal.delete_latest_locations_on_relationship_end();

create or replace function public.update_location_sharing_preference(
  p_couple_id uuid,
  p_is_enabled boolean,
  p_consent_version text,
  p_source text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_id uuid,
  user_id uuid,
  is_enabled boolean,
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.update_location_sharing_preference(
    p_couple_id,
    p_is_enabled,
    p_consent_version,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.update_latest_partner_location(
  p_couple_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric,
  p_captured_at timestamptz,
  p_source text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_id uuid,
  user_id uuid,
  latitude numeric,
  longitude numeric,
  accuracy_m numeric,
  captured_at timestamptz,
  received_at timestamptz,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.update_latest_partner_location(
    p_couple_id,
    p_latitude,
    p_longitude,
    p_accuracy_m,
    p_captured_at,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.get_partner_location_visibility(p_couple_id uuid default null)
returns table (
  couple_id uuid,
  viewer_user_id uuid,
  partner_user_id uuid,
  visibility_state text,
  viewer_sharing_enabled boolean,
  partner_sharing_enabled boolean,
  partner_location_latitude numeric,
  partner_location_longitude numeric,
  partner_location_accuracy_m numeric,
  partner_location_captured_at timestamptz,
  partner_location_is_stale boolean,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_partner_location_visibility(p_couple_id);
$$;

alter table public.location_sharing_preferences enable row level security;
alter table public.latest_partner_locations enable row level security;
alter table public.streak_states enable row level security;
alter table public.couple_activity_events enable row level security;
alter table internal.notification_outbox enable row level security;

create index latest_partner_locations_user_updated_at_idx
on public.latest_partner_locations (user_id, updated_at desc);

create index couple_activity_events_couple_day_kind_idx
on public.couple_activity_events (couple_id, couple_day_id, activity_kind);

create index couple_activity_events_user_created_at_idx
on public.couple_activity_events (user_id, created_at desc);

create index notification_outbox_pending_due_idx
on internal.notification_outbox (scheduled_for, created_at, id)
where sent_at is null
  and failed_at is null;

create index notification_outbox_recipient_created_at_idx
on internal.notification_outbox (recipient_user_id, created_at desc);

create unique index notification_outbox_dedupe_key_unique_idx
on internal.notification_outbox (dedupe_key)
where dedupe_key is not null;

revoke all on public.location_sharing_preferences from public, anon, authenticated;
revoke all on public.latest_partner_locations from public, anon, authenticated;
revoke all on public.streak_states from public, anon, authenticated;
revoke all on public.couple_activity_events from public, anon, authenticated;
revoke all on internal.notification_outbox from public, anon, authenticated;

grant all privileges on public.location_sharing_preferences to service_role;
grant all privileges on public.latest_partner_locations to service_role;
grant all privileges on public.streak_states to service_role;
grant all privileges on public.couple_activity_events to service_role;
grant all privileges on internal.notification_outbox to service_role;

revoke all on function internal.notification_payload_is_safe(jsonb) from public, anon, authenticated;
grant execute on function internal.notification_payload_is_safe(jsonb) to service_role;

revoke all on function internal.assert_notification_payload_safe() from public, anon, authenticated;
grant execute on function internal.assert_notification_payload_safe() to service_role;

revoke all on function internal.enqueue_notification_for_user(uuid, text, jsonb, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_notification_for_user(uuid, text, jsonb, text, text, text, text, timestamptz) to service_role;

revoke all on function internal.enqueue_partner_notification(uuid, uuid, text, jsonb, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_partner_notification(uuid, uuid, text, jsonb, text, text, text, text, timestamptz) to service_role;

revoke all on function internal.resolve_streak_expires_at(uuid, timestamptz) from public, anon, authenticated;
grant execute on function internal.resolve_streak_expires_at(uuid, timestamptz) to service_role;

revoke all on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) to service_role;

revoke all on function internal.record_couple_activity(text, uuid, timestamptz, text, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.record_couple_activity(text, uuid, timestamptz, text, uuid, uuid, bigint, timestamptz) to service_role;

revoke all on function internal.update_location_sharing_preference(uuid, boolean, text, text, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.update_location_sharing_preference(uuid, boolean, text, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.update_latest_partner_location(uuid, numeric, numeric, numeric, timestamptz, text, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.update_latest_partner_location(uuid, numeric, numeric, numeric, timestamptz, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.get_partner_location_visibility(uuid) from public, anon, authenticated;
grant execute on function internal.get_partner_location_visibility(uuid) to authenticated, service_role;

revoke all on function internal.claim_due_notifications(integer) from public, anon, authenticated;
grant execute on function internal.claim_due_notifications(integer) to service_role;

revoke all on function internal.mark_notification_sent(uuid, text) from public, anon, authenticated;
grant execute on function internal.mark_notification_sent(uuid, text) to service_role;

revoke all on function internal.mark_notification_failed(uuid, text, boolean) from public, anon, authenticated;
grant execute on function internal.mark_notification_failed(uuid, text, boolean) to service_role;

revoke all on function internal.enqueue_due_streak_reminders(timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_due_streak_reminders(timestamptz) to service_role;

revoke all on function internal.handle_daily_challenge_completed() from public, anon, authenticated;
grant execute on function internal.handle_daily_challenge_completed() to service_role;

revoke all on function internal.handle_widget_drawing_revision_created() from public, anon, authenticated;
grant execute on function internal.handle_widget_drawing_revision_created() to service_role;

revoke all on function internal.delete_latest_locations_on_preference_disable() from public, anon, authenticated;
grant execute on function internal.delete_latest_locations_on_preference_disable() to service_role;

revoke all on function internal.delete_latest_locations_on_relationship_end() from public, anon, authenticated;
grant execute on function internal.delete_latest_locations_on_relationship_end() to service_role;

revoke all on function public.update_location_sharing_preference(uuid, boolean, text, text, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.update_location_sharing_preference(uuid, boolean, text, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.update_latest_partner_location(uuid, numeric, numeric, numeric, timestamptz, text, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.update_latest_partner_location(uuid, numeric, numeric, numeric, timestamptz, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.get_partner_location_visibility(uuid) from public, anon;
grant execute on function public.get_partner_location_visibility(uuid) to authenticated, service_role;
