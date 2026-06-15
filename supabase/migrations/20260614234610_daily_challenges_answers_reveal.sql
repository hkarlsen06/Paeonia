create table public.couple_days (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  local_date date not null,
  anchor_time_zone_id text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),

  constraint couple_days_couple_local_date_unique
    unique (couple_id, local_date),
  constraint couple_days_anchor_time_zone_id_check
    check (char_length(btrim(anchor_time_zone_id)) between 1 and 128),
  constraint couple_days_window_check
    check (starts_at < ends_at)
);

create table public.daily_challenges (
  couple_day_id uuid not null references public.couple_days (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  completed_at timestamptz,
  partner_notified_at timestamptz,

  constraint daily_challenges_primary_key
    primary key (couple_day_id, user_id),
  constraint daily_challenges_partner_notified_check
    check (partner_notified_at is null or completed_at is not null)
);

create table public.daily_question_instances (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_day_id uuid not null references public.couple_days (id) on delete restrict,
  question_version_id uuid not null references public.question_versions (id) on delete restrict,
  seeded_for_user_id uuid not null references auth.users (id) on delete restrict,
  slot_number smallint not null,
  status text not null default 'active',
  replaced_by_instance_id uuid references public.daily_question_instances (id) on delete restrict,
  replaced_at timestamptz,
  created_at timestamptz not null default now(),

  constraint daily_question_instances_slot_number_check
    check (slot_number between 1 and 3),
  constraint daily_question_instances_status_check
    check (status in ('active', 'shuffled', 'answered')),
  constraint daily_question_instances_replaced_state_check
    check (
      (status = 'shuffled' and replaced_at is not null)
      or (status <> 'shuffled' and replaced_by_instance_id is null and replaced_at is null)
    )
);

create table public.daily_question_shuffles (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  couple_day_id uuid not null references public.couple_days (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  question_id uuid not null references public.questions (id) on delete restrict,
  skipped_instance_id uuid not null references public.daily_question_instances (id) on delete restrict,
  replacement_instance_id uuid not null references public.daily_question_instances (id) on delete restrict,
  slot_number smallint not null,
  skipped_at timestamptz not null default now(),
  exclude_until timestamptz not null,

  constraint daily_question_shuffles_slot_number_check
    check (slot_number between 1 and 3),
  constraint daily_question_shuffles_exclude_until_check
    check (exclude_until > skipped_at)
);

create table public.daily_question_answers (
  id uuid primary key default extensions.gen_random_uuid(),
  instance_id uuid not null references public.daily_question_instances (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  moderation_status text not null default 'visible',
  moderated_at timestamptz,
  moderated_by uuid references auth.users (id) on delete set null,
  moderation_report_id uuid,

  constraint daily_question_answers_instance_user_unique
    unique (instance_id, user_id),
  constraint daily_question_answers_moderation_status_check
    check (moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected'))
);

create trigger set_daily_question_answers_updated_at
before update on public.daily_question_answers
for each row
execute function internal.set_updated_at();

create table public.daily_answer_text (
  answer_id uuid primary key references public.daily_question_answers (id) on delete restrict,
  body text not null,

  constraint daily_answer_text_body_check
    check (char_length(btrim(body)) between 1 and 2000)
);

create table public.daily_answer_partner_choice (
  answer_id uuid primary key references public.daily_question_answers (id) on delete restrict,
  selected_user_id uuid not null references auth.users (id) on delete restrict
);

create table public.daily_answer_media (
  answer_id uuid not null references public.daily_question_answers (id) on delete restrict,
  media_asset_id uuid not null references public.media_assets (id) on delete restrict,
  sort_order smallint not null,

  constraint daily_answer_media_primary_key
    primary key (answer_id, media_asset_id),
  constraint daily_answer_media_sort_order_check
    check (sort_order between 1 and 10),
  constraint daily_answer_media_answer_sort_order_unique
    unique (answer_id, sort_order)
);

create or replace function internal.get_current_entitled_couple_id()
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  select couple.id
  into resolved_couple_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
  order by couple.created_at desc
  limit 1;

  if resolved_couple_id is null
    or not internal.can_access_couple_content(resolved_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  return resolved_couple_id;
end;
$$;

create or replace function internal.resolve_couple_day_anchor_at(
  p_couple_id uuid,
  p_observed_at timestamptz
)
returns table (
  local_date date,
  anchor_time_zone_id text,
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  anchor_row record;
begin
  if p_observed_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  select
    coalesce(timezone_name.name, 'UTC') as resolved_time_zone_id,
    p_observed_at at time zone coalesce(timezone_name.name, 'UTC') as local_observed_at
  into anchor_row
  from public.couple_members member
  left join public.profiles profile
    on profile.user_id = member.user_id
  left join pg_timezone_names timezone_name
    on timezone_name.name = profile.time_zone_id
  where member.couple_id = p_couple_id
    and member.status = 'active'
  order by (p_observed_at at time zone coalesce(timezone_name.name, 'UTC')) asc,
    coalesce(timezone_name.name, 'UTC') asc
  limit 1;

  if anchor_row.resolved_time_zone_id is null then
    raise exception 'active couple members are required'
      using errcode = '23514';
  end if;

  local_date = anchor_row.local_observed_at::date;
  anchor_time_zone_id = anchor_row.resolved_time_zone_id;
  starts_at = local_date::timestamp at time zone anchor_time_zone_id;
  ends_at = (local_date::timestamp + interval '1 day') at time zone anchor_time_zone_id;

  return next;
end;
$$;

create or replace function internal.resolve_couple_day_anchor(p_couple_id uuid)
returns table (
  local_date date,
  anchor_time_zone_id text,
  starts_at timestamptz,
  ends_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.resolve_couple_day_anchor_at(p_couple_id, now());
$$;

create or replace function internal.get_or_create_couple_day_at(
  p_couple_id uuid,
  p_observed_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  anchor_row record;
  resolved_couple_day_id uuid;
begin
  if p_observed_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  select id
  into resolved_couple_day_id
  from public.couple_days
  where couple_id = p_couple_id
    and p_observed_at >= starts_at
    and p_observed_at < ends_at
  order by starts_at desc
  limit 1;

  if resolved_couple_day_id is not null then
    return resolved_couple_day_id;
  end if;

  select *
  into anchor_row
  from internal.resolve_couple_day_anchor_at(p_couple_id, p_observed_at);

  insert into public.couple_days (
    couple_id,
    local_date,
    anchor_time_zone_id,
    starts_at,
    ends_at
  ) values (
    p_couple_id,
    anchor_row.local_date,
    anchor_row.anchor_time_zone_id,
    anchor_row.starts_at,
    anchor_row.ends_at
  )
  on conflict (couple_id, local_date) do nothing
  returning id into resolved_couple_day_id;

  if resolved_couple_day_id is null then
    select id
    into resolved_couple_day_id
    from public.couple_days
    where couple_id = p_couple_id
      and local_date = anchor_row.local_date;
  end if;

  return resolved_couple_day_id;
end;
$$;

create or replace function internal.get_or_create_today_couple_day(p_couple_id uuid)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.get_or_create_couple_day_at(p_couple_id, now());
$$;

create or replace function internal.pick_daily_question_version(
  p_couple_day_id uuid,
  p_user_id uuid,
  p_excluded_question_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  picked_question_version_id uuid;
begin
  select version.id
  into picked_question_version_id
  from public.question_versions version
  join public.questions question
    on question.id = version.question_id
  join public.question_collections collection
    on collection.id = question.collection_id
  where collection.kind = 'system'
    and collection.status = 'active'
    and question.status = 'active'
    and version.status = 'active'
    and (p_excluded_question_id is null or question.id <> p_excluded_question_id)
    and exists (
      select 1
      from public.question_version_localizations localization
      where localization.question_version_id = version.id
        and localization.locale = 'en'
    )
    and exists (
      select 1
      from public.question_version_localizations localization
      where localization.question_version_id = version.id
        and localization.locale = 'nb'
    )
    and (
      select count(*)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ) between 1 and 2
    and not exists (
      select 1
      from public.daily_question_instances existing_instance
      join public.question_versions existing_version
        on existing_version.id = existing_instance.question_version_id
      where existing_instance.couple_day_id = p_couple_day_id
        and existing_instance.seeded_for_user_id = p_user_id
        and existing_instance.status = 'active'
        and existing_version.question_id = question.id
    )
    and not exists (
      select 1
      from public.daily_question_shuffles shuffle
      where shuffle.user_id = p_user_id
        and shuffle.question_id = question.id
        and shuffle.exclude_until > now()
    )
    and (
      (
        select max(answer.created_at)
        from public.daily_question_answers answer
        join public.daily_question_instances answered_instance
          on answered_instance.id = answer.instance_id
        join public.question_versions answered_version
          on answered_version.id = answered_instance.question_version_id
        where answer.user_id = p_user_id
          and answer.deleted_at is null
          and answered_version.question_id = question.id
      ) is null
      or (
        question.resurfaceable
        and (
          select max(answer.created_at)
          from public.daily_question_answers answer
          join public.daily_question_instances answered_instance
            on answered_instance.id = answer.instance_id
          join public.question_versions answered_version
            on answered_version.id = answered_instance.question_version_id
          where answer.user_id = p_user_id
            and answer.deleted_at is null
            and answered_version.question_id = question.id
        ) <= now() - make_interval(months => coalesce(question.resurface_after_months, 6)::integer)
      )
    )
  order by random()
  limit 1;

  if picked_question_version_id is null then
    raise exception 'no eligible daily questions are available'
      using errcode = '22023';
  end if;

  return picked_question_version_id;
end;
$$;

create or replace function internal.ensure_daily_challenge_slots(p_couple_day_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_day_row public.couple_days%rowtype;
  member_row record;
  picked_question_version_id uuid;
begin
  select *
  into couple_day_row
  from public.couple_days
  where id = p_couple_day_id
  for update;

  if not found then
    raise exception 'couple day was not found'
      using errcode = '22023';
  end if;

  for member_row in
    select member.user_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = couple_day_row.couple_id
      and member.status = 'active'
      and couple.status = 'active'
    order by member.joined_at, member.user_id
  loop
    insert into public.daily_challenges (couple_day_id, user_id)
    values (p_couple_day_id, member_row.user_id)
    on conflict (couple_day_id, user_id) do nothing;

    for current_slot_number in 1..3 loop
      if not exists (
        select 1
        from public.daily_question_instances instance
        where instance.couple_day_id = p_couple_day_id
          and instance.seeded_for_user_id = member_row.user_id
          and instance.slot_number = current_slot_number
          and instance.status in ('active', 'answered')
      ) then
        picked_question_version_id = internal.pick_daily_question_version(
          p_couple_day_id,
          member_row.user_id,
          null
        );

        insert into public.daily_question_instances (
          couple_day_id,
          question_version_id,
          seeded_for_user_id,
          slot_number
        ) values (
          p_couple_day_id,
          picked_question_version_id,
          member_row.user_id,
          current_slot_number
        );
      end if;
    end loop;
  end loop;
end;
$$;

create or replace function internal.assert_daily_challenge_member()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.couple_days couple_day
  where couple_day.id = new.couple_day_id;

  if resolved_couple_id is null or not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'daily challenge user must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_challenge_member
before insert or update on public.daily_challenges
for each row
execute function internal.assert_daily_challenge_member();

create or replace function internal.assert_daily_question_instance_member()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.couple_days couple_day
  where couple_day.id = new.couple_day_id;

  if resolved_couple_id is null or not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.seeded_for_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'daily question instance user must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_question_instance_member
before insert or update on public.daily_question_instances
for each row
execute function internal.assert_daily_question_instance_member();

create or replace function internal.assert_daily_question_shuffle_valid()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_day_row public.couple_days%rowtype;
  skipped_row public.daily_question_instances%rowtype;
  replacement_row public.daily_question_instances%rowtype;
  skipped_question_id uuid;
begin
  select *
  into couple_day_row
  from public.couple_days
  where id = new.couple_day_id;

  select *
  into skipped_row
  from public.daily_question_instances
  where id = new.skipped_instance_id;

  select *
  into replacement_row
  from public.daily_question_instances
  where id = new.replacement_instance_id;

  select version.question_id
  into skipped_question_id
  from public.question_versions version
  where version.id = skipped_row.question_version_id;

  if couple_day_row.id is null
    or couple_day_row.couple_id <> new.couple_id
    or skipped_row.id is null
    or replacement_row.id is null
    or skipped_row.couple_day_id <> new.couple_day_id
    or replacement_row.couple_day_id <> new.couple_day_id
    or skipped_row.seeded_for_user_id <> new.user_id
    or replacement_row.seeded_for_user_id <> new.user_id
    or skipped_row.slot_number <> new.slot_number
    or replacement_row.slot_number <> new.slot_number
    or skipped_question_id <> new.question_id then
    raise exception 'daily question shuffle rows must match skipped and replacement instances'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_question_shuffle_valid
before insert or update on public.daily_question_shuffles
for each row
execute function internal.assert_daily_question_shuffle_valid();

create or replace function internal.assert_daily_question_answer_member()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.daily_question_instances instance
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  where instance.id = new.instance_id;

  if resolved_couple_id is null or not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'daily answer user must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_question_answer_member
before insert or update on public.daily_question_answers
for each row
execute function internal.assert_daily_question_answer_member();

create or replace function internal.assert_daily_answer_text_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from public.daily_question_answers answer
    join public.daily_question_instances instance
      on instance.id = answer.instance_id
    join public.question_answer_kinds answer_kind
      on answer_kind.question_version_id = instance.question_version_id
    where answer.id = new.answer_id
      and answer_kind.answer_kind = 'text'
  ) then
    raise exception 'text answers are not allowed for this question'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_answer_text_allowed
before insert or update on public.daily_answer_text
for each row
execute function internal.assert_daily_answer_text_allowed();

create or replace function internal.assert_daily_answer_partner_choice_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.daily_question_answers answer
  join public.daily_question_instances instance
    on instance.id = answer.instance_id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join public.question_answer_kinds answer_kind
    on answer_kind.question_version_id = instance.question_version_id
  where answer.id = new.answer_id
    and answer_kind.answer_kind = 'partner_choice';

  if resolved_couple_id is null then
    raise exception 'partner choice answers are not allowed for this question'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.selected_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'partner choice must select an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_answer_partner_choice_allowed
before insert or update on public.daily_answer_partner_choice
for each row
execute function internal.assert_daily_answer_partner_choice_allowed();

create or replace function internal.assert_daily_answer_media_allowed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  answer_row public.daily_question_answers%rowtype;
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  asset_row public.media_assets%rowtype;
  required_answer_kind text;
begin
  select *
  into answer_row
  from public.daily_question_answers
  where id = new.answer_id;

  select *
  into instance_row
  from public.daily_question_instances
  where id = answer_row.instance_id;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  select *
  into asset_row
  from public.media_assets
  where id = new.media_asset_id;

  required_answer_kind = case asset_row.media_type
    when 'image' then 'photo'
    when 'voice' then 'voice'
    else null
  end;

  if answer_row.id is null
    or instance_row.id is null
    or couple_day_row.id is null
    or asset_row.id is null
    or required_answer_kind is null
    or asset_row.owner_user_id <> answer_row.user_id
    or asset_row.couple_id <> couple_day_row.couple_id
    or asset_row.reserved_parent_kind <> 'daily_answer_media'
    or asset_row.reserved_parent_id <> answer_row.id
    or asset_row.upload_purpose not in ('daily_answer_media', 'voice_note')
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'daily answer media asset is not usable for this answer'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.question_answer_kinds answer_kind
    where answer_kind.question_version_id = instance_row.question_version_id
      and answer_kind.answer_kind = required_answer_kind
  ) then
    raise exception 'media answer kind is not allowed for this question'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_daily_answer_media_allowed
before insert or update on public.daily_answer_media
for each row
execute function internal.assert_daily_answer_media_allowed();

create or replace function internal.can_view_daily_answer(p_answer_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.daily_question_answers target_answer
    join public.daily_question_instances instance
      on instance.id = target_answer.instance_id
    join public.couple_days couple_day
      on couple_day.id = instance.couple_day_id
    where target_answer.id = p_answer_id
      and target_answer.deleted_at is null
      and target_answer.moderation_status = 'visible'
      and internal.can_access_couple_content(couple_day.couple_id)
      and (
        target_answer.user_id = (select auth.uid())
        or exists (
          select 1
          from public.daily_question_answers viewer_answer
          where viewer_answer.instance_id = target_answer.instance_id
            and viewer_answer.user_id = (select auth.uid())
            and viewer_answer.deleted_at is null
            and viewer_answer.moderation_status = 'visible'
        )
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
      )
  );
$$;

create or replace function internal.start_daily_challenge(
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
  resolved_couple_id uuid;
  resolved_couple_day_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  resolved_couple_id = internal.get_current_entitled_couple_id();

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'start_daily_challenge',
      resolved_couple_id::text,
      p_local_created_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'start_daily_challenge',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'couple_day_id')::uuid;
  end if;

  resolved_couple_day_id = internal.get_or_create_couple_day_at(
    resolved_couple_id,
    p_local_created_at
  );

  perform internal.ensure_daily_challenge_slots(resolved_couple_day_id);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('couple_day_id', resolved_couple_day_id)
  );

  return resolved_couple_day_id;
end;
$$;

create or replace function internal.shuffle_daily_question(
  p_slot_number smallint,
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
  active_instance_row public.daily_question_instances%rowtype;
  skipped_question_id uuid;
  picked_question_version_id uuid;
  replacement_instance_id uuid;
  shuffle_count integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_slot_number not between 1 and 3 then
    raise exception 'slot number is out of range'
      using errcode = '23514';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'shuffle_daily_question',
      resolved_couple_id::text,
      current_user_id::text,
      p_slot_number::text,
      p_local_created_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'shuffle_daily_question',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'replacement_instance_id')::uuid;
  end if;

  resolved_couple_day_id = internal.get_or_create_couple_day_at(
    resolved_couple_id,
    p_local_created_at
  );
  perform internal.ensure_daily_challenge_slots(resolved_couple_day_id);

  perform 1
  from public.daily_challenges challenge
  where challenge.couple_day_id = resolved_couple_day_id
    and challenge.user_id = current_user_id
  for update;

  select count(*)
  into shuffle_count
  from public.daily_question_shuffles shuffle
  where shuffle.couple_day_id = resolved_couple_day_id
    and shuffle.user_id = current_user_id;

  if shuffle_count >= 5 then
    raise exception 'daily shuffle limit reached'
      using errcode = '23514';
  end if;

  select *
  into active_instance_row
  from public.daily_question_instances instance
  where instance.couple_day_id = resolved_couple_day_id
    and instance.seeded_for_user_id = current_user_id
    and instance.slot_number = p_slot_number
    and instance.status = 'active'
  for update;

  if not found then
    raise exception 'active daily question slot was not found'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.daily_question_answers answer
    where answer.instance_id = active_instance_row.id
      and answer.user_id = current_user_id
      and answer.deleted_at is null
  ) then
    raise exception 'answered daily questions cannot be shuffled'
      using errcode = '23514';
  end if;

  select version.question_id
  into skipped_question_id
  from public.question_versions version
  where version.id = active_instance_row.question_version_id;

  picked_question_version_id = internal.pick_daily_question_version(
    resolved_couple_day_id,
    current_user_id,
    skipped_question_id
  );

  update public.daily_question_instances
  set
    status = 'shuffled',
    replaced_at = now()
  where id = active_instance_row.id;

  insert into public.daily_question_instances (
    couple_day_id,
    question_version_id,
    seeded_for_user_id,
    slot_number
  ) values (
    resolved_couple_day_id,
    picked_question_version_id,
    current_user_id,
    p_slot_number
  )
  returning id into replacement_instance_id;

  update public.daily_question_instances
  set replaced_by_instance_id = replacement_instance_id
  where id = active_instance_row.id;

  insert into public.daily_question_shuffles (
    couple_id,
    couple_day_id,
    user_id,
    question_id,
    skipped_instance_id,
    replacement_instance_id,
    slot_number,
    exclude_until
  ) values (
    resolved_couple_id,
    resolved_couple_day_id,
    current_user_id,
    skipped_question_id,
    active_instance_row.id,
    replacement_instance_id,
    p_slot_number,
    now() + interval '14 days'
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('replacement_instance_id', replacement_instance_id)
  );

  return replacement_instance_id;
end;
$$;

create or replace function internal.submit_daily_answer(
  p_instance_id uuid,
  p_payload jsonb,
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
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  resolved_answer_id uuid;
  text_body text;
  selected_partner_user_id uuid;
  allowed_kinds text[];
  provided_kinds text[] := array[]::text[];
  provided_kind text;
  media_row record;
  asset_row public.media_assets%rowtype;
  media_kind text;
  completed_own_slots integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'answer payload must be an object'
      using errcode = '23514';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'submit_daily_answer',
      p_instance_id::text,
      p_payload::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'submit_daily_answer',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'answer_id')::uuid;
  end if;

  select *
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  if instance_row.status = 'shuffled' then
    raise exception 'shuffled daily questions cannot be answered'
      using errcode = '23514';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if p_local_created_at < couple_day_row.starts_at
    or p_local_created_at >= couple_day_row.ends_at then
    raise exception 'daily answer timestamp is outside the question day'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    where member.couple_id = couple_day_row.couple_id
      and member.user_id = current_user_id
      and member.status = 'active'
  ) then
    raise exception 'answer user must be an active couple member'
      using errcode = '42501';
  end if;

  if current_user_id <> instance_row.seeded_for_user_id
    and not exists (
      select 1
      from public.daily_question_answers seeded_answer
      where seeded_answer.instance_id = instance_row.id
        and seeded_answer.user_id = instance_row.seeded_for_user_id
        and seeded_answer.deleted_at is null
        and seeded_answer.moderation_status = 'visible'
    ) then
    raise exception 'partner-seeded questions can be answered after your partner answers'
      using errcode = '42501';
  end if;

  select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
  into allowed_kinds
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = instance_row.question_version_id;

  text_body = nullif(btrim(coalesce(p_payload ->> 'text', '')), '');

  if text_body is not null then
    if char_length(text_body) > 2000 then
      raise exception 'answer text is too long'
        using errcode = '23514';
    end if;

    provided_kinds = array_append(provided_kinds, 'text');
  end if;

  if nullif(p_payload ->> 'partner_choice_user_id', '') is not null then
    selected_partner_user_id = (p_payload ->> 'partner_choice_user_id')::uuid;
    provided_kinds = array_append(provided_kinds, 'partner_choice');
  end if;

  if p_payload ? 'media_asset_ids'
    and jsonb_typeof(p_payload -> 'media_asset_ids') <> 'array' then
    raise exception 'media_asset_ids must be an array'
      using errcode = '23514';
  end if;

  for media_row in
    select
      media_item.value::uuid as media_asset_id,
      media_item.ordinality::smallint as sort_order
    from jsonb_array_elements_text(coalesce(p_payload -> 'media_asset_ids', '[]'::jsonb))
      with ordinality as media_item(value, ordinality)
  loop
    select *
    into asset_row
    from public.media_assets
    where id = media_row.media_asset_id;

    media_kind = case asset_row.media_type
      when 'image' then 'photo'
      when 'voice' then 'voice'
      else null
    end;

    if asset_row.id is null
      or media_kind is null
      or asset_row.owner_user_id <> current_user_id
      or asset_row.couple_id <> couple_day_row.couple_id
      or asset_row.reserved_parent_kind <> 'daily_answer_media'
      or asset_row.upload_status <> 'finalized'
      or asset_row.storage_delete_status <> 'none'
      or asset_row.moderation_status <> 'visible'
      or asset_row.deleted_at is not null then
      raise exception 'daily answer media asset is not usable'
        using errcode = '23514';
    end if;

    if not media_kind = any(provided_kinds) then
      provided_kinds = array_append(provided_kinds, media_kind);
    end if;
  end loop;

  if cardinality(provided_kinds) = 0 then
    raise exception 'answer payload must include at least one answer kind'
      using errcode = '23514';
  end if;

  foreach provided_kind in array provided_kinds loop
    if not provided_kind = any(coalesce(allowed_kinds, array[]::text[])) then
      raise exception 'answer kind is not allowed for this question'
        using errcode = '23514';
    end if;
  end loop;

  resolved_answer_id = coalesce(
    nullif(p_payload ->> 'answer_id', '')::uuid,
    extensions.gen_random_uuid()
  );

  insert into public.daily_question_answers (
    id,
    instance_id,
    user_id
  ) values (
    resolved_answer_id,
    instance_row.id,
    current_user_id
  );

  if text_body is not null then
    insert into public.daily_answer_text (answer_id, body)
    values (resolved_answer_id, text_body);
  end if;

  if selected_partner_user_id is not null then
    insert into public.daily_answer_partner_choice (
      answer_id,
      selected_user_id
    ) values (
      resolved_answer_id,
      selected_partner_user_id
    );
  end if;

  for media_row in
    select
      media_item.value::uuid as media_asset_id,
      media_item.ordinality::smallint as sort_order
    from jsonb_array_elements_text(coalesce(p_payload -> 'media_asset_ids', '[]'::jsonb))
      with ordinality as media_item(value, ordinality)
  loop
    insert into public.daily_answer_media (
      answer_id,
      media_asset_id,
      sort_order
    ) values (
      resolved_answer_id,
      media_row.media_asset_id,
      media_row.sort_order
    );
  end loop;

  if current_user_id = instance_row.seeded_for_user_id then
    update public.daily_question_instances
    set status = 'answered'
    where id = instance_row.id
      and status = 'active';

    select count(*)
    into completed_own_slots
    from public.daily_question_instances own_instance
    where own_instance.couple_day_id = instance_row.couple_day_id
      and own_instance.seeded_for_user_id = current_user_id
      and own_instance.status = 'answered';

    if completed_own_slots = 3 then
      update public.daily_challenges
      set completed_at = coalesce(completed_at, now())
      where couple_day_id = instance_row.couple_day_id
        and user_id = current_user_id;
    end if;
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('answer_id', resolved_answer_id)
  );

  return resolved_answer_id;
end;
$$;

create or replace function internal.get_daily_questions_for_couple_day(p_couple_day_id uuid)
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  with target_day as (
    select couple_day.*
    from public.couple_days couple_day
    where couple_day.id = p_couple_day_id
      and internal.can_access_couple_content(couple_day.couple_id)
  )
  select
    target_day.id,
    target_day.couple_id,
    target_day.local_date,
    target_day.starts_at,
    target_day.ends_at,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.status,
    question.id,
    version.id,
    question.key,
    en_localization.prompt,
    en_localization.short_prompt,
    nb_localization.prompt,
    nb_localization.short_prompt,
    (
      select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ),
    own_answer.id,
    own_answer.created_at,
    partner_answer.id,
    partner_answer.created_at,
    coalesce(internal.can_view_daily_answer(partner_answer.id), false)
  from target_day
  join public.daily_question_instances instance
    on instance.couple_day_id = target_day.id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  join public.question_version_localizations en_localization
    on en_localization.question_version_id = version.id
    and en_localization.locale = 'en'
  join public.question_version_localizations nb_localization
    on nb_localization.question_version_id = version.id
    and nb_localization.locale = 'nb'
  left join public.daily_question_answers own_answer
    on own_answer.instance_id = instance.id
    and own_answer.user_id = (select auth.uid())
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> (select auth.uid())
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where instance.status in ('active', 'answered')
    and (
      instance.seeded_for_user_id = (select auth.uid())
      or partner_answer.id is not null
    )
  order by instance.seeded_for_user_id = (select auth.uid()) desc,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.created_at;
$$;

create or replace function internal.get_today_daily_questions()
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_questions_for_couple_day((
    select couple_day.id
    from public.couple_days couple_day
    where couple_day.couple_id = internal.get_current_entitled_couple_id()
      and now() >= couple_day.starts_at
      and now() < couple_day.ends_at
    order by couple_day.starts_at desc
    limit 1
  ));
$$;

create or replace function internal.get_daily_answer_reveal_state(p_couple_day_id uuid)
returns table (
  couple_day_id uuid,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  is_own_answer boolean,
  can_view_answer boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = (select auth.uid()),
    internal.can_view_daily_answer(answer.id)
  from public.couple_days couple_day
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  where couple_day.id = p_couple_day_id
    and internal.can_access_couple_content(couple_day.couple_id)
  order by instance.slot_number, answer.created_at;
$$;

create or replace function internal.get_daily_answer_details(p_couple_day_id uuid)
returns table (
  couple_day_id uuid,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  is_own_answer boolean,
  can_view_answer boolean,
  text_body text,
  selected_user_id uuid,
  media_asset_ids uuid[]
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = (select auth.uid()),
    internal.can_view_daily_answer(answer.id),
    case
      when internal.can_view_daily_answer(answer.id) then answer_text.body
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then partner_choice.selected_user_id
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from public.couple_days couple_day
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where couple_day.id = p_couple_day_id
    and internal.can_access_couple_content(couple_day.couple_id)
  order by instance.slot_number, answer.created_at;
$$;

create or replace function internal.get_question_answer_history(p_question_id uuid)
returns table (
  question_id uuid,
  question_version_id uuid,
  couple_day_id uuid,
  local_date date,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  can_view_answer boolean,
  text_body text,
  selected_user_id uuid,
  media_asset_ids uuid[]
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    question.id,
    version.id,
    couple_day.id,
    couple_day.local_date,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    internal.can_view_daily_answer(answer.id),
    case
      when internal.can_view_daily_answer(answer.id) then answer_text.body
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then partner_choice.selected_user_id
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from public.daily_question_answers answer
  join public.daily_question_instances instance
    on instance.id = answer.instance_id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where question.id = p_question_id
    and question.resurfaceable
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
    and internal.can_access_couple_content(couple_day.couple_id)
  order by couple_day.local_date desc, answer.created_at desc, answer.id;
$$;

create or replace function public.start_daily_challenge(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean
)
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  resolved_couple_day_id uuid;
begin
  resolved_couple_day_id = internal.start_daily_challenge(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_daily_questions_for_couple_day(resolved_couple_day_id);
end;
$$;

create or replace function public.shuffle_daily_question(
  p_slot_number smallint,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean
)
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  resolved_couple_day_id uuid;
  replacement_instance_id uuid;
begin
  replacement_instance_id = internal.shuffle_daily_question(
    p_slot_number,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  select instance.couple_day_id
  into resolved_couple_day_id
  from public.daily_question_instances instance
  where instance.id = replacement_instance_id;

  return query
  select *
  from internal.get_daily_questions_for_couple_day(resolved_couple_day_id);
end;
$$;

create or replace function public.submit_daily_answer(
  p_instance_id uuid,
  p_payload jsonb,
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
  select internal.submit_daily_answer(
    p_instance_id,
    p_payload,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.get_today_daily_questions()
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_today_daily_questions();
$$;

create or replace function public.get_daily_answer_reveal_state(p_couple_day_id uuid)
returns table (
  couple_day_id uuid,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  is_own_answer boolean,
  can_view_answer boolean
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_answer_reveal_state(p_couple_day_id);
$$;

create or replace function public.get_daily_answer_details(p_couple_day_id uuid)
returns table (
  couple_day_id uuid,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  is_own_answer boolean,
  can_view_answer boolean,
  text_body text,
  selected_user_id uuid,
  media_asset_ids uuid[]
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_answer_details(p_couple_day_id);
$$;

create or replace function public.get_question_answer_history(p_question_id uuid)
returns table (
  question_id uuid,
  question_version_id uuid,
  couple_day_id uuid,
  local_date date,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  can_view_answer boolean,
  text_body text,
  selected_user_id uuid,
  media_asset_ids uuid[]
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_question_answer_history(p_question_id);
$$;

alter table public.couple_days enable row level security;
alter table public.daily_challenges enable row level security;
alter table public.daily_question_instances enable row level security;
alter table public.daily_question_shuffles enable row level security;
alter table public.daily_question_answers enable row level security;
alter table public.daily_answer_text enable row level security;
alter table public.daily_answer_partner_choice enable row level security;
alter table public.daily_answer_media enable row level security;

create unique index daily_question_instances_active_slot_unique_idx
on public.daily_question_instances (couple_day_id, seeded_for_user_id, slot_number)
where status = 'active';

create index daily_question_instances_couple_day_question_version_idx
on public.daily_question_instances (couple_day_id, question_version_id);

create index daily_question_instances_seeded_status_idx
on public.daily_question_instances (seeded_for_user_id, status);

create index daily_question_instances_replaced_by_instance_id_idx
on public.daily_question_instances (replaced_by_instance_id)
where replaced_by_instance_id is not null;

create index daily_question_shuffles_user_question_exclude_until_idx
on public.daily_question_shuffles (user_id, question_id, exclude_until);

create index daily_question_shuffles_couple_day_user_idx
on public.daily_question_shuffles (couple_day_id, user_id);

create index daily_question_shuffles_replacement_instance_idx
on public.daily_question_shuffles (replacement_instance_id);

create index daily_question_answers_user_created_at_idx
on public.daily_question_answers (user_id, created_at desc);

create index daily_question_answers_instance_user_idx
on public.daily_question_answers (instance_id, user_id);

create index daily_answer_media_media_asset_id_idx
on public.daily_answer_media (media_asset_id);

create index daily_question_answers_moderated_by_idx
on public.daily_question_answers (moderated_by)
where moderated_by is not null;

revoke all on public.couple_days from public, anon, authenticated;
revoke all on public.daily_challenges from public, anon, authenticated;
revoke all on public.daily_question_instances from public, anon, authenticated;
revoke all on public.daily_question_shuffles from public, anon, authenticated;
revoke all on public.daily_question_answers from public, anon, authenticated;
revoke all on public.daily_answer_text from public, anon, authenticated;
revoke all on public.daily_answer_partner_choice from public, anon, authenticated;
revoke all on public.daily_answer_media from public, anon, authenticated;

grant all privileges on public.couple_days to service_role;
grant all privileges on public.daily_challenges to service_role;
grant all privileges on public.daily_question_instances to service_role;
grant all privileges on public.daily_question_shuffles to service_role;
grant all privileges on public.daily_question_answers to service_role;
grant all privileges on public.daily_answer_text to service_role;
grant all privileges on public.daily_answer_partner_choice to service_role;
grant all privileges on public.daily_answer_media to service_role;

grant usage on schema internal to authenticated;

revoke all on function internal.get_current_entitled_couple_id() from public, anon, authenticated;
grant execute on function internal.get_current_entitled_couple_id() to authenticated, service_role;

revoke all on function internal.resolve_couple_day_anchor_at(uuid, timestamptz) from public, anon, authenticated;
grant execute on function internal.resolve_couple_day_anchor_at(uuid, timestamptz) to service_role;

revoke all on function internal.resolve_couple_day_anchor(uuid) from public, anon, authenticated;
grant execute on function internal.resolve_couple_day_anchor(uuid) to service_role;

revoke all on function internal.get_or_create_couple_day_at(uuid, timestamptz) from public, anon, authenticated;
grant execute on function internal.get_or_create_couple_day_at(uuid, timestamptz) to service_role;

revoke all on function internal.get_or_create_today_couple_day(uuid) from public, anon, authenticated;
grant execute on function internal.get_or_create_today_couple_day(uuid) to service_role;

revoke all on function internal.pick_daily_question_version(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function internal.pick_daily_question_version(uuid, uuid, uuid) to service_role;

revoke all on function internal.ensure_daily_challenge_slots(uuid) from public, anon, authenticated;
grant execute on function internal.ensure_daily_challenge_slots(uuid) to service_role;

revoke all on function internal.assert_daily_challenge_member() from public, anon, authenticated;
grant execute on function internal.assert_daily_challenge_member() to service_role;

revoke all on function internal.assert_daily_question_instance_member() from public, anon, authenticated;
grant execute on function internal.assert_daily_question_instance_member() to service_role;

revoke all on function internal.assert_daily_question_shuffle_valid() from public, anon, authenticated;
grant execute on function internal.assert_daily_question_shuffle_valid() to service_role;

revoke all on function internal.assert_daily_question_answer_member() from public, anon, authenticated;
grant execute on function internal.assert_daily_question_answer_member() to service_role;

revoke all on function internal.assert_daily_answer_text_allowed() from public, anon, authenticated;
grant execute on function internal.assert_daily_answer_text_allowed() to service_role;

revoke all on function internal.assert_daily_answer_partner_choice_allowed() from public, anon, authenticated;
grant execute on function internal.assert_daily_answer_partner_choice_allowed() to service_role;

revoke all on function internal.assert_daily_answer_media_allowed() from public, anon, authenticated;
grant execute on function internal.assert_daily_answer_media_allowed() to service_role;

revoke all on function internal.can_view_daily_answer(uuid) from public, anon, authenticated;
grant execute on function internal.can_view_daily_answer(uuid) to authenticated, service_role;

revoke all on function internal.start_daily_challenge(uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.start_daily_challenge(uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.get_today_daily_questions() from public, anon, authenticated;
grant execute on function internal.get_today_daily_questions() to authenticated, service_role;

revoke all on function internal.get_daily_questions_for_couple_day(uuid) from public, anon, authenticated;
grant execute on function internal.get_daily_questions_for_couple_day(uuid) to authenticated, service_role;

revoke all on function internal.get_daily_answer_reveal_state(uuid) from public, anon, authenticated;
grant execute on function internal.get_daily_answer_reveal_state(uuid) to authenticated, service_role;

revoke all on function internal.get_daily_answer_details(uuid) from public, anon, authenticated;
grant execute on function internal.get_daily_answer_details(uuid) to authenticated, service_role;

revoke all on function internal.get_question_answer_history(uuid) from public, anon, authenticated;
grant execute on function internal.get_question_answer_history(uuid) to authenticated, service_role;

revoke all on function public.start_daily_challenge(uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.start_daily_challenge(uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.get_today_daily_questions() from public, anon;
grant execute on function public.get_today_daily_questions() to authenticated, service_role;

revoke all on function public.get_daily_answer_reveal_state(uuid) from public, anon;
grant execute on function public.get_daily_answer_reveal_state(uuid) to authenticated, service_role;

revoke all on function public.get_daily_answer_details(uuid) from public, anon;
grant execute on function public.get_daily_answer_details(uuid) to authenticated, service_role;

revoke all on function public.get_question_answer_history(uuid) from public, anon;
grant execute on function public.get_question_answer_history(uuid) to authenticated, service_role;
