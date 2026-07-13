BEGIN;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'streak-a@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'streak-b@test.local');

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id) VALUES (
  '00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000a2'
);

INSERT INTO public.couples (id, pair_id, created_by_user_id, status) VALUES (
  '00000000-0000-0000-0000-0000000000c1',
  '00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000a1',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status) VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'active'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'active');

INSERT INTO public.couple_days (
  id,
  couple_id,
  local_date,
  anchor_time_zone_id,
  starts_at,
  ends_at
) VALUES (
  '00000000-0000-0000-0000-0000000000d1',
  '00000000-0000-0000-0000-0000000000c1',
  current_date - 1,
  'UTC',
  date_trunc('day', now()) - interval '1 day',
  date_trunc('day', now())
);

INSERT INTO public.streak_states (
  couple_id,
  current_count,
  longest_count,
  last_qualified_date,
  last_qualified_couple_day_id,
  next_activity_deadline_at
) VALUES (
  '00000000-0000-0000-0000-0000000000c1',
  5,
  8,
  current_date - 1,
  '00000000-0000-0000-0000-0000000000d1',
  now() + interval '1 hour'
);

INSERT INTO public.couple_activity_events (
  couple_id,
  user_id,
  couple_day_id,
  activity_kind,
  occurred_at,
  dedupe_key
) VALUES (
  '00000000-0000-0000-0000-0000000000c1',
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000d1',
  'widget_drawing_saved',
  now() - interval '1 hour',
  'streak-read-model:latest-activity'
);

SELECT is(
  (SELECT current_count FROM internal.get_couple_streak_for_couple(
    '00000000-0000-0000-0000-0000000000c1'
  )),
  5,
  'an active streak exposes its stored count'
);

UPDATE public.streak_states
SET next_activity_deadline_at = now() - interval '36 hours'
WHERE couple_id = '00000000-0000-0000-0000-0000000000c1';

UPDATE public.couple_activity_events
SET occurred_at = now() - interval '3 days'
WHERE dedupe_key = 'streak-read-model:latest-activity';

SELECT is(
  (SELECT current_count FROM internal.get_couple_streak_for_couple(
    '00000000-0000-0000-0000-0000000000c1'
  )),
  0,
  'a broken streak exposes zero while its restore offer is open'
);

UPDATE public.streak_states
SET restore_deadline = now() - interval '1 hour'
WHERE couple_id = '00000000-0000-0000-0000-0000000000c1';

SELECT results_eq(
  $$
    SELECT current_count, restore_available
    FROM internal.get_couple_streak_for_couple(
      '00000000-0000-0000-0000-0000000000c1'
    )
  $$,
  $$ VALUES (0, false) $$,
  'an expired restore offer cannot revive the historical count'
);

UPDATE public.streak_states
SET
  current_count = 1,
  last_qualified_date = current_date,
  next_activity_deadline_at = now() + interval '1 hour'
WHERE couple_id = '00000000-0000-0000-0000-0000000000c1';

SELECT is(
  (SELECT current_count FROM internal.get_couple_streak_for_couple(
    '00000000-0000-0000-0000-0000000000c1'
  )),
  1,
  'new qualifying activity exposes the restarted streak despite an old restore snapshot'
);

SELECT * FROM finish();
ROLLBACK;
