BEGIN;
SELECT plan(23);

INSERT INTO auth.users (id, email) VALUES
  ('91000000-0000-0000-0000-000000000001', 'thread-sender@test.local'),
  ('91000000-0000-0000-0000-000000000002', 'thread-recipient@test.local');

UPDATE public.profiles
SET
  display_name = CASE
    WHEN user_id = '91000000-0000-0000-0000-000000000001' THEN 'Oda'
    ELSE display_name
  END,
  time_zone_id = 'UTC',
  time_zone_updated_at = now()
WHERE user_id IN (
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002'
);

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id) VALUES (
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002'
);

INSERT INTO public.couples (id, pair_id, created_by_user_id, status) VALUES (
  '93000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status) VALUES
  (
    '93000000-0000-0000-0000-000000000001',
    '91000000-0000-0000-0000-000000000001',
    'active'
  ),
  (
    '93000000-0000-0000-0000-000000000001',
    '91000000-0000-0000-0000-000000000002',
    'active'
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
    '94000000-0000-0000-0000-000000000001',
    '91000000-0000-0000-0000-000000000001',
    'ios',
    repeat('a', 64),
    decode(repeat('a', 64), 'hex'),
    'sandbox',
    'en'
  ),
  (
    '94000000-0000-0000-0000-000000000002',
    '91000000-0000-0000-0000-000000000002',
    'ios',
    repeat('b', 64),
    decode(repeat('b', 64), 'hex'),
    'sandbox',
    'en'
  );

SELECT is(
  (
    SELECT messages_enabled
    FROM public.notification_preferences
    WHERE user_id = '91000000-0000-0000-0000-000000000002'
  ),
  true,
  'message notifications default to enabled'
);

SELECT ok(
  has_column_privilege(
    'authenticated',
    'public.notification_preferences',
    'messages_enabled',
    'select'
  ) AND has_column_privilege(
    'authenticated',
    'public.notification_preferences',
    'messages_enabled',
    'update'
  ),
  'authenticated users can read and update the message preference through RLS'
);

INSERT INTO public.memories (
  id,
  couple_id,
  title,
  memory_date,
  created_by_user_id,
  last_edited_by_user_id
) VALUES (
  '95000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  'Private memory title',
  current_date,
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001'
);

DELETE FROM internal.notification_outbox WHERE kind = 'memory_created';

INSERT INTO public.conversation_threads (
  id,
  couple_id,
  kind,
  created_by_user_id
) VALUES (
  '96000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  'memory',
  '91000000-0000-0000-0000-000000000001'
);

INSERT INTO public.memory_threads (memory_id, thread_id) VALUES (
  '95000000-0000-0000-0000-000000000001',
  '96000000-0000-0000-0000-000000000001'
);

SELECT lives_ok(
  $$
    INSERT INTO public.thread_messages (
      id,
      thread_id,
      sender_user_id,
      body
    ) VALUES (
      '97000000-0000-0000-0000-000000000001',
      '96000000-0000-0000-0000-000000000001',
      '91000000-0000-0000-0000-000000000001',
      'Secret message text one'
    )
  $$,
  'a memory-thread message succeeds while activity and push work run'
);

SELECT is(
  (
    SELECT activity_kind
    FROM public.couple_activity_events
    WHERE dedupe_key = 'thread_message_sent:97000000-0000-0000-0000-000000000001'
  ),
  'thread_message_sent',
  'the message records a deduplicated couple activity event'
);

SELECT is(
  (
    SELECT metadata ->> 'thread_id'
    FROM public.couple_activity_events
    WHERE dedupe_key = 'thread_message_sent:97000000-0000-0000-0000-000000000001'
  ),
  '96000000-0000-0000-0000-000000000001',
  'the activity metadata identifies the thread'
);

SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'thread_message_sent'),
  1,
  'one enabled message queues one partner-device alert'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
      AND recipient_user_id = '91000000-0000-0000-0000-000000000002'
  ) AND NOT EXISTS (
    SELECT 1
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
      AND recipient_user_id = '91000000-0000-0000-0000-000000000001'
  ),
  'only the other active partner receives the alert'
);

SELECT ok(
  (
    SELECT payload = jsonb_build_object(
      'type', 'thread_message_sent',
      'couple_id', '93000000-0000-0000-0000-000000000001',
      'thread_id', '96000000-0000-0000-0000-000000000001',
      'message_id', '97000000-0000-0000-0000-000000000001',
      'actor_user_id', '91000000-0000-0000-0000-000000000001',
      'route', 'memories',
      'deeplink', 'paeonia://memories',
      'memory_id', '95000000-0000-0000-0000-000000000001'
    )
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
  ),
  'memory-thread payload matches the client contract exactly'
);

SELECT ok(
  (
    SELECT dedupe_key =
        'thread_message_sent:97000000-0000-0000-0000-000000000001:' ||
        '94000000-0000-0000-0000-000000000002'
      AND apns_collapse_id = 'thread:96000000-0000-0000-0000-000000000001'
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
  ),
  'dedupe and collapse keys are stable per message and thread'
);

SELECT results_eq(
  $$
    SELECT title, body
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
  $$,
  $$ VALUES ('Paeonia'::text, 'Open Paeonia to see what''s new.'::text) $$,
  'private lock-screen detail uses fully generic English copy'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
      AND (
        payload::text ILIKE '%Secret message text one%'
        OR title ILIKE '%Secret message text one%'
        OR body ILIKE '%Secret message text one%'
      )
  ),
  'the message text is absent from the queued payload and copy'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.thread_messages
    WHERE id = '97000000-0000-0000-0000-000000000001'
  ),
  1,
  'the first message remains stored'
);

UPDATE public.notification_preferences
SET lock_screen_detail_level = 'descriptive'
WHERE user_id = '91000000-0000-0000-0000-000000000002';

SELECT ok(
  (
    SELECT revision > 1
    FROM public.notification_preferences
    WHERE user_id = '91000000-0000-0000-0000-000000000002'
  ),
  'preference updates keep using the existing revision trigger'
);

INSERT INTO public.question_collections (
  id,
  kind,
  couple_id,
  created_by_user_id,
  status
) VALUES (
  '98000000-0000-0000-0000-000000000001',
  'custom',
  '93000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  'draft'
);

INSERT INTO public.questions (id, collection_id, key, status) VALUES (
  '98000000-0000-0000-0000-000000000002',
  '98000000-0000-0000-0000-000000000001',
  'thread_message_notification_test',
  'draft'
);

INSERT INTO public.question_versions (id, question_id, version_number, status) VALUES (
  '98000000-0000-0000-0000-000000000003',
  '98000000-0000-0000-0000-000000000002',
  1,
  'draft'
);

INSERT INTO public.couple_days (
  id,
  couple_id,
  local_date,
  anchor_time_zone_id,
  starts_at,
  ends_at
) VALUES (
  '98000000-0000-0000-0000-000000000004',
  '93000000-0000-0000-0000-000000000001',
  current_date,
  'UTC',
  date_trunc('day', now()),
  date_trunc('day', now()) + interval '1 day'
) ON CONFLICT (couple_id, local_date) DO NOTHING;

INSERT INTO public.daily_question_instances (
  id,
  couple_day_id,
  question_version_id,
  seeded_for_user_id,
  slot_number
)
SELECT
  '98000000-0000-0000-0000-000000000005',
  day.id,
  '98000000-0000-0000-0000-000000000003',
  '91000000-0000-0000-0000-000000000001',
  1
FROM public.couple_days day
WHERE day.couple_id = '93000000-0000-0000-0000-000000000001'
  AND day.local_date = current_date;

INSERT INTO public.conversation_threads (
  id,
  couple_id,
  kind,
  created_by_user_id
) VALUES (
  '98000000-0000-0000-0000-000000000006',
  '93000000-0000-0000-0000-000000000001',
  'daily_question',
  '91000000-0000-0000-0000-000000000001'
);

INSERT INTO public.daily_question_threads (instance_id, thread_id) VALUES (
  '98000000-0000-0000-0000-000000000005',
  '98000000-0000-0000-0000-000000000006'
);

SELECT lives_ok(
  $$
    INSERT INTO public.thread_messages (
      id,
      thread_id,
      sender_user_id,
      body
    ) VALUES (
      '97000000-0000-0000-0000-000000000002',
      '98000000-0000-0000-0000-000000000006',
      '91000000-0000-0000-0000-000000000001',
      'Secret message text two'
    )
  $$,
  'a daily-question thread message succeeds'
);

SELECT ok(
  (
    SELECT payload = jsonb_build_object(
      'type', 'thread_message_sent',
      'couple_id', '93000000-0000-0000-0000-000000000001',
      'thread_id', '98000000-0000-0000-0000-000000000006',
      'message_id', '97000000-0000-0000-0000-000000000002',
      'actor_user_id', '91000000-0000-0000-0000-000000000001',
      'route', 'daily',
      'deeplink',
        'paeonia://daily/chat?instanceId=98000000-0000-0000-0000-000000000005',
      'instance_id', '98000000-0000-0000-0000-000000000005'
    )
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
      AND payload ->> 'message_id' = '97000000-0000-0000-0000-000000000002'
  ),
  'daily-question payload matches the client contract exactly'
);

SELECT results_eq(
  $$
    SELECT title, body
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
      AND payload ->> 'message_id' = '97000000-0000-0000-0000-000000000002'
  $$,
  $$ VALUES ('Oda sent you a message'::text, 'Open Paeonia to reply.'::text) $$,
  'descriptive lock-screen detail names the sender without message text'
);

SELECT is(
  internal.notification_alert_title(
    'thread_message_sent',
    jsonb_build_object(
      'actor_user_id', '91000000-0000-0000-0000-000000000001',
      'lock_screen_detail_level', 'descriptive'
    ),
    'nb-NO'
  ),
  'Oda sendte deg en melding',
  'Norwegian descriptive title is localized'
);

SELECT is(
  internal.notification_alert_body(
    'thread_message_sent',
    jsonb_build_object('lock_screen_detail_level', 'descriptive'),
    'nb-NO'
  ),
  'Åpne Paeonia for å svare.',
  'Norwegian descriptive body is localized'
);

UPDATE public.notification_preferences
SET messages_enabled = false
WHERE user_id = '91000000-0000-0000-0000-000000000002';

SELECT lives_ok(
  $$
    INSERT INTO public.thread_messages (
      id,
      thread_id,
      sender_user_id,
      body
    ) VALUES (
      '97000000-0000-0000-0000-000000000003',
      '96000000-0000-0000-0000-000000000001',
      '91000000-0000-0000-0000-000000000001',
      'Secret message text three'
    )
  $$,
  'a message still succeeds when its partner alert is disabled'
);

SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'thread_message_sent'),
  2,
  'messages_enabled false suppresses the new partner alert'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.couple_activity_events
    WHERE dedupe_key = 'thread_message_sent:97000000-0000-0000-0000-000000000003'
  ),
  1,
  'disabled alerts do not suppress streak activity'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.thread_messages
    WHERE id = '97000000-0000-0000-0000-000000000003'
  ),
  1,
  'the message remains stored when the preference suppresses its alert'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM internal.notification_outbox
    WHERE kind = 'thread_message_sent'
      AND (
        payload::text ILIKE '%Secret message text%'
        OR title ILIKE '%Secret message text%'
        OR body ILIKE '%Secret message text%'
      )
  ),
  'no queued thread alert contains any tested message body'
);

SELECT * FROM finish();
ROLLBACK;
