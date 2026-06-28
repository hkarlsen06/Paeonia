-- Behavior tests for latest partner location RPC stale update handling.

BEGIN;

SELECT plan(5);

INSERT INTO auth.users (id, email)
VALUES
  ('00000000-0000-0000-0000-00000000a101', 'location-owner@test.local'),
  ('00000000-0000-0000-0000-00000000a102', 'location-partner@test.local');

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id)
VALUES (
  '00000000-0000-0000-0000-00000000b101',
  '00000000-0000-0000-0000-00000000a101',
  '00000000-0000-0000-0000-00000000a102'
);

INSERT INTO public.couples (id, pair_id, started_on, created_by_user_id, status)
VALUES (
  '00000000-0000-0000-0000-00000000c101',
  '00000000-0000-0000-0000-00000000b101',
  current_date,
  '00000000-0000-0000-0000-00000000a101',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status)
VALUES
  (
    '00000000-0000-0000-0000-00000000c101',
    '00000000-0000-0000-0000-00000000a101',
    'active'
  ),
  (
    '00000000-0000-0000-0000-00000000c101',
    '00000000-0000-0000-0000-00000000a102',
    'active'
  );

INSERT INTO internal.entitlement_grants (
  id,
  user_id,
  grant_kind,
  status,
  scope,
  granted_by
)
VALUES (
  '00000000-0000-0000-0000-00000000e101',
  '00000000-0000-0000-0000-00000000a101',
  'lifetime',
  'active',
  'user',
  'location-rpc-test'
);

INSERT INTO public.location_sharing_preferences (
  couple_id,
  user_id,
  is_enabled,
  enabled_at,
  disabled_at,
  consent_version,
  source
)
VALUES
  (
    '00000000-0000-0000-0000-00000000c101',
    '00000000-0000-0000-0000-00000000a101',
    true,
    '2026-06-28 11:00:00+00',
    null,
    'test-v1',
    'settings_toggle'
  ),
  (
    '00000000-0000-0000-0000-00000000c101',
    '00000000-0000-0000-0000-00000000a102',
    true,
    '2026-06-28 11:00:00+00',
    null,
    'test-v1',
    'settings_toggle'
  );

INSERT INTO public.latest_partner_locations (
  couple_id,
  user_id,
  latitude,
  longitude,
  accuracy_m,
  captured_at,
  received_at,
  source,
  client_operation_id,
  client_id,
  client_sequence
)
VALUES (
  '00000000-0000-0000-0000-00000000c101',
  '00000000-0000-0000-0000-00000000a101',
  59.950000,
  10.750000,
  12.50,
  '2026-06-28 12:00:00+00',
  '2026-06-28 12:00:05+00',
  'foreground_open',
  '00000000-0000-0000-0000-00000000f101',
  '00000000-0000-0000-0000-00000000d101',
  1
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-00000000a101',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-00000000a101","role":"authenticated"}',
    true
  );
end;
$$;

CREATE TEMP TABLE stale_location_result AS
SELECT *
FROM public.update_latest_partner_location(
  '00000000-0000-0000-0000-00000000c101',
  1.000000,
  2.000000,
  4.00,
  '2026-06-28 11:59:00+00',
  'foreground_open',
  '00000000-0000-0000-0000-00000000f102',
  '00000000-0000-0000-0000-00000000d101',
  2,
  '2026-06-28 11:59:01+00'
);

SELECT is(
  (SELECT count(*)::integer FROM stale_location_result),
  1,
  'stale location update returns the current latest row'
);

SELECT ok(
  (
    SELECT captured_at = '2026-06-28 12:00:00+00'::timestamptz
      AND latitude = 59.950000
      AND longitude = 10.750000
    FROM stale_location_result
  ),
  'stale location response contains the stored newer location'
);

SELECT ok(
  (
    SELECT captured_at = '2026-06-28 12:00:00+00'::timestamptz
      AND latitude = 59.950000
      AND longitude = 10.750000
    FROM public.latest_partner_locations
    WHERE couple_id = '00000000-0000-0000-0000-00000000c101'
      AND user_id = '00000000-0000-0000-0000-00000000a101'
  ),
  'stale location update does not overwrite the stored latest row'
);

SELECT is(
  (
    SELECT status
    FROM internal.client_operations
    WHERE user_id = '00000000-0000-0000-0000-00000000a101'
      AND client_operation_id = '00000000-0000-0000-0000-00000000f102'
  ),
  'succeeded',
  'stale location operation is completed for idempotency'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM internal.notification_outbox
    WHERE kind = 'location_updated'
      AND recipient_user_id = '00000000-0000-0000-0000-00000000a102'
  ),
  0,
  'stale location update does not enqueue a partner notification'
);

SELECT * FROM finish();

ROLLBACK;
