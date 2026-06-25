-- Deleting a row from public.couples is an admin/development escape hatch for
-- removing a relationship. Relationship-owned data should follow that delete
-- through the FK graph instead of forcing a fragile hand-written purge order.

do $$
declare
  fk record;
begin
  for fk in
    select *
    from (
      values
        ('public', 'content_reports', 'content_reports_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'conversation_threads', 'conversation_threads_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'couple_activity_events', 'couple_activity_events_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'couple_days', 'couple_days_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'couple_members', 'couple_members_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'daily_question_shuffles', 'daily_question_shuffles_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('internal', 'review_access_sessions', 'review_access_sessions_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'latest_partner_locations', 'latest_partner_locations_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'location_sharing_preferences', 'location_sharing_preferences_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'media_assets', 'media_assets_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'memories', 'memories_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'pairing_invites', 'pairing_invites_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'question_collections', 'question_collections_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'relationship_sync_events', 'relationship_sync_events_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'streak_states', 'streak_states_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),
        ('public', 'widget_canvases', 'widget_canvases_couple_id_fkey', 'couple_id', 'public', 'couples', 'id'),

        ('internal', 'moderation_actions', 'moderation_actions_report_id_fkey', 'report_id', 'public', 'content_reports', 'id'),
        ('internal', 'report_snapshot_assets', 'report_snapshot_assets_report_id_fkey', 'report_id', 'public', 'content_reports', 'id'),
        ('internal', 'report_snapshots', 'report_snapshots_report_id_fkey', 'report_id', 'public', 'content_reports', 'id'),
        ('public', 'content_report_targets', 'content_report_targets_report_id_fkey', 'report_id', 'public', 'content_reports', 'id'),

        ('public', 'daily_question_threads', 'daily_question_threads_thread_id_fkey', 'thread_id', 'public', 'conversation_threads', 'id'),
        ('public', 'memory_threads', 'memory_threads_thread_id_fkey', 'thread_id', 'public', 'conversation_threads', 'id'),
        ('public', 'thread_messages', 'thread_messages_thread_id_fkey', 'thread_id', 'public', 'conversation_threads', 'id'),

        ('public', 'couple_activity_events', 'couple_activity_events_couple_day_id_fkey', 'couple_day_id', 'public', 'couple_days', 'id'),
        ('public', 'daily_challenges', 'daily_challenges_couple_day_id_fkey', 'couple_day_id', 'public', 'couple_days', 'id'),
        ('public', 'daily_question_instances', 'daily_question_instances_couple_day_id_fkey', 'couple_day_id', 'public', 'couple_days', 'id'),
        ('public', 'daily_question_shuffles', 'daily_question_shuffles_couple_day_id_fkey', 'couple_day_id', 'public', 'couple_days', 'id'),

        ('public', 'daily_question_answers', 'daily_question_answers_instance_id_fkey', 'instance_id', 'public', 'daily_question_instances', 'id'),
        ('public', 'daily_question_shuffles', 'daily_question_shuffles_replacement_instance_id_fkey', 'replacement_instance_id', 'public', 'daily_question_instances', 'id'),
        ('public', 'daily_question_shuffles', 'daily_question_shuffles_skipped_instance_id_fkey', 'skipped_instance_id', 'public', 'daily_question_instances', 'id'),
        ('public', 'daily_question_threads', 'daily_question_threads_instance_id_fkey', 'instance_id', 'public', 'daily_question_instances', 'id'),

        ('public', 'daily_answer_media', 'daily_answer_media_answer_id_fkey', 'answer_id', 'public', 'daily_question_answers', 'id'),
        ('public', 'daily_answer_partner_choice', 'daily_answer_partner_choice_answer_id_fkey', 'answer_id', 'public', 'daily_question_answers', 'id'),
        ('public', 'daily_answer_text', 'daily_answer_text_answer_id_fkey', 'answer_id', 'public', 'daily_question_answers', 'id'),

        ('public', 'daily_answer_media', 'daily_answer_media_media_asset_id_fkey', 'media_asset_id', 'public', 'media_assets', 'id'),
        ('public', 'memory_media', 'memory_media_media_asset_id_fkey', 'media_asset_id', 'public', 'media_assets', 'id'),
        ('public', 'thread_message_media', 'thread_message_media_media_asset_id_fkey', 'media_asset_id', 'public', 'media_assets', 'id'),
        ('public', 'widget_drawing_revisions', 'widget_drawing_revisions_payload_media_asset_id_fkey', 'payload_media_asset_id', 'public', 'media_assets', 'id'),

        ('public', 'memory_media', 'memory_media_memory_id_fkey', 'memory_id', 'public', 'memories', 'id'),
        ('public', 'memory_notes', 'memory_notes_memory_id_fkey', 'memory_id', 'public', 'memories', 'id'),
        ('public', 'memory_threads', 'memory_threads_memory_id_fkey', 'memory_id', 'public', 'memories', 'id'),

        ('public', 'questions', 'questions_collection_id_fkey', 'collection_id', 'public', 'question_collections', 'id'),
        ('public', 'question_versions', 'question_versions_question_id_fkey', 'question_id', 'public', 'questions', 'id'),
        ('public', 'daily_question_shuffles', 'daily_question_shuffles_question_id_fkey', 'question_id', 'public', 'questions', 'id'),
        ('public', 'daily_question_instances', 'daily_question_instances_question_version_id_fkey', 'question_version_id', 'public', 'question_versions', 'id'),
        ('public', 'question_answer_kinds', 'question_answer_kinds_question_version_id_fkey', 'question_version_id', 'public', 'question_versions', 'id'),
        ('public', 'question_version_localizations', 'question_version_localizations_question_version_id_fkey', 'question_version_id', 'public', 'question_versions', 'id'),

        ('public', 'thread_message_media', 'thread_message_media_message_id_fkey', 'message_id', 'public', 'thread_messages', 'id'),

        ('public', 'widget_drawing_revisions', 'widget_drawing_revisions_canvas_id_fkey', 'canvas_id', 'public', 'widget_canvases', 'id')
    ) as f(
      child_schema,
      child_table,
      constraint_name,
      child_columns,
      parent_schema,
      parent_table,
      parent_columns
    )
  loop
    execute format(
      'alter table %I.%I drop constraint if exists %I',
      fk.child_schema,
      fk.child_table,
      fk.constraint_name
    );

    execute format(
      'alter table %I.%I add constraint %I foreign key (%s) references %I.%I (%s) on delete cascade',
      fk.child_schema,
      fk.child_table,
      fk.constraint_name,
      fk.child_columns,
      fk.parent_schema,
      fk.parent_table,
      fk.parent_columns
    );
  end loop;
end;
$$;

do $$
declare
  fk record;
begin
  for fk in
    select *
    from (
      values
        ('internal', 'entitlement_grants', 'entitlement_grants_source_review_session_id_fkey', 'source_review_session_id', 'internal', 'review_access_sessions', 'id', 'deferrable initially deferred'),
        ('public', 'daily_question_instances', 'daily_question_instances_replaced_by_instance_id_fkey', 'replaced_by_instance_id', 'public', 'daily_question_instances', 'id', ''),
        ('public', 'streak_states', 'streak_states_last_qualified_couple_day_id_fkey', 'last_qualified_couple_day_id', 'public', 'couple_days', 'id', ''),
        ('public', 'widget_canvases', 'widget_canvases_active_revision_id_fkey', 'active_revision_id', 'public', 'widget_drawing_revisions', 'id', ''),
        ('public', 'widget_drawing_revisions', 'widget_drawing_revisions_parent_revision_id_fkey', 'parent_revision_id', 'public', 'widget_drawing_revisions', 'id', '')
    ) as f(
      child_schema,
      child_table,
      constraint_name,
      child_columns,
      parent_schema,
      parent_table,
      parent_columns,
      deferrability
    )
  loop
    execute format(
      'alter table %I.%I drop constraint if exists %I',
      fk.child_schema,
      fk.child_table,
      fk.constraint_name
    );

    execute format(
      'alter table %I.%I add constraint %I foreign key (%s) references %I.%I (%s) on delete set null %s',
      fk.child_schema,
      fk.child_table,
      fk.constraint_name,
      fk.child_columns,
      fk.parent_schema,
      fk.parent_table,
      fk.parent_columns,
      fk.deferrability
    );
  end loop;
end;
$$;
