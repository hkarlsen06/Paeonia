-- Short-lived user-owned rows should disappear with the Auth user.
alter table public.user_devices
drop constraint if exists user_devices_user_id_fkey,
add constraint user_devices_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table public.location_sharing_preferences
drop constraint if exists location_sharing_preferences_user_id_fkey,
add constraint location_sharing_preferences_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table public.latest_partner_locations
drop constraint if exists latest_partner_locations_user_id_fkey,
add constraint latest_partner_locations_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table public.daily_question_shuffles
drop constraint if exists daily_question_shuffles_user_id_fkey,
add constraint daily_question_shuffles_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table internal.notification_outbox
drop constraint if exists notification_outbox_recipient_user_id_fkey,
add constraint notification_outbox_recipient_user_id_fkey
foreign key (recipient_user_id)
references auth.users (id)
on delete cascade;

alter table internal.notification_outbox
drop constraint if exists notification_outbox_target_device_id_fkey,
add constraint notification_outbox_target_device_id_fkey
foreign key (target_device_id)
references public.user_devices (id)
on delete cascade;

-- Relationship content, reports, and request/audit records keep UUID snapshots
-- after the Auth row is deleted. Do not cascade these rows.
alter table public.privacy_requests
drop constraint if exists privacy_requests_user_id_fkey;

alter table public.content_reports
drop constraint if exists content_reports_reporter_user_id_fkey,
drop constraint if exists content_reports_reported_user_id_fkey;

alter table public.content_report_targets
drop constraint if exists content_report_targets_conduct_user_id_fkey;

alter table public.conversation_threads
drop constraint if exists conversation_threads_created_by_user_id_fkey;

alter table public.couple_activity_events
drop constraint if exists couple_activity_events_user_id_fkey;

alter table public.daily_challenges
drop constraint if exists daily_challenges_user_id_fkey;

alter table public.daily_question_instances
drop constraint if exists daily_question_instances_seeded_for_user_id_fkey;

alter table public.daily_question_answers
drop constraint if exists daily_question_answers_user_id_fkey;

alter table public.daily_answer_partner_choice
drop constraint if exists daily_answer_partner_choice_selected_user_id_fkey;

alter table public.media_assets
drop constraint if exists media_assets_owner_user_id_fkey;

alter table public.memories
drop constraint if exists memories_created_by_user_id_fkey,
drop constraint if exists memories_last_edited_by_user_id_fkey;

alter table public.memory_notes
drop constraint if exists memory_notes_user_id_fkey;

alter table public.memory_media
drop constraint if exists memory_media_owner_user_id_fkey;

alter table public.question_collections
drop constraint if exists question_collections_created_by_user_id_fkey;

alter table public.questions
drop constraint if exists questions_created_by_user_id_fkey;

alter table public.thread_messages
drop constraint if exists thread_messages_sender_user_id_fkey;

alter table public.widget_drawing_revisions
drop constraint if exists widget_drawing_revisions_author_user_id_fkey;
