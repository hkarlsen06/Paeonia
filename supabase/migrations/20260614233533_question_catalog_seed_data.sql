create table public.question_collections (
  id uuid primary key default extensions.gen_random_uuid(),
  kind text not null,
  couple_id uuid references public.couples (id) on delete restrict,
  created_by_user_id uuid references auth.users (id) on delete restrict,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint question_collections_kind_check
    check (kind in ('system', 'custom', 'mini_game')),
  constraint question_collections_status_check
    check (status in ('draft', 'active', 'retired', 'archived')),
  constraint question_collections_system_scope_check
    check (
      kind <> 'system'
      or (couple_id is null and created_by_user_id is null)
    )
);

create trigger set_question_collections_updated_at
before update on public.question_collections
for each row
execute function internal.set_updated_at();

create table public.questions (
  id uuid primary key default extensions.gen_random_uuid(),
  collection_id uuid not null references public.question_collections (id) on delete restrict,
  key text not null,
  status text not null default 'draft',
  resurfaceable boolean not null default true,
  resurface_after_months smallint default 6,
  created_by_user_id uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint questions_key_check
    check (key ~ '^[a-z][a-z0-9_]{2,120}$'),
  constraint questions_status_check
    check (status in ('draft', 'active', 'retired', 'archived')),
  constraint questions_resurface_after_months_check
    check (
      (resurfaceable and resurface_after_months between 1 and 60)
      or (not resurfaceable and (resurface_after_months is null or resurface_after_months between 1 and 60))
    ),
  constraint questions_collection_key_unique
    unique (collection_id, key)
);

create trigger set_questions_updated_at
before update on public.questions
for each row
execute function internal.set_updated_at();

create table public.question_versions (
  id uuid primary key default extensions.gen_random_uuid(),
  question_id uuid not null references public.questions (id) on delete restrict,
  version_number integer not null,
  status text not null default 'draft',
  active_from timestamptz not null default now(),
  retired_at timestamptz,
  created_at timestamptz not null default now(),

  constraint question_versions_version_number_check
    check (version_number > 0),
  constraint question_versions_status_check
    check (status in ('draft', 'active', 'retired')),
  constraint question_versions_retired_state_check
    check (
      (status = 'retired' and retired_at is not null)
      or (status <> 'retired' and retired_at is null)
    ),
  constraint question_versions_question_version_unique
    unique (question_id, version_number)
);

create table public.question_version_localizations (
  question_version_id uuid not null references public.question_versions (id) on delete restrict,
  locale text not null,
  prompt text not null,
  short_prompt text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint question_version_localizations_primary_key
    primary key (question_version_id, locale),
  constraint question_version_localizations_locale_check
    check (locale in ('en', 'nb')),
  constraint question_version_localizations_prompt_check
    check (char_length(btrim(prompt)) between 3 and 500),
  constraint question_version_localizations_short_prompt_check
    check (char_length(btrim(short_prompt)) between 3 and 160)
);

create trigger set_question_version_localizations_updated_at
before update on public.question_version_localizations
for each row
execute function internal.set_updated_at();

create table public.question_answer_kinds (
  question_version_id uuid not null references public.question_versions (id) on delete restrict,
  answer_kind text not null,
  created_at timestamptz not null default now(),

  constraint question_answer_kinds_primary_key
    primary key (question_version_id, answer_kind),
  constraint question_answer_kinds_answer_kind_check
    check (answer_kind in ('text', 'photo', 'voice', 'partner_choice'))
);

create or replace function internal.assert_active_question_version_ready(p_question_version_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  version_row record;
  localized_locale_count integer;
  answer_kind_count integer;
begin
  select
    version.id as question_version_id,
    version.status as question_version_status,
    question.id as question_id,
    question.status as question_status,
    collection.id as collection_id,
    collection.kind as collection_kind,
    collection.status as collection_status
  into version_row
  from public.question_versions version
  join public.questions question
    on question.id = version.question_id
  join public.question_collections collection
    on collection.id = question.collection_id
  where version.id = p_question_version_id;

  if not found then
    return;
  end if;

  select count(*)
  into answer_kind_count
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = p_question_version_id;

  if answer_kind_count > 2 then
    raise exception 'question versions can have at most two answer kinds'
      using errcode = '23514';
  end if;

  if version_row.collection_status = 'active'
    and version_row.question_status = 'active'
    and version_row.question_version_status = 'active' then
    select count(*)
    into localized_locale_count
    from public.question_version_localizations localization
    where localization.question_version_id = p_question_version_id
      and localization.locale in ('en', 'nb');

    if localized_locale_count <> 2 then
      raise exception 'active question versions require en and nb localizations'
        using errcode = '23514';
    end if;

    if answer_kind_count < 1 then
      raise exception 'active question versions require at least one answer kind'
        using errcode = '23514';
    end if;
  end if;
end;
$$;

create or replace function internal.assert_active_question_ready(p_question_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  question_row record;
  active_version_id uuid;
begin
  select
    question.id,
    question.status as question_status,
    collection.kind as collection_kind,
    collection.status as collection_status
  into question_row
  from public.questions question
  join public.question_collections collection
    on collection.id = question.collection_id
  where question.id = p_question_id;

  if not found then
    return;
  end if;

  if question_row.collection_status = 'active'
    and question_row.question_status = 'active' then
    select version.id
    into active_version_id
    from public.question_versions version
    where version.question_id = p_question_id
      and version.status = 'active'
    order by version.version_number desc
    limit 1;

    if active_version_id is null then
      raise exception 'active questions require an active version'
        using errcode = '23514';
    end if;

    perform internal.assert_active_question_version_ready(active_version_id);
  end if;
end;
$$;

create or replace function internal.assert_active_question_collection_ready(p_collection_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  collection_row public.question_collections%rowtype;
  active_question_count integer;
  active_question_id uuid;
begin
  select *
  into collection_row
  from public.question_collections
  where id = p_collection_id;

  if not found then
    return;
  end if;

  if collection_row.status = 'active' then
    select count(*)
    into active_question_count
    from public.questions question
    where question.collection_id = p_collection_id
      and question.status = 'active';

    if active_question_count < 1 then
      raise exception 'active collections require active questions'
        using errcode = '23514';
    end if;

    for active_question_id in
      select question.id
      from public.questions question
      where question.collection_id = p_collection_id
        and question.status = 'active'
    loop
      perform internal.assert_active_question_ready(active_question_id);
    end loop;
  end if;
end;
$$;

create or replace function internal.assert_question_collection_ready_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    perform internal.assert_active_question_collection_ready(old.id);
  else
    perform internal.assert_active_question_collection_ready(new.id);
  end if;

  return null;
end;
$$;

create or replace function internal.assert_question_ready_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    perform internal.assert_active_question_collection_ready(old.collection_id);
    return null;
  end if;

  perform internal.assert_active_question_ready(new.id);

  if new.collection_id is not null then
    perform internal.assert_active_question_collection_ready(new.collection_id);
  end if;

  if tg_op = 'UPDATE'
    and old.collection_id is not null
    and old.collection_id is distinct from new.collection_id then
    perform internal.assert_active_question_collection_ready(old.collection_id);
  end if;

  return null;
end;
$$;

create or replace function internal.assert_question_version_ready_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    perform internal.assert_active_question_ready(old.question_id);
    return null;
  end if;

  perform internal.assert_active_question_version_ready(new.id);

  if new.question_id is not null then
    perform internal.assert_active_question_ready(new.question_id);
  end if;

  if tg_op = 'UPDATE'
    and old.question_id is not null
    and old.question_id is distinct from new.question_id then
    perform internal.assert_active_question_ready(old.question_id);
  end if;

  return null;
end;
$$;

create or replace function internal.assert_question_version_child_ready_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_question_id uuid;
  resolved_question_version_id uuid;
begin
  if tg_op = 'DELETE' then
    resolved_question_version_id = old.question_version_id;
  else
    resolved_question_version_id = new.question_version_id;
  end if;

  perform internal.assert_active_question_version_ready(resolved_question_version_id);

  select version.question_id
  into resolved_question_id
  from public.question_versions version
  where version.id = resolved_question_version_id;

  if resolved_question_id is not null then
    perform internal.assert_active_question_ready(resolved_question_id);
  end if;

  return null;
end;
$$;

create constraint trigger assert_question_collections_ready
after insert or update or delete on public.question_collections
deferrable initially deferred
for each row
execute function internal.assert_question_collection_ready_trigger();

create constraint trigger assert_questions_ready
after insert or update or delete on public.questions
deferrable initially deferred
for each row
execute function internal.assert_question_ready_trigger();

create constraint trigger assert_question_versions_ready
after insert or update or delete on public.question_versions
deferrable initially deferred
for each row
execute function internal.assert_question_version_ready_trigger();

create constraint trigger assert_question_version_localizations_ready
after insert or update or delete on public.question_version_localizations
deferrable initially deferred
for each row
execute function internal.assert_question_version_child_ready_trigger();

create constraint trigger assert_question_answer_kinds_ready
after insert or update or delete on public.question_answer_kinds
deferrable initially deferred
for each row
execute function internal.assert_question_version_child_ready_trigger();

create unique index question_collections_one_active_system_idx
on public.question_collections (kind)
where kind = 'system' and status = 'active';

create index question_collections_kind_status_idx
on public.question_collections (kind, status);

create index question_collections_couple_id_idx
on public.question_collections (couple_id)
where couple_id is not null;

create index questions_collection_status_idx
on public.questions (collection_id, status);

create index question_versions_question_status_idx
on public.question_versions (question_id, status);

create unique index question_versions_one_active_per_question_idx
on public.question_versions (question_id)
where status = 'active';

create index question_version_localizations_locale_idx
on public.question_version_localizations (locale);

create or replace function internal.get_active_question_catalog(p_locale text default null)
returns table (
  collection_id uuid,
  question_id uuid,
  question_key text,
  question_version_id uuid,
  version_number integer,
  locale text,
  prompt text,
  short_prompt text,
  answer_kinds text[],
  resurfaceable boolean,
  resurface_after_months smallint
)
language sql
security definer
set search_path = pg_catalog
as $$
  with active_versions as (
    select
      collection.id as collection_id,
      question.id as question_id,
      question.key as question_key,
      version.id as question_version_id,
      version.version_number,
      question.resurfaceable,
      question.resurface_after_months,
      array_agg(answer_kind.answer_kind order by answer_kind.answer_kind) as answer_kinds
    from public.question_collections collection
    join public.questions question
      on question.collection_id = collection.id
    join public.question_versions version
      on version.question_id = question.id
    join public.question_answer_kinds answer_kind
      on answer_kind.question_version_id = version.id
    where collection.kind = 'system'
      and collection.status = 'active'
      and question.status = 'active'
      and version.status = 'active'
      and exists (
        select 1
        from public.question_version_localizations en_localization
        where en_localization.question_version_id = version.id
          and en_localization.locale = 'en'
      )
      and exists (
        select 1
        from public.question_version_localizations nb_localization
        where nb_localization.question_version_id = version.id
          and nb_localization.locale = 'nb'
      )
    group by
      collection.id,
      question.id,
      question.key,
      version.id,
      version.version_number,
      question.resurfaceable,
      question.resurface_after_months
    having count(*) between 1 and 2
  )
  select
    active_versions.collection_id,
    active_versions.question_id,
    active_versions.question_key,
    active_versions.question_version_id,
    active_versions.version_number,
    localization.locale,
    localization.prompt,
    localization.short_prompt,
    active_versions.answer_kinds,
    active_versions.resurfaceable,
    active_versions.resurface_after_months
  from active_versions
  join public.question_version_localizations localization
    on localization.question_version_id = active_versions.question_version_id
  where p_locale is null or localization.locale = p_locale
  order by active_versions.question_key, localization.locale;
$$;

create or replace function public.get_active_question_catalog(p_locale text default null)
returns table (
  collection_id uuid,
  question_id uuid,
  question_key text,
  question_version_id uuid,
  version_number integer,
  locale text,
  prompt text,
  short_prompt text,
  answer_kinds text[],
  resurfaceable boolean,
  resurface_after_months smallint
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_active_question_catalog(p_locale);
$$;

alter table public.question_collections enable row level security;
alter table public.questions enable row level security;
alter table public.question_versions enable row level security;
alter table public.question_version_localizations enable row level security;
alter table public.question_answer_kinds enable row level security;

do $$
declare
  system_collection_id uuid;
  inserted_question_id uuid;
  inserted_version_id uuid;
  seed_row record;
  seed_answer_kind text;
begin
  insert into public.question_collections (kind, status)
  values ('system', 'draft')
  returning id into system_collection_id;

  for seed_row in
    select *
    from (
      values
        (
          'small_moment_today',
          'What small moment made you think of us today?',
          'A small moment from today',
          'Hvilket lite øyeblikk fikk deg til å tenke på oss i dag?',
          'Et lite øyeblikk fra i dag',
          array['text']::text[]
        ),
        (
          'miss_you_most_today',
          'What did you miss most about me today?',
          'What you missed today',
          'Hva savnet du mest med meg i dag?',
          'Det du savnet i dag',
          array['text']::text[]
        ),
        (
          'photo_from_today',
          'Send a photo that shows part of your day.',
          'A photo from your day',
          'Send et bilde som viser en del av dagen din.',
          'Et bilde fra dagen din',
          array['photo', 'text']::text[]
        ),
        (
          'voice_note_goodnight',
          'Record a short goodnight message.',
          'A short goodnight message',
          'Spill inn en kort god natt-melding.',
          'En kort god natt-melding',
          array['voice', 'text']::text[]
        ),
        (
          'tomorrow_tiny_plan',
          'What is one tiny thing we can do together tomorrow?',
          'One tiny plan for tomorrow',
          'Hva er en liten ting vi kan gjøre sammen i morgen?',
          'En liten plan for i morgen',
          array['text']::text[]
        ),
        (
          'thank_you_today',
          'What do you want to thank me for today?',
          'A thank you from today',
          'Hva vil du takke meg for i dag?',
          'En takk fra i dag',
          array['text']::text[]
        ),
        (
          'comfort_needed',
          'What would help you feel cared for right now?',
          'What would help right now',
          'Hva ville hjulpet deg å føle deg tatt vare på akkurat nå?',
          'Hva som ville hjulpet nå',
          array['text']::text[]
        ),
        (
          'memory_that_fits_today',
          'What memory of us fits today?',
          'A memory that fits today',
          'Hvilket minne om oss passer til i dag?',
          'Et minne som passer i dag',
          array['text']::text[]
        ),
        (
          'question_for_partner',
          'What do you want to ask me tonight?',
          'A question for tonight',
          'Hva vil du spørre meg om i kveld?',
          'Et spørsmål for i kveld',
          array['text']::text[]
        ),
        (
          'choose_next_treat',
          'Who should choose our next small treat?',
          'Who chooses next?',
          'Hvem skal velge vår neste lille belønning?',
          'Hvem velger neste gang?',
          array['partner_choice', 'text']::text[]
        ),
        (
          'song_for_today',
          'What song fits your mood today?',
          'A song for today',
          'Hvilken sang passer humøret ditt i dag?',
          'En sang for i dag',
          array['text']::text[]
        ),
        (
          'one_sentence_day',
          'Describe your day in one sentence.',
          'Your day in one sentence',
          'Beskriv dagen din med en setning.',
          'Dagen din med en setning',
          array['text']::text[]
        )
    ) as seed(
      question_key,
      en_prompt,
      en_short_prompt,
      nb_prompt,
      nb_short_prompt,
      answer_kinds
    )
  loop
    insert into public.questions (
      collection_id,
      key,
      status,
      resurfaceable,
      resurface_after_months
    ) values (
      system_collection_id,
      seed_row.question_key,
      'draft',
      true,
      6
    )
    returning id into inserted_question_id;

    insert into public.question_versions (
      question_id,
      version_number,
      status,
      active_from
    ) values (
      inserted_question_id,
      1,
      'draft',
      now()
    )
    returning id into inserted_version_id;

    insert into public.question_version_localizations (
      question_version_id,
      locale,
      prompt,
      short_prompt
    ) values
      (
        inserted_version_id,
        'en',
        seed_row.en_prompt,
        seed_row.en_short_prompt
      ),
      (
        inserted_version_id,
        'nb',
        seed_row.nb_prompt,
        seed_row.nb_short_prompt
      );

    foreach seed_answer_kind in array seed_row.answer_kinds loop
      insert into public.question_answer_kinds (
        question_version_id,
        answer_kind
      ) values (
        inserted_version_id,
        seed_answer_kind
      );
    end loop;

    update public.question_versions
    set status = 'active'
    where id = inserted_version_id;

    update public.questions
    set status = 'active'
    where id = inserted_question_id;
  end loop;

  update public.question_collections
  set status = 'active'
  where id = system_collection_id;
end;
$$;

revoke all on public.question_collections from public, anon, authenticated;
revoke all on public.questions from public, anon, authenticated;
revoke all on public.question_versions from public, anon, authenticated;
revoke all on public.question_version_localizations from public, anon, authenticated;
revoke all on public.question_answer_kinds from public, anon, authenticated;

grant all privileges on public.question_collections to service_role;
grant all privileges on public.questions to service_role;
grant all privileges on public.question_versions to service_role;
grant all privileges on public.question_version_localizations to service_role;
grant all privileges on public.question_answer_kinds to service_role;

revoke all on function internal.assert_active_question_version_ready(uuid) from public, anon, authenticated;
grant execute on function internal.assert_active_question_version_ready(uuid) to service_role;

revoke all on function internal.assert_active_question_ready(uuid) from public, anon, authenticated;
grant execute on function internal.assert_active_question_ready(uuid) to service_role;

revoke all on function internal.assert_active_question_collection_ready(uuid) from public, anon, authenticated;
grant execute on function internal.assert_active_question_collection_ready(uuid) to service_role;

revoke all on function internal.assert_question_collection_ready_trigger() from public, anon, authenticated;
grant execute on function internal.assert_question_collection_ready_trigger() to service_role;

revoke all on function internal.assert_question_ready_trigger() from public, anon, authenticated;
grant execute on function internal.assert_question_ready_trigger() to service_role;

revoke all on function internal.assert_question_version_ready_trigger() from public, anon, authenticated;
grant execute on function internal.assert_question_version_ready_trigger() to service_role;

revoke all on function internal.assert_question_version_child_ready_trigger() from public, anon, authenticated;
grant execute on function internal.assert_question_version_child_ready_trigger() to service_role;

revoke all on function internal.get_active_question_catalog(text) from public, anon, authenticated;
grant execute on function internal.get_active_question_catalog(text) to authenticated, service_role;

revoke all on function public.get_active_question_catalog(text) from public, anon;
grant execute on function public.get_active_question_catalog(text) to authenticated, service_role;
