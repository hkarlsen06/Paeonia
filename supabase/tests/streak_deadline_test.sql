BEGIN;
SELECT plan(10);

INSERT INTO auth.users (id, email) VALUES
  ('81000000-0000-0000-0000-000000000001', 'streak-time-a@test.local'),
  ('81000000-0000-0000-0000-000000000002', 'streak-time-b@test.local');

INSERT INTO public.profiles (
  user_id,
  display_name,
  time_zone_id,
  time_zone_updated_at,
  onboarding_completed_at
) VALUES
  (
    '81000000-0000-0000-0000-000000000001',
    'A',
    'Europe/Oslo',
    now(),
    now()
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    'B',
    'Europe/Oslo',
    now(),
    now()
  );

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id) VALUES (
  '81000000-0000-0000-0000-000000000010',
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002'
);

INSERT INTO public.couples (id, pair_id, created_by_user_id, status) VALUES (
  '81000000-0000-0000-0000-000000000020',
  '81000000-0000-0000-0000-000000000010',
  '81000000-0000-0000-0000-000000000001',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status) VALUES
  (
    '81000000-0000-0000-0000-000000000020',
    '81000000-0000-0000-0000-000000000001',
    'active'
  ),
  (
    '81000000-0000-0000-0000-000000000020',
    '81000000-0000-0000-0000-000000000002',
    'active'
  );

SELECT is(
  internal.resolve_next_activity_deadline_at(
    '81000000-0000-0000-0000-000000000020',
    '2026-03-28 12:00:00+00'::timestamptz
  ),
  '2026-03-29 22:00:00+00'::timestamptz,
  'spring DST uses midnight after the next local calendar day, not a fixed 48 hours'
);

SELECT is(
  internal.resolve_next_activity_deadline_at(
    '81000000-0000-0000-0000-000000000020',
    '2026-10-24 12:00:00+00'::timestamptz
  ),
  '2026-10-25 23:00:00+00'::timestamptz,
  'autumn DST uses midnight after the next local calendar day, not a fixed 48 hours'
);

INSERT INTO public.user_devices (
  id,
  user_id,
  platform,
  push_token,
  push_token_hash,
  apns_environment,
  time_zone_id,
  last_seen_at
) VALUES (
  '81000000-0000-0000-0000-000000000030',
  '81000000-0000-0000-0000-000000000002',
  'ios',
  'streak-time-zone-test-token',
  extensions.digest('streak-time-zone-test-token', 'sha256'),
  'sandbox',
  'America/Los_Angeles',
  now()
);

SELECT is(
  internal.resolve_next_activity_deadline_at(
    '81000000-0000-0000-0000-000000000020',
    '2026-07-13 12:00:00+00'::timestamptz
  ),
  '2026-07-15 07:00:00+00'::timestamptz,
  'the streak waits for the partner whose protective midnight occurs last'
);

UPDATE public.profiles
SET time_zone_id = 'Pacific/Auckland', time_zone_updated_at = now()
WHERE user_id = '81000000-0000-0000-0000-000000000002';

SELECT is(
  internal.resolve_next_activity_deadline_at(
    '81000000-0000-0000-0000-000000000020',
    '2026-07-13 12:00:00+00'::timestamptz
  ),
  '2026-07-15 12:00:00+00'::timestamptz,
  'the same activity gets a live travel-aware deadline from current time zones'
);

SELECT is(
  internal.resolve_streak_deadline_at(
    '81000000-0000-0000-0000-000000000020',
    '2026-07-13 12:00:00+00'::timestamptz,
    1
  ),
  '2026-07-14 12:00:00+00'::timestamptz,
  'restore without new activity is anchored to the last protective partner midnight'
);

DO $$
BEGIN
  PERFORM internal.apply_couple_activity(
    '81000000-0000-0000-0000-000000000020',
    '81000000-0000-0000-0000-000000000001',
    internal.get_or_create_couple_day_at(
      '81000000-0000-0000-0000-000000000020',
      '2026-07-13 12:00:00+00'::timestamptz
    ),
    'widget_drawing_saved',
    '2026-07-13 12:00:00+00'::timestamptz,
    'streak-deadline-test:drawing',
    '{}'::jsonb
  );
END;
$$;

SELECT is(
  (
    SELECT current_count
    FROM public.streak_states
    WHERE couple_id = '81000000-0000-0000-0000-000000000020'
  ),
  1,
  'saving a drawing starts or extends the shared streak'
);

SELECT is(
  (
    SELECT activity_kind
    FROM public.couple_activity_events
    WHERE dedupe_key = 'streak-deadline-test:drawing'
  ),
  'widget_drawing_saved',
  'drawing activity remains auditable as a qualifying event'
);

UPDATE public.profiles
SET time_zone_id = 'America/Los_Angeles', time_zone_updated_at = now()
WHERE user_id = '81000000-0000-0000-0000-000000000002';

SELECT is(
  (
    SELECT next_activity_deadline_at
    FROM public.streak_states
    WHERE couple_id = '81000000-0000-0000-0000-000000000020'
  ),
  '2026-07-15 07:00:00+00'::timestamptz,
  'a current device time zone immediately recalculates the live streak deadline'
);

UPDATE public.profiles
SET time_zone_id = 'Pacific/Auckland', time_zone_updated_at = now()
WHERE user_id = '81000000-0000-0000-0000-000000000002';

SELECT is(
  (
    SELECT next_activity_deadline_at
    FROM public.streak_states
    WHERE couple_id = '81000000-0000-0000-0000-000000000020'
  ),
  '2026-07-15 07:00:00+00'::timestamptz,
  'the most recently seen active device takes precedence over the onboarding profile zone'
);

UPDATE public.user_devices
SET time_zone_id = 'Pacific/Auckland', last_seen_at = now() + interval '1 second'
WHERE id = '81000000-0000-0000-0000-000000000030';

SELECT is(
  (
    SELECT next_activity_deadline_at
    FROM public.streak_states
    WHERE couple_id = '81000000-0000-0000-0000-000000000020'
  ),
  '2026-07-15 12:00:00+00'::timestamptz,
  'travel reported by the active device updates the live deadline again'
);

SELECT * FROM finish();
ROLLBACK;
