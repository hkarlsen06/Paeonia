create table public.media_assets (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete restrict,
  couple_id uuid references public.couples (id) on delete restrict,
  reserved_parent_kind text not null,
  reserved_parent_id uuid not null,
  reserved_by_client_operation_id uuid not null,
  bucket text not null,
  storage_path text not null,
  media_type text not null,
  upload_purpose text not null,
  expected_media_type text not null,
  expected_bucket text not null,
  mime_type text,
  byte_size bigint,
  sha256 bytea,
  width integer,
  height integer,
  duration_ms integer,
  upload_status text not null default 'pending',
  upload_expires_at timestamptz not null,
  upload_finalized_at timestamptz,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,
  storage_delete_status text not null default 'none',
  storage_deleted_at timestamptz,
  storage_delete_attempts integer not null default 0,
  last_storage_delete_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint media_assets_reserved_parent_kind_check
    check (
      reserved_parent_kind in (
        'profile_photo',
        'memory_media',
        'daily_answer_media',
        'thread_message_media',
        'widget_drawing_revision',
        'report_snapshot'
      )
    ),
  constraint media_assets_bucket_check
    check (bucket in ('profile-photos', 'couple-media', 'widget-drawings', 'report-snapshots')),
  constraint media_assets_media_type_check
    check (media_type in ('image', 'voice', 'drawing_payload', 'report_snapshot')),
  constraint media_assets_upload_purpose_check
    check (
      upload_purpose in (
        'profile_photo',
        'memory_photo',
        'voice_note',
        'daily_answer_media',
        'thread_media',
        'widget_drawing_payload',
        'report_snapshot'
      )
    ),
  constraint media_assets_expected_media_type_check
    check (expected_media_type in ('image', 'voice', 'drawing_payload', 'report_snapshot')),
  constraint media_assets_expected_bucket_check
    check (expected_bucket in ('profile-photos', 'couple-media', 'widget-drawings', 'report-snapshots')),
  constraint media_assets_expected_contract_check
    check (bucket = expected_bucket and media_type = expected_media_type),
  constraint media_assets_storage_path_check
    check (
      char_length(storage_path) between 1 and 1024
      and storage_path !~ '(^/|//|/\./|/\.\./|\.\./|/$)'
    ),
  constraint media_assets_mime_type_check
    check (mime_type is null or char_length(btrim(mime_type)) between 1 and 255),
  constraint media_assets_byte_size_check
    check (byte_size is null or byte_size > 0),
  constraint media_assets_sha256_check
    check (sha256 is null or octet_length(sha256) = 32),
  constraint media_assets_dimensions_check
    check (
      (width is null or width > 0)
      and (height is null or height > 0)
      and (duration_ms is null or duration_ms > 0)
    ),
  constraint media_assets_upload_status_check
    check (upload_status in ('pending', 'finalized', 'failed', 'expired')),
  constraint media_assets_upload_lifecycle_check
    check (
      (
        upload_status = 'pending'
        and upload_finalized_at is null
      )
      or (
        upload_status = 'finalized'
        and upload_finalized_at is not null
        and byte_size is not null
        and mime_type is not null
        and sha256 is not null
      )
      or (
        upload_status in ('failed', 'expired')
        and upload_finalized_at is null
      )
    ),
  constraint media_assets_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected')),
  constraint media_assets_storage_delete_status_check
    check (storage_delete_status in ('none', 'pending', 'retrying', 'deleted', 'failed')),
  constraint media_assets_storage_delete_attempts_check
    check (storage_delete_attempts >= 0),
  constraint media_assets_storage_deleted_at_check
    check (
      (storage_delete_status = 'deleted' and storage_deleted_at is not null)
      or (storage_delete_status <> 'deleted')
    ),
  constraint media_assets_last_storage_delete_error_check
    check (last_storage_delete_error is null or char_length(last_storage_delete_error) <= 4000),
  constraint media_assets_deleted_storage_state_check
    check (
      deleted_at is null
      or storage_delete_status in ('pending', 'retrying', 'deleted', 'failed')
    ),
  constraint media_assets_upload_contract_check
    check (
      (
        upload_purpose = 'profile_photo'
        and reserved_parent_kind = 'profile_photo'
        and reserved_parent_id = owner_user_id
        and bucket = 'profile-photos'
        and media_type = 'image'
        and couple_id is null
      )
      or (
        upload_purpose = 'memory_photo'
        and reserved_parent_kind = 'memory_media'
        and bucket = 'couple-media'
        and media_type = 'image'
        and couple_id is not null
      )
      or (
        upload_purpose = 'voice_note'
        and reserved_parent_kind in ('memory_media', 'daily_answer_media', 'thread_message_media')
        and bucket = 'couple-media'
        and media_type = 'voice'
        and couple_id is not null
      )
      or (
        upload_purpose = 'daily_answer_media'
        and reserved_parent_kind = 'daily_answer_media'
        and bucket = 'couple-media'
        and media_type = 'image'
        and couple_id is not null
      )
      or (
        upload_purpose = 'thread_media'
        and reserved_parent_kind = 'thread_message_media'
        and bucket = 'couple-media'
        and media_type = 'image'
        and couple_id is not null
      )
      or (
        upload_purpose = 'widget_drawing_payload'
        and reserved_parent_kind = 'widget_drawing_revision'
        and bucket = 'widget-drawings'
        and media_type = 'drawing_payload'
        and couple_id is not null
      )
      or (
        upload_purpose = 'report_snapshot'
        and reserved_parent_kind = 'report_snapshot'
        and bucket = 'report-snapshots'
        and media_type = 'report_snapshot'
      )
    )
);

create trigger set_media_assets_updated_at
before update on public.media_assets
for each row
execute function internal.set_updated_at();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values
  (
    'profile-photos',
    'profile-photos',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']::text[]
  ),
  (
    'couple-media',
    'couple-media',
    false,
    52428800,
    array[
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/heif',
      'image/webp',
      'audio/mp4',
      'audio/mpeg',
      'audio/aac',
      'audio/wav',
      'audio/x-caf'
    ]::text[]
  ),
  (
    'widget-drawings',
    'widget-drawings',
    false,
    10485760,
    array['application/octet-stream', 'application/x-pkdrawing']::text[]
  ),
  (
    'report-snapshots',
    'report-snapshots',
    false,
    52428800,
    array['image/jpeg', 'image/png', 'application/pdf', 'application/json']::text[]
  )
on conflict (id) do update
set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  updated_at = now();

create or replace function internal.normalize_media_file_extension(p_file_extension text)
returns text
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  normalized_extension text;
begin
  normalized_extension = lower(btrim(coalesce(p_file_extension, '')));
  normalized_extension = regexp_replace(normalized_extension, '^\.+', '');

  if normalized_extension !~ '^[a-z0-9]{1,16}$' then
    raise exception 'file extension is not supported'
      using errcode = '22023';
  end if;

  if normalized_extension = 'jpeg' then
    return 'jpg';
  end if;

  return normalized_extension;
end;
$$;

create or replace function internal.media_extension_matches_type(
  p_media_type text,
  p_file_extension text
)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select case p_media_type
    when 'image' then p_file_extension in ('jpg', 'png', 'heic', 'heif', 'webp')
    when 'voice' then p_file_extension in ('m4a', 'mp4', 'aac', 'caf', 'wav', 'mp3')
    when 'drawing_payload' then p_file_extension = 'pkdrawing'
    when 'report_snapshot' then p_file_extension in ('jpg', 'png', 'pdf', 'json')
    else false
  end;
$$;

create or replace function internal.media_mime_matches_type(
  p_media_type text,
  p_mime_type text
)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select case p_media_type
    when 'image' then lower(btrim(p_mime_type)) in (
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/heif',
      'image/webp'
    )
    when 'voice' then lower(btrim(p_mime_type)) in (
      'audio/mp4',
      'audio/mpeg',
      'audio/aac',
      'audio/wav',
      'audio/x-caf'
    )
    when 'drawing_payload' then lower(btrim(p_mime_type)) in (
      'application/octet-stream',
      'application/x-pkdrawing'
    )
    when 'report_snapshot' then lower(btrim(p_mime_type)) in (
      'image/jpeg',
      'image/png',
      'application/pdf',
      'application/json'
    )
    else false
  end;
$$;

create or replace function internal.media_byte_limit(p_media_type text)
returns bigint
language sql
security invoker
set search_path = pg_catalog
as $$
  select case p_media_type
    when 'image' then 10485760::bigint
    when 'voice' then 52428800::bigint
    when 'drawing_payload' then 10485760::bigint
    when 'report_snapshot' then 52428800::bigint
    else 0::bigint
  end;
$$;

create or replace function internal.can_upload_reserved_media_object(
  p_bucket text,
  p_storage_path text
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.media_assets asset
    where asset.bucket = p_bucket
      and asset.storage_path = p_storage_path
      and asset.bucket <> 'report-snapshots'
      and asset.owner_user_id = (select auth.uid())
      and asset.upload_status = 'pending'
      and asset.upload_expires_at > now()
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
      and (
        asset.couple_id is null
        or internal.can_access_couple_content(asset.couple_id)
      )
  );
$$;

create or replace function internal.can_read_media_object(
  p_bucket text,
  p_storage_path text
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.media_assets asset
    where asset.bucket = p_bucket
      and asset.storage_path = p_storage_path
      and asset.bucket <> 'report-snapshots'
      and asset.upload_status = 'finalized'
      and asset.upload_finalized_at is not null
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
      and asset.bucket = 'profile-photos'
      and asset.couple_id is null
      and asset.reserved_parent_kind = 'profile_photo'
      and (
        asset.owner_user_id = (select auth.uid())
        or exists (
          select 1
          from public.profiles profile
          join public.couple_members owner_member
            on owner_member.user_id = profile.user_id
          join public.couple_members viewer_member
            on viewer_member.couple_id = owner_member.couple_id
          join public.couples couple
            on couple.id = viewer_member.couple_id
          where profile.profile_photo_asset_id = asset.id
            and profile.user_id = asset.owner_user_id
            and profile.moderation_status = 'visible'
            and profile.deleted_at is null
            and owner_member.status = 'active'
            and viewer_member.user_id = (select auth.uid())
            and viewer_member.status = 'active'
            and couple.status = 'active'
            and internal.can_access_couple_content(couple.id)
        )
      )
  );
$$;

create or replace function internal.create_pending_media_upload(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_reserved_parent_kind text,
  p_reserved_parent_id uuid,
  p_upload_purpose text,
  p_media_type text,
  p_file_extension text,
  p_couple_id uuid default null,
  p_upload_expires_at timestamptz default null,
  p_path_context jsonb default '{}'::jsonb
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  upload_expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  new_media_asset_id uuid;
  normalized_extension text;
  resolved_bucket text;
  resolved_storage_path text;
  resolved_couple_id uuid;
  resolved_upload_expires_at timestamptz;
  expiry_hash_component text;
  canvas_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_reserved_parent_id is null then
    raise exception 'reserved parent id is required'
      using errcode = '23514';
  end if;

  if p_path_context is null then
    p_path_context = '{}'::jsonb;
  end if;

  if jsonb_typeof(p_path_context) <> 'object' then
    raise exception 'path context must be an object'
      using errcode = '23514';
  end if;

  normalized_extension = internal.normalize_media_file_extension(p_file_extension);

  if not internal.media_extension_matches_type(p_media_type, normalized_extension) then
    raise exception 'file extension does not match media type'
      using errcode = '23514';
  end if;

  resolved_upload_expires_at = coalesce(p_upload_expires_at, now() + interval '1 hour');
  expiry_hash_component = case
    when p_upload_expires_at is null then 'server_generated'
    else resolved_upload_expires_at::text
  end;

  if resolved_upload_expires_at <= now() + interval '5 minutes'
    or resolved_upload_expires_at > now() + interval '24 hours' then
    raise exception 'upload expiration is out of range'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_pending_media_upload',
      p_reserved_parent_kind,
      p_reserved_parent_id::text,
      p_upload_purpose,
      p_media_type,
      normalized_extension,
      coalesce(p_couple_id::text, ''),
      expiry_hash_component,
      p_path_context::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_pending_media_upload',
    'media_assets',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'media_asset_id')::uuid,
      replayed_response ->> 'bucket',
      replayed_response ->> 'storage_path',
      (replayed_response ->> 'upload_expires_at')::timestamptz;
    return;
  end if;

  new_media_asset_id = extensions.gen_random_uuid();

  if p_upload_purpose = 'profile_photo' then
    if p_reserved_parent_kind <> 'profile_photo'
      or p_reserved_parent_id <> current_user_id
      or p_media_type <> 'image'
      or p_couple_id is not null then
      raise exception 'profile photo upload contract is invalid'
        using errcode = '23514';
    end if;

    resolved_bucket = 'profile-photos';
    resolved_couple_id = null;
    resolved_storage_path = current_user_id::text || '/' || new_media_asset_id::text || '.' || normalized_extension;
  elsif p_upload_purpose in ('memory_photo', 'voice_note', 'daily_answer_media', 'thread_media') then
    if p_couple_id is null then
      raise exception 'relationship media requires a couple id'
        using errcode = '23514';
    end if;

    if not internal.can_access_couple_content(p_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;

    if (
      p_upload_purpose = 'memory_photo'
      and not (p_reserved_parent_kind = 'memory_media' and p_media_type = 'image')
    ) or (
      p_upload_purpose = 'voice_note'
      and not (
        p_reserved_parent_kind in ('memory_media', 'daily_answer_media', 'thread_message_media')
        and p_media_type = 'voice'
      )
    ) or (
      p_upload_purpose = 'daily_answer_media'
      and not (p_reserved_parent_kind = 'daily_answer_media' and p_media_type = 'image')
    ) or (
      p_upload_purpose = 'thread_media'
      and not (p_reserved_parent_kind = 'thread_message_media' and p_media_type = 'image')
    ) then
      raise exception 'relationship media upload contract is invalid'
        using errcode = '23514';
    end if;

    resolved_bucket = 'couple-media';
    resolved_couple_id = p_couple_id;
    resolved_storage_path = p_couple_id::text || '/' || p_media_type || '/' || new_media_asset_id::text || '.' || normalized_extension;
  elsif p_upload_purpose = 'widget_drawing_payload' then
    if p_reserved_parent_kind <> 'widget_drawing_revision'
      or p_media_type <> 'drawing_payload'
      or p_couple_id is null then
      raise exception 'widget drawing upload contract is invalid'
        using errcode = '23514';
    end if;

    if not internal.can_access_couple_content(p_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;

    canvas_id = nullif(p_path_context ->> 'canvas_id', '')::uuid;

    if canvas_id is null then
      raise exception 'widget drawing uploads require a canvas id'
        using errcode = '23514';
    end if;

    resolved_bucket = 'widget-drawings';
    resolved_couple_id = p_couple_id;
    resolved_storage_path = p_couple_id::text || '/' || canvas_id::text || '/revisions/' || p_reserved_parent_id::text || '/drawing.' || normalized_extension;
  elsif p_upload_purpose = 'report_snapshot' then
    raise exception 'report snapshot uploads require a trusted service path'
      using errcode = '42501';
  else
    raise exception 'upload purpose is not supported'
      using errcode = '23514';
  end if;

  insert into public.media_assets (
    id,
    owner_user_id,
    couple_id,
    reserved_parent_kind,
    reserved_parent_id,
    reserved_by_client_operation_id,
    bucket,
    storage_path,
    media_type,
    upload_purpose,
    expected_media_type,
    expected_bucket,
    upload_status,
    upload_expires_at
  ) values (
    new_media_asset_id,
    current_user_id,
    resolved_couple_id,
    p_reserved_parent_kind,
    p_reserved_parent_id,
    p_client_operation_id,
    resolved_bucket,
    resolved_storage_path,
    p_media_type,
    p_upload_purpose,
    p_media_type,
    resolved_bucket,
    'pending',
    resolved_upload_expires_at
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'media_asset_id', new_media_asset_id,
      'bucket', resolved_bucket,
      'storage_path', resolved_storage_path,
      'upload_expires_at', resolved_upload_expires_at
    )
  );

  return query
  select
    new_media_asset_id,
    resolved_bucket,
    resolved_storage_path,
    resolved_upload_expires_at;
end;
$$;

create or replace function internal.finalize_media_upload(
  p_media_asset_id uuid,
  p_reserved_by_client_operation_id uuid,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_bucket text,
  p_storage_path text,
  p_reserved_parent_kind text,
  p_reserved_parent_id uuid,
  p_upload_purpose text,
  p_media_type text,
  p_mime_type text,
  p_byte_size bigint,
  p_sha256_hex text,
  p_width integer default null,
  p_height integer default null,
  p_duration_ms integer default null
)
returns table (
  media_asset_id uuid,
  upload_status text,
  upload_finalized_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  asset_row public.media_assets%rowtype;
  normalized_mime_type text;
  sha256_bytes bytea;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_sha256_hex is null or p_sha256_hex !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'sha256 must be a 64 character hex string'
      using errcode = '22023';
  end if;

  sha256_bytes = decode(lower(p_sha256_hex), 'hex');
  normalized_mime_type = lower(btrim(coalesce(p_mime_type, '')));

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'finalize_media_upload',
      p_media_asset_id::text,
      p_reserved_by_client_operation_id::text,
      p_bucket,
      p_storage_path,
      p_reserved_parent_kind,
      p_reserved_parent_id::text,
      p_upload_purpose,
      p_media_type,
      normalized_mime_type,
      p_byte_size::text,
      encode(sha256_bytes, 'hex'),
      coalesce(p_width::text, ''),
      coalesce(p_height::text, ''),
      coalesce(p_duration_ms::text, '')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'finalize_media_upload',
    'media_assets',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'media_asset_id')::uuid,
      replayed_response ->> 'upload_status',
      (replayed_response ->> 'upload_finalized_at')::timestamptz;
    return;
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset was not found'
      using errcode = '22023';
  end if;

  if asset_row.owner_user_id <> current_user_id then
    raise exception 'media asset is owned by another user'
      using errcode = '42501';
  end if;

  if asset_row.couple_id is not null
    and not internal.can_access_couple_content(asset_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  if asset_row.reserved_by_client_operation_id <> p_reserved_by_client_operation_id
    or asset_row.bucket <> p_bucket
    or asset_row.storage_path <> p_storage_path
    or asset_row.reserved_parent_kind <> p_reserved_parent_kind
    or asset_row.reserved_parent_id <> p_reserved_parent_id
    or asset_row.upload_purpose <> p_upload_purpose
    or asset_row.expected_media_type <> p_media_type
    or asset_row.expected_bucket <> p_bucket then
    raise exception 'finalize request does not match the reserved upload'
      using errcode = '23514';
  end if;

  if p_byte_size is null or p_byte_size <= 0 or p_byte_size > internal.media_byte_limit(p_media_type) then
    raise exception 'byte size is out of range'
      using errcode = '23514';
  end if;

  if not internal.media_mime_matches_type(p_media_type, normalized_mime_type) then
    raise exception 'mime type does not match media type'
      using errcode = '23514';
  end if;

  if p_media_type = 'image' and (p_width is null or p_height is null) then
    raise exception 'image uploads require dimensions'
      using errcode = '23514';
  end if;

  if p_media_type = 'voice' and p_duration_ms is null then
    raise exception 'voice uploads require duration'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from storage.objects object
    where object.bucket_id = asset_row.bucket
      and object.name = asset_row.storage_path
  ) then
    raise exception 'reserved storage object was not found'
      using errcode = '22023';
  end if;

  if asset_row.upload_status = 'finalized' then
    if asset_row.byte_size = p_byte_size
      and asset_row.mime_type = normalized_mime_type
      and asset_row.sha256 = sha256_bytes
      and asset_row.width is not distinct from p_width
      and asset_row.height is not distinct from p_height
      and asset_row.duration_ms is not distinct from p_duration_ms then
      perform internal.complete_client_operation(
        p_client_operation_id,
        jsonb_build_object(
          'media_asset_id', asset_row.id,
          'upload_status', asset_row.upload_status,
          'upload_finalized_at', asset_row.upload_finalized_at
        )
      );

      return query
      select asset_row.id, asset_row.upload_status, asset_row.upload_finalized_at;
      return;
    end if;

    raise exception 'finalized media metadata cannot be changed'
      using errcode = '23505';
  end if;

  if asset_row.upload_status <> 'pending' then
    raise exception 'media asset is not pending upload'
      using errcode = '23514';
  end if;

  if asset_row.upload_expires_at <= now() then
    update public.media_assets
    set upload_status = 'expired'
    where id = asset_row.id;

    raise exception 'media upload reservation is expired'
      using errcode = '22023';
  end if;

  if asset_row.deleted_at is not null or asset_row.storage_delete_status <> 'none' then
    raise exception 'media asset is queued for deletion'
      using errcode = '23514';
  end if;

  update public.media_assets
  set
    upload_status = 'finalized',
    mime_type = normalized_mime_type,
    byte_size = p_byte_size,
    sha256 = sha256_bytes,
    width = p_width,
    height = p_height,
    duration_ms = p_duration_ms,
    upload_finalized_at = now()
  where id = asset_row.id
  returning * into asset_row;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'media_asset_id', asset_row.id,
      'upload_status', asset_row.upload_status,
      'upload_finalized_at', asset_row.upload_finalized_at
    )
  );

  return query
  select asset_row.id, asset_row.upload_status, asset_row.upload_finalized_at;
end;
$$;

create or replace function internal.mark_media_for_deletion(p_media_asset_id uuid)
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

  update public.media_assets
  set
    deleted_at = coalesce(deleted_at, now()),
    storage_delete_status = case
      when storage_delete_status = 'deleted' then 'deleted'
      when storage_delete_status in ('pending', 'retrying') then storage_delete_status
      else 'pending'
    end,
    last_storage_delete_error = null
  where id = p_media_asset_id
    and owner_user_id = current_user_id
    and bucket = 'profile-photos'
    and couple_id is null
    and reserved_parent_kind = 'profile_photo'
    and bucket <> 'report-snapshots'
    and storage_delete_status <> 'deleted';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.get_media_signed_url(
  p_media_asset_id uuid,
  p_expires_in_seconds integer default 900
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  expires_in_seconds integer,
  signed_url_expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  asset_row public.media_assets%rowtype;
  resolved_expires_in_seconds integer;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  resolved_expires_in_seconds = coalesce(p_expires_in_seconds, 900);

  if resolved_expires_in_seconds < 60 or resolved_expires_in_seconds > 3600 then
    raise exception 'signed URL expiration is out of range'
      using errcode = '23514';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = p_media_asset_id;

  if not found or not internal.can_read_media_object(asset_row.bucket, asset_row.storage_path) then
    raise exception 'media asset is not available'
      using errcode = '42501';
  end if;

  return query
  select
    asset_row.id,
    asset_row.bucket,
    asset_row.storage_path,
    resolved_expires_in_seconds,
    now() + make_interval(secs => resolved_expires_in_seconds);
end;
$$;

create or replace function internal.assert_profile_photo_asset_owner()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  asset_row public.media_assets%rowtype;
begin
  if new.profile_photo_asset_id is null then
    return new;
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.profile_photo_asset_id;

  if not found then
    raise exception 'profile photo asset was not found'
      using errcode = '23503';
  end if;

  if asset_row.owner_user_id <> new.user_id
    or asset_row.bucket <> 'profile-photos'
    or asset_row.media_type <> 'image'
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'profile photo asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.create_pending_media_upload(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_reserved_parent_kind text,
  p_reserved_parent_id uuid,
  p_upload_purpose text,
  p_media_type text,
  p_file_extension text,
  p_couple_id uuid default null,
  p_upload_expires_at timestamptz default null,
  p_path_context jsonb default '{}'::jsonb
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  upload_expires_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.create_pending_media_upload(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_reserved_parent_kind,
    p_reserved_parent_id,
    p_upload_purpose,
    p_media_type,
    p_file_extension,
    p_couple_id,
    p_upload_expires_at,
    p_path_context
  );
$$;

create or replace function public.finalize_media_upload(
  p_media_asset_id uuid,
  p_reserved_by_client_operation_id uuid,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_bucket text,
  p_storage_path text,
  p_reserved_parent_kind text,
  p_reserved_parent_id uuid,
  p_upload_purpose text,
  p_media_type text,
  p_mime_type text,
  p_byte_size bigint,
  p_sha256_hex text,
  p_width integer default null,
  p_height integer default null,
  p_duration_ms integer default null
)
returns table (
  media_asset_id uuid,
  upload_status text,
  upload_finalized_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.finalize_media_upload(
    p_media_asset_id,
    p_reserved_by_client_operation_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_bucket,
    p_storage_path,
    p_reserved_parent_kind,
    p_reserved_parent_id,
    p_upload_purpose,
    p_media_type,
    p_mime_type,
    p_byte_size,
    p_sha256_hex,
    p_width,
    p_height,
    p_duration_ms
  );
$$;

create or replace function public.mark_media_for_deletion(p_media_asset_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_media_for_deletion(p_media_asset_id);
$$;

create or replace function public.get_media_signed_url(
  p_media_asset_id uuid,
  p_expires_in_seconds integer default 900
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  expires_in_seconds integer,
  signed_url_expires_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_media_signed_url(p_media_asset_id, p_expires_in_seconds);
$$;

comment on function public.get_media_signed_url(uuid, integer)
is 'Authorizes the caller for a media asset and returns its private Storage bucket/path. Supabase Storage downloads and signed URL creation are gated by the matching storage.objects SELECT policy.';

alter table public.profiles
add constraint profiles_profile_photo_asset_id_fkey
foreign key (profile_photo_asset_id)
references public.media_assets (id)
on delete set null;

create trigger assert_profiles_profile_photo_asset_owner
before insert or update of profile_photo_asset_id on public.profiles
for each row
execute function internal.assert_profile_photo_asset_owner();

alter table public.media_assets enable row level security;

create policy paeonia_media_pending_upload_insert
on storage.objects
for insert
to authenticated
with check (internal.can_upload_reserved_media_object(bucket_id, name));

create policy paeonia_media_visible_select
on storage.objects
for select
to authenticated
using (internal.can_read_media_object(bucket_id, name));

create index media_assets_owner_created_at_idx
on public.media_assets (owner_user_id, created_at desc);

create index media_assets_couple_created_at_idx
on public.media_assets (couple_id, created_at desc);

create unique index media_assets_bucket_storage_path_unique_idx
on public.media_assets (bucket, storage_path);

create index media_assets_upload_status_expires_at_idx
on public.media_assets (upload_status, upload_expires_at);

create index media_assets_storage_delete_retry_idx
on public.media_assets (storage_delete_status, storage_delete_attempts, updated_at);

create index media_assets_reserved_parent_idx
on public.media_assets (reserved_parent_kind, reserved_parent_id);

create index media_assets_sha256_idx
on public.media_assets (sha256)
where sha256 is not null;

create index media_assets_moderated_by_idx
on public.media_assets (moderated_by)
where moderated_by is not null;

create index profiles_profile_photo_asset_id_idx
on public.profiles (profile_photo_asset_id)
where profile_photo_asset_id is not null;

revoke all on public.media_assets from public, anon, authenticated;
grant all privileges on public.media_assets to service_role;

grant usage on schema internal to authenticated;

revoke all on function internal.normalize_media_file_extension(text) from public, anon, authenticated;
grant execute on function internal.normalize_media_file_extension(text) to service_role;

revoke all on function internal.media_extension_matches_type(text, text) from public, anon, authenticated;
grant execute on function internal.media_extension_matches_type(text, text) to service_role;

revoke all on function internal.media_mime_matches_type(text, text) from public, anon, authenticated;
grant execute on function internal.media_mime_matches_type(text, text) to service_role;

revoke all on function internal.media_byte_limit(text) from public, anon, authenticated;
grant execute on function internal.media_byte_limit(text) to service_role;

revoke all on function internal.can_upload_reserved_media_object(text, text) from public, anon, authenticated;
grant execute on function internal.can_upload_reserved_media_object(text, text) to authenticated, service_role;

revoke all on function internal.can_read_media_object(text, text) from public, anon, authenticated;
grant execute on function internal.can_read_media_object(text, text) to authenticated, service_role;

revoke all on function internal.create_pending_media_upload(uuid, uuid, bigint, timestamptz, text, uuid, text, text, text, uuid, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function internal.create_pending_media_upload(uuid, uuid, bigint, timestamptz, text, uuid, text, text, text, uuid, timestamptz, jsonb) to authenticated, service_role;

revoke all on function internal.finalize_media_upload(uuid, uuid, uuid, uuid, bigint, timestamptz, text, text, text, uuid, text, text, text, bigint, text, integer, integer, integer) from public, anon, authenticated;
grant execute on function internal.finalize_media_upload(uuid, uuid, uuid, uuid, bigint, timestamptz, text, text, text, uuid, text, text, text, bigint, text, integer, integer, integer) to authenticated, service_role;

revoke all on function internal.mark_media_for_deletion(uuid) from public, anon, authenticated;
grant execute on function internal.mark_media_for_deletion(uuid) to authenticated, service_role;

revoke all on function internal.get_media_signed_url(uuid, integer) from public, anon, authenticated;
grant execute on function internal.get_media_signed_url(uuid, integer) to authenticated, service_role;

revoke all on function internal.assert_profile_photo_asset_owner() from public, anon, authenticated;
grant execute on function internal.assert_profile_photo_asset_owner() to service_role;

revoke all on function public.create_pending_media_upload(uuid, uuid, bigint, timestamptz, text, uuid, text, text, text, uuid, timestamptz, jsonb) from public, anon;
grant execute on function public.create_pending_media_upload(uuid, uuid, bigint, timestamptz, text, uuid, text, text, text, uuid, timestamptz, jsonb) to authenticated, service_role;

revoke all on function public.finalize_media_upload(uuid, uuid, uuid, uuid, bigint, timestamptz, text, text, text, uuid, text, text, text, bigint, text, integer, integer, integer) from public, anon;
grant execute on function public.finalize_media_upload(uuid, uuid, uuid, uuid, bigint, timestamptz, text, text, text, uuid, text, text, text, bigint, text, integer, integer, integer) to authenticated, service_role;

revoke all on function public.mark_media_for_deletion(uuid) from public, anon;
grant execute on function public.mark_media_for_deletion(uuid) to authenticated, service_role;

revoke all on function public.get_media_signed_url(uuid, integer) from public, anon;
grant execute on function public.get_media_signed_url(uuid, integer) to authenticated, service_role;
