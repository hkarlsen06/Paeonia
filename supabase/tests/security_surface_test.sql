BEGIN;
SELECT plan(19);

SELECT ok(
  NOT has_schema_privilege('anon', 'internal', 'usage'),
  'anon has no internal schema usage'
);

SELECT ok(
  NOT has_schema_privilege('authenticated', 'internal', 'usage'),
  'authenticated has no internal schema usage'
);

SELECT ok(
  has_schema_privilege('service_role', 'internal', 'usage'),
  'service_role keeps internal schema usage'
);

SELECT ok(
  NOT has_schema_privilege('anon', 'storage_private', 'usage'),
  'anon has no storage_private schema usage'
);

SELECT ok(
  has_schema_privilege('authenticated', 'storage_private', 'usage'),
  'authenticated can use storage policy helper schema'
);

SELECT is(
  (
    SELECT coalesce(string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text), '')
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'internal'
      AND has_function_privilege('authenticated', p.oid, 'execute')
  ),
  '',
  'authenticated cannot execute internal functions directly'
);

SELECT is(
  (
    SELECT coalesce(string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text), '')
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'internal'
      AND has_function_privilege('anon', p.oid, 'execute')
  ),
  '',
  'anon cannot execute internal functions directly'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'p')
      AND n.nspname IN ('public', 'internal')
      AND NOT c.relrowsecurity
  ),
  0,
  'all public and internal tables have RLS enabled'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'v', 'm', 'p')
      AND n.nspname IN ('public', 'internal')
      AND (
        has_table_privilege('anon', c.oid, 'select')
        OR has_table_privilege('anon', c.oid, 'insert')
        OR has_table_privilege('anon', c.oid, 'update')
        OR has_table_privilege('anon', c.oid, 'delete')
      )
  ),
  0,
  'anon has no direct public/internal table privileges'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'user_entitlements'
      AND has_table_privilege('authenticated', c.oid, 'select')
  ),
  0,
  'authenticated cannot directly select user_entitlements'
);

SELECT ok(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND has_function_privilege('authenticated', p.oid, 'execute')
  ) >= 40,
  'authenticated can execute public RPC wrappers'
);

SELECT is(
  (
    SELECT coalesce(string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text), '')
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND has_function_privilege('authenticated', p.oid, 'execute')
      AND pg_get_functiondef(p.oid) LIKE '%internal.%'
      AND NOT p.prosecdef
  ),
  '',
  'authenticated public RPC wrappers that call internal helpers are security definer'
);

SELECT is(
  (
    SELECT coalesce(string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text), '')
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) LIKE '%internal.%'
      AND NOT p.prosecdef
      AND (
        has_function_privilege('anon', p.oid, 'execute')
        OR has_function_privilege('authenticated', p.oid, 'execute')
        OR NOT has_function_privilege('service_role', p.oid, 'execute')
        OR NOT coalesce(p.proconfig @> ARRAY['search_path=pg_catalog'], false)
      )
  ),
  '',
  'security invoker public wrappers that call internal helpers are service-role only and pin search_path'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND NOT coalesce(p.proconfig @> ARRAY['search_path=pg_catalog'], false)
  ),
  0,
  'public RPC wrappers pin search_path'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname LIKE 'paeonia%'
      AND (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%internal.%'
  ),
  0,
  'storage policies do not call internal helpers directly'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM storage.buckets
    WHERE id IN ('profile-photos', 'couple-media', 'widget-drawings', 'report-snapshots')
      AND public = false
  ),
  4,
  'private storage buckets exist'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.questions
  ),
  12,
  'initial question seed has 12 questions'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.question_version_localizations
    WHERE locale = 'en'
  ),
  12,
  'initial question seed has English localizations'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.question_version_localizations
    WHERE locale = 'nb'
  ),
  12,
  'initial question seed has Norwegian Bokmal localizations'
);

SELECT * FROM finish();
ROLLBACK;
