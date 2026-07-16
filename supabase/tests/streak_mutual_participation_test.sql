BEGIN;
SELECT plan(14);

INSERT INTO auth.users (id, email) VALUES
  ('82000000-0000-0000-0000-000000000001', 'mutual-streak-a@test.local'),
  ('82000000-0000-0000-0000-000000000002', 'mutual-streak-b@test.local');

UPDATE public.profiles
SET time_zone_id = 'UTC', time_zone_updated_at = now()
WHERE user_id IN (
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002'
);

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id) VALUES (
  '82000000-0000-0000-0000-000000000010',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002'
);

INSERT INTO public.couples (id, pair_id, created_by_user_id, status) VALUES (
  '82000000-0000-0000-0000-000000000020',
  '82000000-0000-0000-0000-000000000010',
  '82000000-0000-0000-0000-000000000001',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status) VALUES
  (
    '82000000-0000-0000-0000-000000000020',
    '82000000-0000-0000-0000-000000000001',
    'active'
  ),
  (
    '82000000-0000-0000-0000-000000000020',
    '82000000-0000-0000-0000-000000000002',
    'active'
  );

INSERT INTO public.couple_days (
  id,
  couple_id,
  local_date,
  anchor_time_zone_id,
  starts_at,
  ends_at
) VALUES
  (
    '82000000-0000-0000-0000-000000000031',
    '82000000-0000-0000-0000-000000000020',
    current_date - 1,
    'UTC',
    date_trunc('day', now()) - interval '1 day',
    date_trunc('day', now())
  ),
  (
    '82000000-0000-0000-0000-000000000032',
    '82000000-0000-0000-0000-000000000020',
    current_date,
    'UTC',
    date_trunc('day', now()),
    date_trunc('day', now()) + interval '1 day'
  );

SELECT lives_ok(
  $$
    SELECT internal.apply_couple_activity(
      '82000000-0000-0000-0000-000000000020',
      '82000000-0000-0000-0000-000000000001',
      '82000000-0000-0000-0000-000000000031',
      'daily_challenge_completed',
      date_trunc('day', now()) - interval '14 hours',
      'mutual-streak:first-a',
      '{}'::jsonb
    )
  $$,
  'the first partner contribution remains a valid auditable event'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.streak_states
    WHERE couple_id = '82000000-0000-0000-0000-000000000020'
  ),
  0,
  'one partner cannot start the couple streak'
);

SELECT lives_ok(
  $$
    SELECT internal.apply_couple_activity(
      '82000000-0000-0000-0000-000000000020',
      '82000000-0000-0000-0000-000000000001',
      '82000000-0000-0000-0000-000000000031',
      'widget_drawing_saved',
      date_trunc('day', now()) - interval '13 hours',
      'mutual-streak:second-a',
      '{}'::jsonb
    )
  $$,
  'repeat activity by the same partner is accepted'
);

SELECT is(
  (
    SELECT internal.get_couple_day_streak_qualified_at(
      '82000000-0000-0000-0000-000000000020',
      '82000000-0000-0000-0000-000000000031'
    )
  ),
  NULL::timestamptz,
  'repeat activity by one partner still does not qualify the day'
);

SELECT lives_ok(
  $$
    SELECT internal.apply_couple_activity(
      '82000000-0000-0000-0000-000000000020',
      '82000000-0000-0000-0000-000000000002',
      '82000000-0000-0000-0000-000000000031',
      'memory_created',
      date_trunc('day', now()) - interval '12 hours',
      'mutual-streak:first-b',
      '{}'::jsonb
    )
  $$,
  'the second partner can qualify the shared day'
);

SELECT is(
  (
    SELECT current_count
    FROM public.streak_states
    WHERE couple_id = '82000000-0000-0000-0000-000000000020'
  ),
  1,
  'the streak starts only after both partners contribute'
);

SELECT is(
  internal.get_couple_day_streak_qualified_at(
    '82000000-0000-0000-0000-000000000020',
    '82000000-0000-0000-0000-000000000031'
  ),
  date_trunc('day', now()) - interval '12 hours',
  'the day qualifies when the later partner first contributes, not on a repeat event'
);

SELECT internal.apply_couple_activity(
  '82000000-0000-0000-0000-000000000020',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000032',
  'thread_message_sent',
  date_trunc('day', now()) + interval '10 hours',
  'mutual-streak:next-day-a',
  '{}'::jsonb
);

SELECT is(
  (
    SELECT current_count
    FROM public.streak_states
    WHERE couple_id = '82000000-0000-0000-0000-000000000020'
  ),
  1,
  'one partner cannot advance an existing streak on the next day'
);

SELECT results_eq(
  $$
    SELECT current_user_contributed_today, partner_contributed_today
    FROM internal.get_couple_streak_participation_for_user(
      '82000000-0000-0000-0000-000000000020',
      '82000000-0000-0000-0000-000000000001',
      date_trunc('day', now()) + interval '23 hours 30 minutes'
    )
  $$,
  $$ VALUES (true, false) $$,
  'the app read model distinguishes which partner still needs to contribute'
);

INSERT INTO public.user_devices (
  id,
  user_id,
  platform,
  push_token,
  push_token_hash,
  apns_environment,
  locale
) VALUES
  (
    '82000000-0000-0000-0000-000000000041',
    '82000000-0000-0000-0000-000000000001',
    'ios',
    repeat('a', 64),
    decode(repeat('a', 64), 'hex'),
    'sandbox',
    'en'
  ),
  (
    '82000000-0000-0000-0000-000000000042',
    '82000000-0000-0000-0000-000000000002',
    'ios',
    repeat('b', 64),
    decode(repeat('b', 64), 'hex'),
    'sandbox',
    'nb'
  );

-- Put the live deadline inside the scheduler window. The scheduler refreshes it
-- from the mutually qualified event before selecting missing contributors.
SELECT is(
  internal.enqueue_due_streak_reminders(
    date_trunc('day', now()) + interval '23 hours 30 minutes'
  ),
  1,
  'only the partner who has not contributed receives a reminder'
);

SELECT is(
  (
    SELECT recipient_user_id
    FROM internal.notification_outbox
    WHERE kind = 'streak_reminder'
      AND payload ->> 'couple_id' = '82000000-0000-0000-0000-000000000020'
  ),
  '82000000-0000-0000-0000-000000000002'::uuid,
  'the already-contributing partner is excluded from reminder fanout'
);

SELECT is(
  internal.enqueue_due_streak_reminders(
    date_trunc('day', now()) + interval '23 hours 30 minutes'
  ),
  0,
  'recipient-scoped reminder deduplication is stable across scheduler retries'
);

SELECT is(
  internal.notification_alert_body(
    'streak_reminder',
    '{}'::jsonb,
    'en'
  ),
  'Do one small thing today. Your streak continues once both of you have checked in.',
  'reminder copy clearly explains that both partners must contribute'
);

UPDATE public.streak_states
SET
  current_count = 1,
  longest_count = 9,
  next_activity_deadline_at = now() - interval '1 hour',
  restore_available = true,
  restorable_count = 9,
  restorable_through_date = current_date - 1,
  restore_deadline = now() + interval '1 hour'
WHERE couple_id = '82000000-0000-0000-0000-000000000020';

SELECT is(
  (
    internal.apply_streak_restore(
      '82000000-0000-0000-0000-000000000020',
      '82000000-0000-0000-0000-000000000001',
      (
        SELECT id
        FROM public.subscription_products
        WHERE apple_product_id = 'no.paeonia.streak.restore'
      ),
      'sandbox',
      'mutual-streak-restore-transaction',
      'mutual-streak-restore-original',
      now(),
      NULL
    ) ->> 'restoredCount'
  )::integer,
  9,
  'a restore does not add today when only one partner has contributed'
);

SELECT * FROM finish();
ROLLBACK;
