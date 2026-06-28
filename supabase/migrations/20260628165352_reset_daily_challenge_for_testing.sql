-- Testing helper: reset a couple's currently-active daily challenge so they can do
-- it again. Clears all skips (shuffles) and removes their answers, wipes the day's
-- question instances, then re-seeds three fresh active slots per partner.
--
-- This is an admin/testing tool: it takes any couple id and bypasses the per-user
-- auth that the app's RPCs enforce, so it is NOT granted to app users. Run it from
-- the Supabase SQL runner (which executes as a superuser), e.g.
--
--   select public.reset_daily_challenge_for_testing('00000000-0000-0000-0000-000000000000');
--
-- It returns the number of couple-days reset (0 if no challenge is active right now).
-- It intentionally leaves the streak, activity events, and uploaded media assets
-- untouched — only the answering state of today's challenge is reset.
create or replace function public.reset_daily_challenge_for_testing(p_couple_id uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_couple_day_id uuid;
  v_reset_count integer := 0;
  v_thread_ids uuid[];
begin
  if p_couple_id is null then
    raise exception 'p_couple_id is required'
      using errcode = '22023';
  end if;

  for v_couple_day_id in
    select id
    from public.couple_days
    where couple_id = p_couple_id
      and now() >= starts_at
      and now() < ends_at
  loop
    -- 1. Tear down any conversation threads attached to this day's instances
    --    (defensive — the answering flow does not create these today).
    select array_agg(thread.thread_id)
    into v_thread_ids
    from public.daily_question_threads thread
    where thread.instance_id in (
      select instance.id
      from public.daily_question_instances instance
      where instance.couple_day_id = v_couple_day_id
    );

    if v_thread_ids is not null then
      delete from public.thread_message_media
      where message_id in (
        select id from public.thread_messages where thread_id = any(v_thread_ids)
      );
      delete from public.thread_messages where thread_id = any(v_thread_ids);
      delete from public.daily_question_threads where thread_id = any(v_thread_ids);
      delete from public.conversation_threads where id = any(v_thread_ids);
    end if;

    -- 2. Remove every answer (and its detail rows) for this day's instances.
    --    Linked media assets are left in place; moderation reports null out via FK.
    delete from public.daily_answer_media
    where answer_id in (
      select answer.id
      from public.daily_question_answers answer
      join public.daily_question_instances instance
        on instance.id = answer.instance_id
      where instance.couple_day_id = v_couple_day_id
    );

    delete from public.daily_answer_text
    where answer_id in (
      select answer.id
      from public.daily_question_answers answer
      join public.daily_question_instances instance
        on instance.id = answer.instance_id
      where instance.couple_day_id = v_couple_day_id
    );

    delete from public.daily_answer_partner_choice
    where answer_id in (
      select answer.id
      from public.daily_question_answers answer
      join public.daily_question_instances instance
        on instance.id = answer.instance_id
      where instance.couple_day_id = v_couple_day_id
    );

    delete from public.daily_question_answers
    where instance_id in (
      select instance.id
      from public.daily_question_instances instance
      where instance.couple_day_id = v_couple_day_id
    );

    -- 3. Reset all skips for the day.
    delete from public.daily_question_shuffles
    where couple_day_id = v_couple_day_id;

    -- 4. Wipe the instances. Clear the self-referential "replaced by" links first so
    --    the rows can all be deleted. Status is left as-is — flipping shuffled rows to
    --    'active' would collide with the active-slot unique index; nulling only the
    --    link still satisfies the shuffled-state check (which needs replaced_at set).
    update public.daily_question_instances
    set replaced_by_instance_id = null
    where couple_day_id = v_couple_day_id
      and replaced_by_instance_id is not null;

    delete from public.daily_question_instances
    where couple_day_id = v_couple_day_id;

    -- 5. Clear completion so the card returns to its active state.
    update public.daily_challenges
    set completed_at = null,
        partner_notified_at = null
    where couple_day_id = v_couple_day_id;

    -- 6. Re-seed three fresh active slots per partner.
    perform internal.ensure_daily_challenge_slots(v_couple_day_id);

    v_reset_count := v_reset_count + 1;
  end loop;

  return v_reset_count;
end;
$$;

revoke all on function public.reset_daily_challenge_for_testing(uuid) from public, anon, authenticated;
grant execute on function public.reset_daily_challenge_for_testing(uuid) to service_role;
