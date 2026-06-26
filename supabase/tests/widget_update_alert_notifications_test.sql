-- Behavior tests for the widget update notifications (20260626164532):
-- silent refresh bypasses the toggle, the alert respects it, and the alert copy
-- is localized per recipient device.
--
-- Fixed ids (author < recipient by uuid order) keep each assertion able to
-- reference the seeded rows without psql variables.

BEGIN;
SELECT plan(11);

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

-- 4) Alert enqueues one row per recipient device.
SELECT is(
  internal.enqueue_widget_update_alert(
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-0000000000a1',
    gen_random_uuid(), gen_random_uuid()
  ),
  2,
  'alert enqueues one row per recipient device'
);

-- 5) Title is the author's display name.
SELECT is(
  (SELECT string_agg(DISTINCT title, ',') FROM internal.notification_outbox
   WHERE recipient_user_id = '00000000-0000-0000-0000-0000000000a2' AND apns_push_type = 'alert'),
  'Oda',
  'alert title is the author display name'
);

-- 6-7) Body is localized to each device's own locale.
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

-- 8) A dead token (invalid_token) fails its row immediately, not after retries.
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

-- 9) A transient failure leaves the row retryable (failed_at stays null).
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

-- 10) Silent refresh ignores the toggle (still enqueues for both devices).
SELECT is(
  internal.enqueue_notification_for_user(
    '00000000-0000-0000-0000-0000000000a2', 'widget_updated',
    jsonb_build_object('type', 'widget_updated', 'canvas_id', 'x'),
    'silent-test', 'private', 'background', 'widget', now()
  ),
  2,
  'silent refresh bypasses the disabled toggle'
);

-- 11) Alert respects the toggle (enqueues nothing when off).
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
