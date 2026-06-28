drop function if exists public.start_daily_challenge(uuid, uuid, bigint, timestamptz);
drop function if exists public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz);
drop function if exists public.get_today_daily_questions();
drop function if exists internal.get_today_daily_questions();

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
  can_view_partner_answer boolean,
  is_current_day boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  with current_context as (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  ),
  current_day as (
    select couple_day.id, couple_day.starts_at
    from public.couple_days couple_day
    join current_context context
      on context.couple_id = couple_day.couple_id
    where now() >= couple_day.starts_at
      and now() < couple_day.ends_at
    order by couple_day.starts_at desc
    limit 1
  ),
  selected_instances as (
    select instance.id, true as is_current_day
    from current_day
    join public.daily_question_instances instance
      on instance.couple_day_id = current_day.id
    where instance.status in ('active', 'answered')

    union

    select instance.id, false as is_current_day
    from current_context context
    join public.couple_days couple_day
      on couple_day.couple_id = context.couple_id
    join public.daily_question_instances instance
      on instance.couple_day_id = couple_day.id
    left join public.daily_question_answers viewer_answer
      on viewer_answer.instance_id = instance.id
      and viewer_answer.user_id = context.current_user_id
      and viewer_answer.deleted_at is null
      and viewer_answer.moderation_status = 'visible'
    left join public.daily_question_answers seeded_answer
      on seeded_answer.instance_id = instance.id
      and seeded_answer.user_id = instance.seeded_for_user_id
      and seeded_answer.deleted_at is null
      and seeded_answer.moderation_status = 'visible'
    left join public.daily_question_answers other_answer
      on other_answer.instance_id = instance.id
      and other_answer.user_id <> context.current_user_id
      and other_answer.deleted_at is null
      and other_answer.moderation_status = 'visible'
    where instance.status in ('active', 'answered')
      and not exists (
        select 1
        from current_day
        where current_day.id = couple_day.id
      )
      and couple_day.starts_at < coalesce((select current_day.starts_at from current_day), now())
      and (
        (
          instance.seeded_for_user_id <> context.current_user_id
          and seeded_answer.id is not null
          and viewer_answer.id is null
        )
        or (
          instance.seeded_for_user_id = context.current_user_id
          and viewer_answer.id is not null
          and other_answer.id is null
        )
      )
  )
  select
    couple_day.id,
    couple_day.couple_id,
    couple_day.local_date,
    couple_day.starts_at,
    couple_day.ends_at,
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
    coalesce(internal.can_view_daily_answer(partner_answer.id), false),
    selected_instances.is_current_day
  from selected_instances
  join public.daily_question_instances instance
    on instance.id = selected_instances.id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join current_context context
    on context.couple_id = couple_day.couple_id
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
    and own_answer.user_id = context.current_user_id
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> context.current_user_id
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where selected_instances.is_current_day = false
    or instance.seeded_for_user_id = context.current_user_id
    or partner_answer.id is not null
  order by
    selected_instances.is_current_day desc,
    couple_day.starts_at desc,
    instance.seeded_for_user_id = context.current_user_id desc,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.created_at;
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
  can_view_partner_answer boolean,
  is_current_day boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.get_today_daily_questions();
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
  can_view_partner_answer boolean,
  is_current_day boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.start_daily_challenge(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_questions();
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
  can_view_partner_answer boolean,
  is_current_day boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.shuffle_daily_question(
    p_slot_number,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_questions();
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
    or (
      current_user_id = instance_row.seeded_for_user_id
      and p_local_created_at >= couple_day_row.ends_at
    ) then
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

revoke all on function internal.get_today_daily_questions() from public, anon, authenticated;
grant execute on function internal.get_today_daily_questions() to service_role;

revoke all on function internal.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz)
from public, anon, authenticated;
grant execute on function internal.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz)
to service_role;

revoke all on function public.get_today_daily_questions() from public, anon, authenticated;
grant execute on function public.get_today_daily_questions() to authenticated, service_role;

revoke all on function public.start_daily_challenge(uuid, uuid, bigint, timestamptz)
from public, anon, authenticated;
grant execute on function public.start_daily_challenge(uuid, uuid, bigint, timestamptz)
to authenticated, service_role;

revoke all on function public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz)
from public, anon, authenticated;
grant execute on function public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz)
to authenticated, service_role;
