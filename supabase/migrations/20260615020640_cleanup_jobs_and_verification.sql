alter table internal.report_snapshot_assets
add column updated_at timestamptz not null default now();

create trigger set_report_snapshot_assets_updated_at
before update on internal.report_snapshot_assets
for each row
execute function internal.set_updated_at();

alter table internal.storekit_transactions
add column reconciliation_claimed_at timestamptz,
add column reconciliation_attempts integer not null default 0,
add column last_reconciliation_error text,
add constraint storekit_transactions_reconciliation_attempts_check
  check (reconciliation_attempts >= 0),
add constraint storekit_transactions_last_reconciliation_error_check
  check (last_reconciliation_error is null or char_length(last_reconciliation_error) <= 4000);

create index pairing_invites_status_expires_at_cleanup_idx
on public.pairing_invites (status, expires_at);

create index review_access_codes_status_expires_at_cleanup_idx
on internal.review_access_codes (status, expires_at);

create index entitlement_grants_status_expires_at_cleanup_idx
on internal.entitlement_grants (status, expires_at);

create index storekit_transactions_reconciliation_claim_idx
on internal.storekit_transactions (
  status,
  expires_at,
  last_reconciled_at,
  reconciliation_claimed_at
);

create index report_snapshot_assets_storage_retry_idx
on internal.report_snapshot_assets (
  storage_delete_status,
  storage_delete_attempts,
  updated_at
)
where delete_after is not null and copy_status = 'copied';

create index content_reports_pair_id_fk_idx
on public.content_reports (pair_id)
where pair_id is not null;

create index conversation_threads_created_by_user_id_fk_idx
on public.conversation_threads (created_by_user_id)
where created_by_user_id is not null;

create index conversation_threads_moderated_by_fk_idx
on public.conversation_threads (moderated_by)
where moderated_by is not null;

create index conversation_threads_moderation_report_id_fk_idx
on public.conversation_threads (moderation_report_id)
where moderation_report_id is not null;

create index couple_activity_events_couple_day_id_fk_idx
on public.couple_activity_events (couple_day_id)
where couple_day_id is not null;

create index daily_answer_partner_choice_selected_user_id_fk_idx
on public.daily_answer_partner_choice (selected_user_id)
where selected_user_id is not null;

create index daily_challenges_user_id_fk_idx
on public.daily_challenges (user_id)
where user_id is not null;

create index daily_question_answers_moderation_report_id_fk_idx
on public.daily_question_answers (moderation_report_id)
where moderation_report_id is not null;

create index daily_question_instances_question_version_id_fk_idx
on public.daily_question_instances (question_version_id)
where question_version_id is not null;

create index daily_question_shuffles_couple_id_fk_idx
on public.daily_question_shuffles (couple_id)
where couple_id is not null;

create index daily_question_shuffles_question_id_fk_idx
on public.daily_question_shuffles (question_id)
where question_id is not null;

create index daily_question_shuffles_skipped_instance_id_fk_idx
on public.daily_question_shuffles (skipped_instance_id)
where skipped_instance_id is not null;

create index entitlement_grants_product_id_fk_idx
on internal.entitlement_grants (product_id)
where product_id is not null;

create index moderation_actions_reviewer_user_id_fk_idx
on internal.moderation_actions (reviewer_user_id)
where reviewer_user_id is not null;

create index notification_outbox_target_device_id_fk_idx
on internal.notification_outbox (target_device_id)
where target_device_id is not null;

create index pair_safety_warning_flags_source_report_id_fk_idx
on internal.pair_safety_warning_flags (source_report_id)
where source_report_id is not null;

create index pairing_invite_attempts_matched_invite_id_fk_idx
on internal.pairing_invite_attempts (matched_invite_id)
where matched_invite_id is not null;

create index report_snapshot_assets_source_media_asset_id_fk_idx
on internal.report_snapshot_assets (source_media_asset_id)
where source_media_asset_id is not null;

create index review_access_attempts_matched_code_id_fk_idx
on internal.review_access_attempts (matched_code_id)
where matched_code_id is not null;

create index review_access_sessions_couple_id_fk_idx
on internal.review_access_sessions (couple_id)
where couple_id is not null;

create index review_access_sessions_entitlement_grant_id_fk_idx
on internal.review_access_sessions (entitlement_grant_id)
where entitlement_grant_id is not null;

create index storekit_notification_events_raw_payload_id_fk_idx
on internal.storekit_notification_events (raw_payload_id)
where raw_payload_id is not null;

create index storekit_transactions_raw_payload_id_fk_idx
on internal.storekit_transactions (raw_payload_id)
where raw_payload_id is not null;

create index location_sharing_preferences_user_id_fk_idx
on public.location_sharing_preferences (user_id)
where user_id is not null;

create index media_assets_moderation_report_id_fk_idx
on public.media_assets (moderation_report_id)
where moderation_report_id is not null;

create index memories_created_by_user_id_fk_idx
on public.memories (created_by_user_id)
where created_by_user_id is not null;

create index memories_last_edited_by_user_id_fk_idx
on public.memories (last_edited_by_user_id)
where last_edited_by_user_id is not null;

create index memories_moderated_by_fk_idx
on public.memories (moderated_by)
where moderated_by is not null;

create index memories_moderation_report_id_fk_idx
on public.memories (moderation_report_id)
where moderation_report_id is not null;

create index memory_media_moderated_by_fk_idx
on public.memory_media (moderated_by)
where moderated_by is not null;

create index memory_media_moderation_report_id_fk_idx
on public.memory_media (moderation_report_id)
where moderation_report_id is not null;

create index memory_notes_moderated_by_fk_idx
on public.memory_notes (moderated_by)
where moderated_by is not null;

create index memory_notes_moderation_report_id_fk_idx
on public.memory_notes (moderation_report_id)
where moderation_report_id is not null;

create index pairing_invites_couple_id_fk_idx
on public.pairing_invites (couple_id)
where couple_id is not null;

create index profiles_moderation_report_id_fk_idx
on public.profiles (moderation_report_id)
where moderation_report_id is not null;

create index question_collections_created_by_user_id_fk_idx
on public.question_collections (created_by_user_id)
where created_by_user_id is not null;

create index questions_created_by_user_id_fk_idx
on public.questions (created_by_user_id)
where created_by_user_id is not null;

create index relationship_blocks_source_report_id_fk_idx
on public.relationship_blocks (source_report_id)
where source_report_id is not null;

create index streak_states_last_qualified_couple_day_id_fk_idx
on public.streak_states (last_qualified_couple_day_id)
where last_qualified_couple_day_id is not null;

create index thread_messages_moderated_by_fk_idx
on public.thread_messages (moderated_by)
where moderated_by is not null;

create index thread_messages_moderation_report_id_fk_idx
on public.thread_messages (moderation_report_id)
where moderation_report_id is not null;

create index widget_canvases_active_revision_id_fk_idx
on public.widget_canvases (active_revision_id)
where active_revision_id is not null;

create index widget_drawing_revisions_moderated_by_fk_idx
on public.widget_drawing_revisions (moderated_by)
where moderated_by is not null;

create index widget_drawing_revisions_moderation_report_id_fk_idx
on public.widget_drawing_revisions (moderation_report_id)
where moderation_report_id is not null;

create or replace function internal.cleanup_expired_relationship_content(
  p_now timestamptz default now(),
  p_limit integer default 25
)
returns table (
  couple_id uuid,
  queued_media_count integer,
  sync_event_count integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  cleanup_couple public.couples%rowtype;
  member_row record;
begin
  if p_now is null then
    raise exception 'cleanup timestamp is required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'relationship cleanup limit is out of range'
      using errcode = '23514';
  end if;

  for cleanup_couple in
    select *
    from public.couples couple
    where couple.status = 'ended'
      and couple.delete_after is not null
      and couple.delete_after <= p_now
    order by couple.delete_after, couple.id
    for update skip locked
    limit p_limit
  loop
    update public.daily_question_answers answer
    set
      deleted_at = coalesce(answer.deleted_at, p_now),
      moderation_status = case
        when answer.moderation_status = 'visible' then 'hidden'
        else answer.moderation_status
      end
    from public.daily_question_instances instance
    join public.couple_days couple_day
      on couple_day.id = instance.couple_day_id
    where answer.instance_id = instance.id
      and couple_day.couple_id = cleanup_couple.id;

    update public.conversation_threads thread
    set
      deleted_at = coalesce(thread.deleted_at, p_now),
      moderation_status = case
        when thread.moderation_status = 'visible' then 'hidden'
        else thread.moderation_status
      end
    where thread.couple_id = cleanup_couple.id;

    update public.thread_messages message
    set
      deleted_at = coalesce(message.deleted_at, p_now),
      moderation_status = case
        when message.moderation_status = 'visible' then 'hidden'
        else message.moderation_status
      end
    from public.conversation_threads thread
    where message.thread_id = thread.id
      and thread.couple_id = cleanup_couple.id;

    update public.memories memory
    set
      deleted_at = coalesce(memory.deleted_at, p_now),
      moderation_status = case
        when memory.moderation_status = 'visible' then 'hidden'
        else memory.moderation_status
      end
    where memory.couple_id = cleanup_couple.id;

    update public.memory_notes note
    set
      deleted_at = coalesce(note.deleted_at, p_now),
      moderation_status = case
        when note.moderation_status = 'visible' then 'hidden'
        else note.moderation_status
      end
    from public.memories memory
    where note.memory_id = memory.id
      and memory.couple_id = cleanup_couple.id;

    update public.memory_media memory_media
    set
      deleted_at = coalesce(memory_media.deleted_at, p_now),
      moderation_status = case
        when memory_media.moderation_status = 'visible' then 'hidden'
        else memory_media.moderation_status
      end
    from public.memories memory
    where memory_media.memory_id = memory.id
      and memory.couple_id = cleanup_couple.id;

    update public.widget_canvases canvas
    set deleted_at = coalesce(canvas.deleted_at, p_now)
    where canvas.couple_id = cleanup_couple.id;

    update public.widget_drawing_revisions revision
    set
      deleted_at = coalesce(revision.deleted_at, p_now),
      moderation_status = case
        when revision.moderation_status = 'visible' then 'hidden'
        else revision.moderation_status
      end
    from public.widget_canvases canvas
    where revision.canvas_id = canvas.id
      and canvas.couple_id = cleanup_couple.id;

    update public.media_assets asset
    set
      deleted_at = coalesce(asset.deleted_at, p_now),
      storage_delete_status = case
        when asset.storage_delete_status = 'deleted' then 'deleted'
        when asset.storage_delete_status in ('pending', 'retrying') then asset.storage_delete_status
        else 'pending'
      end,
      last_storage_delete_error = null
    where asset.couple_id = cleanup_couple.id
      and asset.bucket <> 'report-snapshots'
      and asset.storage_delete_status <> 'deleted';

    get diagnostics queued_media_count = row_count;

    delete from public.latest_partner_locations latest
    where latest.couple_id = cleanup_couple.id;

    update public.couples
    set status = 'deleted'
    where id = cleanup_couple.id
      and status = 'ended';

    sync_event_count = 0;

    for member_row in
      select member.user_id, member.status
      from public.couple_members member
      where member.couple_id = cleanup_couple.id
    loop
      perform internal.create_relationship_sync_event(
        member_row.user_id,
        cleanup_couple.id,
        null,
        'content_purged',
        'relationship_cleanup',
        'deleted',
        member_row.status,
        cleanup_couple.ended_at,
        cleanup_couple.delete_after,
        '{"relationship_content":"purge","location":"purge","widget_cache":"purge","pending_uploads":"purge"}'::jsonb
      );

      sync_event_count = sync_event_count + 1;
    end loop;

    couple_id = cleanup_couple.id;
    return next;
  end loop;
end;
$$;

create or replace function internal.purge_deleted_relationship_content(
  p_now timestamptz default now(),
  p_limit integer default 25
)
returns table (
  couple_id uuid,
  media_rows_deleted integer,
  content_rows_deleted integer,
  sync_event_count integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  cleanup_couple public.couples%rowtype;
  member_row record;
  changed_rows integer;
begin
  if p_now is null then
    raise exception 'purge timestamp is required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'relationship purge limit is out of range'
      using errcode = '23514';
  end if;

  for cleanup_couple in
    select *
    from public.couples couple
    where couple.status = 'deleted'
      and couple.delete_after is not null
      and couple.delete_after <= p_now
      and not exists (
        select 1
        from public.media_assets asset
        where asset.couple_id = couple.id
          and asset.bucket <> 'report-snapshots'
          and asset.storage_delete_status <> 'deleted'
      )
      and not exists (
        select 1
        from public.relationship_sync_events event
        where event.couple_id = couple.id
          and event.event_kind = 'content_purged'
          and event.reason = 'relationship_hard_purge'
      )
    order by couple.delete_after, couple.id
    for update skip locked
    limit p_limit
  loop
    media_rows_deleted = 0;
    content_rows_deleted = 0;
    sync_event_count = 0;

    update public.content_report_targets target
    set
      daily_answer_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.daily_question_answers answer
    join public.daily_question_instances instance
      on instance.id = answer.instance_id
    join public.couple_days couple_day
      on couple_day.id = instance.couple_day_id
    where target.daily_answer_id = answer.id
      and couple_day.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      memory_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.memories memory
    where target.memory_id = memory.id
      and memory.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      memory_note_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.memory_notes note
    join public.memories memory
      on memory.id = note.memory_id
    where target.memory_note_id = note.id
      and memory.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      memory_media_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.memory_media memory_media
    join public.memories memory
      on memory.id = memory_media.memory_id
    where target.memory_media_id = memory_media.id
      and memory.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      message_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.thread_messages message
    join public.conversation_threads thread
      on thread.id = message.thread_id
    where target.message_id = message.id
      and thread.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      message_media_message_id = null,
      message_media_asset_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.thread_message_media message_media
    join public.thread_messages message
      on message.id = message_media.message_id
    join public.conversation_threads thread
      on thread.id = message.thread_id
    where target.message_media_message_id = message_media.message_id
      and target.message_media_asset_id = message_media.media_asset_id
      and thread.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      widget_drawing_revision_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.widget_drawing_revisions revision
    join public.widget_canvases canvas
      on canvas.id = revision.canvas_id
    where target.widget_drawing_revision_id = revision.id
      and canvas.couple_id = cleanup_couple.id;

    update public.content_report_targets target
    set
      media_asset_id = null,
      live_target_deleted_at = coalesce(target.live_target_deleted_at, p_now)
    from public.media_assets asset
    where target.media_asset_id = asset.id
      and asset.couple_id = cleanup_couple.id;

    delete from public.thread_message_media message_media
    using public.thread_messages message,
      public.conversation_threads thread
    where message_media.message_id = message.id
      and message.thread_id = thread.id
      and thread.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.daily_answer_media answer_media
    using public.daily_question_answers answer,
      public.daily_question_instances instance,
      public.couple_days couple_day
    where answer_media.answer_id = answer.id
      and answer.instance_id = instance.id
      and instance.couple_day_id = couple_day.id
      and couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.daily_answer_partner_choice partner_choice
    using public.daily_question_answers answer,
      public.daily_question_instances instance,
      public.couple_days couple_day
    where partner_choice.answer_id = answer.id
      and answer.instance_id = instance.id
      and instance.couple_day_id = couple_day.id
      and couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.daily_answer_text answer_text
    using public.daily_question_answers answer,
      public.daily_question_instances instance,
      public.couple_days couple_day
    where answer_text.answer_id = answer.id
      and answer.instance_id = instance.id
      and instance.couple_day_id = couple_day.id
      and couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.daily_question_threads daily_thread
    using public.daily_question_instances instance,
      public.couple_days couple_day
    where daily_thread.instance_id = instance.id
      and instance.couple_day_id = couple_day.id
      and couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.memory_threads memory_thread
    using public.memories memory
    where memory_thread.memory_id = memory.id
      and memory.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.thread_messages message
    using public.conversation_threads thread
    where message.thread_id = thread.id
      and thread.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.conversation_threads thread
    where thread.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.memory_media memory_media
    using public.memories memory
    where memory_media.memory_id = memory.id
      and memory.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.memory_notes note
    using public.memories memory
    where note.memory_id = memory.id
      and memory.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.memories memory
    where memory.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    update public.widget_canvases canvas
    set active_revision_id = null
    where canvas.couple_id = cleanup_couple.id
      and canvas.active_revision_id is not null;

    loop
      delete from public.widget_drawing_revisions revision
      using public.widget_canvases canvas
      where revision.canvas_id = canvas.id
        and canvas.couple_id = cleanup_couple.id
        and not exists (
          select 1
          from public.widget_drawing_revisions child
          where child.parent_revision_id = revision.id
        );

      get diagnostics changed_rows = row_count;
      exit when changed_rows = 0;
      content_rows_deleted = content_rows_deleted + changed_rows;
    end loop;

    if exists (
      select 1
      from public.widget_drawing_revisions revision
      join public.widget_canvases canvas
        on canvas.id = revision.canvas_id
      where canvas.couple_id = cleanup_couple.id
    ) then
      raise exception 'widget revisions could not be purged because parent links remain'
        using errcode = '23503';
    end if;

    delete from public.widget_canvases canvas
    where canvas.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.couple_activity_events event
    where event.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.streak_states streak
    where streak.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.daily_question_shuffles shuffle
    where shuffle.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.daily_question_answers answer
    using public.daily_question_instances instance,
      public.couple_days couple_day
    where answer.instance_id = instance.id
      and instance.couple_day_id = couple_day.id
      and couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    loop
      delete from public.daily_question_instances instance
      using public.couple_days couple_day
      where instance.couple_day_id = couple_day.id
        and couple_day.couple_id = cleanup_couple.id
        and not exists (
          select 1
          from public.daily_question_instances previous_instance
          where previous_instance.replaced_by_instance_id = instance.id
        );

      get diagnostics changed_rows = row_count;
      exit when changed_rows = 0;
      content_rows_deleted = content_rows_deleted + changed_rows;
    end loop;

    if exists (
      select 1
      from public.daily_question_instances instance
      join public.couple_days couple_day
        on couple_day.id = instance.couple_day_id
      where couple_day.couple_id = cleanup_couple.id
    ) then
      raise exception 'daily question instances could not be purged because replacement links remain'
        using errcode = '23503';
    end if;

    delete from public.daily_challenges challenge
    using public.couple_days couple_day
    where challenge.couple_day_id = couple_day.id
      and couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.couple_days couple_day
    where couple_day.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.location_sharing_preferences preference
    where preference.couple_id = cleanup_couple.id;
    get diagnostics changed_rows = row_count;
    content_rows_deleted = content_rows_deleted + changed_rows;

    delete from public.media_assets asset
    where asset.couple_id = cleanup_couple.id
      and asset.bucket <> 'report-snapshots'
      and asset.storage_delete_status = 'deleted';
    get diagnostics media_rows_deleted = row_count;

    for member_row in
      select member.user_id, member.status
      from public.couple_members member
      where member.couple_id = cleanup_couple.id
    loop
      perform internal.create_relationship_sync_event(
        member_row.user_id,
        cleanup_couple.id,
        null,
        'content_purged',
        'relationship_hard_purge',
        'deleted',
        member_row.status,
        cleanup_couple.ended_at,
        cleanup_couple.delete_after,
        '{"relationship_content":"purge","location":"purge","widget_cache":"purge","pending_uploads":"purge"}'::jsonb
      );

      sync_event_count = sync_event_count + 1;
    end loop;

    couple_id = cleanup_couple.id;
    return next;
  end loop;
end;
$$;

create or replace function internal.claim_expired_pending_uploads(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  storage_delete_attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null then
    raise exception 'cleanup timestamp is required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'pending upload claim limit is out of range'
      using errcode = '23514';
  end if;

  return query
  with picked as (
    select asset.id
    from public.media_assets asset
    where asset.upload_status = 'pending'
      and asset.upload_expires_at <= p_now
      and asset.storage_delete_status <> 'deleted'
    order by asset.upload_expires_at, asset.id
    for update skip locked
    limit p_limit
  ),
  claimed as (
    update public.media_assets asset
    set
      upload_status = 'expired',
      deleted_at = coalesce(asset.deleted_at, p_now),
      storage_delete_status = 'retrying',
      storage_delete_attempts = asset.storage_delete_attempts + 1,
      last_storage_delete_error = null
    from picked
    where asset.id = picked.id
    returning asset.id, asset.bucket, asset.storage_path, asset.storage_delete_attempts
  )
  select claimed.id, claimed.bucket, claimed.storage_path, claimed.storage_delete_attempts
  from claimed;
end;
$$;

create or replace function internal.claim_media_storage_deletes(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_retry_after interval default interval '15 minutes',
  p_max_attempts integer default 5
)
returns table (
  media_asset_id uuid,
  bucket text,
  storage_path text,
  storage_delete_attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null or p_retry_after is null then
    raise exception 'storage delete claim timestamp and retry window are required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'storage delete claim limit is out of range'
      using errcode = '23514';
  end if;

  if p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 25 then
    raise exception 'storage delete max attempts is out of range'
      using errcode = '23514';
  end if;

  return query
  with picked as (
    select asset.id
    from public.media_assets asset
    where asset.storage_delete_status in ('pending', 'retrying')
      and asset.storage_delete_attempts < p_max_attempts
      and (
        asset.storage_delete_status <> 'retrying'
        or asset.updated_at <= p_now - p_retry_after
      )
    order by asset.updated_at, asset.storage_delete_attempts, asset.id
    for update skip locked
    limit p_limit
  ),
  claimed as (
    update public.media_assets asset
    set
      storage_delete_status = 'retrying',
      storage_delete_attempts = asset.storage_delete_attempts + 1,
      last_storage_delete_error = null
    from picked
    where asset.id = picked.id
    returning asset.id, asset.bucket, asset.storage_path, asset.storage_delete_attempts
  )
  select claimed.id, claimed.bucket, claimed.storage_path, claimed.storage_delete_attempts
  from claimed;
end;
$$;

create or replace function internal.mark_media_storage_deleted(p_media_asset_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update public.media_assets asset
  set
    deleted_at = coalesce(asset.deleted_at, now()),
    storage_delete_status = 'deleted',
    storage_deleted_at = coalesce(asset.storage_deleted_at, now()),
    last_storage_delete_error = null
  where asset.id = p_media_asset_id
    and asset.storage_delete_status in ('pending', 'retrying', 'failed')
    and (
      asset.deleted_at is not null
      or asset.upload_status = 'expired'
    );

  get diagnostics changed_rows = row_count;

  if changed_rows = 1 then
    return true;
  end if;

  return exists (
    select 1
    from public.media_assets asset
    where asset.id = p_media_asset_id
      and asset.storage_delete_status = 'deleted'
  );
end;
$$;

create or replace function internal.mark_media_storage_delete_failed(
  p_media_asset_id uuid,
  p_error text,
  p_terminal boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update public.media_assets asset
  set
    storage_delete_status = case when coalesce(p_terminal, false) then 'failed' else 'retrying' end,
    last_storage_delete_error = left(nullif(btrim(coalesce(p_error, '')), ''), 4000)
  where asset.id = p_media_asset_id
    and asset.storage_delete_status in ('pending', 'retrying', 'failed')
    and (
      asset.deleted_at is not null
      or asset.upload_status = 'expired'
    );

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.claim_report_snapshot_storage_deletes(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_retry_after interval default interval '15 minutes',
  p_max_attempts integer default 5
)
returns table (
  snapshot_asset_id uuid,
  report_id uuid,
  bucket text,
  storage_path text,
  storage_delete_attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null or p_retry_after is null then
    raise exception 'report snapshot claim timestamp and retry window are required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'report snapshot claim limit is out of range'
      using errcode = '23514';
  end if;

  if p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 25 then
    raise exception 'report snapshot max attempts is out of range'
      using errcode = '23514';
  end if;

  return query
  with picked as (
    select asset.id
    from internal.report_snapshot_assets asset
    where asset.delete_after is not null
      and asset.delete_after <= p_now
      and asset.copy_status = 'copied'
      and asset.storage_delete_status in ('none', 'pending', 'retrying')
      and asset.storage_delete_attempts < p_max_attempts
      and (
        asset.storage_delete_status <> 'retrying'
        or asset.updated_at <= p_now - p_retry_after
      )
    order by asset.delete_after, asset.updated_at, asset.id
    for update skip locked
    limit p_limit
  ),
  claimed as (
    update internal.report_snapshot_assets asset
    set
      storage_delete_status = 'retrying',
      storage_delete_attempts = asset.storage_delete_attempts + 1,
      last_storage_delete_error = null
    from picked
    where asset.id = picked.id
    returning
      asset.id,
      asset.report_id,
      asset.bucket,
      asset.storage_path,
      asset.storage_delete_attempts
  )
  select
    claimed.id,
    claimed.report_id,
    claimed.bucket,
    claimed.storage_path,
    claimed.storage_delete_attempts
  from claimed;
end;
$$;

create or replace function internal.mark_report_snapshot_storage_deleted(p_snapshot_asset_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.report_snapshot_assets asset
  set
    storage_delete_status = 'deleted',
    storage_deleted_at = coalesce(asset.storage_deleted_at, now()),
    last_storage_delete_error = null
  where asset.id = p_snapshot_asset_id
    and asset.delete_after is not null
    and asset.delete_after <= now()
    and asset.copy_status = 'copied'
    and asset.storage_delete_status in ('pending', 'retrying', 'failed');

  get diagnostics changed_rows = row_count;

  if changed_rows = 1 then
    return true;
  end if;

  return exists (
    select 1
    from internal.report_snapshot_assets asset
    where asset.id = p_snapshot_asset_id
      and asset.storage_delete_status = 'deleted'
  );
end;
$$;

create or replace function internal.mark_report_snapshot_storage_delete_failed(
  p_snapshot_asset_id uuid,
  p_error text,
  p_terminal boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.report_snapshot_assets asset
  set
    storage_delete_status = case when coalesce(p_terminal, false) then 'failed' else 'retrying' end,
    last_storage_delete_error = left(nullif(btrim(coalesce(p_error, '')), ''), 4000)
  where asset.id = p_snapshot_asset_id
    and asset.delete_after is not null
    and asset.copy_status = 'copied'
    and asset.storage_delete_status in ('pending', 'retrying', 'failed');

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.purge_deleted_report_snapshots(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns table (
  snapshot_asset_rows_deleted integer,
  snapshot_rows_deleted integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null then
    raise exception 'report snapshot purge timestamp is required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'report snapshot purge limit is out of range'
      using errcode = '23514';
  end if;

  with deleted_assets as (
    select asset.id
    from internal.report_snapshot_assets asset
    where asset.delete_after is not null
      and asset.delete_after <= p_now
      and (
        (
          asset.copy_status = 'copied'
          and asset.storage_delete_status = 'deleted'
        )
        or asset.copy_status in ('pending_copy', 'copy_failed')
      )
    order by asset.delete_after, asset.id
    limit p_limit
  )
  delete from internal.report_snapshot_assets asset
  using deleted_assets
  where asset.id = deleted_assets.id;

  get diagnostics snapshot_asset_rows_deleted = row_count;

  with deletable_snapshots as (
    select snapshot.report_id
    from internal.report_snapshots snapshot
    where snapshot.delete_after is not null
      and snapshot.delete_after <= p_now
      and not exists (
        select 1
        from internal.report_snapshot_assets asset
        where asset.report_id = snapshot.report_id
      )
    order by snapshot.delete_after, snapshot.report_id
    limit p_limit
  )
  delete from internal.report_snapshots snapshot
  using deletable_snapshots
  where snapshot.report_id = deletable_snapshots.report_id;

  get diagnostics snapshot_rows_deleted = row_count;

  return next;
end;
$$;

create or replace function internal.cleanup_attempt_logs(
  p_now timestamptz default now(),
  p_pairing_retention interval default interval '30 days',
  p_review_retention interval default interval '30 days',
  p_limit integer default 1000
)
returns table (
  pairing_attempts_deleted integer,
  review_attempts_deleted integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null
    or p_pairing_retention is null
    or p_review_retention is null then
    raise exception 'attempt cleanup timestamp and retention windows are required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'attempt cleanup limit is out of range'
      using errcode = '23514';
  end if;

  with expired_pairing_attempts as (
    select attempt.id
    from internal.pairing_invite_attempts attempt
    where attempt.attempted_at < p_now - p_pairing_retention
    order by attempt.attempted_at, attempt.id
    limit p_limit
  )
  delete from internal.pairing_invite_attempts attempt
  using expired_pairing_attempts
  where attempt.id = expired_pairing_attempts.id;

  get diagnostics pairing_attempts_deleted = row_count;

  with expired_review_attempts as (
    select attempt.id
    from internal.review_access_attempts attempt
    where attempt.attempted_at < p_now - p_review_retention
    order by attempt.attempted_at, attempt.id
    limit p_limit
  )
  delete from internal.review_access_attempts attempt
  using expired_review_attempts
  where attempt.id = expired_review_attempts.id;

  get diagnostics review_attempts_deleted = row_count;

  return next;
end;
$$;

create or replace function internal.expire_stale_invites_and_review_codes(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns table (
  pairing_invites_expired integer,
  review_codes_expired integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null then
    raise exception 'expiry timestamp is required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'expiry limit is out of range'
      using errcode = '23514';
  end if;

  with expired_invites as (
    select invite.id
    from public.pairing_invites invite
    where invite.status = 'pending'
      and invite.expires_at <= p_now
    order by invite.expires_at, invite.id
    for update skip locked
    limit p_limit
  )
  update public.pairing_invites invite
  set status = 'expired'
  from expired_invites
  where invite.id = expired_invites.id;

  get diagnostics pairing_invites_expired = row_count;

  with expired_codes as (
    select code.id
    from internal.review_access_codes code
    where code.status = 'active'
      and code.expires_at is not null
      and code.expires_at <= p_now
    order by code.expires_at, code.id
    for update skip locked
    limit p_limit
  )
  update internal.review_access_codes code
  set status = 'expired'
  from expired_codes
  where code.id = expired_codes.id;

  get diagnostics review_codes_expired = row_count;

  return next;
end;
$$;

create or replace function internal.expire_stale_entitlements(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns table (
  storekit_transactions_expired integer,
  entitlement_grants_expired integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_row record;
  member_row record;
  affected_user_ids uuid[] := '{}'::uuid[];
begin
  if p_now is null then
    raise exception 'entitlement expiry timestamp is required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'entitlement expiry limit is out of range'
      using errcode = '23514';
  end if;

  with expired_transactions as (
    select tx.id
    from internal.storekit_transactions tx
    where tx.status in ('active', 'grace', 'billing_retry')
      and tx.expires_at is not null
      and tx.expires_at <= p_now
    order by tx.expires_at, tx.id
    for update skip locked
    limit p_limit
  ),
  updated_transactions as (
    update internal.storekit_transactions tx
    set status = 'expired'
    from expired_transactions
    where tx.id = expired_transactions.id
    returning tx.user_id
  )
  select
    count(*)::integer,
    coalesce(array_agg(distinct updated_transactions.user_id), '{}'::uuid[])
  into storekit_transactions_expired, affected_user_ids
  from updated_transactions;

  with expired_grants as (
    select grant_row.id
    from internal.entitlement_grants grant_row
    where grant_row.status = 'active'
      and grant_row.expires_at is not null
      and grant_row.expires_at <= p_now
    order by grant_row.expires_at, grant_row.id
    for update skip locked
    limit p_limit
  ),
  updated_grants as (
    update internal.entitlement_grants grant_row
    set status = 'expired'
    from expired_grants
    where grant_row.id = expired_grants.id
    returning grant_row.user_id
  )
  select
    count(*)::integer,
    affected_user_ids || coalesce(array_agg(distinct updated_grants.user_id), '{}'::uuid[])
  into entitlement_grants_expired, affected_user_ids
  from updated_grants;

  for couple_row in
    select distinct couple.id, couple.status, couple.ended_at, couple.delete_after
    from unnest(affected_user_ids) as affected_user(user_id)
    join public.couple_members affected_member
      on affected_member.user_id = affected_user.user_id
    join public.couples couple
      on couple.id = affected_member.couple_id
    where affected_member.status = 'active'
      and couple.status = 'active'
      and not exists (
        select 1
        from public.couple_members member
        where member.couple_id = couple.id
          and member.status = 'active'
          and internal.user_has_direct_entitlement(member.user_id)
      )
  loop
    for member_row in
      select member.user_id, member.status
      from public.couple_members member
      where member.couple_id = couple_row.id
    loop
      perform internal.create_relationship_sync_event(
        member_row.user_id,
        couple_row.id,
        null,
        'entitlement_lost',
        'entitlement_expired',
        couple_row.status,
        member_row.status,
        couple_row.ended_at,
        couple_row.delete_after,
        '{"entitlement":"refresh","relationship_content":"hide","media_cache":"purge","widget_cache":"purge"}'::jsonb
      );
    end loop;
  end loop;

  return next;
end;
$$;

create or replace function internal.claim_storekit_transactions_for_reconciliation(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_reconcile_after interval default interval '6 hours',
  p_retry_after interval default interval '15 minutes',
  p_max_attempts integer default 10
)
returns table (
  transaction_id uuid,
  user_id uuid,
  product_id uuid,
  environment text,
  app_account_token uuid,
  original_transaction_id text,
  storekit_transaction_id text,
  status text,
  expires_at timestamptz,
  reconciliation_attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null
    or p_reconcile_after is null
    or p_retry_after is null then
    raise exception 'StoreKit reconciliation timestamps are required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'StoreKit reconciliation claim limit is out of range'
      using errcode = '23514';
  end if;

  if p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 100 then
    raise exception 'StoreKit reconciliation max attempts is out of range'
      using errcode = '23514';
  end if;

  return query
  with picked as (
    select tx.id
    from internal.storekit_transactions tx
    where tx.status in ('active', 'grace', 'billing_retry')
      and tx.reconciliation_attempts < p_max_attempts
      and (
        tx.last_reconciled_at is null
        or tx.last_reconciled_at <= p_now - p_reconcile_after
        or tx.expires_at <= p_now + interval '24 hours'
      )
      and (
        tx.reconciliation_claimed_at is null
        or tx.reconciliation_claimed_at <= p_now - p_retry_after
      )
    order by
      tx.expires_at nulls first,
      tx.last_reconciled_at nulls first,
      tx.id
    for update skip locked
    limit p_limit
  ),
  claimed as (
    update internal.storekit_transactions tx
    set
      reconciliation_claimed_at = p_now,
      reconciliation_attempts = tx.reconciliation_attempts + 1,
      last_reconciliation_error = null
    from picked
    where tx.id = picked.id
    returning tx.*
  )
  select
    claimed.id,
    claimed.user_id,
    claimed.product_id,
    claimed.environment,
    claimed.app_account_token,
    claimed.original_transaction_id,
    claimed.transaction_id,
    claimed.status,
    claimed.expires_at,
    claimed.reconciliation_attempts
  from claimed;
end;
$$;

create or replace function internal.mark_storekit_transaction_reconciled(p_transaction_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.storekit_transactions tx
  set
    last_reconciled_at = now(),
    reconciliation_claimed_at = null,
    reconciliation_attempts = 0,
    last_reconciliation_error = null
  where tx.id = p_transaction_id;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.mark_storekit_transaction_reconciliation_failed(
  p_transaction_id uuid,
  p_error text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.storekit_transactions tx
  set
    reconciliation_claimed_at = now(),
    last_reconciliation_error = left(nullif(btrim(coalesce(p_error, '')), ''), 4000)
  where tx.id = p_transaction_id;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

revoke all on function internal.cleanup_expired_relationship_content(timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.cleanup_expired_relationship_content(timestamptz, integer) to service_role;

revoke all on function internal.purge_deleted_relationship_content(timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.purge_deleted_relationship_content(timestamptz, integer) to service_role;

revoke all on function internal.claim_expired_pending_uploads(timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.claim_expired_pending_uploads(timestamptz, integer) to service_role;

revoke all on function internal.claim_media_storage_deletes(timestamptz, integer, interval, integer) from public, anon, authenticated;
grant execute on function internal.claim_media_storage_deletes(timestamptz, integer, interval, integer) to service_role;

revoke all on function internal.mark_media_storage_deleted(uuid) from public, anon, authenticated;
grant execute on function internal.mark_media_storage_deleted(uuid) to service_role;

revoke all on function internal.mark_media_storage_delete_failed(uuid, text, boolean) from public, anon, authenticated;
grant execute on function internal.mark_media_storage_delete_failed(uuid, text, boolean) to service_role;

revoke all on function internal.claim_report_snapshot_storage_deletes(timestamptz, integer, interval, integer) from public, anon, authenticated;
grant execute on function internal.claim_report_snapshot_storage_deletes(timestamptz, integer, interval, integer) to service_role;

revoke all on function internal.mark_report_snapshot_storage_deleted(uuid) from public, anon, authenticated;
grant execute on function internal.mark_report_snapshot_storage_deleted(uuid) to service_role;

revoke all on function internal.mark_report_snapshot_storage_delete_failed(uuid, text, boolean) from public, anon, authenticated;
grant execute on function internal.mark_report_snapshot_storage_delete_failed(uuid, text, boolean) to service_role;

revoke all on function internal.purge_deleted_report_snapshots(timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.purge_deleted_report_snapshots(timestamptz, integer) to service_role;

revoke all on function internal.cleanup_attempt_logs(timestamptz, interval, interval, integer) from public, anon, authenticated;
grant execute on function internal.cleanup_attempt_logs(timestamptz, interval, interval, integer) to service_role;

revoke all on function internal.expire_stale_invites_and_review_codes(timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.expire_stale_invites_and_review_codes(timestamptz, integer) to service_role;

revoke all on function internal.expire_stale_entitlements(timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.expire_stale_entitlements(timestamptz, integer) to service_role;

revoke all on function internal.claim_storekit_transactions_for_reconciliation(timestamptz, integer, interval, interval, integer) from public, anon, authenticated;
grant execute on function internal.claim_storekit_transactions_for_reconciliation(timestamptz, integer, interval, interval, integer) to service_role;

revoke all on function internal.mark_storekit_transaction_reconciled(uuid) from public, anon, authenticated;
grant execute on function internal.mark_storekit_transaction_reconciled(uuid) to service_role;

revoke all on function internal.mark_storekit_transaction_reconciliation_failed(uuid, text) from public, anon, authenticated;
grant execute on function internal.mark_storekit_transaction_reconciliation_failed(uuid, text) to service_role;
