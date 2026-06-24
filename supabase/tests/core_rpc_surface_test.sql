BEGIN;
SELECT plan(35);

INSERT INTO internal.app_runtime_secrets (secret_name, secret_value)
VALUES ('invite_code_pepper', 'test-pepper-value-for-pairing-invite-hashes');

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

SELECT ok(
  pg_get_functiondef('internal.request_account_deletion()'::regprocedure)
    LIKE '%#variable_conflict use_column%',
  'account deletion RPC resolves privacy request status as a table column'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname = 'record_storekit_server_notification'
      AND has_function_privilege('service_role', p.oid, 'execute')
      AND NOT has_function_privilege('authenticated', p.oid, 'execute')
      AND NOT has_function_privilege('anon', p.oid, 'execute')
  ),
  1,
  'StoreKit notification webhook RPC is service-role only'
);

SELECT is(
  octet_length(internal.hash_pairing_invite_code('ABC123')),
  32,
  'six-character pairing invite codes hash to sha256'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_constraint constraint_row
    JOIN pg_class table_row
      ON table_row.oid = constraint_row.conrelid
    JOIN pg_namespace schema_row
      ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname = 'public'
      AND table_row.relname IN ('profiles', 'notification_preferences')
      AND constraint_row.conname IN (
        'profiles_user_id_fkey',
        'notification_preferences_user_id_fkey'
      )
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%REFERENCES auth.users(id) ON DELETE CASCADE%'
  ),
  2,
  'auth user hard deletion removes automatic self-owned identity rows'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_constraint constraint_row
    JOIN pg_class table_row
      ON table_row.oid = constraint_row.conrelid
    JOIN pg_namespace schema_row
      ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname IN ('public', 'internal')
      AND constraint_row.confrelid = 'auth.users'::regclass
      AND constraint_row.confdeltype IN ('a', 'r')
  ),
  0,
  'app schemas do not block Auth user deletion with restrictive user foreign keys'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_constraint constraint_row
    JOIN pg_class table_row
      ON table_row.oid = constraint_row.conrelid
    JOIN pg_namespace schema_row
      ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname IN ('public', 'internal')
      AND constraint_row.conname IN (
        'client_operations_user_id_fkey',
        'daily_question_shuffles_user_id_fkey',
        'latest_partner_locations_user_id_fkey',
        'location_sharing_preferences_user_id_fkey',
        'notification_outbox_recipient_user_id_fkey',
        'notification_preferences_user_id_fkey',
        'profiles_user_id_fkey',
        'user_devices_user_id_fkey'
      )
      AND constraint_row.confdeltype = 'c'
  ),
  8,
  'short-lived user-owned rows cascade when an Auth user is deleted'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_constraint constraint_row
    JOIN pg_class table_row
      ON table_row.oid = constraint_row.conrelid
    JOIN pg_namespace schema_row
      ON schema_row.oid = table_row.relnamespace
    WHERE schema_row.nspname = 'internal'
      AND table_row.relname = 'notification_outbox'
      AND constraint_row.conname = 'notification_outbox_target_device_id_fkey'
      AND constraint_row.confdeltype = 'c'
  ),
  1,
  'notification outbox rows do not block deleted device cleanup'
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
    AND NOT has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update'),
  'authenticated may read profile display names but must update names through auth metadata'
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
