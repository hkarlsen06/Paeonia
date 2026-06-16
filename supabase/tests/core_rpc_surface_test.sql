BEGIN;
SELECT plan(28);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'get_my_entitlement',
        'get_my_couple_entitlement',
        'create_pairing_invite',
        'preview_pairing_invite',
        'accept_pairing_invite',
        'leave_relationship',
        'start_daily_challenge',
        'submit_daily_answer',
        'get_daily_answer_reveal_state',
        'create_pending_media_upload',
        'finalize_media_upload',
        'create_memory',
        'submit_widget_drawing_revision',
        'update_location_sharing_preference',
        'submit_content_report',
        'request_account_deletion'
      )
  ),
  16,
  'core public RPC wrappers exist'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'get_my_entitlement',
        'get_my_couple_entitlement',
        'create_pairing_invite',
        'preview_pairing_invite',
        'accept_pairing_invite',
        'leave_relationship',
        'start_daily_challenge',
        'submit_daily_answer',
        'get_daily_answer_reveal_state',
        'create_pending_media_upload',
        'finalize_media_upload',
        'create_memory',
        'submit_widget_drawing_revision',
        'update_location_sharing_preference',
        'submit_content_report',
        'request_account_deletion'
      )
      AND p.prosecdef
  ),
  16,
  'core public RPC wrappers are security definer'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'get_my_entitlement',
        'get_my_couple_entitlement',
        'create_pairing_invite',
        'preview_pairing_invite',
        'accept_pairing_invite',
        'leave_relationship',
        'start_daily_challenge',
        'submit_daily_answer',
        'get_daily_answer_reveal_state',
        'create_pending_media_upload',
        'finalize_media_upload',
        'create_memory',
        'submit_widget_drawing_revision',
        'update_location_sharing_preference',
        'submit_content_report',
        'request_account_deletion'
      )
      AND has_function_privilege('authenticated', p.oid, 'execute')
  ),
  16,
  'authenticated can execute core public RPC wrappers'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'get_my_entitlement',
        'get_my_couple_entitlement',
        'create_pairing_invite',
        'preview_pairing_invite',
        'accept_pairing_invite',
        'leave_relationship',
        'start_daily_challenge',
        'submit_daily_answer',
        'get_daily_answer_reveal_state',
        'create_pending_media_upload',
        'finalize_media_upload',
        'create_memory',
        'submit_widget_drawing_revision',
        'update_location_sharing_preference',
        'submit_content_report',
        'request_account_deletion'
      )
      AND has_function_privilege('anon', p.oid, 'execute')
  ),
  0,
  'anon cannot execute core public RPC wrappers'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname IN (
        'relationship_pairs',
        'couples',
        'couple_members',
        'daily_question_answers',
        'daily_answer_text',
        'daily_answer_media',
        'media_assets',
        'memories',
        'memory_notes',
        'widget_drawing_revisions',
        'latest_partner_locations',
        'content_reports',
        'content_report_targets'
      )
  ),
  13,
  'sensitive public tables exist'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname IN (
        'relationship_pairs',
        'couples',
        'couple_members',
        'daily_question_answers',
        'daily_answer_text',
        'daily_answer_media',
        'media_assets',
        'memories',
        'memory_notes',
        'widget_drawing_revisions',
        'latest_partner_locations',
        'content_reports',
        'content_report_targets'
      )
      AND has_table_privilege('authenticated', c.oid, 'insert')
  ),
  0,
  'authenticated cannot directly insert sensitive public tables'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname IN (
        'relationship_pairs',
        'couples',
        'couple_members',
        'daily_question_answers',
        'daily_answer_text',
        'daily_answer_media',
        'media_assets',
        'memories',
        'memory_notes',
        'widget_drawing_revisions',
        'latest_partner_locations',
        'content_reports',
        'content_report_targets'
      )
      AND has_table_privilege('authenticated', c.oid, 'update')
  ),
  0,
  'authenticated cannot directly update sensitive public tables'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname IN (
        'relationship_pairs',
        'couples',
        'couple_members',
        'daily_question_answers',
        'daily_answer_text',
        'daily_answer_media',
        'media_assets',
        'memories',
        'memory_notes',
        'widget_drawing_revisions',
        'latest_partner_locations',
        'content_reports',
        'content_report_targets'
      )
      AND has_table_privilege('authenticated', c.oid, 'delete')
  ),
  0,
  'authenticated cannot directly delete sensitive public tables'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'relationship_pairs',
        'couples',
        'couple_members',
        'daily_question_answers',
        'daily_answer_text',
        'daily_answer_media',
        'media_assets',
        'memories',
        'memory_notes',
        'widget_drawing_revisions',
        'latest_partner_locations'
      )
  ),
  0,
  'relationship-owned content has no broad direct RLS policies'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'content_reports'
      AND cmd = 'SELECT'
  ),
  1,
  'report rows have one self-read policy'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'content_report_targets'
      AND cmd = 'SELECT'
  ),
  1,
  'report targets have one self-read policy'
);

SELECT ok(
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'select')
    AND has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update'),
  'authenticated may read and update allowed own profile columns through RLS'
);

SELECT ok(
  has_column_privilege(
    'authenticated',
    'public.notification_preferences',
    'streak_reminders_enabled',
    'update'
  ),
  'authenticated may update allowed notification preference columns through RLS'
);

SELECT ok(
  has_column_privilege('authenticated', 'public.privacy_requests', 'request_kind', 'insert')
    AND has_column_privilege('authenticated', 'public.privacy_requests', 'requester_note', 'insert'),
  'authenticated may create privacy requests through column-limited RLS'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.register_user_device(text, text, text, text, text, text)',
    'execute'
  )
    AND NOT has_table_privilege('authenticated', 'public.user_devices', 'insert'),
  'authenticated registers devices through RPC instead of direct insert'
);

SELECT ok(
  has_column_privilege('authenticated', 'public.subscription_products', 'apple_product_id', 'select')
    AND has_column_privilege('authenticated', 'public.subscription_products', 'billing_period', 'select'),
  'authenticated may read active subscription products through RLS'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.question_collections', 'select'),
  'authenticated cannot directly read raw question collections'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.get_active_question_catalog(text)', 'execute'),
  'authenticated reads questions through catalog RPC'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'internal'
      AND c.relkind IN ('r', 'p')
      AND (
        has_table_privilege('authenticated', c.oid, 'select')
        OR has_table_privilege('authenticated', c.oid, 'insert')
        OR has_table_privilege('authenticated', c.oid, 'update')
        OR has_table_privilege('authenticated', c.oid, 'delete')
      )
  ),
  0,
  'authenticated has no direct internal table privileges'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'internal'
      AND c.relkind IN ('r', 'p')
      AND (
        has_table_privilege('anon', c.oid, 'select')
        OR has_table_privilege('anon', c.oid, 'insert')
        OR has_table_privilege('anon', c.oid, 'update')
        OR has_table_privilege('anon', c.oid, 'delete')
      )
  ),
  0,
  'anon has no direct internal table privileges'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'storage'
      AND c.relname = 'objects'
      AND c.relrowsecurity
  ),
  1,
  'storage objects has RLS enabled'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname IN (
        'paeonia_media_pending_upload_insert',
        'paeonia_media_visible_select'
      )
  ),
  2,
  'storage object policies are installed'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname IN (
        'paeonia_media_pending_upload_insert',
        'paeonia_media_visible_select'
      )
      AND roles = ARRAY['authenticated']::name[]
  ),
  2,
  'storage object policies are authenticated-only'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'storage_private'
      AND p.proname IN (
        'paeonia_can_upload_reserved_media_object',
        'paeonia_can_read_media_object'
      )
      AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'execute')
  ),
  2,
  'storage policy helper functions are callable and security definer'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM internal.client_operations
  ),
  0,
  'client operation ledger starts empty in local reset'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM internal.notification_outbox
  ),
  0,
  'notification outbox starts empty in local reset'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM internal.storekit_transactions
  ),
  0,
  'StoreKit transaction ledger starts empty in local reset'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.relationship_sync_events
  ),
  0,
  'relationship sync event stream starts empty in local reset'
);

SELECT * FROM finish();
ROLLBACK;
