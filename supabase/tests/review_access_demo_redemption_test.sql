BEGIN;
SELECT plan(14);

-- Fixed identities so assertions can reference them across statements.
-- 1111 = demo partner, 2222 = reviewer, 3333/4444 = an unrelated real couple,
-- 5555 = a second reviewer who tries an already-consumed code.
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'demo-partner@demo.invalid'),
  ('22222222-2222-2222-2222-222222222222', 'reviewer@demo.invalid'),
  ('33333333-3333-3333-3333-333333333333', 'real-a@demo.invalid'),
  ('44444444-4444-4444-4444-444444444444', 'real-b@demo.invalid'),
  ('55555555-5555-5555-5555-555555555555', 'reviewer-2@demo.invalid');

CREATE TEMPORARY TABLE t_ids (k text PRIMARY KEY, v uuid);

-- Register the demo partner and issue a code, then redeem it.
SELECT internal.register_review_demo_partner(1::smallint, '11111111-1111-1111-1111-111111111111', 'Alex');
INSERT INTO t_ids VALUES ('code', internal.issue_review_access_code('ABC123', '11111111-1111-1111-1111-111111111111'));
INSERT INTO t_ids VALUES ('couple', internal.redeem_review_access(
  (SELECT v FROM t_ids WHERE k = 'code'),
  '22222222-2222-2222-2222-222222222222'
));

-- Seeded relationship shape.
SELECT is(
  (SELECT count(*)::int FROM public.couple_members
   WHERE couple_id = (SELECT v FROM t_ids WHERE k = 'couple') AND status = 'active'),
  2,
  'redeem seeds two active couple members'
);

SELECT is(
  (SELECT count(*)::int FROM public.streak_states
   WHERE couple_id = (SELECT v FROM t_ids WHERE k = 'couple')
     AND current_count = 0 AND restorable_count = 12 AND restore_deadline > now()),
  1,
  'redeem seeds a broken, restorable streak with a live window'
);

SELECT is(
  (SELECT count(*)::int FROM public.latest_partner_locations
   WHERE couple_id = (SELECT v FROM t_ids WHERE k = 'couple')
     AND user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'redeem seeds the partner location'
);

SELECT is(
  (SELECT count(*)::int FROM public.location_sharing_preferences
   WHERE couple_id = (SELECT v FROM t_ids WHERE k = 'couple')
     AND user_id = '11111111-1111-1111-1111-111111111111' AND is_enabled),
  1,
  'redeem enables partner location sharing'
);

SELECT is(
  (SELECT count(*)::int FROM internal.review_access_sessions
   WHERE code_id = (SELECT v FROM t_ids WHERE k = 'code')
     AND user_id = '22222222-2222-2222-2222-222222222222'
     AND couple_id = (SELECT v FROM t_ids WHERE k = 'couple')),
  1,
  'redeem records a review-access session'
);

SELECT is(
  (SELECT redemption_count FROM internal.review_access_codes
   WHERE id = (SELECT v FROM t_ids WHERE k = 'code')),
  1,
  'redeem consumes exactly one redemption'
);

-- Idempotent replay: same reviewer + code returns the same couple and does not
-- create a second couple or bump the counter. The code was issued with the
-- default max_redemptions = 1, so it is already at its ceiling here -- this also
-- guards that replay is checked BEFORE the ceiling (a reviewer is never locked
-- out of their own couple by an exhausted code).
SELECT is(
  internal.redeem_review_access(
    (SELECT v FROM t_ids WHERE k = 'code'),
    '22222222-2222-2222-2222-222222222222'
  ),
  (SELECT v FROM t_ids WHERE k = 'couple'),
  'redeem is idempotent for the same reviewer even at the redemption ceiling'
);

SELECT is(
  (SELECT redemption_count FROM internal.review_access_codes
   WHERE id = (SELECT v FROM t_ids WHERE k = 'code')),
  1,
  'idempotent replay does not consume another redemption'
);

-- A different reviewer is rejected once the code is consumed: the ceiling still
-- blocks a genuinely new redemption (it just no longer blocks replay above).
SELECT throws_ok(
  $$ SELECT internal.redeem_review_access(
       (SELECT v FROM t_ids WHERE k = 'code'),
       '55555555-5555-5555-5555-555555555555'
     ) $$,
  '22023',
  NULL,
  'a consumed code rejects a new reviewer'
);

-- Dispatch lookup.
SELECT is(
  (internal.find_active_review_access_code('ABC123')).id,
  (SELECT v FROM t_ids WHERE k = 'code'),
  'find_active_review_access_code matches the issued code'
);

SELECT ok(
  (internal.find_active_review_access_code('ZZZZZZ')).id IS NULL,
  'an unknown code is not treated as a review code (falls through to invites)'
);

-- Seed an unrelated real couple that reset must not touch.
INSERT INTO t_ids VALUES ('real_couple', extensions.gen_random_uuid());
INSERT INTO public.couples (id, pair_id, status, started_on, created_by_user_id)
VALUES (
  (SELECT v FROM t_ids WHERE k = 'real_couple'),
  internal.get_or_create_relationship_pair(
    '33333333-3333-3333-3333-333333333333',
    '44444444-4444-4444-4444-444444444444'
  ),
  'active', current_date, '33333333-3333-3333-3333-333333333333'
);
INSERT INTO public.couple_members (couple_id, user_id, role, status) VALUES
  ((SELECT v FROM t_ids WHERE k = 'real_couple'), '33333333-3333-3333-3333-333333333333', 'creator', 'active'),
  ((SELECT v FROM t_ids WHERE k = 'real_couple'), '44444444-4444-4444-4444-444444444444', 'partner', 'active');

-- Revoking a code makes it unredeemable.
SELECT internal.revoke_review_access_codes();
SELECT throws_ok(
  $$ SELECT internal.redeem_review_access(
       (SELECT v FROM t_ids WHERE k = 'code'),
       '22222222-2222-2222-2222-222222222222'
     ) $$,
  '22023',
  NULL,
  'a revoked code cannot be redeemed'
);

-- Reset clears the demo couple but leaves the real couple intact.
SELECT internal.reset_review_demo();

SELECT is(
  (SELECT count(*)::int FROM public.couples
   WHERE id = (SELECT v FROM t_ids WHERE k = 'couple')),
  0,
  'reset deletes the demo couple'
);

SELECT is(
  (SELECT count(*)::int FROM public.couples
   WHERE id = (SELECT v FROM t_ids WHERE k = 'real_couple')),
  1,
  'reset is scoped to demo partners and leaves real couples untouched'
);

SELECT * FROM finish();
ROLLBACK;
