-- The paid restore window is 24 hours after the streak has broken. The natural
-- grace day remains separate: a streak breaks at next_activity_deadline_at + 1
-- day, and paid restore closes one day after that.

with adjusted_restore_deadlines as (
  select
    couple_id,
    next_activity_deadline_at + interval '1 day' + interval '24 hours' as new_restore_deadline
  from public.streak_states
  where restorable_count > 0
    and next_activity_deadline_at is not null
    and restore_deadline is not null
    and restore_deadline = next_activity_deadline_at + interval '1 day' + interval '48 hours'
)
update public.streak_states streak
set
  restore_deadline = adjusted.new_restore_deadline,
  restore_available = adjusted.new_restore_deadline > now()
from adjusted_restore_deadlines adjusted
where streak.couple_id = adjusted.couple_id;

do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef('internal.detect_streak_break(uuid)'::regprocedure)
  into function_definition;

  execute replace(
    function_definition,
    $$interval '48 hours'$$,
    $$interval '24 hours'$$
  );

  select pg_get_functiondef(
    'internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb)'::regprocedure
  )
  into function_definition;

  execute replace(
    function_definition,
    $$interval '48 hours'$$,
    $$interval '24 hours'$$
  );
end;
$migration$;
