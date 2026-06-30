create or replace function internal.media_asset_has_live_reference(p_media_asset_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.profiles profile
    where profile.profile_photo_asset_id = p_media_asset_id
      and profile.deleted_at is null
  )
  or exists (
    select 1
    from public.daily_answer_media answer_media
    join public.daily_question_answers answer
      on answer.id = answer_media.answer_id
    where answer_media.media_asset_id = p_media_asset_id
      and answer.deleted_at is null
  )
  or exists (
    select 1
    from public.memory_media memory_media
    join public.memories memory
      on memory.id = memory_media.memory_id
    where memory_media.media_asset_id = p_media_asset_id
      and memory_media.deleted_at is null
      and memory.deleted_at is null
  )
  or exists (
    select 1
    from public.thread_message_media message_media
    join public.thread_messages message
      on message.id = message_media.message_id
    join public.conversation_threads thread
      on thread.id = message.thread_id
    where message_media.media_asset_id = p_media_asset_id
      and message.deleted_at is null
      and thread.deleted_at is null
  )
  or exists (
    select 1
    from public.widget_drawing_revisions revision
    join public.widget_canvases canvas
      on canvas.id = revision.canvas_id
    where revision.payload_media_asset_id = p_media_asset_id
      and revision.deleted_at is null
      and canvas.deleted_at is null
  );
$$;

create or replace function internal.queue_orphaned_media_asset_for_delete(p_media_asset_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  if p_media_asset_id is null then
    return false;
  end if;

  update public.media_assets asset
  set
    deleted_at = coalesce(asset.deleted_at, now()),
    storage_delete_status = case
      when asset.storage_delete_status = 'deleted' then 'deleted'
      when asset.storage_delete_status in ('pending', 'retrying') then asset.storage_delete_status
      else 'pending'
    end,
    last_storage_delete_error = null
  where asset.id = p_media_asset_id
    and asset.bucket <> 'report-snapshots'
    and asset.upload_status = 'finalized'
    and asset.upload_finalized_at is not null
    and asset.storage_delete_status in ('none', 'failed')
    and not internal.media_asset_has_live_reference(asset.id);

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.queue_orphaned_media_assets_for_delete(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_count integer;
begin
  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'orphaned media queue limit is out of range'
      using errcode = '23514';
  end if;

  with picked as (
    select asset.id
    from public.media_assets asset
    where asset.bucket <> 'report-snapshots'
      and asset.upload_status = 'finalized'
      and asset.upload_finalized_at is not null
      and asset.storage_delete_status in ('none', 'failed')
      and not internal.media_asset_has_live_reference(asset.id)
    order by asset.updated_at, asset.id
    for update skip locked
    limit p_limit
  ),
  queued as (
    update public.media_assets asset
    set
      deleted_at = coalesce(asset.deleted_at, now()),
      storage_delete_status = case
        when asset.storage_delete_status in ('pending', 'retrying') then asset.storage_delete_status
        else 'pending'
      end,
      last_storage_delete_error = null
    from picked
    where asset.id = picked.id
    returning asset.id
  )
  select count(*)::integer
  into queued_count
  from queued;

  return queued_count;
end;
$$;

create or replace function internal.queue_old_media_asset_if_orphaned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  old_media_asset_id uuid;
begin
  if TG_TABLE_SCHEMA <> 'public' then
    raise exception 'orphaned media trigger is not configured for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
      using errcode = '23514';
  end if;

  if TG_TABLE_NAME = 'profiles' then
    old_media_asset_id = old.profile_photo_asset_id;
  elsif TG_TABLE_NAME in ('daily_answer_media', 'memory_media', 'thread_message_media') then
    old_media_asset_id = old.media_asset_id;
  elsif TG_TABLE_NAME = 'widget_drawing_revisions' then
    old_media_asset_id = old.payload_media_asset_id;
  else
    raise exception 'orphaned media trigger is not configured for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
      using errcode = '23514';
  end if;

  perform internal.queue_orphaned_media_asset_for_delete(old_media_asset_id);

  if TG_OP = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function internal.queue_memory_media_assets_if_orphaned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  media_row record;
begin
  for media_row in
    select memory_media.media_asset_id
    from public.memory_media memory_media
    where memory_media.memory_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;

create or replace function internal.queue_daily_answer_media_assets_if_orphaned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  media_row record;
begin
  for media_row in
    select answer_media.media_asset_id
    from public.daily_answer_media answer_media
    where answer_media.answer_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;

create or replace function internal.queue_thread_message_media_assets_if_orphaned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  media_row record;
begin
  for media_row in
    select message_media.media_asset_id
    from public.thread_message_media message_media
    where message_media.message_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;

create or replace function internal.queue_thread_media_assets_if_orphaned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  media_row record;
begin
  for media_row in
    select message_media.media_asset_id
    from public.thread_message_media message_media
    join public.thread_messages message
      on message.id = message_media.message_id
    where message.thread_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;

create or replace function internal.queue_widget_payloads_if_orphaned()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  revision_row record;
begin
  for revision_row in
    select revision.payload_media_asset_id
    from public.widget_drawing_revisions revision
    where revision.canvas_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(
      revision_row.payload_media_asset_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists queue_orphaned_profile_photo_after_update on public.profiles;
create constraint trigger queue_orphaned_profile_photo_after_update
after update of profile_photo_asset_id, deleted_at on public.profiles
deferrable initially deferred
for each row
when (
  old.profile_photo_asset_id is not null
  and (
    old.profile_photo_asset_id is distinct from new.profile_photo_asset_id
    or (old.deleted_at is null and new.deleted_at is not null)
  )
)
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_profile_photo_after_delete on public.profiles;
create constraint trigger queue_orphaned_profile_photo_after_delete
after delete on public.profiles
deferrable initially deferred
for each row
when (old.profile_photo_asset_id is not null)
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_daily_answer_media_after_update on public.daily_answer_media;
create constraint trigger queue_orphaned_daily_answer_media_after_update
after update of media_asset_id on public.daily_answer_media
deferrable initially deferred
for each row
when (old.media_asset_id is distinct from new.media_asset_id)
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_daily_answer_media_after_delete on public.daily_answer_media;
create constraint trigger queue_orphaned_daily_answer_media_after_delete
after delete on public.daily_answer_media
deferrable initially deferred
for each row
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_daily_answer_media_after_answer_delete on public.daily_question_answers;
create constraint trigger queue_orphaned_daily_answer_media_after_answer_delete
after update of deleted_at on public.daily_question_answers
deferrable initially deferred
for each row
when (old.deleted_at is null and new.deleted_at is not null)
execute function internal.queue_daily_answer_media_assets_if_orphaned();

drop trigger if exists queue_orphaned_memory_media_after_update on public.memory_media;
create constraint trigger queue_orphaned_memory_media_after_update
after update of media_asset_id, deleted_at on public.memory_media
deferrable initially deferred
for each row
when (
  old.media_asset_id is distinct from new.media_asset_id
  or (old.deleted_at is null and new.deleted_at is not null)
)
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_memory_media_after_delete on public.memory_media;
create constraint trigger queue_orphaned_memory_media_after_delete
after delete on public.memory_media
deferrable initially deferred
for each row
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_memory_media_after_memory_delete on public.memories;
create constraint trigger queue_orphaned_memory_media_after_memory_delete
after update of deleted_at on public.memories
deferrable initially deferred
for each row
when (old.deleted_at is null and new.deleted_at is not null)
execute function internal.queue_memory_media_assets_if_orphaned();

drop trigger if exists queue_orphaned_thread_message_media_after_update on public.thread_message_media;
create constraint trigger queue_orphaned_thread_message_media_after_update
after update of media_asset_id on public.thread_message_media
deferrable initially deferred
for each row
when (old.media_asset_id is distinct from new.media_asset_id)
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_thread_message_media_after_delete on public.thread_message_media;
create constraint trigger queue_orphaned_thread_message_media_after_delete
after delete on public.thread_message_media
deferrable initially deferred
for each row
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_thread_message_media_after_message_delete on public.thread_messages;
create constraint trigger queue_orphaned_thread_message_media_after_message_delete
after update of deleted_at on public.thread_messages
deferrable initially deferred
for each row
when (old.deleted_at is null and new.deleted_at is not null)
execute function internal.queue_thread_message_media_assets_if_orphaned();

drop trigger if exists queue_orphaned_thread_media_after_thread_delete on public.conversation_threads;
create constraint trigger queue_orphaned_thread_media_after_thread_delete
after update of deleted_at on public.conversation_threads
deferrable initially deferred
for each row
when (old.deleted_at is null and new.deleted_at is not null)
execute function internal.queue_thread_media_assets_if_orphaned();

drop trigger if exists queue_orphaned_widget_payload_after_update on public.widget_drawing_revisions;
create constraint trigger queue_orphaned_widget_payload_after_update
after update of payload_media_asset_id, deleted_at on public.widget_drawing_revisions
deferrable initially deferred
for each row
when (
  old.payload_media_asset_id is distinct from new.payload_media_asset_id
  or (old.deleted_at is null and new.deleted_at is not null)
)
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_widget_payload_after_delete on public.widget_drawing_revisions;
create constraint trigger queue_orphaned_widget_payload_after_delete
after delete on public.widget_drawing_revisions
deferrable initially deferred
for each row
execute function internal.queue_old_media_asset_if_orphaned();

drop trigger if exists queue_orphaned_widget_payload_after_canvas_delete on public.widget_canvases;
create constraint trigger queue_orphaned_widget_payload_after_canvas_delete
after update of deleted_at on public.widget_canvases
deferrable initially deferred
for each row
when (old.deleted_at is null and new.deleted_at is not null)
execute function internal.queue_widget_payloads_if_orphaned();

create or replace function internal.invoke_media_storage_cleanup()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.media_storage_cleanup_queued', true) = '1' then
    return null;
  end if;

  if not exists (
    select 1
    from public.media_assets asset
    where asset.storage_delete_status = 'pending'
  ) then
    return null;
  end if;

  perform set_config('paeonia.media_storage_cleanup_queued', '1', true);

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in ('media_storage_cleanup_secret', 'widget_drain_secret')
  order by case name
    when 'media_storage_cleanup_secret' then 0
    else 1
  end
  limit 1;

  if coalesce(drain_secret, '') <> '' then
    perform net.http_post(
      url := 'https://api.paeonia.no/functions/v1/cleanup-media-storage',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-drain-secret', drain_secret
      ),
      body := '{}'::jsonb
    );
  end if;

  return null;
end;
$$;

drop trigger if exists invoke_media_storage_cleanup_on_media_assets on public.media_assets;
create trigger invoke_media_storage_cleanup_on_media_assets
after update of storage_delete_status on public.media_assets
for each statement
execute function internal.invoke_media_storage_cleanup();

create or replace function public.claim_media_storage_deletes(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_retry_after interval default interval '15 minutes',
  p_max_attempts integer default 5
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  storage_delete_attempts integer
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.claim_media_storage_deletes(
    p_now,
    p_limit,
    p_retry_after,
    p_max_attempts
  );
$$;

create or replace function public.mark_media_storage_deleted(p_media_asset_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.mark_media_storage_deleted(p_media_asset_id);
$$;

create or replace function public.mark_media_storage_delete_failed(
  p_media_asset_id uuid,
  p_error text,
  p_terminal boolean default false
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.mark_media_storage_delete_failed(
    p_media_asset_id,
    p_error,
    p_terminal
  );
$$;

create or replace function public.claim_report_snapshot_storage_deletes(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_retry_after interval default interval '15 minutes',
  p_max_attempts integer default 5
)
returns table (
  snapshot_asset_id uuid,
  report_id uuid,
  bucket text,
  storage_path text,
  storage_delete_attempts integer
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.claim_report_snapshot_storage_deletes(
    p_now,
    p_limit,
    p_retry_after,
    p_max_attempts
  );
$$;

create or replace function public.mark_report_snapshot_storage_deleted(
  p_snapshot_asset_id uuid
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.mark_report_snapshot_storage_deleted(p_snapshot_asset_id);
$$;

create or replace function public.mark_report_snapshot_storage_delete_failed(
  p_snapshot_asset_id uuid,
  p_error text,
  p_terminal boolean default false
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.mark_report_snapshot_storage_delete_failed(
    p_snapshot_asset_id,
    p_error,
    p_terminal
  );
$$;

select internal.queue_orphaned_media_assets_for_delete(10000);

revoke all on function internal.media_asset_has_live_reference(uuid) from public, anon, authenticated;
grant execute on function internal.media_asset_has_live_reference(uuid) to service_role;

revoke all on function internal.queue_orphaned_media_asset_for_delete(uuid) from public, anon, authenticated;
grant execute on function internal.queue_orphaned_media_asset_for_delete(uuid) to service_role;

revoke all on function internal.queue_orphaned_media_assets_for_delete(integer) from public, anon, authenticated;
grant execute on function internal.queue_orphaned_media_assets_for_delete(integer) to service_role;

revoke all on function internal.queue_old_media_asset_if_orphaned() from public, anon, authenticated;

revoke all on function internal.queue_memory_media_assets_if_orphaned() from public, anon, authenticated;

revoke all on function internal.queue_daily_answer_media_assets_if_orphaned() from public, anon, authenticated;

revoke all on function internal.queue_thread_message_media_assets_if_orphaned() from public, anon, authenticated;

revoke all on function internal.queue_thread_media_assets_if_orphaned() from public, anon, authenticated;

revoke all on function internal.queue_widget_payloads_if_orphaned() from public, anon, authenticated;

revoke all on function internal.invoke_media_storage_cleanup() from public, anon, authenticated;
grant execute on function internal.invoke_media_storage_cleanup() to service_role;

revoke all on function public.claim_media_storage_deletes(timestamptz, integer, interval, integer) from public, anon, authenticated;
grant execute on function public.claim_media_storage_deletes(timestamptz, integer, interval, integer) to service_role;

revoke all on function public.mark_media_storage_deleted(uuid) from public, anon, authenticated;
grant execute on function public.mark_media_storage_deleted(uuid) to service_role;

revoke all on function public.mark_media_storage_delete_failed(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.mark_media_storage_delete_failed(uuid, text, boolean) to service_role;

revoke all on function public.claim_report_snapshot_storage_deletes(timestamptz, integer, interval, integer) from public, anon, authenticated;
grant execute on function public.claim_report_snapshot_storage_deletes(timestamptz, integer, interval, integer) to service_role;

revoke all on function public.mark_report_snapshot_storage_deleted(uuid) from public, anon, authenticated;
grant execute on function public.mark_report_snapshot_storage_deleted(uuid) to service_role;

revoke all on function public.mark_report_snapshot_storage_delete_failed(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.mark_report_snapshot_storage_delete_failed(uuid, text, boolean) to service_role;
