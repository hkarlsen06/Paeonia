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
  location_was_stored boolean = false;
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
    couple_id = existing_location.couple_id;
    user_id = existing_location.user_id;
    latitude = existing_location.latitude;
    longitude = existing_location.longitude;
    accuracy_m = existing_location.accuracy_m;
    captured_at = existing_location.captured_at;
    received_at = existing_location.received_at;
    updated_at = existing_location.updated_at;
  else
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
      select *
      into existing_location
      from public.latest_partner_locations latest
      where latest.couple_id = p_couple_id
        and latest.user_id = current_user_id
      for update;

      if not found then
        raise exception 'stale location update could not be resolved'
          using errcode = '40001';
      end if;

      couple_id = existing_location.couple_id;
      user_id = existing_location.user_id;
      latitude = existing_location.latitude;
      longitude = existing_location.longitude;
      accuracy_m = existing_location.accuracy_m;
      captured_at = existing_location.captured_at;
      received_at = existing_location.received_at;
      updated_at = existing_location.updated_at;
    else
      location_was_stored = true;
    end if;
  end if;

  if location_was_stored and exists (
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

notify pgrst, 'reload schema';
