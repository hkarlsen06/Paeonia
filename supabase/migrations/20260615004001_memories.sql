create table public.memories (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  title text not null,
  memory_date date not null,
  created_by_user_id uuid not null references auth.users (id) on delete restrict,
  last_edited_by_user_id uuid not null references auth.users (id) on delete restrict,
  revision integer not null default 1,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint memories_title_check
    check (char_length(btrim(title)) between 1 and 160),
  constraint memories_revision_check
    check (revision > 0),
  constraint memories_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger touch_memories_updated_at_and_revision
before update on public.memories
for each row
execute function internal.touch_updated_at_and_revision();

create table public.memory_notes (
  id uuid primary key default extensions.gen_random_uuid(),
  memory_id uuid not null references public.memories (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  body text not null,
  revision integer not null default 1,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint memory_notes_memory_user_unique
    unique (memory_id, user_id),
  constraint memory_notes_body_check
    check (char_length(btrim(body)) between 1 and 4000),
  constraint memory_notes_revision_check
    check (revision > 0),
  constraint memory_notes_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger touch_memory_notes_updated_at_and_revision
before update on public.memory_notes
for each row
execute function internal.touch_updated_at_and_revision();

create table public.memory_media (
  id uuid primary key default extensions.gen_random_uuid(),
  memory_id uuid not null references public.memories (id) on delete restrict,
  media_asset_id uuid not null references public.media_assets (id) on delete restrict,
  owner_user_id uuid not null references auth.users (id) on delete restrict,
  sort_order smallint not null,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint memory_media_memory_asset_unique
    unique (memory_id, media_asset_id),
  constraint memory_media_sort_order_check
    check (sort_order between 1 and 20),
  constraint memory_media_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger set_memory_media_updated_at
before update on public.memory_media
for each row
execute function internal.set_updated_at();

alter table public.memory_threads
add constraint memory_threads_memory_id_fkey
foreign key (memory_id)
references public.memories (id)
on delete restrict;

create or replace function internal.can_access_visible_memory(p_memory_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.memories memory
    where memory.id = p_memory_id
      and memory.deleted_at is null
      and memory.moderation_status = 'visible'
      and internal.can_access_couple_content(memory.couple_id)
  );
$$;

create or replace function internal.assert_memory_member_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from public.couple_members created_member
    join public.couple_members edited_member
      on edited_member.couple_id = created_member.couple_id
    join public.couples couple
      on couple.id = created_member.couple_id
    where created_member.couple_id = new.couple_id
      and created_member.user_id = new.created_by_user_id
      and created_member.status = 'active'
      and edited_member.user_id = new.last_edited_by_user_id
      and edited_member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'memory users must be active couple members'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_memory_member_allowed
before insert or update of couple_id, created_by_user_id, last_edited_by_user_id on public.memories
for each row
execute function internal.assert_memory_member_allowed();

create or replace function internal.assert_memory_note_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from public.memories memory
    join public.couple_members member
      on member.couple_id = memory.couple_id
    join public.couples couple
      on couple.id = memory.couple_id
    where memory.id = new.memory_id
      and memory.deleted_at is null
      and memory.moderation_status = 'visible'
      and member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'memory note user must be an active memory couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_memory_note_allowed
before insert or update of memory_id, user_id on public.memory_notes
for each row
execute function internal.assert_memory_note_allowed();

create or replace function internal.assert_memory_media_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  memory_row public.memories%rowtype;
  asset_row public.media_assets%rowtype;
begin
  select *
  into memory_row
  from public.memories
  where id = new.memory_id;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible' then
    raise exception 'visible memory was not found for media attachment'
      using errcode = '23503';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.media_asset_id;

  if not found
    or asset_row.owner_user_id <> new.owner_user_id
    or asset_row.couple_id <> memory_row.couple_id
    or asset_row.reserved_parent_kind <> 'memory_media'
    or asset_row.reserved_parent_id <> new.id
    or asset_row.upload_purpose not in ('memory_photo', 'voice_note')
    or asset_row.media_type not in ('image', 'voice')
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'memory media asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_memory_media_allowed
before insert or update of id, memory_id, media_asset_id, owner_user_id on public.memory_media
for each row
execute function internal.assert_memory_media_allowed();

create or replace function internal.normalize_memory_title(p_title text)
returns text
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  normalized_title text;
begin
  normalized_title = nullif(btrim(coalesce(p_title, '')), '');

  if normalized_title is null then
    raise exception 'memory title is required'
      using errcode = '23514';
  end if;

  if char_length(normalized_title) > 160 then
    raise exception 'memory title is too long'
      using errcode = '23514';
  end if;

  return normalized_title;
end;
$$;

create or replace function internal.normalize_memory_note_body(p_body text)
returns text
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  normalized_body text;
begin
  normalized_body = nullif(btrim(coalesce(p_body, '')), '');

  if normalized_body is null then
    raise exception 'memory note body is required'
      using errcode = '23514';
  end if;

  if char_length(normalized_body) > 4000 then
    raise exception 'memory note body is too long'
      using errcode = '23514';
  end if;

  return normalized_body;
end;
$$;

create or replace function internal.attach_memory_media_assets(
  p_memory_id uuid,
  p_media_asset_ids uuid[]
)
returns uuid[]
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  media_ids uuid[];
  media_count integer;
  unique_media_count integer;
  active_image_count integer;
  next_sort_order smallint;
  inserted_media_ids uuid[] := array[]::uuid[];
  media_row record;
  asset_row public.media_assets%rowtype;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);
  media_count = cardinality(media_ids);

  if media_count = 0 then
    return inserted_media_ids;
  end if;

  if media_count > 10 then
    raise exception 'a memory can attach at most 10 media assets at once'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from unnest(media_ids) as media_id(id)
    where media_id.id is null
  ) then
    raise exception 'memory media asset id cannot be null'
      using errcode = '23514';
  end if;

  select count(distinct media_id.id)
  into unique_media_count
  from unnest(media_ids) as media_id(id);

  if unique_media_count <> media_count then
    raise exception 'memory media asset ids must be unique'
      using errcode = '23514';
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'memory_media:' || p_memory_id::text || ':' || current_user_id::text,
      0
    )
  );

  select count(*)
  into active_image_count
  from public.memory_media memory_media
  join public.media_assets asset
    on asset.id = memory_media.media_asset_id
  where memory_media.memory_id = p_memory_id
    and memory_media.owner_user_id = current_user_id
    and memory_media.deleted_at is null
    and memory_media.moderation_status = 'visible'
    and asset.media_type = 'image'
    and asset.deleted_at is null
    and asset.moderation_status = 'visible';

  select coalesce(max(memory_media.sort_order), 0)::smallint + 1
  into next_sort_order
  from public.memory_media memory_media
  where memory_media.memory_id = p_memory_id
    and memory_media.owner_user_id = current_user_id
    and memory_media.deleted_at is null;

  for media_row in
    select
      media_item.value as media_asset_id,
      media_item.ordinality::smallint as ordinal_position
    from unnest(media_ids) with ordinality as media_item(value, ordinality)
  loop
    select *
    into asset_row
    from public.media_assets
    where id = media_row.media_asset_id
    for update;

    if not found
      or asset_row.owner_user_id <> current_user_id
      or asset_row.couple_id <> memory_row.couple_id
      or asset_row.reserved_parent_kind <> 'memory_media'
      or asset_row.upload_purpose not in ('memory_photo', 'voice_note')
      or asset_row.media_type not in ('image', 'voice')
      or asset_row.upload_status <> 'finalized'
      or asset_row.storage_delete_status <> 'none'
      or asset_row.moderation_status <> 'visible'
      or asset_row.deleted_at is not null then
      raise exception 'memory media asset is not usable'
        using errcode = '23514';
    end if;

    if asset_row.media_type = 'image' then
      active_image_count = active_image_count + 1;

      if active_image_count > 5 then
        raise exception 'each partner can add at most 5 photos to a memory'
          using errcode = '23514';
      end if;
    end if;

    insert into public.memory_media (
      id,
      memory_id,
      media_asset_id,
      owner_user_id,
      sort_order
    ) values (
      asset_row.reserved_parent_id,
      memory_row.id,
      asset_row.id,
      current_user_id,
      next_sort_order + media_row.ordinal_position - 1
    );

    inserted_media_ids = array_append(inserted_media_ids, asset_row.reserved_parent_id);
  end loop;

  return inserted_media_ids;
end;
$$;

create or replace function internal.create_memory(
  p_memory_id uuid,
  p_title text,
  p_memory_date date,
  p_note_body text,
  p_media_asset_ids uuid[],
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
  normalized_title text;
  normalized_note_body text;
  media_ids uuid[];
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_title = internal.normalize_memory_title(p_title);

  if p_memory_id is null then
    raise exception 'memory id is required'
      using errcode = '23514';
  end if;

  if p_memory_date is null then
    raise exception 'memory date is required'
      using errcode = '23514';
  end if;

  normalized_note_body = nullif(btrim(coalesce(p_note_body, '')), '');
  if normalized_note_body is not null and char_length(normalized_note_body) > 4000 then
    raise exception 'memory note body is too long'
      using errcode = '23514';
  end if;

  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);

  if normalized_note_body is null and cardinality(media_ids) = 0 then
    raise exception 'memory must include a note or media'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_memory',
      p_memory_id::text,
      normalized_title,
      p_memory_date::text,
      coalesce(normalized_note_body, ''),
      media_ids::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_memory',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'memory_id')::uuid;
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();
  insert into public.memories (
    id,
    couple_id,
    title,
    memory_date,
    created_by_user_id,
    last_edited_by_user_id
  ) values (
    p_memory_id,
    resolved_couple_id,
    normalized_title,
    p_memory_date,
    current_user_id,
    current_user_id
  );

  if normalized_note_body is not null then
    insert into public.memory_notes (
      memory_id,
      user_id,
      body
    ) values (
      p_memory_id,
      current_user_id,
      normalized_note_body
    );
  end if;

  perform internal.attach_memory_media_assets(p_memory_id, media_ids);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('memory_id', p_memory_id)
  );

  return p_memory_id;
end;
$$;

create or replace function internal.update_memory(
  p_memory_id uuid,
  p_expected_revision integer,
  p_title text,
  p_memory_date date,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  memory_id uuid,
  revision integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  normalized_title text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'expected memory revision is required'
      using errcode = '23514';
  end if;

  normalized_title = internal.normalize_memory_title(p_title);

  if p_memory_date is null then
    raise exception 'memory date is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_memory',
      p_memory_id::text,
      p_expected_revision::text,
      normalized_title,
      p_memory_date::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_memory',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'memory_id')::uuid,
      (replayed_response ->> 'revision')::integer,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  if memory_row.revision <> p_expected_revision then
    raise exception 'memory revision conflict'
      using errcode = '40001';
  end if;

  update public.memories
  set
    title = normalized_title,
    memory_date = p_memory_date,
    last_edited_by_user_id = current_user_id
  where id = memory_row.id
  returning public.memories.id, public.memories.revision, public.memories.updated_at
  into memory_id, revision, updated_at;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'memory_id', memory_id,
      'revision', revision,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;

create or replace function internal.hide_memory(
  p_memory_id uuid,
  p_expected_revision integer,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  memory_id uuid,
  revision integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'expected memory revision is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'hide_memory',
      p_memory_id::text,
      p_expected_revision::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'hide_memory',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'memory_id')::uuid,
      (replayed_response ->> 'revision')::integer,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  if memory_row.revision <> p_expected_revision then
    raise exception 'memory revision conflict'
      using errcode = '40001';
  end if;

  update public.memories
  set
    deleted_at = now(),
    last_edited_by_user_id = current_user_id
  where id = memory_row.id
  returning public.memories.id, public.memories.revision, public.memories.updated_at
  into memory_id, revision, updated_at;

  update public.conversation_threads thread
  set deleted_at = coalesce(thread.deleted_at, now())
  from public.memory_threads memory_thread
  where memory_thread.thread_id = thread.id
    and memory_thread.memory_id = memory_row.id
    and thread.deleted_at is null;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'memory_id', memory_id,
      'revision', revision,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;

create or replace function internal.upsert_memory_note(
  p_memory_id uuid,
  p_expected_revision integer,
  p_body text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  note_id uuid,
  revision integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  note_row public.memory_notes%rowtype;
  normalized_body text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_body = internal.normalize_memory_note_body(p_body);

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'upsert_memory_note',
      p_memory_id::text,
      coalesce(p_expected_revision::text, ''),
      normalized_body
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'upsert_memory_note',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'note_id')::uuid,
      (replayed_response ->> 'revision')::integer,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  select *
  into note_row
  from public.memory_notes
  where memory_id = p_memory_id
    and user_id = current_user_id
  for update;

  if found then
    if note_row.deleted_at is not null or note_row.moderation_status <> 'visible' then
      raise exception 'memory note is not editable'
        using errcode = '42501';
    end if;

    if p_expected_revision is null or note_row.revision <> p_expected_revision then
      raise exception 'memory note revision conflict'
        using errcode = '40001';
    end if;

    update public.memory_notes
    set body = normalized_body
    where id = note_row.id
    returning public.memory_notes.id, public.memory_notes.revision, public.memory_notes.updated_at
    into note_id, revision, updated_at;
  else
    if p_expected_revision is not null and p_expected_revision <> 0 then
      raise exception 'memory note revision conflict'
        using errcode = '40001';
    end if;

    insert into public.memory_notes (
      memory_id,
      user_id,
      body
    ) values (
      p_memory_id,
      current_user_id,
      normalized_body
    )
    returning public.memory_notes.id, public.memory_notes.revision, public.memory_notes.updated_at
    into note_id, revision, updated_at;
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'note_id', note_id,
      'revision', revision,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;

create or replace function internal.attach_memory_media(
  p_memory_id uuid,
  p_media_asset_ids uuid[],
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid[]
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  media_ids uuid[];
  inserted_media_ids uuid[];
  request_hash bytea;
  replayed_response jsonb;
begin
  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);

  if cardinality(media_ids) = 0 then
    raise exception 'memory media asset ids are required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'attach_memory_media',
      p_memory_id::text,
      media_ids::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'attach_memory_media',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return (
      select coalesce(array_agg(value::uuid order by ordinality), array[]::uuid[])
      from jsonb_array_elements_text(replayed_response -> 'memory_media_ids')
        with ordinality as values(value, ordinality)
    );
  end if;

  inserted_media_ids = internal.attach_memory_media_assets(p_memory_id, media_ids);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('memory_media_ids', inserted_media_ids)
  );

  return inserted_media_ids;
end;
$$;

create or replace function internal.remove_memory_media(
  p_memory_media_id uuid,
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
  memory_media_row public.memory_media%rowtype;
  memory_row public.memories%rowtype;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'remove_memory_media',
      p_memory_media_id::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'remove_memory_media',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'memory_media_id')::uuid;
  end if;

  select *
  into memory_media_row
  from public.memory_media
  where id = p_memory_media_id
  for update;

  if not found
    or memory_media_row.deleted_at is not null
    or memory_media_row.moderation_status <> 'visible'
    or memory_media_row.owner_user_id <> current_user_id then
    raise exception 'memory media is not removable'
      using errcode = '42501';
  end if;

  select *
  into memory_row
  from public.memories
  where id = memory_media_row.memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  update public.memory_media
  set deleted_at = now()
  where id = memory_media_row.id;

  update public.media_assets
  set
    storage_delete_status = case
      when storage_delete_status = 'none' then 'pending'
      else storage_delete_status
    end,
    deleted_at = coalesce(deleted_at, now())
  where id = memory_media_row.media_asset_id
    and owner_user_id = current_user_id
    and storage_delete_status <> 'deleted';

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('memory_media_id', memory_media_row.id)
  );

  return memory_media_row.id;
end;
$$;

create or replace function internal.create_memory_thread_with_message(
  p_memory_id uuid,
  p_body text,
  p_media_asset_ids uuid[],
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  thread_id uuid,
  message_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  resolved_thread_id uuid;
  resolved_message_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_memory_thread_with_message',
      p_memory_id::text,
      coalesce(nullif(btrim(coalesce(p_body, '')), ''), ''),
      coalesce(p_media_asset_ids::text, '{}')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_memory_thread_with_message',
    'conversation_threads',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'thread_id')::uuid,
      (replayed_response ->> 'message_id')::uuid;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'memory_thread:' || memory_row.id::text,
      0
    )
  );

  select existing_thread.thread_id
  into resolved_thread_id
  from public.memory_threads existing_thread
  where existing_thread.memory_id = memory_row.id;

  if resolved_thread_id is null then
    insert into public.conversation_threads (
      couple_id,
      kind,
      created_by_user_id
    ) values (
      memory_row.couple_id,
      'memory',
      current_user_id
    )
    returning id into resolved_thread_id;

    insert into public.memory_threads (
      memory_id,
      thread_id
    ) values (
      memory_row.id,
      resolved_thread_id
    );
  end if;

  resolved_message_id = internal.insert_thread_message(
    resolved_thread_id,
    p_body,
    p_media_asset_ids
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'thread_id', resolved_thread_id,
      'message_id', resolved_message_id
    )
  );

  return query
  select resolved_thread_id, resolved_message_id;
end;
$$;

create or replace function internal.get_memories(
  p_updated_after timestamptz default null,
  p_cursor_memory_id uuid default null,
  p_limit integer default 100
)
returns table (
  memory_id uuid,
  couple_id uuid,
  title text,
  memory_date date,
  created_by_user_id uuid,
  last_edited_by_user_id uuid,
  revision integer,
  moderation_status text,
  deleted_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  sync_updated_at timestamptz,
  own_note_id uuid,
  own_note_body text,
  own_note_revision integer,
  own_note_updated_at timestamptz,
  own_note_deleted_at timestamptz,
  own_note_moderation_status text,
  partner_note_id uuid,
  partner_note_user_id uuid,
  partner_note_body text,
  partner_note_revision integer,
  partner_note_updated_at timestamptz,
  partner_note_deleted_at timestamptz,
  partner_note_moderation_status text,
  memory_media_ids uuid[],
  media_asset_ids uuid[],
  memory_media_states jsonb,
  thread_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'memory read limit is out of range'
      using errcode = '23514';
  end if;

  return query
  with current_couple as (
    select internal.get_current_entitled_couple_id() as couple_id
  ),
  memory_rows as (
  select
    memory.id as memory_id,
    memory.couple_id,
    case
      when memory.deleted_at is null and memory.moderation_status = 'visible' then memory.title
      else null
    end as title,
    memory.memory_date,
    memory.created_by_user_id,
    memory.last_edited_by_user_id,
    memory.revision,
    memory.moderation_status,
    memory.deleted_at,
    memory.created_at,
    memory.updated_at,
    greatest(
      memory.updated_at,
      coalesce(own_note.updated_at, '-infinity'::timestamptz),
      coalesce(partner_note.updated_at, '-infinity'::timestamptz),
      coalesce(media.media_updated_at, '-infinity'::timestamptz)
    ) as sync_updated_at,
    own_note.id,
    case
      when memory.deleted_at is null
        and memory.moderation_status = 'visible'
        and own_note.deleted_at is null
        and own_note.moderation_status = 'visible'
        then own_note.body
      else null
    end as own_note_body,
    own_note.revision,
    own_note.updated_at,
    own_note.deleted_at,
    own_note.moderation_status,
    partner_note.id,
    partner_note.user_id,
    case
      when memory.deleted_at is null
        and memory.moderation_status = 'visible'
        and partner_note.deleted_at is null
        and partner_note.moderation_status = 'visible'
        then partner_note.body
      else null
    end as partner_note_body,
    partner_note.revision,
    partner_note.updated_at,
    partner_note.deleted_at,
    partner_note.moderation_status,
    coalesce(media.memory_media_ids, array[]::uuid[]),
    coalesce(media.media_asset_ids, array[]::uuid[]),
    coalesce(media.memory_media_states, '[]'::jsonb),
    memory_thread.thread_id
  from current_couple
  join public.memories memory
    on memory.couple_id = current_couple.couple_id
  left join public.memory_notes own_note
    on own_note.memory_id = memory.id
    and own_note.user_id = (select auth.uid())
  left join public.memory_notes partner_note
    on partner_note.memory_id = memory.id
    and partner_note.user_id <> (select auth.uid())
  left join lateral (
    select
      array_agg(memory_media.id order by memory_media.owner_user_id, memory_media.sort_order, memory_media.id)
        filter (
          where memory.deleted_at is null
            and memory_media.deleted_at is null
            and memory_media.moderation_status = 'visible'
            and asset.reserved_parent_kind = 'memory_media'
            and asset.reserved_parent_id = memory_media.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        ) as memory_media_ids,
      array_agg(memory_media.media_asset_id order by memory_media.owner_user_id, memory_media.sort_order, memory_media.id)
        filter (
          where memory.deleted_at is null
            and memory_media.deleted_at is null
            and memory_media.moderation_status = 'visible'
            and asset.reserved_parent_kind = 'memory_media'
            and asset.reserved_parent_id = memory_media.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        ) as media_asset_ids,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'memory_media_id', memory_media.id,
            'media_asset_id', memory_media.media_asset_id,
            'owner_user_id', memory_media.owner_user_id,
            'sort_order', memory_media.sort_order,
            'deleted_at', memory_media.deleted_at,
            'moderation_status', memory_media.moderation_status,
            'asset_deleted_at', asset.deleted_at,
            'asset_moderation_status', asset.moderation_status,
            'asset_storage_delete_status', asset.storage_delete_status,
            'updated_at', greatest(memory_media.updated_at, asset.updated_at)
          )
          order by memory_media.owner_user_id, memory_media.sort_order, memory_media.id
        ),
        '[]'::jsonb
      ) as memory_media_states,
      max(greatest(memory_media.updated_at, asset.updated_at)) as media_updated_at
    from public.memory_media memory_media
    join public.media_assets asset
      on asset.id = memory_media.media_asset_id
    where memory_media.memory_id = memory.id
  ) media
    on true
  left join public.memory_threads memory_thread
    on memory_thread.memory_id = memory.id
  )
  select *
  from memory_rows memory_page
  where p_updated_after is null
    or memory_page.sync_updated_at > p_updated_after
    or (
      memory_page.sync_updated_at = p_updated_after
      and memory_page.memory_id > coalesce(p_cursor_memory_id, '00000000-0000-0000-0000-000000000000'::uuid)
    )
  order by memory_page.sync_updated_at, memory_page.memory_id
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
      )
  );
$$;

create or replace function internal.get_conversation_threads()
returns table (
  thread_id uuid,
  couple_id uuid,
  kind text,
  daily_question_instance_id uuid,
  memory_id uuid,
  created_by_user_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz,
  moderation_status text,
  last_message_id uuid,
  last_message_at timestamptz,
  last_message_sender_user_id uuid,
  last_message_deleted_at timestamptz,
  last_message_moderation_status text,
  last_message_body text
)
language sql
security definer
set search_path = pg_catalog
as $$
  with current_couple as (
    select internal.get_current_entitled_couple_id() as couple_id
  )
  select
    thread.id,
    thread.couple_id,
    thread.kind,
    daily_thread.instance_id,
    memory_thread.memory_id,
    thread.created_by_user_id,
    thread.created_at,
    thread.updated_at,
    thread.deleted_at,
    thread.moderation_status,
    last_message.id,
    last_message.created_at,
    last_message.sender_user_id,
    last_message.deleted_at,
    last_message.moderation_status,
    case
      when thread.deleted_at is null
        and thread.moderation_status = 'visible'
        and last_message.deleted_at is null
        and last_message.moderation_status = 'visible'
        then last_message.body
      else null
    end
  from current_couple
  join public.conversation_threads thread
    on thread.couple_id = current_couple.couple_id
  left join public.daily_question_threads daily_thread
    on daily_thread.thread_id = thread.id
  left join public.memory_threads memory_thread
    on memory_thread.thread_id = thread.id
  left join lateral (
    select message.*
    from public.thread_messages message
    where message.thread_id = thread.id
    order by message.created_at desc, message.id desc
    limit 1
  ) last_message
    on true
  where internal.can_access_couple_content(thread.couple_id)
  order by last_message.created_at desc, thread.created_at desc, thread.id;
$$;

create or replace function internal.get_thread_messages(p_thread_id uuid)
returns table (
  thread_id uuid,
  message_id uuid,
  sender_user_id uuid,
  body text,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  moderation_status text,
  media_asset_ids uuid[],
  media_states jsonb
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    thread.id,
    message.id,
    message.sender_user_id,
    case
      when thread.deleted_at is null
        and thread.moderation_status = 'visible'
        and message.deleted_at is null
        and message.moderation_status = 'visible'
        then message.body
      else null
    end,
    message.created_at,
    message.edited_at,
    message.deleted_at,
    message.moderation_status,
    coalesce(media.media_asset_ids, array[]::uuid[]),
    coalesce(media.media_states, '[]'::jsonb)
  from public.conversation_threads thread
  join public.thread_messages message
    on message.thread_id = thread.id
  left join lateral (
    select
      array_agg(message_media.media_asset_id order by message_media.sort_order)
        filter (
          where thread.deleted_at is null
            and thread.moderation_status = 'visible'
            and message.deleted_at is null
            and message.moderation_status = 'visible'
            and asset.reserved_parent_kind = 'thread_message_media'
            and asset.reserved_parent_id = message.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        ) as media_asset_ids,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'media_asset_id', message_media.media_asset_id,
            'sort_order', message_media.sort_order,
            'asset_deleted_at', asset.deleted_at,
            'asset_moderation_status', asset.moderation_status,
            'asset_storage_delete_status', asset.storage_delete_status,
            'updated_at', asset.updated_at
          )
          order by message_media.sort_order, message_media.media_asset_id
        ),
        '[]'::jsonb
      ) as media_states
    from public.thread_message_media message_media
    join public.media_assets asset
      on asset.id = message_media.media_asset_id
    where message_media.message_id = message.id
  ) media
    on true
  where thread.id = p_thread_id
    and internal.can_access_couple_content(thread.couple_id)
  order by message.created_at, message.id;
$$;

create or replace function public.create_memory(
  p_memory_id uuid,
  p_title text,
  p_memory_date date,
  p_note_body text,
  p_media_asset_ids uuid[],
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.create_memory(
    p_memory_id,
    p_title,
    p_memory_date,
    p_note_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.update_memory(
  p_memory_id uuid,
  p_expected_revision integer,
  p_title text,
  p_memory_date date,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  memory_id uuid,
  revision integer,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.update_memory(
    p_memory_id,
    p_expected_revision,
    p_title,
    p_memory_date,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.hide_memory(
  p_memory_id uuid,
  p_expected_revision integer,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  memory_id uuid,
  revision integer,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.hide_memory(
    p_memory_id,
    p_expected_revision,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.upsert_memory_note(
  p_memory_id uuid,
  p_expected_revision integer,
  p_body text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  note_id uuid,
  revision integer,
  updated_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.upsert_memory_note(
    p_memory_id,
    p_expected_revision,
    p_body,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.attach_memory_media(
  p_memory_id uuid,
  p_media_asset_ids uuid[],
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid[]
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.attach_memory_media(
    p_memory_id,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.remove_memory_media(
  p_memory_media_id uuid,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.remove_memory_media(
    p_memory_media_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.get_memories(
  p_updated_after timestamptz default null,
  p_cursor_memory_id uuid default null,
  p_limit integer default 100
)
returns table (
  memory_id uuid,
  couple_id uuid,
  title text,
  memory_date date,
  created_by_user_id uuid,
  last_edited_by_user_id uuid,
  revision integer,
  moderation_status text,
  deleted_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  sync_updated_at timestamptz,
  own_note_id uuid,
  own_note_body text,
  own_note_revision integer,
  own_note_updated_at timestamptz,
  own_note_deleted_at timestamptz,
  own_note_moderation_status text,
  partner_note_id uuid,
  partner_note_user_id uuid,
  partner_note_body text,
  partner_note_revision integer,
  partner_note_updated_at timestamptz,
  partner_note_deleted_at timestamptz,
  partner_note_moderation_status text,
  memory_media_ids uuid[],
  media_asset_ids uuid[],
  memory_media_states jsonb,
  thread_id uuid
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_memories(p_updated_after, p_cursor_memory_id, p_limit);
$$;

alter table public.memories enable row level security;
alter table public.memory_notes enable row level security;
alter table public.memory_media enable row level security;

create index memories_couple_memory_date_id_idx
on public.memories (couple_id, memory_date desc, id);

create index memories_couple_updated_at_id_idx
on public.memories (couple_id, updated_at, id);

create index memories_visibility_idx
on public.memories (couple_id, moderation_status, deleted_at);

create index memory_notes_user_updated_at_idx
on public.memory_notes (user_id, updated_at desc);

create index memory_notes_memory_visibility_idx
on public.memory_notes (memory_id, moderation_status, deleted_at);

create index memory_notes_memory_updated_at_idx
on public.memory_notes (memory_id, updated_at);

create index memory_media_memory_sort_order_idx
on public.memory_media (memory_id, sort_order);

create index memory_media_owner_memory_idx
on public.memory_media (owner_user_id, memory_id);

create index memory_media_media_asset_id_idx
on public.memory_media (media_asset_id);

create index memory_media_visibility_idx
on public.memory_media (memory_id, moderation_status, deleted_at);

create index memory_media_memory_updated_at_idx
on public.memory_media (memory_id, updated_at);

create unique index memory_media_active_owner_sort_order_idx
on public.memory_media (memory_id, owner_user_id, sort_order)
where deleted_at is null;

revoke all on public.memories from public, anon, authenticated;
revoke all on public.memory_notes from public, anon, authenticated;
revoke all on public.memory_media from public, anon, authenticated;

grant all privileges on public.memories to service_role;
grant all privileges on public.memory_notes to service_role;
grant all privileges on public.memory_media to service_role;

revoke all on function internal.can_access_visible_memory(uuid) from public, anon, authenticated;
grant execute on function internal.can_access_visible_memory(uuid) to authenticated, service_role;

revoke all on function internal.assert_memory_member_allowed() from public, anon, authenticated;
grant execute on function internal.assert_memory_member_allowed() to service_role;

revoke all on function internal.assert_memory_note_allowed() from public, anon, authenticated;
grant execute on function internal.assert_memory_note_allowed() to service_role;

revoke all on function internal.assert_memory_media_allowed() from public, anon, authenticated;
grant execute on function internal.assert_memory_media_allowed() to service_role;

revoke all on function internal.normalize_memory_title(text) from public, anon, authenticated;
grant execute on function internal.normalize_memory_title(text) to authenticated, service_role;

revoke all on function internal.normalize_memory_note_body(text) from public, anon, authenticated;
grant execute on function internal.normalize_memory_note_body(text) to authenticated, service_role;

revoke all on function internal.attach_memory_media_assets(uuid, uuid[]) from public, anon, authenticated;
grant execute on function internal.attach_memory_media_assets(uuid, uuid[]) to authenticated, service_role;

revoke all on function internal.create_memory(uuid, text, date, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.create_memory(uuid, text, date, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.update_memory(uuid, integer, text, date, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.update_memory(uuid, integer, text, date, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.hide_memory(uuid, integer, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.hide_memory(uuid, integer, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.upsert_memory_note(uuid, integer, text, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.upsert_memory_note(uuid, integer, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.attach_memory_media(uuid, uuid[], uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.attach_memory_media(uuid, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.remove_memory_media(uuid, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.remove_memory_media(uuid, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.create_memory_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.create_memory_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.can_read_media_object(text, text) from public, anon, authenticated;
grant execute on function internal.can_read_media_object(text, text) to authenticated, service_role;

revoke all on function internal.get_conversation_threads() from public, anon, authenticated;
grant execute on function internal.get_conversation_threads() to authenticated, service_role;

revoke all on function internal.get_thread_messages(uuid) from public, anon, authenticated;
grant execute on function internal.get_thread_messages(uuid) to authenticated, service_role;

revoke all on function internal.get_memories(timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function internal.get_memories(timestamptz, uuid, integer) to authenticated, service_role;

revoke all on function public.create_memory(uuid, text, date, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.create_memory(uuid, text, date, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.update_memory(uuid, integer, text, date, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.update_memory(uuid, integer, text, date, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.hide_memory(uuid, integer, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.hide_memory(uuid, integer, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.upsert_memory_note(uuid, integer, text, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.upsert_memory_note(uuid, integer, text, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.attach_memory_media(uuid, uuid[], uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.attach_memory_media(uuid, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.remove_memory_media(uuid, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.remove_memory_media(uuid, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.get_memories(timestamptz, uuid, integer) from public, anon;
grant execute on function public.get_memories(timestamptz, uuid, integer) to authenticated, service_role;
