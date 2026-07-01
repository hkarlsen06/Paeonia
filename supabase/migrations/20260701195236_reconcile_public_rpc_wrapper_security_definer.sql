-- Reconcile repo migrations with production: every authenticated-callable
-- public.* wrapper that reaches internal.* must be security definer, because
-- authenticated has no USAGE on the internal schema (see AGENTS.md).
--
-- Production already runs all of these as security definer (fixed out-of-band),
-- but the migration chain's final state left ~25 of them security invoker, so
-- any replayed environment (supabase db reset, preview branch, recovery) came
-- up with `permission denied for schema internal` (42501) on these RPCs.
--
-- Statements were generated from production via
-- pg_get_function_identity_arguments over prosecdef wrappers, so applying this
-- to production is a state no-op. Search paths are already pinned to
-- pg_catalog by each function's original create statement.
--
-- The service-role-only drain wrappers (claim_notification_batch,
-- claim_widget_push_batch, mark_notification_result, mark_widget_push_result,
-- mark_streak_restore_refunded, record_verified_streak_restore) are
-- intentionally security invoker and are NOT listed here.

alter function public.accept_pairing_invite(p_invite_code text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone, p_started_on date) security definer;
alter function public.attach_memory_media(p_memory_id uuid, p_media_asset_ids uuid[], p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.block_relationship(p_blocked_user_id uuid) security definer;
alter function public.complete_review_access_session(p_review_session_id uuid) security definer;
alter function public.create_daily_question_thread_with_message(p_instance_id uuid, p_body text, p_media_asset_ids uuid[], p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.create_memory(p_memory_id uuid, p_title text, p_memory_date date, p_note_body text, p_media_asset_ids uuid[], p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.create_memory_thread_with_message(p_memory_id uuid, p_body text, p_media_asset_ids uuid[], p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.create_pairing_invite(p_invite_code text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone, p_expires_at timestamp with time zone) security definer;
alter function public.create_pending_media_upload(p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone, p_reserved_parent_kind text, p_reserved_parent_id uuid, p_upload_purpose text, p_media_type text, p_file_extension text, p_couple_id uuid, p_upload_expires_at timestamp with time zone, p_path_context jsonb) security definer;
alter function public.disable_user_device(p_device_id uuid) security definer;
alter function public.finalize_media_upload(p_media_asset_id uuid, p_reserved_by_client_operation_id uuid, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone, p_bucket text, p_storage_path text, p_reserved_parent_kind text, p_reserved_parent_id uuid, p_upload_purpose text, p_media_type text, p_mime_type text, p_byte_size bigint, p_sha256_hex text, p_width integer, p_height integer, p_duration_ms integer) security definer;
alter function public.get_access_snapshot() security definer;
alter function public.get_active_question_catalog(p_locale text) security definer;
alter function public.get_conversation_threads() security definer;
alter function public.get_couple_streak() security definer;
alter function public.get_current_relationship_state() security definer;
alter function public.get_daily_answer_details(p_couple_day_id uuid) security definer;
alter function public.get_daily_answer_details_for_couple_days(p_couple_day_ids uuid[]) security definer;
alter function public.get_daily_answer_history_details() security definer;
alter function public.get_daily_answer_reveal_state(p_couple_day_id uuid) security definer;
alter function public.get_daily_questions_history() security definer;
alter function public.get_media_signed_url(p_media_asset_id uuid, p_expires_in_seconds integer) security definer;
alter function public.get_memories(p_updated_after timestamp with time zone, p_cursor_memory_id uuid, p_limit integer) security definer;
alter function public.get_my_couple_entitlement() security definer;
alter function public.get_my_entitlement() security definer;
alter function public.get_or_create_app_account_token(p_user_id uuid) security definer;
alter function public.get_or_create_widget_canvas(p_couple_id uuid) security definer;
alter function public.get_partner_location_visibility(p_couple_id uuid) security definer;
alter function public.get_question_answer_history(p_question_id uuid) security definer;
alter function public.get_thread_messages(p_thread_id uuid) security definer;
alter function public.get_today_daily_challenge_snapshot() security definer;
alter function public.get_today_daily_questions() security definer;
alter function public.get_widget_canvas(p_couple_id uuid) security definer;
alter function public.get_widget_drawing_revisions(p_canvas_id uuid, p_updated_after timestamp with time zone, p_limit integer, p_updated_after_revision_id uuid, p_created_before timestamp with time zone, p_created_before_revision_id uuid) security definer;
alter function public.hide_memory(p_memory_id uuid, p_expected_revision integer, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.leave_relationship(p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.mark_media_for_deletion(p_media_asset_id uuid) security definer;
alter function public.mark_relationship_ended_notice_seen(p_couple_id uuid) security definer;
alter function public.preview_pairing_invite(p_invite_code text) security definer;
alter function public.register_user_device(p_platform text, p_push_token text, p_apns_environment text, p_locale text, p_time_zone_id text, p_app_version text) security definer;
alter function public.register_widget_push_device(p_widget_kind text, p_widget_push_token text, p_apns_environment text, p_locale text, p_time_zone_id text, p_app_version text) security definer;
alter function public.remove_memory_media(p_memory_media_id uuid, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.request_account_deletion() security definer;
alter function public.revoke_pairing_invite(p_invite_id uuid) security definer;
alter function public.rotate_pairing_invite(p_current_invite_id uuid, p_invite_code text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone, p_expires_at timestamp with time zone) security definer;
alter function public.send_thread_message(p_thread_id uuid, p_body text, p_media_asset_ids uuid[], p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.shuffle_daily_question(p_slot_number smallint, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.shuffle_daily_question_snapshot(p_slot_number smallint, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.start_daily_challenge(p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.start_daily_challenge_snapshot(p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.submit_content_report(p_reason text, p_note text, p_target_kind text, p_target_id uuid, p_target_aux_id uuid, p_block_reported_user boolean, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.submit_daily_answer(p_instance_id uuid, p_payload jsonb, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.submit_leave_and_report(p_reason text, p_note text, p_target_kind text, p_target_id uuid, p_target_aux_id uuid, p_block_reported_user boolean, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.submit_widget_drawing_revision(p_canvas_id uuid, p_payload_media_asset_id uuid, p_parent_revision_id uuid, p_payload_bytes bigint, p_uncompressed_bytes bigint, p_compression text, p_stroke_count integer, p_point_count integer, p_bounds jsonb, p_sha256_hex text, p_client_decode_validated_at timestamp with time zone, p_client_renderer_version text, p_client_validation_version text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.unblock_pair(p_pair_id uuid) security definer;
alter function public.update_daily_answer_partner_choice(p_instance_id uuid, p_selected_user_id uuid, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.update_daily_answer_text(p_instance_id uuid, p_text text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.update_latest_partner_location(p_couple_id uuid, p_latitude numeric, p_longitude numeric, p_captured_at timestamp with time zone, p_source text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.update_latest_partner_location(p_couple_id uuid, p_latitude numeric, p_longitude numeric, p_accuracy_m numeric, p_captured_at timestamp with time zone, p_source text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.update_location_sharing_preference(p_couple_id uuid, p_is_enabled boolean, p_source text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.update_location_sharing_preference(p_couple_id uuid, p_is_enabled boolean, p_consent_version text, p_source text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.update_memory(p_memory_id uuid, p_expected_revision integer, p_title text, p_memory_date date, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.upsert_memory_note(p_memory_id uuid, p_expected_revision integer, p_body text, p_client_operation_id uuid, p_client_id uuid, p_client_sequence bigint, p_local_created_at timestamp with time zone) security definer;
alter function public.validate_my_pairing_invite(p_invite_id uuid, p_invite_code text) security definer;

notify pgrst, 'reload schema';
