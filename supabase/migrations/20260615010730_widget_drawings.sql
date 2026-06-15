create table public.widget_canvases (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  active_revision_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint widget_canvases_couple_id_unique
    unique (couple_id)
);

create trigger set_widget_canvases_updated_at
before update on public.widget_canvases
for each row
execute function internal.set_updated_at();

create table public.widget_drawing_revisions (
  id uuid primary key default extensions.gen_random_uuid(),
  canvas_id uuid not null references public.widget_canvases (id) on delete restrict,
  author_user_id uuid not null references auth.users (id) on delete restrict,
  parent_revision_id uuid references public.widget_drawing_revisions (id) on delete restrict,
  format text not null default 'pkdrawing',
  format_version integer not null default 1,
  payload_media_asset_id uuid not null references public.media_assets (id) on delete restrict,
  payload_bytes bigint not null,
  uncompressed_bytes bigint not null,
  compression text not null default 'none',
  stroke_count integer,
  point_count integer,
  bounds jsonb,
  renderer_version integer not null default 1,
  client_decode_validated_at timestamptz not null,
  client_renderer_version text not null,
  client_validation_version text not null,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint widget_drawing_revisions_payload_asset_unique
    unique (payload_media_asset_id),
  constraint widget_drawing_revisions_format_check
    check (format = 'pkdrawing'),
  constraint widget_drawing_revisions_format_version_check
    check (format_version = 1),
  constraint widget_drawing_revisions_payload_bytes_check
    check (payload_bytes between 1 and 2097152),
  constraint widget_drawing_revisions_uncompressed_bytes_check
    check (uncompressed_bytes between 1 and 2097152),
  constraint widget_drawing_revisions_compression_check
    check (compression in ('none', 'gzip')),
  constraint widget_drawing_revisions_uncompressed_contract_check
    check (
      (compression = 'none' and uncompressed_bytes = payload_bytes)
      or (compression = 'gzip' and uncompressed_bytes >= payload_bytes)
    ),
  constraint widget_drawing_revisions_stroke_count_check
    check (stroke_count is null or stroke_count between 0 and 5000),
  constraint widget_drawing_revisions_point_count_check
    check (point_count is null or point_count between 0 and 200000),
  constraint widget_drawing_revisions_bounds_check
    check (
      bounds is null
      or (
        jsonb_typeof(bounds) = 'object'
        and octet_length(bounds::text) <= 2048
      )
    ),
  constraint widget_drawing_revisions_renderer_version_check
    check (renderer_version > 0),
  constraint widget_drawing_revisions_client_renderer_version_check
    check (char_length(btrim(client_renderer_version)) between 1 and 80),
  constraint widget_drawing_revisions_client_validation_version_check
    check (char_length(btrim(client_validation_version)) between 1 and 80),
  constraint widget_drawing_revisions_client_decode_validated_at_check
    check (client_decode_validated_at <= now() + interval '5 minutes'),
  constraint widget_drawing_revisions_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger set_widget_drawing_revisions_updated_at
before update on public.widget_drawing_revisions
for each row
execute function internal.set_updated_at();

alter table public.widget_canvases
add constraint widget_canvases_active_revision_id_fkey
foreign key (active_revision_id)
references public.widget_drawing_revisions (id)
on delete restrict;

create or replace function internal.assert_widget_canvas_couple_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if not exists (
    select 1
    from public.couples couple
    where couple.id = new.couple_id
      and couple.status = 'active'
  ) then
    raise exception 'widget canvas requires an active couple'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_widget_canvas_couple_allowed
before insert or update of couple_id, deleted_at on public.widget_canvases
for each row
execute function internal.assert_widget_canvas_couple_allowed();

create or replace function internal.assert_widget_canvas_active_revision_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.active_revision_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.widget_drawing_revisions revision
    where revision.id = new.active_revision_id
      and revision.canvas_id = new.id
      and revision.deleted_at is null
      and revision.moderation_status = 'visible'
  ) then
    raise exception 'active widget revision must be a visible revision for the same canvas'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_widget_canvas_active_revision_allowed
before insert or update of active_revision_id on public.widget_canvases
for each row
execute function internal.assert_widget_canvas_active_revision_allowed();

create or replace function internal.assert_widget_drawing_revision_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canvas_row public.widget_canvases%rowtype;
  parent_canvas_id uuid;
  asset_row public.media_assets%rowtype;
  expected_storage_path text;
begin
  select *
  into canvas_row
  from public.widget_canvases
  where id = new.canvas_id;

  if not found
    or canvas_row.deleted_at is not null
    or not internal.can_access_couple_content(canvas_row.couple_id) then
    raise exception 'active entitled widget canvas access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = canvas_row.couple_id
      and member.user_id = new.author_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'widget revision author must be an active couple member'
      using errcode = '23514';
  end if;

  if new.parent_revision_id is not null then
    select parent.canvas_id
    into parent_canvas_id
    from public.widget_drawing_revisions parent
    where parent.id = new.parent_revision_id;

    if parent_canvas_id is distinct from new.canvas_id then
      raise exception 'parent widget revision must belong to the same canvas'
        using errcode = '23514';
    end if;
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.payload_media_asset_id;

  expected_storage_path = canvas_row.couple_id::text || '/'
    || new.canvas_id::text
    || '/revisions/'
    || new.id::text
    || '/drawing.pkdrawing';

  if not found
    or asset_row.owner_user_id <> new.author_user_id
    or asset_row.couple_id <> canvas_row.couple_id
    or asset_row.reserved_parent_kind <> 'widget_drawing_revision'
    or asset_row.reserved_parent_id <> new.id
    or asset_row.bucket <> 'widget-drawings'
    or asset_row.storage_path <> expected_storage_path
    or asset_row.media_type <> 'drawing_payload'
    or asset_row.upload_purpose <> 'widget_drawing_payload'
    or asset_row.expected_media_type <> 'drawing_payload'
    or asset_row.expected_bucket <> 'widget-drawings'
    or asset_row.upload_status <> 'finalized'
    or asset_row.upload_finalized_at is null
    or asset_row.byte_size <> new.payload_bytes
    or asset_row.byte_size > 2097152
    or asset_row.sha256 is null
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'widget drawing payload asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_widget_drawing_revision_allowed
before insert or update of canvas_id, author_user_id, parent_revision_id, payload_media_asset_id, payload_bytes on public.widget_drawing_revisions
for each row
execute function internal.assert_widget_drawing_revision_allowed();

create or replace function internal.get_or_create_widget_canvas(p_couple_id uuid default null)
returns table (
  canvas_id uuid,
  couple_id uuid,
  active_revision_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  if p_couple_id is null then
    resolved_couple_id = internal.get_current_entitled_couple_id();
  else
    resolved_couple_id = p_couple_id;

    if not internal.can_access_couple_content(resolved_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'widget_canvas:' || resolved_couple_id::text,
      0
    )
  );

  insert into public.widget_canvases (couple_id)
  values (resolved_couple_id)
  on conflict on constraint widget_canvases_couple_id_unique do nothing;

  return query
  select
    canvas.id,
    canvas.couple_id,
    canvas.active_revision_id,
    canvas.created_at,
    canvas.updated_at
  from public.widget_canvases canvas
  where canvas.couple_id = resolved_couple_id
    and canvas.deleted_at is null;
end;
$$;

create or replace function internal.submit_widget_drawing_revision(
  p_canvas_id uuid,
  p_payload_media_asset_id uuid,
  p_parent_revision_id uuid,
  p_payload_bytes bigint,
  p_uncompressed_bytes bigint,
  p_compression text,
  p_stroke_count integer,
  p_point_count integer,
  p_bounds jsonb,
  p_sha256_hex text,
  p_client_decode_validated_at timestamptz,
  p_client_renderer_version text,
  p_client_validation_version text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  canvas_id uuid,
  revision_id uuid,
  active_revision_id uuid,
  payload_media_asset_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  canvas_row public.widget_canvases%rowtype;
  asset_row public.media_assets%rowtype;
  inserted_revision public.widget_drawing_revisions%rowtype;
  resolved_revision_id uuid;
  normalized_compression text;
  normalized_client_renderer_version text;
  normalized_client_validation_version text;
  resolved_uncompressed_bytes bigint;
  sha256_bytes bytea;
  expected_storage_path text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_canvas_id is null or p_payload_media_asset_id is null then
    raise exception 'widget canvas and payload asset are required'
      using errcode = '23514';
  end if;

  normalized_compression = lower(btrim(coalesce(p_compression, 'none')));
  if normalized_compression not in ('none', 'gzip') then
    raise exception 'widget drawing compression is not supported'
      using errcode = '23514';
  end if;

  if p_payload_bytes is null or p_payload_bytes <= 0 or p_payload_bytes > 2097152 then
    raise exception 'widget drawing payload bytes are out of range'
      using errcode = '23514';
  end if;

  resolved_uncompressed_bytes = coalesce(p_uncompressed_bytes, p_payload_bytes);

  if resolved_uncompressed_bytes <= 0 or resolved_uncompressed_bytes > 2097152 then
    raise exception 'widget drawing uncompressed bytes are out of range'
      using errcode = '23514';
  end if;

  if (
    normalized_compression = 'none'
    and resolved_uncompressed_bytes <> p_payload_bytes
  ) or (
    normalized_compression = 'gzip'
    and resolved_uncompressed_bytes < p_payload_bytes
  ) then
    raise exception 'widget drawing compression metadata is invalid'
      using errcode = '23514';
  end if;

  if p_stroke_count is not null and (p_stroke_count < 0 or p_stroke_count > 5000) then
    raise exception 'widget drawing stroke count is out of range'
      using errcode = '23514';
  end if;

  if p_point_count is not null and (p_point_count < 0 or p_point_count > 200000) then
    raise exception 'widget drawing point count is out of range'
      using errcode = '23514';
  end if;

  if p_bounds is not null
    and (
      jsonb_typeof(p_bounds) <> 'object'
      or octet_length(p_bounds::text) > 2048
    ) then
    raise exception 'widget drawing bounds metadata is invalid'
      using errcode = '23514';
  end if;

  if p_sha256_hex is null or p_sha256_hex !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'widget drawing sha256 must be a 64 character hex string'
      using errcode = '22023';
  end if;

  sha256_bytes = decode(lower(p_sha256_hex), 'hex');
  normalized_client_renderer_version = nullif(btrim(coalesce(p_client_renderer_version, '')), '');
  normalized_client_validation_version = nullif(btrim(coalesce(p_client_validation_version, '')), '');

  if normalized_client_renderer_version is null
    or char_length(normalized_client_renderer_version) > 80
    or normalized_client_validation_version is null
    or char_length(normalized_client_validation_version) > 80 then
    raise exception 'widget drawing client validation metadata is invalid'
      using errcode = '23514';
  end if;

  if p_client_decode_validated_at is null
    or p_client_decode_validated_at > now() + interval '5 minutes' then
    raise exception 'widget drawing client decode validation timestamp is invalid'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'submit_widget_drawing_revision',
      p_canvas_id::text,
      p_payload_media_asset_id::text,
      coalesce(p_parent_revision_id::text, ''),
      p_payload_bytes::text,
      resolved_uncompressed_bytes::text,
      normalized_compression,
      coalesce(p_stroke_count::text, ''),
      coalesce(p_point_count::text, ''),
      coalesce(p_bounds::text, ''),
      encode(sha256_bytes, 'hex'),
      p_client_decode_validated_at::text,
      normalized_client_renderer_version,
      normalized_client_validation_version
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'submit_widget_drawing_revision',
    'widget',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'canvas_id')::uuid,
      (replayed_response ->> 'revision_id')::uuid,
      (replayed_response ->> 'active_revision_id')::uuid,
      (replayed_response ->> 'payload_media_asset_id')::uuid,
      (replayed_response ->> 'created_at')::timestamptz,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into canvas_row
  from public.widget_canvases
  where id = p_canvas_id
  for update;

  if not found
    or canvas_row.deleted_at is not null
    or not internal.can_access_couple_content(canvas_row.couple_id) then
    raise exception 'active entitled widget canvas access is required'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'widget_canvas_revision:' || canvas_row.id::text,
      0
    )
  );

  if canvas_row.active_revision_id is distinct from p_parent_revision_id then
    raise exception 'widget drawing parent revision conflict'
      using errcode = '40001';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = p_payload_media_asset_id
  for update;

  if not found then
    raise exception 'widget drawing payload asset was not found'
      using errcode = '22023';
  end if;

  resolved_revision_id = asset_row.reserved_parent_id;
  expected_storage_path = canvas_row.couple_id::text || '/'
    || canvas_row.id::text
    || '/revisions/'
    || resolved_revision_id::text
    || '/drawing.pkdrawing';

  if asset_row.owner_user_id <> current_user_id
    or asset_row.couple_id <> canvas_row.couple_id
    or asset_row.reserved_parent_kind <> 'widget_drawing_revision'
    or asset_row.bucket <> 'widget-drawings'
    or asset_row.storage_path <> expected_storage_path
    or asset_row.media_type <> 'drawing_payload'
    or asset_row.upload_purpose <> 'widget_drawing_payload'
    or asset_row.expected_media_type <> 'drawing_payload'
    or asset_row.expected_bucket <> 'widget-drawings'
    or asset_row.upload_status <> 'finalized'
    or asset_row.upload_finalized_at is null
    or asset_row.byte_size <> p_payload_bytes
    or asset_row.byte_size > 2097152
    or asset_row.mime_type not in ('application/octet-stream', 'application/x-pkdrawing')
    or asset_row.sha256 <> sha256_bytes
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'widget drawing payload asset is not usable'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.widget_drawing_revisions existing_revision
    where existing_revision.id = resolved_revision_id
      or existing_revision.payload_media_asset_id = asset_row.id
  ) then
    raise exception 'widget drawing payload asset was already saved'
      using errcode = '23505';
  end if;

  insert into public.widget_drawing_revisions (
    id,
    canvas_id,
    author_user_id,
    parent_revision_id,
    payload_media_asset_id,
    payload_bytes,
    uncompressed_bytes,
    compression,
    stroke_count,
    point_count,
    bounds,
    client_decode_validated_at,
    client_renderer_version,
    client_validation_version
  ) values (
    resolved_revision_id,
    canvas_row.id,
    current_user_id,
    p_parent_revision_id,
    asset_row.id,
    p_payload_bytes,
    resolved_uncompressed_bytes,
    normalized_compression,
    p_stroke_count,
    p_point_count,
    p_bounds,
    p_client_decode_validated_at,
    normalized_client_renderer_version,
    normalized_client_validation_version
  )
  returning * into inserted_revision;

  update public.widget_canvases canvas
  set active_revision_id = inserted_revision.id
  where canvas.id = canvas_row.id
  returning canvas.active_revision_id, canvas.updated_at
  into active_revision_id, updated_at;

  canvas_id = canvas_row.id;
  revision_id = inserted_revision.id;
  payload_media_asset_id = inserted_revision.payload_media_asset_id;
  created_at = inserted_revision.created_at;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'canvas_id', canvas_id,
      'revision_id', revision_id,
      'active_revision_id', active_revision_id,
      'payload_media_asset_id', payload_media_asset_id,
      'created_at', created_at,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;

create or replace function internal.get_widget_canvas(p_couple_id uuid default null)
returns table (
  canvas_id uuid,
  couple_id uuid,
  active_revision_id uuid,
  active_revision_moderation_status text,
  active_revision_deleted_at timestamptz,
  active_revision_author_user_id uuid,
  payload_media_asset_id uuid,
  payload_bucket text,
  payload_storage_path text,
  payload_sha256_hex text,
  payload_bytes bigint,
  uncompressed_bytes bigint,
  compression text,
  stroke_count integer,
  point_count integer,
  bounds jsonb,
  format text,
  format_version integer,
  renderer_version integer,
  client_decode_validated_at timestamptz,
  client_renderer_version text,
  client_validation_version text,
  revision_created_at timestamptz,
  canvas_created_at timestamptz,
  canvas_updated_at timestamptz,
  sync_updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  if p_couple_id is null then
    resolved_couple_id = internal.get_current_entitled_couple_id();
  else
    resolved_couple_id = p_couple_id;

    if not internal.can_access_couple_content(resolved_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;
  end if;

  return query
  select
    canvas.id,
    canvas.couple_id,
    canvas.active_revision_id,
    revision.moderation_status,
    revision.deleted_at,
    case when visible_payload.is_visible then revision.author_user_id end,
    case when visible_payload.is_visible then revision.payload_media_asset_id end,
    case when visible_payload.is_visible then asset.bucket end,
    case when visible_payload.is_visible then asset.storage_path end,
    case when visible_payload.is_visible then encode(asset.sha256, 'hex') end,
    case when visible_payload.is_visible then revision.payload_bytes end,
    case when visible_payload.is_visible then revision.uncompressed_bytes end,
    case when visible_payload.is_visible then revision.compression end,
    case when visible_payload.is_visible then revision.stroke_count end,
    case when visible_payload.is_visible then revision.point_count end,
    case when visible_payload.is_visible then revision.bounds end,
    case when visible_payload.is_visible then revision.format end,
    case when visible_payload.is_visible then revision.format_version end,
    case when visible_payload.is_visible then revision.renderer_version end,
    case when visible_payload.is_visible then revision.client_decode_validated_at end,
    case when visible_payload.is_visible then revision.client_renderer_version end,
    case when visible_payload.is_visible then revision.client_validation_version end,
    case when visible_payload.is_visible then revision.created_at end,
    canvas.created_at,
    canvas.updated_at,
    greatest(
      canvas.updated_at,
      coalesce(revision.updated_at, '-infinity'::timestamptz),
      coalesce(asset.updated_at, '-infinity'::timestamptz)
    )
  from public.widget_canvases canvas
  left join public.widget_drawing_revisions revision
    on revision.id = canvas.active_revision_id
  left join public.media_assets asset
    on asset.id = revision.payload_media_asset_id
  cross join lateral (
    select coalesce(
      revision.id is not null
      and revision.deleted_at is null
      and revision.moderation_status = 'visible'
      and asset.id is not null
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null,
      false
    ) as is_visible
  ) visible_payload
  where canvas.couple_id = resolved_couple_id
    and canvas.deleted_at is null;
end;
$$;

create or replace function internal.get_widget_drawing_revisions(
  p_canvas_id uuid,
  p_updated_after timestamptz default null,
  p_limit integer default 100,
  p_updated_after_revision_id uuid default null,
  p_created_before timestamptz default null,
  p_created_before_revision_id uuid default null
)
returns table (
  canvas_id uuid,
  revision_id uuid,
  author_user_id uuid,
  parent_revision_id uuid,
  moderation_status text,
  deleted_at timestamptz,
  payload_media_asset_id uuid,
  payload_bucket text,
  payload_storage_path text,
  payload_sha256_hex text,
  payload_bytes bigint,
  uncompressed_bytes bigint,
  compression text,
  stroke_count integer,
  point_count integer,
  bounds jsonb,
  format text,
  format_version integer,
  renderer_version integer,
  client_decode_validated_at timestamptz,
  client_renderer_version text,
  client_validation_version text,
  created_at timestamptz,
  updated_at timestamptz,
  sync_updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'widget drawing revision read limit is out of range'
      using errcode = '23514';
  end if;

  if p_updated_after is not null and p_created_before is not null then
    raise exception 'widget drawing sync and history cursors cannot be combined'
      using errcode = '23514';
  end if;

  if (p_updated_after is null) <> (p_updated_after_revision_id is null) then
    raise exception 'widget drawing sync cursor requires timestamp and revision id'
      using errcode = '23514';
  end if;

  if (p_created_before is null) <> (p_created_before_revision_id is null) then
    raise exception 'widget drawing history cursor requires timestamp and revision id'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.widget_canvases canvas
    where canvas.id = p_canvas_id
      and canvas.deleted_at is null
      and internal.can_access_couple_content(canvas.couple_id)
  ) then
    raise exception 'active entitled widget canvas access is required'
      using errcode = '42501';
  end if;

  if p_updated_after is not null then
    return query
    with revision_rows as (
      select
        revision.canvas_id as row_canvas_id,
        revision.id as row_revision_id,
        revision.author_user_id as row_author_user_id,
        revision.parent_revision_id as row_parent_revision_id,
        revision.moderation_status as row_moderation_status,
        revision.deleted_at as row_deleted_at,
        case when visible_payload.is_visible then revision.payload_media_asset_id end as row_payload_media_asset_id,
        case when visible_payload.is_visible then asset.bucket end as row_payload_bucket,
        case when visible_payload.is_visible then asset.storage_path end as row_payload_storage_path,
        case when visible_payload.is_visible then encode(asset.sha256, 'hex') end as row_payload_sha256_hex,
        case when visible_payload.is_visible then revision.payload_bytes end as row_payload_bytes,
        case when visible_payload.is_visible then revision.uncompressed_bytes end as row_uncompressed_bytes,
        case when visible_payload.is_visible then revision.compression end as row_compression,
        case when visible_payload.is_visible then revision.stroke_count end as row_stroke_count,
        case when visible_payload.is_visible then revision.point_count end as row_point_count,
        case when visible_payload.is_visible then revision.bounds end as row_bounds,
        case when visible_payload.is_visible then revision.format end as row_format,
        case when visible_payload.is_visible then revision.format_version end as row_format_version,
        case when visible_payload.is_visible then revision.renderer_version end as row_renderer_version,
        case when visible_payload.is_visible then revision.client_decode_validated_at end as row_client_decode_validated_at,
        case when visible_payload.is_visible then revision.client_renderer_version end as row_client_renderer_version,
        case when visible_payload.is_visible then revision.client_validation_version end as row_client_validation_version,
        revision.created_at as row_created_at,
        revision.updated_at as row_updated_at,
        greatest(revision.updated_at, coalesce(asset.updated_at, '-infinity'::timestamptz)) as row_sync_updated_at
      from public.widget_drawing_revisions revision
      join public.media_assets asset
        on asset.id = revision.payload_media_asset_id
      cross join lateral (
        select (
          revision.deleted_at is null
          and revision.moderation_status = 'visible'
          and asset.upload_status = 'finalized'
          and asset.storage_delete_status = 'none'
          and asset.moderation_status = 'visible'
          and asset.deleted_at is null
        ) as is_visible
      ) visible_payload
      where revision.canvas_id = p_canvas_id
    )
    select
      row_canvas_id,
      row_revision_id,
      row_author_user_id,
      row_parent_revision_id,
      row_moderation_status,
      row_deleted_at,
      row_payload_media_asset_id,
      row_payload_bucket,
      row_payload_storage_path,
      row_payload_sha256_hex,
      row_payload_bytes,
      row_uncompressed_bytes,
      row_compression,
      row_stroke_count,
      row_point_count,
      row_bounds,
      row_format,
      row_format_version,
      row_renderer_version,
      row_client_decode_validated_at,
      row_client_renderer_version,
      row_client_validation_version,
      row_created_at,
      row_updated_at,
      row_sync_updated_at
    from revision_rows
    where row_sync_updated_at > p_updated_after
      or (
        row_sync_updated_at = p_updated_after
        and row_revision_id > p_updated_after_revision_id
      )
    order by row_sync_updated_at, row_revision_id
    limit p_limit;

    return;
  end if;

  return query
  with revision_rows as (
    select
      revision.canvas_id as row_canvas_id,
      revision.id as row_revision_id,
      revision.author_user_id as row_author_user_id,
      revision.parent_revision_id as row_parent_revision_id,
      revision.moderation_status as row_moderation_status,
      revision.deleted_at as row_deleted_at,
      case when visible_payload.is_visible then revision.payload_media_asset_id end as row_payload_media_asset_id,
      case when visible_payload.is_visible then asset.bucket end as row_payload_bucket,
      case when visible_payload.is_visible then asset.storage_path end as row_payload_storage_path,
      case when visible_payload.is_visible then encode(asset.sha256, 'hex') end as row_payload_sha256_hex,
      case when visible_payload.is_visible then revision.payload_bytes end as row_payload_bytes,
      case when visible_payload.is_visible then revision.uncompressed_bytes end as row_uncompressed_bytes,
      case when visible_payload.is_visible then revision.compression end as row_compression,
      case when visible_payload.is_visible then revision.stroke_count end as row_stroke_count,
      case when visible_payload.is_visible then revision.point_count end as row_point_count,
      case when visible_payload.is_visible then revision.bounds end as row_bounds,
      case when visible_payload.is_visible then revision.format end as row_format,
      case when visible_payload.is_visible then revision.format_version end as row_format_version,
      case when visible_payload.is_visible then revision.renderer_version end as row_renderer_version,
      case when visible_payload.is_visible then revision.client_decode_validated_at end as row_client_decode_validated_at,
      case when visible_payload.is_visible then revision.client_renderer_version end as row_client_renderer_version,
      case when visible_payload.is_visible then revision.client_validation_version end as row_client_validation_version,
      revision.created_at as row_created_at,
      revision.updated_at as row_updated_at,
      greatest(revision.updated_at, coalesce(asset.updated_at, '-infinity'::timestamptz)) as row_sync_updated_at
    from public.widget_drawing_revisions revision
    join public.media_assets asset
      on asset.id = revision.payload_media_asset_id
    cross join lateral (
      select (
        revision.deleted_at is null
        and revision.moderation_status = 'visible'
        and asset.upload_status = 'finalized'
        and asset.storage_delete_status = 'none'
        and asset.moderation_status = 'visible'
        and asset.deleted_at is null
      ) as is_visible
    ) visible_payload
    where revision.canvas_id = p_canvas_id
  )
  select
    row_canvas_id,
    row_revision_id,
    row_author_user_id,
    row_parent_revision_id,
    row_moderation_status,
    row_deleted_at,
    row_payload_media_asset_id,
    row_payload_bucket,
    row_payload_storage_path,
    row_payload_sha256_hex,
    row_payload_bytes,
    row_uncompressed_bytes,
    row_compression,
    row_stroke_count,
    row_point_count,
    row_bounds,
    row_format,
    row_format_version,
    row_renderer_version,
    row_client_decode_validated_at,
    row_client_renderer_version,
    row_client_validation_version,
    row_created_at,
    row_updated_at,
    row_sync_updated_at
  from revision_rows
  where p_created_before is null
    or row_created_at < p_created_before
    or (
      row_created_at = p_created_before
      and row_revision_id < p_created_before_revision_id
    )
  order by row_created_at desc, row_revision_id desc
  limit p_limit;
end;
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
      and (
        (
          asset.bucket = 'profile-photos'
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
        )
        or (
          asset.reserved_parent_kind = 'daily_answer_media'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.daily_answer_media answer_media
            join public.daily_question_answers answer
              on answer.id = answer_media.answer_id
            where answer_media.media_asset_id = asset.id
              and internal.can_view_daily_answer(answer.id)
          )
        )
        or (
          asset.reserved_parent_kind = 'thread_message_media'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.thread_message_media message_media
            join public.thread_messages message
              on message.id = message_media.message_id
            join public.conversation_threads thread
              on thread.id = message.thread_id
            where message_media.media_asset_id = asset.id
              and asset.reserved_parent_id = message.id
              and message.deleted_at is null
              and message.moderation_status = 'visible'
              and thread.deleted_at is null
              and thread.moderation_status = 'visible'
              and thread.couple_id = asset.couple_id
              and internal.can_access_couple_content(thread.couple_id)
              and (
                thread.kind <> 'memory'
                or exists (
                  select 1
                  from public.memory_threads parent_memory_thread
                  join public.memories memory
                    on memory.id = parent_memory_thread.memory_id
                  where parent_memory_thread.thread_id = thread.id
                    and memory.deleted_at is null
                    and memory.moderation_status = 'visible'
                )
              )
          )
        )
        or (
          asset.reserved_parent_kind = 'memory_media'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.memory_media memory_media
            join public.memories memory
              on memory.id = memory_media.memory_id
            where memory_media.media_asset_id = asset.id
              and asset.reserved_parent_id = memory_media.id
              and memory_media.deleted_at is null
              and memory_media.moderation_status = 'visible'
              and memory.deleted_at is null
              and memory.moderation_status = 'visible'
              and memory.couple_id = asset.couple_id
              and internal.can_access_couple_content(memory.couple_id)
          )
        )
        or (
          asset.reserved_parent_kind = 'widget_drawing_revision'
          and asset.bucket = 'widget-drawings'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.widget_drawing_revisions revision
            join public.widget_canvases canvas
              on canvas.id = revision.canvas_id
            where revision.payload_media_asset_id = asset.id
              and asset.reserved_parent_id = revision.id
              and revision.deleted_at is null
              and revision.moderation_status = 'visible'
              and canvas.deleted_at is null
              and canvas.couple_id = asset.couple_id
              and internal.can_access_couple_content(canvas.couple_id)
          )
        )
      )
  );
$$;

create or replace function public.get_or_create_widget_canvas(p_couple_id uuid default null)
returns table (
  canvas_id uuid,
  couple_id uuid,
  active_revision_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_or_create_widget_canvas(p_couple_id);
$$;

create or replace function public.submit_widget_drawing_revision(
  p_canvas_id uuid,
  p_payload_media_asset_id uuid,
  p_parent_revision_id uuid,
  p_payload_bytes bigint,
  p_uncompressed_bytes bigint,
  p_compression text,
  p_stroke_count integer,
  p_point_count integer,
  p_bounds jsonb,
  p_sha256_hex text,
  p_client_decode_validated_at timestamptz,
  p_client_renderer_version text,
  p_client_validation_version text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  canvas_id uuid,
  revision_id uuid,
  active_revision_id uuid,
  payload_media_asset_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.submit_widget_drawing_revision(
    p_canvas_id,
    p_payload_media_asset_id,
    p_parent_revision_id,
    p_payload_bytes,
    p_uncompressed_bytes,
    p_compression,
    p_stroke_count,
    p_point_count,
    p_bounds,
    p_sha256_hex,
    p_client_decode_validated_at,
    p_client_renderer_version,
    p_client_validation_version,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.get_widget_canvas(p_couple_id uuid default null)
returns table (
  canvas_id uuid,
  couple_id uuid,
  active_revision_id uuid,
  active_revision_moderation_status text,
  active_revision_deleted_at timestamptz,
  active_revision_author_user_id uuid,
  payload_media_asset_id uuid,
  payload_bucket text,
  payload_storage_path text,
  payload_sha256_hex text,
  payload_bytes bigint,
  uncompressed_bytes bigint,
  compression text,
  stroke_count integer,
  point_count integer,
  bounds jsonb,
  format text,
  format_version integer,
  renderer_version integer,
  client_decode_validated_at timestamptz,
  client_renderer_version text,
  client_validation_version text,
  revision_created_at timestamptz,
  canvas_created_at timestamptz,
  canvas_updated_at timestamptz,
  sync_updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_widget_canvas(p_couple_id);
$$;

create or replace function public.get_widget_drawing_revisions(
  p_canvas_id uuid,
  p_updated_after timestamptz default null,
  p_limit integer default 100,
  p_updated_after_revision_id uuid default null,
  p_created_before timestamptz default null,
  p_created_before_revision_id uuid default null
)
returns table (
  canvas_id uuid,
  revision_id uuid,
  author_user_id uuid,
  parent_revision_id uuid,
  moderation_status text,
  deleted_at timestamptz,
  payload_media_asset_id uuid,
  payload_bucket text,
  payload_storage_path text,
  payload_sha256_hex text,
  payload_bytes bigint,
  uncompressed_bytes bigint,
  compression text,
  stroke_count integer,
  point_count integer,
  bounds jsonb,
  format text,
  format_version integer,
  renderer_version integer,
  client_decode_validated_at timestamptz,
  client_renderer_version text,
  client_validation_version text,
  created_at timestamptz,
  updated_at timestamptz,
  sync_updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_widget_drawing_revisions(
    p_canvas_id,
    p_updated_after,
    p_limit,
    p_updated_after_revision_id,
    p_created_before,
    p_created_before_revision_id
  );
$$;

alter table public.widget_canvases enable row level security;
alter table public.widget_drawing_revisions enable row level security;

create index widget_drawing_revisions_canvas_created_at_id_idx
on public.widget_drawing_revisions (canvas_id, created_at desc, id desc);

create index widget_drawing_revisions_author_created_at_idx
on public.widget_drawing_revisions (author_user_id, created_at desc);

create index widget_drawing_revisions_canvas_updated_at_id_idx
on public.widget_drawing_revisions (canvas_id, updated_at, id);

create index widget_drawing_revisions_parent_revision_id_idx
on public.widget_drawing_revisions (parent_revision_id)
where parent_revision_id is not null;

revoke all on public.widget_canvases from public, anon, authenticated;
revoke all on public.widget_drawing_revisions from public, anon, authenticated;

grant all privileges on public.widget_canvases to service_role;
grant all privileges on public.widget_drawing_revisions to service_role;

revoke all on function internal.assert_widget_canvas_couple_allowed() from public, anon, authenticated;
grant execute on function internal.assert_widget_canvas_couple_allowed() to service_role;

revoke all on function internal.assert_widget_canvas_active_revision_allowed() from public, anon, authenticated;
grant execute on function internal.assert_widget_canvas_active_revision_allowed() to service_role;

revoke all on function internal.assert_widget_drawing_revision_allowed() from public, anon, authenticated;
grant execute on function internal.assert_widget_drawing_revision_allowed() to service_role;

revoke all on function internal.get_or_create_widget_canvas(uuid) from public, anon, authenticated;
grant execute on function internal.get_or_create_widget_canvas(uuid) to authenticated, service_role;

revoke all on function internal.submit_widget_drawing_revision(uuid, uuid, uuid, bigint, bigint, text, integer, integer, jsonb, text, timestamptz, text, text, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.submit_widget_drawing_revision(uuid, uuid, uuid, bigint, bigint, text, integer, integer, jsonb, text, timestamptz, text, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.get_widget_canvas(uuid) from public, anon, authenticated;
grant execute on function internal.get_widget_canvas(uuid) to authenticated, service_role;

revoke all on function internal.get_widget_drawing_revisions(uuid, timestamptz, integer, uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function internal.get_widget_drawing_revisions(uuid, timestamptz, integer, uuid, timestamptz, uuid) to authenticated, service_role;

revoke all on function internal.can_read_media_object(text, text) from public, anon, authenticated;
grant execute on function internal.can_read_media_object(text, text) to authenticated, service_role;

revoke all on function public.get_or_create_widget_canvas(uuid) from public, anon;
grant execute on function public.get_or_create_widget_canvas(uuid) to authenticated, service_role;

revoke all on function public.submit_widget_drawing_revision(uuid, uuid, uuid, bigint, bigint, text, integer, integer, jsonb, text, timestamptz, text, text, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.submit_widget_drawing_revision(uuid, uuid, uuid, bigint, bigint, text, integer, integer, jsonb, text, timestamptz, text, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.get_widget_canvas(uuid) from public, anon;
grant execute on function public.get_widget_canvas(uuid) to authenticated, service_role;

revoke all on function public.get_widget_drawing_revisions(uuid, timestamptz, integer, uuid, timestamptz, uuid) from public, anon;
grant execute on function public.get_widget_drawing_revisions(uuid, timestamptz, integer, uuid, timestamptz, uuid) to authenticated, service_role;
