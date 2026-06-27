do $$
declare
  development_question_keys text[] := array[
    'small_moment_today',
    'miss_you_most_today',
    'photo_from_today',
    'voice_note_goodnight',
    'tomorrow_tiny_plan',
    'thank_you_today',
    'comfort_needed',
    'memory_that_fits_today',
    'question_for_partner',
    'choose_next_treat',
    'song_for_today',
    'one_sentence_day'
  ];
  deleted_instance_count integer;
begin
  if not exists (
    select 1
    from public.question_collections collection
    join public.questions question
      on question.collection_id = collection.id
    where collection.kind = 'system'
      and question.key = any(development_question_keys)
  ) then
    return;
  end if;

  if exists (
    select 1
    from public.daily_question_answers answer
    join public.daily_question_instances instance
      on instance.id = answer.instance_id
    join public.question_versions version
      on version.id = instance.question_version_id
    join public.questions question
      on question.id = version.question_id
    join public.question_collections collection
      on collection.id = question.collection_id
    where collection.kind = 'system'
      and question.key = any(development_question_keys)
  ) then
    raise exception 'development daily questions already have answers; refusing to delete relationship content'
      using errcode = '23503';
  end if;

  if exists (
    select 1
    from public.daily_question_threads thread
    join public.daily_question_instances instance
      on instance.id = thread.instance_id
    join public.question_versions version
      on version.id = instance.question_version_id
    join public.questions question
      on question.id = version.question_id
    join public.question_collections collection
      on collection.id = question.collection_id
    where collection.kind = 'system'
      and question.key = any(development_question_keys)
  ) then
    raise exception 'development daily questions already have threads; refusing to delete relationship content'
      using errcode = '23503';
  end if;

  delete from public.daily_question_shuffles shuffle
  where shuffle.question_id in (
      select question.id
      from public.question_collections collection
      join public.questions question
        on question.collection_id = collection.id
      where collection.kind = 'system'
        and question.key = any(development_question_keys)
    )
    or shuffle.skipped_instance_id in (
      select instance.id
      from public.daily_question_instances instance
      join public.question_versions version
        on version.id = instance.question_version_id
      join public.questions question
        on question.id = version.question_id
      join public.question_collections collection
        on collection.id = question.collection_id
      where collection.kind = 'system'
        and question.key = any(development_question_keys)
    )
    or shuffle.replacement_instance_id in (
      select instance.id
      from public.daily_question_instances instance
      join public.question_versions version
        on version.id = instance.question_version_id
      join public.questions question
        on question.id = version.question_id
      join public.question_collections collection
        on collection.id = question.collection_id
      where collection.kind = 'system'
        and question.key = any(development_question_keys)
    );

  loop
    delete from public.daily_question_instances instance
    using public.question_versions version,
      public.questions question,
      public.question_collections collection
    where instance.question_version_id = version.id
      and version.question_id = question.id
      and question.collection_id = collection.id
      and collection.kind = 'system'
      and question.key = any(development_question_keys)
      and not exists (
        select 1
        from public.daily_question_instances previous_instance
        where previous_instance.replaced_by_instance_id = instance.id
      );

    get diagnostics deleted_instance_count = row_count;
    exit when deleted_instance_count = 0;
  end loop;

  if exists (
    select 1
    from public.daily_question_instances instance
    join public.question_versions version
      on version.id = instance.question_version_id
    join public.questions question
      on question.id = version.question_id
    join public.question_collections collection
      on collection.id = question.collection_id
    where collection.kind = 'system'
      and question.key = any(development_question_keys)
  ) then
    raise exception 'development daily question instances could not be deleted because replacement links remain'
      using errcode = '23503';
  end if;

  delete from public.question_collections collection
  where collection.kind = 'system'
    and exists (
      select 1
      from public.questions question
      where question.collection_id = collection.id
        and question.key = any(development_question_keys)
    )
    and not exists (
      select 1
      from public.questions question
      where question.collection_id = collection.id
        and not (question.key = any(development_question_keys))
    );

  delete from public.questions question
  using public.question_collections collection
  where question.collection_id = collection.id
    and collection.kind = 'system'
    and question.key = any(development_question_keys);
end;
$$;
