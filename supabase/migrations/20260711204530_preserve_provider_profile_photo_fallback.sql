-- Keep an imported OAuth profile photo as a private fallback behind a person's
-- optional Paeonia-uploaded override. The effective avatar is always the custom
-- photo first, then the provider fallback.

alter table public.profiles
add column if not exists provider_profile_photo_asset_id uuid,
add column if not exists provider_profile_photo_source text;

alter table public.profiles
add constraint profiles_provider_profile_photo_source_check
check (
  (provider_profile_photo_asset_id is null and provider_profile_photo_source is null)
  or (
    provider_profile_photo_asset_id is not null
    and provider_profile_photo_source = 'google'
  )
);

alter table public.profiles
add constraint profiles_provider_profile_photo_asset_id_fkey
foreign key (provider_profile_photo_asset_id)
references public.media_assets (id)
on delete restrict;

create index profiles_provider_profile_photo_asset_id_idx
on public.profiles (provider_profile_photo_asset_id)
where provider_profile_photo_asset_id is not null;

grant select (
  provider_profile_photo_asset_id,
  provider_profile_photo_source
) on public.profiles to authenticated;

create or replace function internal.assert_profile_photo_asset_owner()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  asset_row public.media_assets%rowtype;
  candidate_asset_id uuid;
begin
  if new.deleted_at is not null then
    new.profile_photo_asset_id = null;
    new.provider_profile_photo_asset_id = null;
    new.provider_profile_photo_source = null;
    return new;
  end if;

  if (new.provider_profile_photo_asset_id is null)
    <> (new.provider_profile_photo_source is null) then
    raise exception 'provider profile photo asset and source must be set together'
      using errcode = '23514';
  end if;

  if new.provider_profile_photo_source is not null
    and new.provider_profile_photo_source <> 'google' then
    raise exception 'provider profile photo source is not supported'
      using errcode = '23514';
  end if;

  foreach candidate_asset_id in array array[
    new.profile_photo_asset_id,
    new.provider_profile_photo_asset_id
  ]
  loop
    if candidate_asset_id is null then
      continue;
    end if;

    select *
    into asset_row
    from public.media_assets
    where id = candidate_asset_id;

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
  end loop;

  return new;
end;
$$;

drop trigger if exists assert_profiles_profile_photo_asset_owner on public.profiles;
create trigger assert_profiles_profile_photo_asset_owner
before insert or update of
  profile_photo_asset_id,
  provider_profile_photo_asset_id,
  provider_profile_photo_source,
  deleted_at
on public.profiles
for each row
execute function internal.assert_profile_photo_asset_owner();

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
    where (
        profile.profile_photo_asset_id = p_media_asset_id
        or profile.provider_profile_photo_asset_id = p_media_asset_id
      )
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
    perform internal.queue_orphaned_media_asset_for_delete(old.profile_photo_asset_id);
    perform internal.queue_orphaned_media_asset_for_delete(
      old.provider_profile_photo_asset_id
    );

    if TG_OP = 'DELETE' then
      return old;
    end if;
    return new;
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

drop trigger if exists queue_orphaned_profile_photo_after_update on public.profiles;
create constraint trigger queue_orphaned_profile_photo_after_update
after update of
  profile_photo_asset_id,
  provider_profile_photo_asset_id,
  provider_profile_photo_source,
  deleted_at
on public.profiles
deferrable initially deferred
for each row
when (
  (
    old.profile_photo_asset_id is not null
    and (
      old.profile_photo_asset_id is distinct from new.profile_photo_asset_id
      or (old.deleted_at is null and new.deleted_at is not null)
    )
  )
  or (
    old.provider_profile_photo_asset_id is not null
    and (
      old.provider_profile_photo_asset_id
        is distinct from new.provider_profile_photo_asset_id
      or (old.deleted_at is null and new.deleted_at is not null)
    )
  )
)
execute function internal.queue_old_media_asset_if_orphaned();

-- Extend the latest media authorization function so the owner and their active
-- partner can read the private provider fallback through the existing signed-URL
-- path. No provider URL is stored or returned.
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
              where (
                  profile.profile_photo_asset_id = asset.id
                  or profile.provider_profile_photo_asset_id = asset.id
                )
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

-- Keep the public relationship-state shape stable while returning the effective
-- partner avatar (custom override first, provider fallback second).
create or replace function internal.get_current_relationship_state()
returns table (
  couple_id uuid,
  pair_id uuid,
  relationship_status text,
  member_status text,
  partner_user_id uuid,
  partner_display_name text,
  partner_profile_photo_asset_id uuid,
  started_on date,
  ended_at timestamptz,
  delete_after timestamptz,
  ended_notice_seen_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    couple.id,
    couple.pair_id,
    couple.status,
    self_member.status,
    partner_member.user_id,
    case
      when partner_profile.moderation_status = 'visible' then partner_profile.display_name
      else null
    end,
    case
      when partner_profile.moderation_status = 'visible' then coalesce(
        partner_profile.profile_photo_asset_id,
        partner_profile.provider_profile_photo_asset_id
      )
      else null
    end,
    couple.started_on,
    couple.ended_at,
    couple.delete_after,
    self_member.ended_notice_seen_at
  from public.couple_members self_member
  join public.couples couple
    on couple.id = self_member.couple_id
  left join public.couple_members partner_member
    on partner_member.couple_id = self_member.couple_id
    and partner_member.user_id <> self_member.user_id
  left join public.profiles partner_profile
    on partner_profile.user_id = partner_member.user_id
  where self_member.user_id = (select auth.uid())
    and (
      (couple.status = 'active' and self_member.status = 'active')
      or (
        couple.status = 'ended'
        and self_member.status in ('ended_notice_pending', 'ended_notice_seen', 'left')
      )
    )
  order by
    case when couple.status = 'active' and self_member.status = 'active' then 0 else 1 end,
    couple.created_at desc
  limit 1;
$$;

-- Paired profile editing must update the display name and custom-photo override
-- together. Authenticated intentionally has no direct UPDATE privilege on
-- profiles.display_name, so expose one narrowly scoped, validated boundary.
create or replace function public.update_own_profile(
  p_display_name text,
  p_profile_photo_asset_id uuid
)
returns table (
  user_id uuid,
  display_name text,
  time_zone_id text,
  time_zone_updated_at timestamptz,
  onboarding_completed_at timestamptz,
  profile_photo_asset_id uuid,
  provider_profile_photo_asset_id uuid,
  provider_profile_photo_source text
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  normalized_display_name text;
begin
  current_user_id = (select auth.uid());
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_display_name = btrim(coalesce(p_display_name, ''));
  if char_length(normalized_display_name) not between 1 and 80
    or normalized_display_name ~ '[[:space:]]' then
    raise exception 'display name must be one name between 1 and 80 characters'
      using errcode = '23514';
  end if;

  return query
  update public.profiles profile
  set
    display_name = normalized_display_name,
    profile_photo_asset_id = p_profile_photo_asset_id
  where profile.user_id = current_user_id
    and profile.deleted_at is null
  returning
    profile.user_id,
    profile.display_name,
    profile.time_zone_id,
    profile.time_zone_updated_at,
    profile.onboarding_completed_at,
    profile.profile_photo_asset_id,
    profile.provider_profile_photo_asset_id,
    profile.provider_profile_photo_source;

  if not found then
    raise exception 'active profile was not found'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.update_own_profile(text, uuid) from public, anon;
grant execute on function public.update_own_profile(text, uuid) to authenticated, service_role;

comment on function public.update_own_profile(text, uuid)
is 'Atomically updates the authenticated user profile display name and optional custom-photo override; the provider fallback is preserved.';

-- Provider imports use a separate boundary so clients can create the fallback
-- but cannot relabel it as a custom override or mutate another profile.
create or replace function public.set_own_provider_profile_photo(
  p_profile_photo_asset_id uuid,
  p_source text
)
returns table (
  user_id uuid,
  display_name text,
  time_zone_id text,
  time_zone_updated_at timestamptz,
  onboarding_completed_at timestamptz,
  profile_photo_asset_id uuid,
  provider_profile_photo_asset_id uuid,
  provider_profile_photo_source text
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
begin
  current_user_id = (select auth.uid());
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_profile_photo_asset_id is null or p_source is distinct from 'google' then
    raise exception 'provider profile photo input is invalid'
      using errcode = '23514';
  end if;

  return query
  update public.profiles profile
  set
    provider_profile_photo_asset_id = p_profile_photo_asset_id,
    provider_profile_photo_source = p_source
  where profile.user_id = current_user_id
    and profile.deleted_at is null
  returning
    profile.user_id,
    profile.display_name,
    profile.time_zone_id,
    profile.time_zone_updated_at,
    profile.onboarding_completed_at,
    profile.profile_photo_asset_id,
    profile.provider_profile_photo_asset_id,
    profile.provider_profile_photo_source;

  if not found then
    raise exception 'active profile was not found'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.set_own_provider_profile_photo(uuid, text) from public, anon;
grant execute on function public.set_own_provider_profile_photo(uuid, text)
to authenticated, service_role;

comment on function public.set_own_provider_profile_photo(uuid, text)
is 'Links a private, owner-scoped OAuth photo as the authenticated user provider fallback.';

comment on column public.profiles.profile_photo_asset_id
is 'Optional Paeonia-uploaded profile-photo override. When null, clients use provider_profile_photo_asset_id.';

comment on column public.profiles.provider_profile_photo_asset_id
is 'Private imported OAuth profile-photo fallback; never stores or exposes the provider URL.';

comment on column public.profiles.provider_profile_photo_source
is 'OAuth source for the imported private fallback. MVP supports google.';
