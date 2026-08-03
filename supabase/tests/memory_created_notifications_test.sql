BEGIN;
SELECT plan(18);

INSERT INTO auth.users (id, email) VALUES
  ('81000000-0000-0000-0000-000000000001', 'memory-author@test.local'),
  ('81000000-0000-0000-0000-000000000002', 'memory-recipient@test.local');

UPDATE public.profiles
SET display_name = 'Oda'
WHERE user_id = '81000000-0000-0000-0000-000000000001';

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id) VALUES (
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002'
);

INSERT INTO public.couples (id, pair_id, created_by_user_id, status) VALUES (
  '83000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status) VALUES
  ('83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'active'),
  ('83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002', 'active');

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
    '84000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000002',
    'ios',
    repeat('a', 64),
    decode(repeat('a', 64), 'hex'),
    'sandbox',
    'en'
  ),
  (
    '84000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000002',
    'ios',
    repeat('b', 64),
    decode(repeat('b', 64), 'hex'),
    'sandbox',
    'nb-NO'
  );

SELECT is(
  (SELECT memories_enabled FROM public.notification_preferences
   WHERE user_id = '81000000-0000-0000-0000-000000000002'),
  true,
  'new-memory notifications default to enabled'
);

SELECT is(
  internal.notification_alert_title(
    'memory_created',
    jsonb_build_object('actor_user_id', '81000000-0000-0000-0000-000000000001'),
    'en'
  ),
  'Oda added a new memory',
  'English title names the partner without memory content'
);

SELECT is(
  internal.notification_alert_title(
    'memory_created',
    jsonb_build_object('actor_user_id', '81000000-0000-0000-0000-000000000001'),
    'nb-NO'
  ),
  'Oda la til et nytt minne',
  'Norwegian title names the partner without memory content'
);

SELECT is(
  internal.notification_alert_body('memory_created', '{}'::jsonb, 'en'),
  'Open Paeonia to see it.',
  'English body is localized'
);

SELECT is(
  internal.notification_alert_body('memory_created', '{}'::jsonb, 'nb-NO'),
  'Åpne Paeonia for å se det.',
  'Norwegian body is localized'
);

INSERT INTO public.memories (
  id,
  couple_id,
  title,
  memory_date,
  created_by_user_id,
  last_edited_by_user_id
) VALUES (
  '85000000-0000-0000-0000-000000000001',
  '83000000-0000-0000-0000-000000000001',
  'Private beach weekend',
  current_date,
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001'
);

SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'memory_created'),
  2,
  'one memory queues one alert for each recipient device'
);

SELECT is(
  (SELECT count(DISTINCT recipient_user_id)::integer
   FROM internal.notification_outbox WHERE kind = 'memory_created'),
  1,
  'only the partner receives the alert'
);

SELECT is(
  (SELECT title FROM internal.notification_outbox
   WHERE kind = 'memory_created' AND target_device_id = '84000000-0000-0000-0000-000000000001'),
  'Oda added a new memory',
  'English device receives English copy'
);

SELECT is(
  (SELECT title FROM internal.notification_outbox
   WHERE kind = 'memory_created' AND target_device_id = '84000000-0000-0000-0000-000000000002'),
  'Oda la til et nytt minne',
  'Norwegian device receives Norwegian copy'
);

SELECT is(
  (SELECT payload ->> 'deeplink' FROM internal.notification_outbox
   WHERE kind = 'memory_created' LIMIT 1),
  'paeonia://memories',
  'payload opens the Memories surface'
);

SELECT is(
  (SELECT payload ->> 'memory_id' FROM internal.notification_outbox
   WHERE kind = 'memory_created' LIMIT 1),
  '85000000-0000-0000-0000-000000000001',
  'payload identifies the created memory for stable deduplication'
);

SELECT is(
  (SELECT apns_collapse_id FROM internal.notification_outbox
   WHERE kind = 'memory_created' LIMIT 1),
  'memory:85000000-0000-0000-0000-000000000001',
  'each memory has its own collapse id so separate creations stay separate'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM internal.notification_outbox
    WHERE kind = 'memory_created'
      AND (payload::text ILIKE '%Private beach weekend%' OR body ILIKE '%Private beach weekend%')
  ),
  'notification does not leak the memory title or content'
);

UPDATE public.memories
SET title = 'Edited private title'
WHERE id = '85000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'memory_created'),
  2,
  'editing a memory does not queue another notification'
);

SELECT is(
  internal.enqueue_partner_notification(
    '83000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    'memory_created',
    jsonb_build_object(
      'type', 'memory_created',
      'memory_id', '85000000-0000-0000-0000-000000000001',
      'actor_user_id', '81000000-0000-0000-0000-000000000001',
      'route', 'memories',
      'deeplink', 'paeonia://memories'
    ),
    'memory_created:85000000-0000-0000-0000-000000000001',
    'private',
    'alert',
    'memory:85000000-0000-0000-0000-000000000001',
    now()
  ),
  0,
  'retrying the same memory notification is deduplicated per device'
);

UPDATE public.notification_preferences
SET memories_enabled = false
WHERE user_id = '81000000-0000-0000-0000-000000000002';

INSERT INTO public.memories (
  id,
  couple_id,
  title,
  memory_date,
  created_by_user_id,
  last_edited_by_user_id
) VALUES (
  '85000000-0000-0000-0000-000000000002',
  '83000000-0000-0000-0000-000000000001',
  'Another private memory',
  current_date,
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001'
);

SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'memory_created'),
  2,
  'disabled memory preference suppresses new alerts'
);

SELECT is(
  (SELECT count(*)::integer FROM internal.claim_notification_batch(50)),
  0,
  'the drain rechecks a disabled memory preference before sending queued alerts'
);

SELECT is(
  (SELECT count(*)::integer
   FROM internal.notification_outbox
   WHERE kind = 'memory_created' AND failed_at IS NOT NULL),
  2,
  'queued memory alerts become ineligible when the preference is turned off'
);

SELECT * FROM finish();
ROLLBACK;
