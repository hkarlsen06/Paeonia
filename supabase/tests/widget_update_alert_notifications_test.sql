-- Behavior tests for the widget update notifications (20260626164532):
-- silent refresh bypasses the toggle, the alert respects it, and the alert copy
-- is localized per recipient device.
--
-- Fixed ids (author < recipient by uuid order) keep each assertion able to
-- reference the seeded rows without psql variables.

BEGIN;
SELECT plan(21);

-- Inserting auth.users auto-creates profiles + notification_preferences.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'author@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'recipient@test.local');

UPDATE public.profiles SET display_name = 'Oda'
WHERE user_id = '00000000-0000-0000-0000-0000000000a1';

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id) VALUES (
  '00000000-0000-0000-0000-0000000000b1',
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000a2'
);

INSERT INTO public.couples (id, pair_id, started_on, created_by_user_id, status) VALUES (
  '00000000-0000-0000-0000-0000000000c1',
  '00000000-0000-0000-0000-0000000000b1',
  current_date,
  '00000000-0000-0000-0000-0000000000a1',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status) VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', 'active'),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a2', 'active');

-- Recipient has two devices in different locales to prove per-device copy.
INSERT INTO public.user_devices (id, user_id, platform, push_token, push_token_hash, apns_environment, locale) VALUES
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a2', 'ios', repeat('a', 64), decode(repeat('a', 64), 'hex'), 'sandbox', 'en'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a2', 'ios', repeat('b', 64), decode(repeat('b', 64), 'hex'), 'sandbox', 'nb-NO');

UPDATE public.notification_preferences SET widget_updates_enabled = true
WHERE user_id = '00000000-0000-0000-0000-0000000000a2';

-- 1-3) Localized body resolves per locale, with English fallback.
SELECT is(
  internal.widget_updated_notification_body('en'),
  'Added a new drawing',
  'English body'
);
SELECT is(
  internal.widget_updated_notification_body('no'),
  'La til en ny tegning',
  'Norwegian variants map to nb'
);
SELECT is(
  internal.widget_updated_notification_body('de-DE'),
  'Added a new drawing',
  'unknown locale falls back to English'
);

-- 4-6) Shared locale helper normalizes every Norwegian Apple locale family to nb.
SELECT is(
  internal.notification_locale_language('no-NO'),
  'nb',
  'no locale maps to nb'
);
SELECT is(
  internal.notification_locale_language('nb'),
  'nb',
  'nb locale maps to nb'
);
SELECT is(
  internal.notification_locale_language('nn'),
  'nb',
  'nn locale maps to nb for MVP copy'
);

-- 7-8) Partner-answer copy uses the actor name and shared localized bodies.
SELECT is(
  internal.notification_alert_title(
    'partner_answered',
    jsonb_build_object('actor_user_id', '00000000-0000-0000-0000-0000000000a1'),
    'en'
  ),
  'Oda answered the same question!',
  'partner answered title includes actor name'
);
SELECT is(
  internal.notification_alert_body('partner_answered', '{}'::jsonb, 'nb-NO'),
  'Åpne Paeonia for å se hva partneren din skrev.',
  'partner answered body localizes to Norwegian Bokmål'
);

UPDATE public.notification_preferences SET partner_answered_enabled = false
WHERE user_id = '00000000-0000-0000-0000-0000000000a2';

-- 9) Partner-answer alerts respect their own preference column.
SELECT is(
  internal.enqueue_notification_for_user(
    '00000000-0000-0000-0000-0000000000a2',
    'partner_answered',
    jsonb_build_object(
      'type', 'partner_answered',
      'actor_user_id', '00000000-0000-0000-0000-0000000000a1',
      'route', 'daily',
      'deeplink', 'paeonia://daily/today'
    ),
    'partner-pref-disabled',
    'private',
    'alert',
    'daily:test',
    now()
  ),
  0,
  'partner answered preference disables alert rows'
);

UPDATE public.notification_preferences SET partner_answered_enabled = true
WHERE user_id = '00000000-0000-0000-0000-0000000000a2';

-- 10) Alert enqueues one row per recipient device.
SELECT is(
  internal.enqueue_widget_update_alert(
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-0000000000a1',
    gen_random_uuid(), gen_random_uuid()
  ),
  2,
  'alert enqueues one row per recipient device'
);

-- 11) Title is the author's display name.
SELECT is(
  (SELECT string_agg(DISTINCT title, ',') FROM internal.notification_outbox
   WHERE recipient_user_id = '00000000-0000-0000-0000-0000000000a2' AND apns_push_type = 'alert'),
  'Oda',
  'alert title is the author display name'
);

-- 12-13) Body is localized to each device's own locale.
SELECT is(
  (SELECT body FROM internal.notification_outbox
   WHERE target_device_id = '00000000-0000-0000-0000-0000000000d1' AND apns_push_type = 'alert'),
  'Added a new drawing',
  'English device gets English body'
);
SELECT is(
  (SELECT body FROM internal.notification_outbox
   WHERE target_device_id = '00000000-0000-0000-0000-0000000000d2' AND apns_push_type = 'alert'),
  'La til en ny tegning',
  'Norwegian device gets Norwegian body'
);

INSERT INTO public.question_collections (id, kind, couple_id, created_by_user_id, status) VALUES (
  '00000000-0000-0000-0000-0000000000e1',
  'custom',
  '00000000-0000-0000-0000-0000000000c1',
  '00000000-0000-0000-0000-0000000000a1',
  'draft'
);

INSERT INTO public.questions (id, collection_id, key, status) VALUES (
  '00000000-0000-0000-0000-0000000000e2',
  '00000000-0000-0000-0000-0000000000e1',
  'notification_test_question',
  'draft'
);

INSERT INTO public.question_versions (id, question_id, version_number, status) VALUES (
  '00000000-0000-0000-0000-0000000000e3',
  '00000000-0000-0000-0000-0000000000e2',
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
  '00000000-0000-0000-0000-0000000000e4',
  '00000000-0000-0000-0000-0000000000c1',
  current_date,
  'UTC',
  now(),
  now() + interval '1 day'
);

INSERT INTO public.daily_question_instances (
  id,
  couple_day_id,
  question_version_id,
  seeded_for_user_id,
  slot_number
) VALUES (
  '00000000-0000-0000-0000-0000000000e5',
  '00000000-0000-0000-0000-0000000000e4',
  '00000000-0000-0000-0000-0000000000e3',
  '00000000-0000-0000-0000-0000000000a1',
  1
);

INSERT INTO public.daily_question_answers (id, instance_id, user_id) VALUES (
  '00000000-0000-0000-0000-0000000000e6',
  '00000000-0000-0000-0000-0000000000e5',
  '00000000-0000-0000-0000-0000000000a2'
);

-- 14) The first visible answer does not queue partner-answer notifications.
SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'partner_answered'),
  0,
  'first visible answer does not queue partner answered notification'
);

INSERT INTO public.daily_question_answers (id, instance_id, user_id) VALUES (
  '00000000-0000-0000-0000-0000000000e7',
  '00000000-0000-0000-0000-0000000000e5',
  '00000000-0000-0000-0000-0000000000a1'
);

-- 15) The second visible answer queues one row per recipient device.
SELECT is(
  (SELECT count(*)::integer FROM internal.notification_outbox WHERE kind = 'partner_answered'),
  2,
  'second visible answer queues partner answered notification per device'
);

-- 16) Partner-answer payload carries the canonical daily reveal deeplink.
SELECT is(
  (
    SELECT payload ->> 'deeplink'
    FROM internal.notification_outbox
    WHERE kind = 'partner_answered'
    LIMIT 1
  ),
  'paeonia://daily/reveal?instanceId=00000000-0000-0000-0000-0000000000e5&coupleDayId=00000000-0000-0000-0000-0000000000e4',
  'partner answered payload has daily reveal deeplink'
);

-- 17) The delivery claim returns non-widget app notifications too.
SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.claim_notification_batch(20)
    WHERE payload ->> 'type' = 'partner_answered'
  ),
  'claim batch returns partner answered app notifications'
);

-- 18) A dead token (invalid_token) fails its row immediately, not after retries.
SELECT internal.mark_notification_result(
  (SELECT id FROM internal.notification_outbox
   WHERE target_device_id = '00000000-0000-0000-0000-0000000000d1' AND apns_push_type = 'alert' LIMIT 1),
  false, NULL, NULL, true
);
SELECT ok(
  (SELECT failed_at IS NOT NULL FROM internal.notification_outbox
   WHERE target_device_id = '00000000-0000-0000-0000-0000000000d1' AND apns_push_type = 'alert' LIMIT 1),
  'invalid token fails the row immediately'
);

-- 19) A transient failure leaves the row retryable (failed_at stays null).
SELECT internal.mark_notification_result(
  (SELECT id FROM internal.notification_outbox
   WHERE target_device_id = '00000000-0000-0000-0000-0000000000d2' AND apns_push_type = 'alert' LIMIT 1),
  false, NULL, 'TooManyRequests', false
);
SELECT ok(
  (SELECT failed_at IS NULL FROM internal.notification_outbox
   WHERE target_device_id = '00000000-0000-0000-0000-0000000000d2' AND apns_push_type = 'alert' LIMIT 1),
  'transient failure keeps the row retryable'
);

-- Turn the alert toggle off.
UPDATE public.notification_preferences SET widget_updates_enabled = false
WHERE user_id = '00000000-0000-0000-0000-0000000000a2';

-- 20) Silent refresh ignores the toggle (still enqueues for both devices).
SELECT is(
  internal.enqueue_notification_for_user(
    '00000000-0000-0000-0000-0000000000a2', 'widget_updated',
    jsonb_build_object('type', 'widget_updated', 'canvas_id', 'x'),
    'silent-test', 'private', 'background', 'widget', now()
  ),
  2,
  'silent refresh bypasses the disabled toggle'
);

-- 21) Alert respects the toggle (enqueues nothing when off).
SELECT is(
  internal.enqueue_widget_update_alert(
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-0000000000a1',
    gen_random_uuid(), gen_random_uuid()
  ),
  0,
  'alert is suppressed when the toggle is off'
);

SELECT * FROM finish();
ROLLBACK;
