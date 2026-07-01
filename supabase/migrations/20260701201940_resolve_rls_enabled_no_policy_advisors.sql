-- Supabase's RLS/no-policy advisor flags tables with RLS enabled and zero
-- policies, even when ordinary client roles have no direct table grants.
-- Keep the existing RPC/read-model access model unchanged by adding only
-- service-role policies. These policies document that trusted backend jobs may
-- use the tables without granting `anon` or `authenticated` direct access.

do $$
declare
  target_table record;
  policy_name text;
begin
  for target_table in
    select *
    from (
      values
        ('internal', 'app_account_tokens'),
        ('internal', 'app_runtime_secrets'),
        ('internal', 'client_operations'),
        ('internal', 'entitlement_grants'),
        ('internal', 'moderation_actions'),
        ('internal', 'notification_outbox'),
        ('internal', 'pair_safety_warning_flags'),
        ('internal', 'pairing_invite_attempts'),
        ('internal', 'pairing_invite_secrets'),
        ('internal', 'privacy_request_events'),
        ('internal', 'report_snapshot_assets'),
        ('internal', 'report_snapshots'),
        ('internal', 'review_access_attempts'),
        ('internal', 'review_access_codes'),
        ('internal', 'review_access_sessions'),
        ('internal', 'review_demo_partners'),
        ('internal', 'storekit_notification_events'),
        ('internal', 'storekit_payloads'),
        ('internal', 'storekit_transactions'),
        ('internal', 'streak_restorations'),
        ('internal', 'widget_push_outbox'),
        ('public', 'conversation_threads'),
        ('public', 'couple_activity_events'),
        ('public', 'couple_days'),
        ('public', 'couple_members'),
        ('public', 'couples'),
        ('public', 'daily_answer_media'),
        ('public', 'daily_answer_partner_choice'),
        ('public', 'daily_answer_text'),
        ('public', 'daily_challenges'),
        ('public', 'daily_question_answers'),
        ('public', 'daily_question_instances'),
        ('public', 'daily_question_shuffles'),
        ('public', 'daily_question_threads'),
        ('public', 'latest_partner_locations'),
        ('public', 'location_sharing_preferences'),
        ('public', 'media_assets'),
        ('public', 'memories'),
        ('public', 'memory_media'),
        ('public', 'memory_notes'),
        ('public', 'memory_threads'),
        ('public', 'question_answer_kinds'),
        ('public', 'question_collections'),
        ('public', 'question_version_localizations'),
        ('public', 'question_versions'),
        ('public', 'questions'),
        ('public', 'relationship_blocks'),
        ('public', 'relationship_pairs'),
        ('public', 'streak_states'),
        ('public', 'thread_message_media'),
        ('public', 'thread_messages'),
        ('public', 'widget_canvases'),
        ('public', 'widget_drawing_revisions')
    ) as listed_tables(schema_name, table_name)
  loop
    policy_name := target_table.table_name || '_service_role_all';

    execute format(
      'drop policy if exists %I on %I.%I',
      policy_name,
      target_table.schema_name,
      target_table.table_name
    );

    execute format(
      'create policy %I on %I.%I for all to service_role using (true) with check (true)',
      policy_name,
      target_table.schema_name,
      target_table.table_name
    );
  end loop;
end;
$$;
