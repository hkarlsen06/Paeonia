BEGIN;
SELECT plan(18);

INSERT INTO auth.users (id, email)
VALUES
  ('70000000-0000-0000-0000-000000000001', 'started-on-a@test.local'),
  ('70000000-0000-0000-0000-000000000002', 'started-on-b@test.local'),
  ('70000000-0000-0000-0000-000000000003', 'started-on-outsider@test.local');

INSERT INTO public.profiles (
  user_id,
  display_name,
  time_zone_id,
  time_zone_updated_at,
  onboarding_completed_at
)
VALUES
  (
    '70000000-0000-0000-0000-000000000001',
    'A',
    'Pacific/Kiritimati',
    now(),
    now()
  ),
  (
    '70000000-0000-0000-0000-000000000002',
    'B',
    'America/Los_Angeles',
    now(),
    now()
  ),
  (
    '70000000-0000-0000-0000-000000000003',
    'C',
    'Not/A_Time_Zone',
    now(),
    now()
  )
ON CONFLICT (user_id) DO UPDATE
SET
  display_name = excluded.display_name,
  time_zone_id = excluded.time_zone_id,
  time_zone_updated_at = excluded.time_zone_updated_at,
  onboarding_completed_at = excluded.onboarding_completed_at;

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id)
VALUES (
  '71000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000002'
);

INSERT INTO public.couples (id, pair_id, started_on, created_by_user_id, status)
VALUES (
  '72000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000001',
  null,
  '70000000-0000-0000-0000-000000000001',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, role, status)
VALUES
  (
    '72000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    'creator',
    'active'
  ),
  (
    '72000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000002',
    'partner',
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
  '73000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001',
  'lifetime',
  'active',
  'user',
  'relationship-started-on-test'
);

SELECT is(
  internal.user_local_date(
    '70000000-0000-0000-0000-000000000001',
    '2026-01-01 12:30:00+00'::timestamptz
  ),
  '2026-01-02'::date,
  'relationship date validation uses the authenticated profile timezone across UTC midnight'
);

SELECT is(
  internal.user_local_date(
    '70000000-0000-0000-0000-000000000003',
    '2026-01-01 23:30:00+00'::timestamptz
  ),
  '2026-01-01'::date,
  'an invalid or missing profile timezone safely falls back to UTC'
);

SELECT is(
  (
    SELECT is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couples'
      AND column_name = 'started_on'
  ),
  'YES',
  'couples.started_on is nullable'
);

SELECT ok(
  (
    SELECT p.prosecdef
      AND coalesce(p.proconfig @> ARRAY['search_path=pg_catalog'], false)
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'set_couple_started_on'
  ),
  'set_couple_started_on is security definer with a fixed search path'
);

SELECT ok(
  pg_get_functiondef(
    'public.accept_pairing_invite(text,uuid,uuid,bigint,timestamptz,date)'::regprocedure
  ) LIKE '%find_active_review_access_code%'
  AND pg_get_functiondef(
    'public.accept_pairing_invite(text,uuid,uuid,bigint,timestamptz,date)'::regprocedure
  ) LIKE '%redeem_review_access%',
  'nullable invite acceptance preserves App Review demo-code dispatch'
);

SELECT ok(
  pg_get_function_arguments(
    'public.accept_pairing_invite(text,uuid,uuid,bigint,timestamptz,date)'::regprocedure
  ) LIKE '%p_started_on date DEFAULT NULL::date%',
  'ordinary invite acceptance defaults the relationship date to null'
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '70000000-0000-0000-0000-000000000001',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"70000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true
  );
end;
$$;

SELECT is(
  public.set_couple_started_on(
    internal.user_local_date('70000000-0000-0000-0000-000000000001', now()),
    '74000000-0000-0000-0000-000000000001',
    '75000000-0000-0000-0000-000000000001',
    1,
    now()
  ),
  internal.user_local_date('70000000-0000-0000-0000-000000000001', now()),
  'the first entitled partner can set their local today'
);

SELECT is(
  (SELECT started_on FROM public.couples WHERE id = '72000000-0000-0000-0000-000000000001'),
  internal.user_local_date('70000000-0000-0000-0000-000000000001', now()),
  'the chosen date is stored on the couple'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.relationship_sync_events
    WHERE couple_id = '72000000-0000-0000-0000-000000000001'
      AND event_kind = 'relationship_updated'
      AND reason = 'relationship_start_date_changed'
  ),
  2,
  'a relationship date change creates one refresh event per partner'
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '70000000-0000-0000-0000-000000000002',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"70000000-0000-0000-0000-000000000002","role":"authenticated"}',
    true
  );
end;
$$;

SELECT is(
  public.set_couple_started_on(
    '2020-02-29'::date,
    '74000000-0000-0000-0000-000000000002',
    '76000000-0000-0000-0000-000000000001',
    1,
    now()
  ),
  '2020-02-29'::date,
  'the other partner covered by the couple entitlement can edit the date'
);

SELECT is(
  (SELECT started_on FROM public.couples WHERE id = '72000000-0000-0000-0000-000000000001'),
  '2020-02-29'::date,
  'the second partner edit is stored'
);

SELECT is(
  public.set_couple_started_on(
    '2021-01-01'::date,
    '74000000-0000-0000-0000-000000000005',
    '76000000-0000-0000-0000-000000000001',
    3,
    now()
  ),
  '2021-01-01'::date,
  'a newer queued edit is accepted'
);

SELECT is(
  public.set_couple_started_on(
    '2019-01-01'::date,
    '74000000-0000-0000-0000-000000000006',
    '76000000-0000-0000-0000-000000000001',
    2,
    now() - interval '1 minute'
  ),
  '2021-01-01'::date,
  'a delayed lower-sequence retry returns the newer stored date'
);

SELECT is(
  (SELECT started_on FROM public.couples WHERE id = '72000000-0000-0000-0000-000000000001'),
  '2021-01-01'::date,
  'a delayed retry cannot overwrite a newer edit from the same client'
);

SELECT throws_ok(
  $$
    SELECT public.set_couple_started_on(
      internal.user_local_date('70000000-0000-0000-0000-000000000002', now()) + 1,
      '74000000-0000-0000-0000-000000000003',
      '76000000-0000-0000-0000-000000000001',
      4,
      now()
    )
  $$,
  '23514',
  NULL,
  'a date after the authenticated user local today is rejected'
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '70000000-0000-0000-0000-000000000003',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"70000000-0000-0000-0000-000000000003","role":"authenticated"}',
    true
  );
end;
$$;

SELECT throws_ok(
  $$
    SELECT public.set_couple_started_on(
      '2020-01-01'::date,
      '74000000-0000-0000-0000-000000000004',
      '77000000-0000-0000-0000-000000000001',
      1,
      now()
    )
  $$,
  '42501',
  NULL,
  'a user outside an active entitled couple cannot change a relationship date'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.set_couple_started_on(date,uuid,uuid,bigint,timestamptz)',
    'execute'
  )
  AND NOT has_function_privilege(
    'anon',
    'public.set_couple_started_on(date,uuid,uuid,bigint,timestamptz)',
    'execute'
  ),
  'only authenticated client users can call the relationship date wrapper'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.relationship_sync_events
    WHERE couple_id = '72000000-0000-0000-0000-000000000001'
      AND event_kind = 'relationship_updated'
  ),
  6,
  'each non-superseded edit fans out to both partner sync streams'
);

SELECT * FROM finish();
ROLLBACK;
