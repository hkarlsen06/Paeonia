create table public.conversation_threads (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  kind text not null,
  created_by_user_id uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,

  constraint conversation_threads_kind_check
    check (kind in ('daily_question', 'memory')),
  constraint conversation_threads_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger set_conversation_threads_updated_at
before update on public.conversation_threads
for each row
execute function internal.set_updated_at();

create table public.daily_question_threads (
  instance_id uuid primary key references public.daily_question_instances (id) on delete restrict,
  thread_id uuid not null references public.conversation_threads (id) on delete restrict,
  created_at timestamptz not null default now(),

  constraint daily_question_threads_thread_id_unique
    unique (thread_id)
);

create table public.memory_threads (
  memory_id uuid primary key,
  thread_id uuid not null references public.conversation_threads (id) on delete restrict,
  created_at timestamptz not null default now(),

  constraint memory_threads_thread_id_unique
    unique (thread_id)
);

create table public.thread_messages (
  id uuid primary key default extensions.gen_random_uuid(),
  thread_id uuid not null references public.conversation_threads (id) on delete restrict,
  sender_user_id uuid not null references auth.users (id) on delete restrict,
  body text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,

  constraint thread_messages_body_check
    check (body is null or char_length(btrim(body)) between 1 and 4000),
  constraint thread_messages_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger set_thread_messages_updated_at
before update on public.thread_messages
for each row
execute function internal.set_updated_at();

create table public.thread_message_media (
  message_id uuid not null references public.thread_messages (id) on delete restrict,
  media_asset_id uuid not null references public.media_assets (id) on delete restrict,
  sort_order smallint not null,

  constraint thread_message_media_primary_key
    primary key (message_id, media_asset_id),
  constraint thread_message_media_sort_order_check
    check (sort_order between 1 and 10),
  constraint thread_message_media_message_sort_order_unique
    unique (message_id, sort_order)
);

create or replace function internal.assert_conversation_thread_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = new.couple_id
      and member.user_id = new.created_by_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'thread creator must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_conversation_thread_allowed
before insert or update of couple_id, created_by_user_id on public.conversation_threads
for each row
execute function internal.assert_conversation_thread_allowed();

create or replace function internal.assert_daily_question_thread_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  thread_row public.conversation_threads%rowtype;
  instance_couple_id uuid;
begin
  select *
  into thread_row
  from public.conversation_threads
  where id = new.thread_id;

  if not found then
    raise exception 'thread was not found'
      using errcode = '23503';
  end if;

  if thread_row.kind <> 'daily_question' then
    raise exception 'daily question thread must use daily_question kind'
      using errcode = '23514';
  end if;

  select couple_day.couple_id
  into instance_couple_id
  from public.daily_question_instances instance
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  where instance.id = new.instance_id;

  if instance_couple_id is null then
    raise exception 'daily question instance was not found'
      using errcode = '23503';
  end if;

  if instance_couple_id <> thread_row.couple_id then
    raise exception 'daily question thread couple mismatch'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_question_thread_allowed
before insert or update on public.daily_question_threads
for each row
execute function internal.assert_daily_question_thread_allowed();

create or replace function internal.assert_memory_thread_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  thread_kind text;
begin
  select thread.kind
  into thread_kind
  from public.conversation_threads thread
  where thread.id = new.thread_id;

  if thread_kind is null then
    raise exception 'thread was not found'
      using errcode = '23503';
  end if;

  if thread_kind <> 'memory' then
    raise exception 'memory thread must use memory kind'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_memory_thread_allowed
before insert or update on public.memory_threads
for each row
execute function internal.assert_memory_thread_allowed();

create or replace function internal.assert_thread_message_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from public.conversation_threads thread
    join public.couple_members member
      on member.couple_id = thread.couple_id
    join public.couples couple
      on couple.id = thread.couple_id
    where thread.id = new.thread_id
      and thread.deleted_at is null
      and thread.moderation_status = 'visible'
      and member.user_id = new.sender_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'message sender must be an active visible thread member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_thread_message_allowed
before insert or update of thread_id, sender_user_id on public.thread_messages
for each row
execute function internal.assert_thread_message_allowed();

create or replace function internal.assert_thread_message_media_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  message_row public.thread_messages%rowtype;
  thread_row public.conversation_threads%rowtype;
  asset_row public.media_assets%rowtype;
begin
  select *
  into message_row
  from public.thread_messages
  where id = new.message_id;

  if not found then
    raise exception 'thread message was not found'
      using errcode = '23503';
  end if;

  select *
  into thread_row
  from public.conversation_threads
  where id = message_row.thread_id;

  if not found then
    raise exception 'conversation thread was not found'
      using errcode = '23503';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.media_asset_id;

  if not found
    or asset_row.owner_user_id <> message_row.sender_user_id
    or asset_row.couple_id <> thread_row.couple_id
    or asset_row.reserved_parent_kind <> 'thread_message_media'
    or asset_row.reserved_parent_id <> new.message_id
    or asset_row.upload_purpose not in ('thread_media', 'voice_note')
    or asset_row.media_type not in ('image', 'voice')
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'thread message media asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_thread_message_media_allowed
before insert or update on public.thread_message_media
for each row
execute function internal.assert_thread_message_media_allowed();

create or replace function internal.insert_thread_message(
  p_thread_id uuid,
  p_body text,
  p_media_asset_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  thread_row public.conversation_threads%rowtype;
  normalized_body text;
  media_ids uuid[];
  media_count integer;
  unique_media_count integer;
  resolved_message_id uuid;
  first_asset public.media_assets%rowtype;
  media_row record;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  select *
  into thread_row
  from public.conversation_threads
  where id = p_thread_id
  for update;

  if not found
    or thread_row.deleted_at is not null
    or thread_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(thread_row.couple_id) then
    raise exception 'active entitled thread access is required'
      using errcode = '42501';
  end if;

  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);
  media_count = cardinality(media_ids);

  if media_count > 10 then
    raise exception 'thread messages can include at most 10 media assets'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from unnest(media_ids) as media_id(id)
    where media_id.id is null
  ) then
    raise exception 'thread message media asset id cannot be null'
      using errcode = '23514';
  end if;

  select count(distinct media_id.id)
  into unique_media_count
  from unnest(media_ids) as media_id(id);

  if unique_media_count <> media_count then
    raise exception 'thread message media asset ids must be unique'
      using errcode = '23514';
  end if;

  normalized_body = nullif(btrim(coalesce(p_body, '')), '');

  if normalized_body is not null and char_length(normalized_body) > 4000 then
    raise exception 'thread message body is too long'
      using errcode = '23514';
  end if;

  if normalized_body is null and media_count = 0 then
    raise exception 'thread message must include text or media'
      using errcode = '23514';
  end if;

  if media_count > 0 then
    select *
    into first_asset
    from public.media_assets
    where id = media_ids[1];

    if not found then
      raise exception 'thread message media asset is not usable'
        using errcode = '23514';
    end if;

    resolved_message_id = first_asset.reserved_parent_id;
  else
    resolved_message_id = extensions.gen_random_uuid();
  end if;

  insert into public.thread_messages (
    id,
    thread_id,
    sender_user_id,
    body
  ) values (
    resolved_message_id,
    thread_row.id,
    current_user_id,
    normalized_body
  );

  for media_row in
    select
      media_item.value as media_asset_id,
      media_item.ordinality::smallint as sort_order
    from unnest(media_ids) with ordinality as media_item(value, ordinality)
  loop
    insert into public.thread_message_media (
      message_id,
      media_asset_id,
      sort_order
    ) values (
      resolved_message_id,
      media_row.media_asset_id,
      media_row.sort_order
    );
  end loop;

  return resolved_message_id;
end;
$$;

create or replace function internal.create_daily_question_thread_with_message(
  p_instance_id uuid,
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
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  resolved_thread_id uuid;
  resolved_message_id uuid;
  visible_answer_count integer;
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
      'create_daily_question_thread_with_message',
      p_instance_id::text,
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
    'create_daily_question_thread_with_message',
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
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found or instance_row.status = 'shuffled' then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.daily_question_answers answer
    where answer.instance_id = instance_row.id
      and answer.user_id = current_user_id
      and answer.deleted_at is null
      and answer.moderation_status = 'visible'
  ) then
    raise exception 'you must answer this daily question before starting its thread'
      using errcode = '42501';
  end if;

  select count(distinct answer.user_id)
  into visible_answer_count
  from public.daily_question_answers answer
  where answer.instance_id = instance_row.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible';

  if visible_answer_count < 2 then
    raise exception 'daily question thread requires both partners to answer'
      using errcode = '23514';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'daily_question_thread:' || instance_row.id::text,
      0
    )
  );

  select existing_thread.thread_id
  into resolved_thread_id
  from public.daily_question_threads existing_thread
  where existing_thread.instance_id = instance_row.id;

  if resolved_thread_id is null then
    insert into public.conversation_threads (
      couple_id,
      kind,
      created_by_user_id
    ) values (
      couple_day_row.couple_id,
      'daily_question',
      current_user_id
    )
    returning id into resolved_thread_id;

    insert into public.daily_question_threads (
      instance_id,
      thread_id
    ) values (
      instance_row.id,
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
begin
  perform
    p_memory_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at;

  thread_id = null;
  message_id = null;

  raise exception 'memory threads require the memories migration'
    using errcode = '0A000';
end;
$$;

create or replace function internal.send_thread_message(
  p_thread_id uuid,
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
  resolved_message_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  request_hash = extensions.digest(
    concat_ws(
      '|',
      'send_thread_message',
      p_thread_id::text,
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
    'send_thread_message',
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

  resolved_message_id = internal.insert_thread_message(
    p_thread_id,
    p_body,
    p_media_asset_ids
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'thread_id', p_thread_id,
      'message_id', resolved_message_id
    )
  );

  return query
  select p_thread_id, resolved_message_id;
end;
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
          )
        )
      )
  );
$$;

create or replace function public.create_daily_question_thread_with_message(
  p_instance_id uuid,
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
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.create_daily_question_thread_with_message(
    p_instance_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.create_memory_thread_with_message(
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
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.create_memory_thread_with_message(
    p_memory_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.send_thread_message(
  p_thread_id uuid,
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
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.send_thread_message(
    p_thread_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.get_conversation_threads()
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
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_conversation_threads();
$$;

create or replace function public.get_thread_messages(p_thread_id uuid)
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
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_thread_messages(p_thread_id);
$$;

alter table public.conversation_threads enable row level security;
alter table public.daily_question_threads enable row level security;
alter table public.memory_threads enable row level security;
alter table public.thread_messages enable row level security;
alter table public.thread_message_media enable row level security;

create index conversation_threads_couple_created_at_idx
on public.conversation_threads (couple_id, created_at desc);

create index conversation_threads_couple_visibility_idx
on public.conversation_threads (couple_id, moderation_status, deleted_at);

create index thread_messages_thread_created_at_id_idx
on public.thread_messages (thread_id, created_at, id);

create index thread_messages_sender_created_at_idx
on public.thread_messages (sender_user_id, created_at desc);

create index thread_messages_thread_visibility_idx
on public.thread_messages (thread_id, moderation_status, deleted_at, created_at);

create index thread_message_media_media_asset_id_idx
on public.thread_message_media (media_asset_id);

revoke all on public.conversation_threads from public, anon, authenticated;
revoke all on public.daily_question_threads from public, anon, authenticated;
revoke all on public.memory_threads from public, anon, authenticated;
revoke all on public.thread_messages from public, anon, authenticated;
revoke all on public.thread_message_media from public, anon, authenticated;

grant all privileges on public.conversation_threads to service_role;
grant all privileges on public.daily_question_threads to service_role;
grant all privileges on public.memory_threads to service_role;
grant all privileges on public.thread_messages to service_role;
grant all privileges on public.thread_message_media to service_role;

revoke all on function internal.assert_conversation_thread_allowed() from public, anon, authenticated;
grant execute on function internal.assert_conversation_thread_allowed() to service_role;

revoke all on function internal.assert_daily_question_thread_allowed() from public, anon, authenticated;
grant execute on function internal.assert_daily_question_thread_allowed() to service_role;

revoke all on function internal.assert_memory_thread_allowed() from public, anon, authenticated;
grant execute on function internal.assert_memory_thread_allowed() to service_role;

revoke all on function internal.assert_thread_message_allowed() from public, anon, authenticated;
grant execute on function internal.assert_thread_message_allowed() to service_role;

revoke all on function internal.assert_thread_message_media_allowed() from public, anon, authenticated;
grant execute on function internal.assert_thread_message_media_allowed() to service_role;

revoke all on function internal.insert_thread_message(uuid, text, uuid[]) from public, anon, authenticated;
grant execute on function internal.insert_thread_message(uuid, text, uuid[]) to authenticated, service_role;

revoke all on function internal.create_daily_question_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.create_daily_question_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.create_memory_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.create_memory_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.send_thread_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.send_thread_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.get_conversation_threads() from public, anon, authenticated;
grant execute on function internal.get_conversation_threads() to authenticated, service_role;

revoke all on function internal.get_thread_messages(uuid) from public, anon, authenticated;
grant execute on function internal.get_thread_messages(uuid) to authenticated, service_role;

revoke all on function public.create_daily_question_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.create_daily_question_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.create_memory_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.create_memory_thread_with_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.send_thread_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.send_thread_message(uuid, text, uuid[], uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.get_conversation_threads() from public, anon;
grant execute on function public.get_conversation_threads() to authenticated, service_role;

revoke all on function public.get_thread_messages(uuid) from public, anon;
grant execute on function public.get_thread_messages(uuid) to authenticated, service_role;
