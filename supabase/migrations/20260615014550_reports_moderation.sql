create table public.content_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  reporter_user_id uuid not null references auth.users (id) on delete restrict,
  reported_user_id uuid not null references auth.users (id) on delete restrict,
  couple_id uuid not null references public.couples (id) on delete restrict,
  pair_id uuid not null references public.relationship_pairs (id) on delete restrict,
  reason text not null,
  note text,
  status text not null default 'submitted',
  block_requested boolean not null default false,
  leave_requested boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,

  constraint content_reports_distinct_users_check
    check (reporter_user_id <> reported_user_id),
  constraint content_reports_reason_check
    check (reason in ('harassment', 'abuse', 'threat', 'sexual_content', 'hate', 'privacy', 'impersonation', 'self_harm', 'spam', 'other')),
  constraint content_reports_note_check
    check (note is null or char_length(btrim(note)) <= 4000),
  constraint content_reports_status_check
    check (status in ('submitted', 'under_review', 'action_taken', 'rejected', 'closed')),
  constraint content_reports_resolved_state_check
    check (
      (status in ('submitted', 'under_review') and resolved_at is null)
      or (status in ('action_taken', 'rejected', 'closed') and resolved_at is not null)
    )
);

create trigger set_content_reports_updated_at
before update on public.content_reports
for each row
execute function internal.set_updated_at();

create table public.content_report_targets (
  report_id uuid primary key references public.content_reports (id) on delete restrict,
  target_kind text not null,
  daily_answer_id uuid references public.daily_question_answers (id) on delete set null,
  memory_id uuid references public.memories (id) on delete set null,
  memory_note_id uuid references public.memory_notes (id) on delete set null,
  memory_media_id uuid references public.memory_media (id) on delete set null,
  message_id uuid references public.thread_messages (id) on delete set null,
  message_media_message_id uuid,
  message_media_asset_id uuid,
  widget_drawing_revision_id uuid references public.widget_drawing_revisions (id) on delete set null,
  media_asset_id uuid references public.media_assets (id) on delete set null,
  profile_user_id uuid references public.profiles (user_id) on delete set null,
  conduct_user_id uuid references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  live_target_deleted_at timestamptz,

  constraint content_report_targets_message_media_fkey
    foreign key (message_media_message_id, message_media_asset_id)
    references public.thread_message_media (message_id, media_asset_id)
    on delete set null,
  constraint content_report_targets_message_media_pair_check
    check ((message_media_message_id is null) = (message_media_asset_id is null)),
  constraint content_report_targets_target_kind_check
    check (target_kind in ('daily_answer', 'memory', 'memory_note', 'memory_media', 'thread_message', 'thread_message_media', 'widget_drawing_revision', 'media_asset', 'profile', 'conduct')),
  constraint content_report_targets_live_target_check
    check (
      (
        live_target_deleted_at is null
        and num_nonnulls(
          daily_answer_id,
          memory_id,
          memory_note_id,
          memory_media_id,
          message_id,
          case when message_media_message_id is not null then message_media_message_id end,
          widget_drawing_revision_id,
          media_asset_id,
          profile_user_id,
          conduct_user_id
        ) = 1
        and (
          (target_kind = 'daily_answer' and daily_answer_id is not null)
          or (target_kind = 'memory' and memory_id is not null)
          or (target_kind = 'memory_note' and memory_note_id is not null)
          or (target_kind = 'memory_media' and memory_media_id is not null)
          or (target_kind = 'thread_message' and message_id is not null)
          or (target_kind = 'thread_message_media' and message_media_message_id is not null)
          or (target_kind = 'widget_drawing_revision' and widget_drawing_revision_id is not null)
          or (target_kind = 'media_asset' and media_asset_id is not null)
          or (target_kind = 'profile' and profile_user_id is not null)
          or (target_kind = 'conduct' and conduct_user_id is not null)
        )
      )
      or (
        live_target_deleted_at is not null
        and daily_answer_id is null
        and memory_id is null
        and memory_note_id is null
        and memory_media_id is null
        and message_id is null
        and message_media_message_id is null
        and message_media_asset_id is null
        and widget_drawing_revision_id is null
        and media_asset_id is null
        and profile_user_id is null
        and conduct_user_id is null
      )
    )
);

create table internal.report_snapshots (
  report_id uuid primary key references public.content_reports (id) on delete restrict,
  snapshot jsonb not null,
  delete_after timestamptz,
  created_at timestamptz not null default now(),

  constraint report_snapshots_snapshot_check
    check (jsonb_typeof(snapshot) = 'object' and octet_length(snapshot::text) <= 65536)
);

create table internal.report_snapshot_assets (
  id uuid primary key default extensions.gen_random_uuid(),
  report_id uuid not null references public.content_reports (id) on delete restrict,
  source_media_asset_id uuid references public.media_assets (id) on delete set null,
  source_bucket text not null,
  source_storage_path text not null,
  bucket text not null,
  storage_path text not null,
  media_type text not null,
  byte_size bigint,
  sha256 bytea,
  copy_status text not null default 'pending_copy',
  copy_claimed_at timestamptz,
  copy_attempts integer not null default 0,
  copy_completed_at timestamptz,
  last_copy_error text,
  delete_after timestamptz,
  storage_delete_status text not null default 'none',
  storage_deleted_at timestamptz,
  storage_delete_attempts integer not null default 0,
  last_storage_delete_error text,
  created_at timestamptz not null default now(),

  constraint report_snapshot_assets_bucket_check
    check (bucket = 'report-snapshots'),
  constraint report_snapshot_assets_source_bucket_check
    check (source_bucket in ('profile-photos', 'couple-media', 'widget-drawings')),
  constraint report_snapshot_assets_storage_path_check
    check (
      char_length(storage_path) between 1 and 1024
      and storage_path !~ '(^/|//|/\./|/\.\./|\.\./|/$)'
    ),
  constraint report_snapshot_assets_source_storage_path_check
    check (
      char_length(source_storage_path) between 1 and 1024
      and source_storage_path !~ '(^/|//|/\./|/\.\./|\.\./|/$)'
    ),
  constraint report_snapshot_assets_media_type_check
    check (media_type in ('image', 'voice', 'drawing_payload', 'report_snapshot')),
  constraint report_snapshot_assets_byte_size_check
    check (byte_size is null or byte_size > 0),
  constraint report_snapshot_assets_sha256_check
    check (sha256 is null or octet_length(sha256) = 32),
  constraint report_snapshot_assets_copy_status_check
    check (copy_status in ('pending_copy', 'copying', 'copied', 'copy_failed')),
  constraint report_snapshot_assets_copy_attempts_check
    check (copy_attempts >= 0),
  constraint report_snapshot_assets_copy_state_check
    check (
      (
        copy_status in ('pending_copy', 'copying', 'copy_failed')
        and copy_completed_at is null
      )
      or (
        copy_status = 'copied'
        and copy_completed_at is not null
        and byte_size is not null
        and sha256 is not null
      )
    ),
  constraint report_snapshot_assets_last_copy_error_check
    check (last_copy_error is null or char_length(last_copy_error) <= 4000),
  constraint report_snapshot_assets_storage_delete_status_check
    check (storage_delete_status in ('none', 'pending', 'retrying', 'deleted', 'failed')),
  constraint report_snapshot_assets_storage_deleted_at_check
    check (
      (storage_delete_status = 'deleted' and storage_deleted_at is not null)
      or storage_delete_status <> 'deleted'
    ),
  constraint report_snapshot_assets_attempts_check
    check (storage_delete_attempts >= 0),
  constraint report_snapshot_assets_last_error_check
    check (last_storage_delete_error is null or char_length(last_storage_delete_error) <= 4000)
);

create table internal.moderation_actions (
  id uuid primary key default extensions.gen_random_uuid(),
  report_id uuid references public.content_reports (id) on delete restrict,
  action_kind text not null,
  status text not null default 'started',
  target_kind text,
  target_id uuid,
  previous_moderation_status text,
  new_moderation_status text,
  storage_action text,
  operator_kind text not null,
  operator_identifier text not null,
  reviewer_user_id uuid references auth.users (id) on delete set null,
  runbook_id text,
  reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint moderation_actions_action_kind_check
    check (action_kind in ('hide', 'remove', 'restore', 'reject_upload', 'delete_storage', 'create_pair_warning', 'clear_pair_warning', 'block_pair', 'unblock_pair')),
  constraint moderation_actions_status_check
    check (status in ('started', 'applied', 'partially_applied', 'failed')),
  constraint moderation_actions_moderation_status_check
    check (
      previous_moderation_status is null
      or previous_moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected')
    ),
  constraint moderation_actions_new_moderation_status_check
    check (
      new_moderation_status is null
      or new_moderation_status in ('pending_review', 'visible', 'hidden', 'removed', 'rejected')
    ),
  constraint moderation_actions_storage_action_check
    check (storage_action is null or storage_action in ('none', 'queued_delete', 'deleted', 'failed')),
  constraint moderation_actions_operator_kind_check
    check (operator_kind in ('service_role', 'sql_runbook', 'edge_function', 'admin_user')),
  constraint moderation_actions_operator_identifier_check
    check (char_length(btrim(operator_identifier)) between 1 and 255),
  constraint moderation_actions_runbook_id_check
    check (runbook_id is null or char_length(btrim(runbook_id)) between 1 and 255),
  constraint moderation_actions_reason_check
    check (reason is null or char_length(reason) <= 1000),
  constraint moderation_actions_notes_check
    check (notes is null or char_length(notes) <= 4000)
);

create trigger set_moderation_actions_updated_at
before update on internal.moderation_actions
for each row
execute function internal.set_updated_at();

alter table public.profiles
add constraint profiles_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.media_assets
add constraint media_assets_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.daily_question_answers
add constraint daily_question_answers_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.conversation_threads
add constraint conversation_threads_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.thread_messages
add constraint thread_messages_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.memories
add constraint memories_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.memory_notes
add constraint memory_notes_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.memory_media
add constraint memory_media_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.widget_drawing_revisions
add constraint widget_drawing_revisions_moderation_report_id_fkey
foreign key (moderation_report_id)
references public.content_reports (id)
on delete set null;

alter table public.relationship_blocks
add constraint relationship_blocks_source_report_id_fkey
foreign key (source_report_id)
references public.content_reports (id)
on delete set null;

alter table internal.pair_safety_warning_flags
add constraint pair_safety_warning_flags_source_report_id_fkey
foreign key (source_report_id)
references public.content_reports (id)
on delete cascade;

create or replace function internal.is_admin()
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select false;
$$;

create or replace function internal.can_report_relationship_content(
  p_couple_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = p_user_id
      and member.status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen')
      and (
        couple.status = 'active'
        or (
          couple.status = 'ended'
          and couple.delete_after is not null
          and couple.delete_after > now()
        )
      )
  );
$$;

create or replace function internal.find_reportable_relationship_between(
  p_reporter_user_id uuid,
  p_reported_user_id uuid
)
returns table (
  couple_id uuid,
  pair_id uuid
)
language sql
security definer
set search_path = pg_catalog
as $$
  select couple.id, couple.pair_id
  from public.couple_members reporter_member
  join public.couple_members reported_member
    on reported_member.couple_id = reporter_member.couple_id
  join public.couples couple
    on couple.id = reporter_member.couple_id
  where reporter_member.user_id = p_reporter_user_id
    and reported_member.user_id = p_reported_user_id
    and reporter_member.status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen')
    and reported_member.status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen')
    and (
      couple.status = 'active'
      or (
        couple.status = 'ended'
        and couple.delete_after is not null
        and couple.delete_after > now()
      )
    )
  order by couple.status = 'active' desc, couple.created_at desc
  limit 1;
$$;

create or replace function internal.resolve_content_report_target(
  p_reporter_user_id uuid,
  p_target_kind text,
  p_target_id uuid,
  p_target_aux_id uuid default null
)
returns table (
  target_kind text,
  reported_user_id uuid,
  couple_id uuid,
  pair_id uuid,
  snapshot jsonb
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_target_id is null then
    raise exception 'report target id is required'
      using errcode = '23514';
  end if;

  if p_target_kind = 'daily_answer' then
    return query
    select
      p_target_kind,
      answer.user_id,
      couple_day.couple_id,
      couple.pair_id,
      jsonb_strip_nulls(jsonb_build_object(
        'target_kind', p_target_kind,
        'daily_answer_id', answer.id,
        'answer_user_id', answer.user_id,
        'created_at', answer.created_at,
        'moderation_status', answer.moderation_status,
        'text_body', answer_text.body,
        'media_asset_ids', (
          select coalesce(jsonb_agg(answer_media.media_asset_id order by answer_media.sort_order), '[]'::jsonb)
          from public.daily_answer_media answer_media
          join public.media_assets asset
            on asset.id = answer_media.media_asset_id
          where answer_media.answer_id = answer.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        )
      ))
    from public.daily_question_answers answer
    join public.daily_question_instances instance
      on instance.id = answer.instance_id
    join public.couple_days couple_day
      on couple_day.id = instance.couple_day_id
    join public.couples couple
      on couple.id = couple_day.couple_id
    left join public.daily_answer_text answer_text
      on answer_text.answer_id = answer.id
    where answer.id = p_target_id
      and answer.deleted_at is null
      and answer.moderation_status = 'visible'
      and internal.can_view_daily_answer(answer.id);
  elsif p_target_kind = 'memory' then
    return query
    select
      p_target_kind,
      case
        when memory.last_edited_by_user_id <> p_reporter_user_id then memory.last_edited_by_user_id
        else memory.created_by_user_id
      end,
      memory.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'memory_id', memory.id,
        'title', memory.title,
        'memory_date', memory.memory_date,
        'created_by_user_id', memory.created_by_user_id,
        'last_edited_by_user_id', memory.last_edited_by_user_id,
        'moderation_status', memory.moderation_status,
        'media_asset_ids', (
          select coalesce(jsonb_agg(memory_media.media_asset_id order by memory_media.sort_order), '[]'::jsonb)
          from public.memory_media memory_media
          join public.media_assets asset
            on asset.id = memory_media.media_asset_id
          where memory_media.memory_id = memory.id
            and memory_media.deleted_at is null
            and memory_media.moderation_status = 'visible'
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        )
      )
    from public.memories memory
    join public.couples couple
      on couple.id = memory.couple_id
    where memory.id = p_target_id
      and memory.deleted_at is null
      and memory.moderation_status = 'visible';
  elsif p_target_kind = 'memory_note' then
    return query
    select
      p_target_kind,
      note.user_id,
      memory.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'memory_note_id', note.id,
        'memory_id', note.memory_id,
        'note_user_id', note.user_id,
        'body', note.body,
        'moderation_status', note.moderation_status
      )
    from public.memory_notes note
    join public.memories memory
      on memory.id = note.memory_id
    join public.couples couple
      on couple.id = memory.couple_id
    where note.id = p_target_id
      and note.deleted_at is null
      and note.moderation_status = 'visible'
      and memory.deleted_at is null
      and memory.moderation_status = 'visible';
  elsif p_target_kind = 'memory_media' then
    return query
    select
      p_target_kind,
      memory_media.owner_user_id,
      memory.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'memory_media_id', memory_media.id,
        'memory_id', memory_media.memory_id,
        'media_asset_id', memory_media.media_asset_id,
        'owner_user_id', memory_media.owner_user_id,
        'moderation_status', memory_media.moderation_status
      )
    from public.memory_media memory_media
    join public.memories memory
      on memory.id = memory_media.memory_id
    join public.couples couple
      on couple.id = memory.couple_id
    join public.media_assets asset
      on asset.id = memory_media.media_asset_id
    where memory_media.id = p_target_id
      and memory_media.deleted_at is null
      and memory_media.moderation_status = 'visible'
      and memory.deleted_at is null
      and memory.moderation_status = 'visible'
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null;
  elsif p_target_kind = 'thread_message' then
    return query
    select
      p_target_kind,
      message.sender_user_id,
      thread.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'message_id', message.id,
        'thread_id', message.thread_id,
        'sender_user_id', message.sender_user_id,
        'body', message.body,
        'moderation_status', message.moderation_status,
        'media_asset_ids', (
          select coalesce(jsonb_agg(message_media.media_asset_id order by message_media.sort_order), '[]'::jsonb)
          from public.thread_message_media message_media
          join public.media_assets asset
            on asset.id = message_media.media_asset_id
          where message_media.message_id = message.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        )
      )
    from public.thread_messages message
    join public.conversation_threads thread
      on thread.id = message.thread_id
    join public.couples couple
      on couple.id = thread.couple_id
    where message.id = p_target_id
      and message.deleted_at is null
      and message.moderation_status = 'visible'
      and thread.deleted_at is null
      and thread.moderation_status = 'visible';
  elsif p_target_kind = 'thread_message_media' then
    if p_target_aux_id is null then
      raise exception 'thread message media reports require a media asset id'
        using errcode = '23514';
    end if;

    return query
    select
      p_target_kind,
      message.sender_user_id,
      thread.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'message_id', message.id,
        'media_asset_id', message_media.media_asset_id,
        'sender_user_id', message.sender_user_id
      )
    from public.thread_message_media message_media
    join public.thread_messages message
      on message.id = message_media.message_id
    join public.conversation_threads thread
      on thread.id = message.thread_id
    join public.couples couple
      on couple.id = thread.couple_id
    join public.media_assets asset
      on asset.id = message_media.media_asset_id
    where message_media.message_id = p_target_id
      and message_media.media_asset_id = p_target_aux_id
      and message.deleted_at is null
      and message.moderation_status = 'visible'
      and thread.deleted_at is null
      and thread.moderation_status = 'visible'
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null;
  elsif p_target_kind = 'widget_drawing_revision' then
    return query
    select
      p_target_kind,
      revision.author_user_id,
      canvas.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'widget_drawing_revision_id', revision.id,
        'canvas_id', revision.canvas_id,
        'author_user_id', revision.author_user_id,
        'payload_media_asset_id', revision.payload_media_asset_id,
        'moderation_status', revision.moderation_status
      )
    from public.widget_drawing_revisions revision
    join public.widget_canvases canvas
      on canvas.id = revision.canvas_id
    join public.couples couple
      on couple.id = canvas.couple_id
    join public.media_assets asset
      on asset.id = revision.payload_media_asset_id
    where revision.id = p_target_id
      and revision.deleted_at is null
      and revision.moderation_status = 'visible'
      and canvas.deleted_at is null
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null;
  elsif p_target_kind = 'media_asset' then
    return query
    select
      p_target_kind,
      asset.owner_user_id,
      asset.couple_id,
      couple.pair_id,
      jsonb_build_object(
        'target_kind', p_target_kind,
        'media_asset_id', asset.id,
        'owner_user_id', asset.owner_user_id,
        'bucket', asset.bucket,
        'storage_path', asset.storage_path,
        'media_type', asset.media_type,
        'upload_purpose', asset.upload_purpose,
        'moderation_status', asset.moderation_status
      )
    from public.media_assets asset
    join public.couples couple
      on couple.id = asset.couple_id
    where asset.id = p_target_id
      and asset.couple_id is not null
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null;
  elsif p_target_kind in ('profile', 'conduct') then
    return query
    select
      p_target_kind,
      p_target_id,
      relationship.couple_id,
      relationship.pair_id,
      jsonb_strip_nulls(jsonb_build_object(
        'target_kind', p_target_kind,
        'reported_user_id', p_target_id,
        'profile_display_name', profile.display_name,
        'profile_photo_asset_id', profile.profile_photo_asset_id,
        'profile_moderation_status', profile.moderation_status
      ))
    from internal.find_reportable_relationship_between(p_reporter_user_id, p_target_id) relationship
    left join public.profiles profile
      on profile.user_id = p_target_id
    where p_target_kind = 'conduct'
      or (
        profile.user_id is not null
        and profile.deleted_at is null
        and profile.moderation_status = 'visible'
      )
    limit 1;
  else
    raise exception 'report target kind is not supported'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function internal.enqueue_report_snapshot_assets(
  p_report_id uuid,
  p_target_snapshot jsonb
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  inserted_rows integer;
begin
  if p_report_id is null then
    raise exception 'report id is required'
      using errcode = '23514';
  end if;

  if p_target_snapshot is null or jsonb_typeof(p_target_snapshot) <> 'object' then
    raise exception 'report target snapshot is required'
      using errcode = '23514';
  end if;

  with raw_media_ids as (
    select distinct (media_value.media_json #>> '{}')::uuid as media_asset_id
    from jsonb_array_elements(coalesce(p_target_snapshot -> 'media_asset_ids', '[]'::jsonb)) as media_value(media_json)
    where (media_value.media_json #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

    union

    select (p_target_snapshot ->> 'media_asset_id')::uuid
    where (p_target_snapshot ->> 'media_asset_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

    union

    select (p_target_snapshot ->> 'payload_media_asset_id')::uuid
    where (p_target_snapshot ->> 'payload_media_asset_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

    union

    select (p_target_snapshot ->> 'profile_photo_asset_id')::uuid
    where (p_target_snapshot ->> 'profile_photo_asset_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ),
  source_assets as (
    select distinct on (asset.id)
      asset.id,
      asset.bucket,
      asset.storage_path,
      asset.media_type,
      asset.byte_size,
      asset.sha256
    from raw_media_ids raw
    join public.media_assets asset
      on asset.id = raw.media_asset_id
    where asset.bucket <> 'report-snapshots'
      and asset.upload_status = 'finalized'
      and asset.upload_finalized_at is not null
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
      and asset.byte_size is not null
      and asset.sha256 is not null
    order by asset.id
  ),
  prepared_assets as (
    select
      extensions.gen_random_uuid() as snapshot_asset_id,
      source_assets.*
    from source_assets
  )
  insert into internal.report_snapshot_assets (
    id,
    report_id,
    source_media_asset_id,
    source_bucket,
    source_storage_path,
    bucket,
    storage_path,
    media_type,
    byte_size,
    sha256,
    copy_status
  )
  select
    prepared.snapshot_asset_id,
    p_report_id,
    prepared.id,
    prepared.bucket,
    prepared.storage_path,
    'report-snapshots',
    p_report_id::text || '/' || prepared.snapshot_asset_id::text ||
      case
        when prepared.storage_path ~ '\.[A-Za-z0-9]{1,16}$'
          then lower(substring(prepared.storage_path from '\.[A-Za-z0-9]{1,16}$'))
        else ''
      end,
    prepared.media_type,
    prepared.byte_size,
    prepared.sha256,
    'pending_copy'
  from prepared_assets prepared;

  get diagnostics inserted_rows = row_count;
  return inserted_rows;
end;
$$;

create or replace function internal.claim_report_snapshot_asset_copies(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_retry_after interval default interval '15 minutes',
  p_max_attempts integer default 5
)
returns table (
  snapshot_asset_id uuid,
  report_id uuid,
  source_bucket text,
  source_storage_path text,
  destination_bucket text,
  destination_storage_path text,
  copy_attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_now is null or p_retry_after is null then
    raise exception 'report snapshot copy claim timestamp and retry window are required'
      using errcode = '23514';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'report snapshot copy claim limit is out of range'
      using errcode = '23514';
  end if;

  if p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 25 then
    raise exception 'report snapshot copy max attempts is out of range'
      using errcode = '23514';
  end if;

  return query
  with picked as (
    select asset.id
    from internal.report_snapshot_assets asset
    where asset.copy_attempts < p_max_attempts
      and (asset.delete_after is null or asset.delete_after > p_now)
      and (
        asset.copy_status = 'pending_copy'
        or (
          asset.copy_status = 'copying'
          and asset.copy_claimed_at <= p_now - p_retry_after
        )
      )
    order by asset.created_at, asset.id
    for update skip locked
    limit p_limit
  ),
  claimed as (
    update internal.report_snapshot_assets asset
    set
      copy_status = 'copying',
      copy_claimed_at = p_now,
      copy_attempts = asset.copy_attempts + 1,
      last_copy_error = null
    from picked
    where asset.id = picked.id
    returning
      asset.id,
      asset.report_id,
      asset.source_bucket,
      asset.source_storage_path,
      asset.bucket,
      asset.storage_path,
      asset.copy_attempts
  )
  select
    claimed.id,
    claimed.report_id,
    claimed.source_bucket,
    claimed.source_storage_path,
    claimed.bucket,
    claimed.storage_path,
    claimed.copy_attempts
  from claimed;
end;
$$;

create or replace function internal.mark_report_snapshot_asset_copied(p_snapshot_asset_id uuid)
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
    copy_status = 'copied',
    copy_completed_at = coalesce(asset.copy_completed_at, now()),
    last_copy_error = null,
    storage_delete_status = 'none',
    storage_deleted_at = null,
    last_storage_delete_error = null
  where asset.id = p_snapshot_asset_id
    and asset.copy_status in ('pending_copy', 'copying', 'copy_failed')
    and asset.byte_size is not null
    and asset.sha256 is not null;

  get diagnostics changed_rows = row_count;

  if changed_rows = 1 then
    return true;
  end if;

  return exists (
    select 1
    from internal.report_snapshot_assets asset
    where asset.id = p_snapshot_asset_id
      and asset.copy_status = 'copied'
  );
end;
$$;

create or replace function internal.mark_report_snapshot_asset_copy_failed(
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
    copy_status = case when coalesce(p_terminal, false) then 'copy_failed' else 'pending_copy' end,
    last_copy_error = left(nullif(btrim(coalesce(p_error, '')), ''), 4000)
  where asset.id = p_snapshot_asset_id
    and asset.copy_status in ('pending_copy', 'copying', 'copy_failed');

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.submit_content_report(
  p_reason text,
  p_note text,
  p_target_kind text,
  p_target_id uuid,
  p_target_aux_id uuid,
  p_leave_relationship boolean,
  p_block_reported_user boolean,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  normalized_reason text;
  normalized_note text;
  normalized_target_kind text;
  target_row record;
  report_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_reason = lower(btrim(coalesce(p_reason, '')));
  normalized_target_kind = lower(btrim(coalesce(p_target_kind, '')));
  normalized_note = nullif(btrim(coalesce(p_note, '')), '');

  if normalized_reason not in ('harassment', 'abuse', 'threat', 'sexual_content', 'hate', 'privacy', 'impersonation', 'self_harm', 'spam', 'other') then
    raise exception 'report reason is not supported'
      using errcode = '23514';
  end if;

  if normalized_note is not null and char_length(normalized_note) > 4000 then
    raise exception 'report note is too long'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'submit_content_report',
      normalized_reason,
      coalesce(normalized_note, ''),
      normalized_target_kind,
      p_target_id::text,
      coalesce(p_target_aux_id::text, ''),
      coalesce(p_leave_relationship, false)::text,
      coalesce(p_block_reported_user, false)::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'submit_content_report',
    'reports',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'report_id')::uuid;
  end if;

  select *
  into target_row
  from internal.resolve_content_report_target(
    current_user_id,
    normalized_target_kind,
    p_target_id,
    p_target_aux_id
  );

  if not found then
    raise exception 'report target was not found'
      using errcode = '22023';
  end if;

  if target_row.reported_user_id = current_user_id then
    raise exception 'users cannot report themselves'
      using errcode = '23514';
  end if;

  if not internal.can_report_relationship_content(target_row.couple_id, current_user_id) then
    raise exception 'report target is not connected to a reportable relationship'
      using errcode = '42501';
  end if;

  insert into public.content_reports (
    reporter_user_id,
    reported_user_id,
    couple_id,
    pair_id,
    reason,
    note,
    block_requested,
    leave_requested
  ) values (
    current_user_id,
    target_row.reported_user_id,
    target_row.couple_id,
    target_row.pair_id,
    normalized_reason,
    normalized_note,
    coalesce(p_block_reported_user, false),
    coalesce(p_leave_relationship, false)
  )
  returning id into report_id;

  insert into public.content_report_targets (
    report_id,
    target_kind,
    daily_answer_id,
    memory_id,
    memory_note_id,
    memory_media_id,
    message_id,
    message_media_message_id,
    message_media_asset_id,
    widget_drawing_revision_id,
    media_asset_id,
    profile_user_id,
    conduct_user_id
  ) values (
    report_id,
    normalized_target_kind,
    case when normalized_target_kind = 'daily_answer' then p_target_id end,
    case when normalized_target_kind = 'memory' then p_target_id end,
    case when normalized_target_kind = 'memory_note' then p_target_id end,
    case when normalized_target_kind = 'memory_media' then p_target_id end,
    case when normalized_target_kind = 'thread_message' then p_target_id end,
    case when normalized_target_kind = 'thread_message_media' then p_target_id end,
    case when normalized_target_kind = 'thread_message_media' then p_target_aux_id end,
    case when normalized_target_kind = 'widget_drawing_revision' then p_target_id end,
    case when normalized_target_kind = 'media_asset' then p_target_id end,
    case when normalized_target_kind = 'profile' then p_target_id end,
    case when normalized_target_kind = 'conduct' then p_target_id end
  );

  insert into internal.report_snapshots (
    report_id,
    snapshot,
    delete_after
  ) values (
    report_id,
    jsonb_build_object(
      'schema_version', 1,
      'report_id', report_id,
      'target', target_row.snapshot,
      'reporter_user_id', current_user_id,
      'reported_user_id', target_row.reported_user_id,
      'couple_id', target_row.couple_id,
      'pair_id', target_row.pair_id,
      'reason', normalized_reason,
      'note', normalized_note,
      'created_at', now()
    ),
    null
  );

  perform internal.enqueue_report_snapshot_assets(report_id, target_row.snapshot);

  insert into internal.pair_safety_warning_flags (pair_id, source_report_id)
  values (target_row.pair_id, report_id)
  on conflict do nothing;

  if coalesce(p_block_reported_user, false) then
    perform internal.block_relationship(target_row.reported_user_id, report_id);
  elsif coalesce(p_leave_relationship, false) then
    perform internal.end_relationship_for_pair(target_row.pair_id, current_user_id, 'reported');
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('report_id', report_id)
  );

  return report_id;
end;
$$;

create or replace function internal.infer_report_target_for_moderation(p_report_id uuid)
returns table (
  target_kind text,
  target_id uuid,
  target_aux_id uuid
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    target.target_kind,
    coalesce(
      target.daily_answer_id,
      target.memory_id,
      target.memory_note_id,
      target.memory_media_id,
      target.message_id,
      target.message_media_message_id,
      target.widget_drawing_revision_id,
      target.media_asset_id,
      target.profile_user_id,
      target.conduct_user_id
    ),
    target.message_media_asset_id
  from public.content_report_targets target
  where target.report_id = p_report_id;
$$;

create or replace function internal.apply_report_moderation_action(
  p_report_id uuid,
  p_action_kind text,
  p_operator_kind text,
  p_operator_identifier text,
  p_reason text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  report_row public.content_reports%rowtype;
  target_row record;
  normalized_action text;
  normalized_operator_kind text;
  normalized_operator_identifier text;
  target_new_status text;
  previous_status text;
  current_moderation_report_id uuid;
  current_deleted_at timestamptz;
  current_storage_delete_status text;
  storage_action text;
  queued_storage_rows integer;
  action_id uuid;
begin
  select *
  into report_row
  from public.content_reports
  where id = p_report_id
  for update;

  if not found then
    raise exception 'content report was not found'
      using errcode = '22023';
  end if;

  select *
  into target_row
  from internal.infer_report_target_for_moderation(p_report_id);

  if not found then
    raise exception 'content report target was not found'
      using errcode = '22023';
  end if;

  normalized_action = lower(btrim(coalesce(p_action_kind, '')));
  normalized_operator_kind = lower(btrim(coalesce(p_operator_kind, '')));
  normalized_operator_identifier = nullif(btrim(coalesce(p_operator_identifier, '')), '');

  if normalized_action not in ('hide', 'remove', 'restore', 'reject_upload', 'delete_storage', 'create_pair_warning', 'clear_pair_warning', 'block_pair', 'unblock_pair') then
    raise exception 'moderation action is not supported'
      using errcode = '23514';
  end if;

  if normalized_operator_kind not in ('service_role', 'sql_runbook', 'edge_function', 'admin_user')
    or normalized_operator_identifier is null then
    raise exception 'moderation operator metadata is required'
      using errcode = '23514';
  end if;

  target_new_status = case normalized_action
    when 'hide' then 'hidden'
    when 'remove' then 'removed'
    when 'delete_storage' then 'removed'
    when 'restore' then 'visible'
    when 'reject_upload' then 'rejected'
    else null
  end;

  if target_new_status is not null then
    if target_row.target_kind = 'daily_answer' then
      select moderation_status, moderation_report_id
      into previous_status, current_moderation_report_id
      from public.daily_question_answers
      where id = target_row.target_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if exists (
          select 1
          from public.daily_answer_media answer_media
          join public.media_assets asset
            on asset.id = answer_media.media_asset_id
          where answer_media.answer_id = target_row.target_id
            and (
              asset.deleted_at is not null
              or asset.storage_delete_status <> 'none'
            )
        ) then
          raise exception 'cannot restore content with media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.daily_question_answers
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'memory' then
      select moderation_status, moderation_report_id
      into previous_status, current_moderation_report_id
      from public.memories
      where id = target_row.target_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if exists (
          select 1
          from public.memory_media memory_media
          join public.media_assets asset
            on asset.id = memory_media.media_asset_id
          where memory_media.memory_id = target_row.target_id
            and (
              asset.deleted_at is not null
              or asset.storage_delete_status <> 'none'
            )
        ) then
          raise exception 'cannot restore content with media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.memories
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'memory_note' then
      select moderation_status, moderation_report_id
      into previous_status, current_moderation_report_id
      from public.memory_notes
      where id = target_row.target_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore'
        and current_moderation_report_id is distinct from report_row.id then
        raise exception 'cannot restore content moderated by a different report'
          using errcode = '23514';
      end if;

      update public.memory_notes
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'memory_media' then
      select
        memory_media.moderation_status,
        memory_media.moderation_report_id,
        asset.deleted_at,
        asset.storage_delete_status
      into
        previous_status,
        current_moderation_report_id,
        current_deleted_at,
        current_storage_delete_status
      from public.memory_media memory_media
      join public.media_assets asset
        on asset.id = memory_media.media_asset_id
      where memory_media.id = target_row.target_id
      for update of memory_media, asset;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if current_deleted_at is not null
          or current_storage_delete_status <> 'none' then
          raise exception 'cannot restore media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.memory_media
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'thread_message' then
      select moderation_status, moderation_report_id
      into previous_status, current_moderation_report_id
      from public.thread_messages
      where id = target_row.target_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if exists (
          select 1
          from public.thread_message_media message_media
          join public.media_assets asset
            on asset.id = message_media.media_asset_id
          where message_media.message_id = target_row.target_id
            and (
              asset.deleted_at is not null
              or asset.storage_delete_status <> 'none'
            )
        ) then
          raise exception 'cannot restore content with media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.thread_messages
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'thread_message_media' then
      select moderation_status, moderation_report_id, deleted_at, storage_delete_status
      into previous_status, current_moderation_report_id, current_deleted_at, current_storage_delete_status
      from public.media_assets
      where id = target_row.target_aux_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if current_deleted_at is not null
          or current_storage_delete_status <> 'none' then
          raise exception 'cannot restore media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.media_assets
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_aux_id;
    elsif target_row.target_kind = 'widget_drawing_revision' then
      select
        revision.moderation_status,
        revision.moderation_report_id,
        asset.deleted_at,
        asset.storage_delete_status
      into
        previous_status,
        current_moderation_report_id,
        current_deleted_at,
        current_storage_delete_status
      from public.widget_drawing_revisions revision
      join public.media_assets asset
        on asset.id = revision.payload_media_asset_id
      where revision.id = target_row.target_id
      for update of revision, asset;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if current_deleted_at is not null
          or current_storage_delete_status <> 'none' then
          raise exception 'cannot restore media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.widget_drawing_revisions
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'media_asset' then
      select moderation_status, moderation_report_id, deleted_at, storage_delete_status
      into previous_status, current_moderation_report_id, current_deleted_at, current_storage_delete_status
      from public.media_assets
      where id = target_row.target_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if current_deleted_at is not null
          or current_storage_delete_status <> 'none' then
          raise exception 'cannot restore media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.media_assets
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where id = target_row.target_id;
    elsif target_row.target_kind = 'profile' then
      select moderation_status, moderation_report_id
      into previous_status, current_moderation_report_id
      from public.profiles
      where user_id = target_row.target_id
      for update;

      if not found then
        raise exception 'moderation target was not found'
          using errcode = '22023';
      end if;

      if normalized_action = 'restore' then
        if current_moderation_report_id is distinct from report_row.id then
          raise exception 'cannot restore content moderated by a different report'
            using errcode = '23514';
        end if;

        if exists (
          select 1
          from public.profiles profile
          join public.media_assets asset
            on asset.id = profile.profile_photo_asset_id
          where profile.user_id = target_row.target_id
            and (
              asset.deleted_at is not null
              or asset.storage_delete_status <> 'none'
            )
        ) then
          raise exception 'cannot restore content with media queued for storage deletion'
            using errcode = '23514';
        end if;
      end if;

      update public.profiles
      set
        moderation_status = target_new_status,
        moderated_at = now(),
        moderation_report_id = case when normalized_action = 'restore' then null else report_row.id end
      where user_id = target_row.target_id;
    else
      raise exception 'moderation action cannot change this target kind'
        using errcode = '23514';
    end if;

    storage_action = 'none';

    if normalized_action in ('remove', 'delete_storage') then
      queued_storage_rows = 0;

      if target_row.target_kind = 'daily_answer' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        from public.daily_answer_media answer_media
        where answer_media.answer_id = target_row.target_id
          and asset.id = answer_media.media_asset_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'memory' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        from public.memory_media memory_media
        where memory_media.memory_id = target_row.target_id
          and asset.id = memory_media.media_asset_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'memory_media' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        from public.memory_media memory_media
        where memory_media.id = target_row.target_id
          and asset.id = memory_media.media_asset_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'thread_message' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        from public.thread_message_media message_media
        where message_media.message_id = target_row.target_id
          and asset.id = message_media.media_asset_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'thread_message_media' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        where asset.id = target_row.target_aux_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'widget_drawing_revision' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        from public.widget_drawing_revisions revision
        where revision.id = target_row.target_id
          and asset.id = revision.payload_media_asset_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'media_asset' then
        update public.media_assets
        set
          deleted_at = coalesce(deleted_at, now()),
          storage_delete_status = case
            when storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        where id = target_row.target_id;

        get diagnostics queued_storage_rows = row_count;
      elsif target_row.target_kind = 'profile'
        and normalized_action = 'delete_storage' then
        update public.media_assets asset
        set
          deleted_at = coalesce(asset.deleted_at, now()),
          storage_delete_status = case
            when asset.storage_delete_status = 'deleted' then 'deleted'
            else 'pending'
          end,
          last_storage_delete_error = null
        from public.profiles profile
        where profile.user_id = target_row.target_id
          and asset.id = profile.profile_photo_asset_id;

        get diagnostics queued_storage_rows = row_count;
      end if;

      if queued_storage_rows > 0 then
        storage_action = 'queued_delete';
      elsif normalized_action = 'delete_storage' then
        raise exception 'delete_storage found no storage assets for this target'
          using errcode = '23514';
      end if;
    end if;
  elsif normalized_action = 'create_pair_warning' then
    insert into internal.pair_safety_warning_flags (pair_id, source_report_id)
    values (report_row.pair_id, report_row.id)
    on conflict do nothing;
  elsif normalized_action = 'clear_pair_warning' then
    delete from internal.pair_safety_warning_flags warning
    where warning.pair_id = report_row.pair_id
      and warning.source_report_id = report_row.id;
  elsif normalized_action = 'block_pair' then
    insert into public.relationship_blocks (
      pair_id,
      blocked_by_user_id,
      blocked_user_id,
      source_report_id
    ) values (
      report_row.pair_id,
      report_row.reporter_user_id,
      report_row.reported_user_id,
      report_row.id
    )
    on conflict (pair_id, blocked_by_user_id, blocked_user_id)
    where revoked_at is null
    do update set source_report_id = coalesce(public.relationship_blocks.source_report_id, excluded.source_report_id);

    perform internal.end_relationship_for_pair(report_row.pair_id, report_row.reporter_user_id, 'moderation_block');
  elsif normalized_action = 'unblock_pair' then
    update public.relationship_blocks
    set
      revoked_at = coalesce(revoked_at, now()),
      revoked_by_user_id = blocked_by_user_id,
      revoke_reason = 'admin_correction'
    where pair_id = report_row.pair_id
      and revoked_at is null;
  end if;

  insert into internal.moderation_actions (
    report_id,
    action_kind,
    status,
    target_kind,
    target_id,
    previous_moderation_status,
    new_moderation_status,
    storage_action,
    operator_kind,
    operator_identifier,
    reason,
    notes
  ) values (
    report_row.id,
    normalized_action,
    'applied',
    target_row.target_kind,
    target_row.target_id,
    previous_status,
    target_new_status,
    storage_action,
    normalized_operator_kind,
    normalized_operator_identifier,
    p_reason,
    p_notes
  )
  returning id into action_id;

  update public.content_reports
  set
    status = case when normalized_action = 'restore' then 'closed' else 'action_taken' end,
    resolved_at = coalesce(resolved_at, now())
  where id = report_row.id;

  update internal.report_snapshots
  set delete_after = coalesce(delete_after, now() + interval '180 days')
  where report_id = report_row.id;

  update internal.report_snapshot_assets
  set delete_after = coalesce(delete_after, now() + interval '180 days')
  where report_id = report_row.id;

  return action_id;
end;
$$;

create or replace function public.submit_content_report(
  p_reason text,
  p_note text,
  p_target_kind text,
  p_target_id uuid,
  p_target_aux_id uuid,
  p_block_reported_user boolean,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.submit_content_report(
    p_reason,
    p_note,
    p_target_kind,
    p_target_id,
    p_target_aux_id,
    false,
    p_block_reported_user,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.submit_leave_and_report(
  p_reason text,
  p_note text,
  p_target_kind text,
  p_target_id uuid,
  p_target_aux_id uuid,
  p_block_reported_user boolean,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.submit_content_report(
    p_reason,
    p_note,
    p_target_kind,
    p_target_id,
    p_target_aux_id,
    true,
    p_block_reported_user,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function internal.tombstone_content_report_target()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if TG_TABLE_SCHEMA <> 'public' then
    raise exception 'content report tombstone trigger is only valid for public tables'
      using errcode = '23514';
  end if;

  if TG_TABLE_NAME = 'daily_question_answers' then
    update public.content_report_targets
    set
      daily_answer_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'daily_answer'
      and daily_answer_id = old.id;
  elsif TG_TABLE_NAME = 'memories' then
    update public.content_report_targets
    set
      memory_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'memory'
      and memory_id = old.id;
  elsif TG_TABLE_NAME = 'memory_notes' then
    update public.content_report_targets
    set
      memory_note_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'memory_note'
      and memory_note_id = old.id;
  elsif TG_TABLE_NAME = 'memory_media' then
    update public.content_report_targets
    set
      memory_media_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'memory_media'
      and memory_media_id = old.id;
  elsif TG_TABLE_NAME = 'thread_messages' then
    update public.content_report_targets
    set
      message_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'thread_message'
      and message_id = old.id;
  elsif TG_TABLE_NAME = 'thread_message_media' then
    update public.content_report_targets
    set
      message_media_message_id = null,
      message_media_asset_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'thread_message_media'
      and message_media_message_id = old.message_id
      and message_media_asset_id = old.media_asset_id;
  elsif TG_TABLE_NAME = 'widget_drawing_revisions' then
    update public.content_report_targets
    set
      widget_drawing_revision_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'widget_drawing_revision'
      and widget_drawing_revision_id = old.id;
  elsif TG_TABLE_NAME = 'media_assets' then
    update public.content_report_targets
    set
      media_asset_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'media_asset'
      and media_asset_id = old.id;
  elsif TG_TABLE_NAME = 'profiles' then
    update public.content_report_targets
    set
      profile_user_id = null,
      live_target_deleted_at = coalesce(live_target_deleted_at, now())
    where target_kind = 'profile'
      and profile_user_id = old.user_id;
  else
    raise exception 'content report tombstone trigger is not configured for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
      using errcode = '23514';
  end if;

  return old;
end;
$$;

create trigger tombstone_content_report_target_daily_answer
before delete on public.daily_question_answers
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_memory
before delete on public.memories
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_memory_note
before delete on public.memory_notes
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_memory_media
before delete on public.memory_media
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_thread_message
before delete on public.thread_messages
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_thread_message_media
before delete on public.thread_message_media
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_widget_revision
before delete on public.widget_drawing_revisions
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_media_asset
before delete on public.media_assets
for each row
execute function internal.tombstone_content_report_target();

create trigger tombstone_content_report_target_profile
before delete on public.profiles
for each row
execute function internal.tombstone_content_report_target();

alter table public.content_reports enable row level security;
alter table public.content_report_targets enable row level security;
alter table internal.report_snapshots enable row level security;
alter table internal.report_snapshot_assets enable row level security;
alter table internal.moderation_actions enable row level security;

create policy content_reports_select_own
on public.content_reports
for select
to authenticated
using (reporter_user_id = (select auth.uid()));

create policy content_report_targets_select_own_report
on public.content_report_targets
for select
to authenticated
using (
  exists (
    select 1
    from public.content_reports report
    where report.id = content_report_targets.report_id
      and report.reporter_user_id = (select auth.uid())
  )
);

create index content_reports_reporter_created_at_idx
on public.content_reports (reporter_user_id, created_at desc);

create index content_reports_reported_created_at_idx
on public.content_reports (reported_user_id, created_at desc);

create index content_reports_couple_created_at_idx
on public.content_reports (couple_id, created_at desc);

create index content_reports_status_created_at_idx
on public.content_reports (status, created_at);

create index content_report_targets_daily_answer_id_idx
on public.content_report_targets (daily_answer_id)
where daily_answer_id is not null;

create index content_report_targets_memory_id_idx
on public.content_report_targets (memory_id)
where memory_id is not null;

create index content_report_targets_memory_note_id_idx
on public.content_report_targets (memory_note_id)
where memory_note_id is not null;

create index content_report_targets_memory_media_id_idx
on public.content_report_targets (memory_media_id)
where memory_media_id is not null;

create index content_report_targets_message_id_idx
on public.content_report_targets (message_id)
where message_id is not null;

create index content_report_targets_message_media_idx
on public.content_report_targets (message_media_message_id, message_media_asset_id)
where message_media_message_id is not null;

create index content_report_targets_widget_revision_id_idx
on public.content_report_targets (widget_drawing_revision_id)
where widget_drawing_revision_id is not null;

create index content_report_targets_media_asset_id_idx
on public.content_report_targets (media_asset_id)
where media_asset_id is not null;

create index content_report_targets_profile_user_id_idx
on public.content_report_targets (profile_user_id)
where profile_user_id is not null;

create index content_report_targets_conduct_user_id_idx
on public.content_report_targets (conduct_user_id)
where conduct_user_id is not null;

create index report_snapshot_assets_delete_status_idx
on internal.report_snapshot_assets (delete_after, storage_delete_status);

create unique index report_snapshot_assets_report_source_unique_idx
on internal.report_snapshot_assets (report_id, source_media_asset_id)
where source_media_asset_id is not null;

create unique index report_snapshot_assets_bucket_storage_path_unique_idx
on internal.report_snapshot_assets (bucket, storage_path);

create index report_snapshot_assets_copy_claim_idx
on internal.report_snapshot_assets (copy_status, copy_attempts, copy_claimed_at, created_at);

create index moderation_actions_report_created_at_idx
on internal.moderation_actions (report_id, created_at desc);

revoke all on public.content_reports from public, anon, authenticated;
revoke all on public.content_report_targets from public, anon, authenticated;
revoke all on internal.report_snapshots from public, anon, authenticated;
revoke all on internal.report_snapshot_assets from public, anon, authenticated;
revoke all on internal.moderation_actions from public, anon, authenticated;

grant select on public.content_reports to authenticated;
grant select on public.content_report_targets to authenticated;

grant all privileges on public.content_reports to service_role;
grant all privileges on public.content_report_targets to service_role;
grant all privileges on internal.report_snapshots to service_role;
grant all privileges on internal.report_snapshot_assets to service_role;
grant all privileges on internal.moderation_actions to service_role;

revoke all on function internal.is_admin() from public, anon, authenticated;
grant execute on function internal.is_admin() to service_role;

revoke all on function internal.can_report_relationship_content(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.can_report_relationship_content(uuid, uuid) to service_role;

revoke all on function internal.find_reportable_relationship_between(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.find_reportable_relationship_between(uuid, uuid) to service_role;

revoke all on function internal.resolve_content_report_target(uuid, text, uuid, uuid) from public, anon, authenticated;
grant execute on function internal.resolve_content_report_target(uuid, text, uuid, uuid) to service_role;

revoke all on function internal.enqueue_report_snapshot_assets(uuid, jsonb) from public, anon, authenticated;
grant execute on function internal.enqueue_report_snapshot_assets(uuid, jsonb) to service_role;

revoke all on function internal.claim_report_snapshot_asset_copies(timestamptz, integer, interval, integer) from public, anon, authenticated;
grant execute on function internal.claim_report_snapshot_asset_copies(timestamptz, integer, interval, integer) to service_role;

revoke all on function internal.mark_report_snapshot_asset_copied(uuid) from public, anon, authenticated;
grant execute on function internal.mark_report_snapshot_asset_copied(uuid) to service_role;

revoke all on function internal.mark_report_snapshot_asset_copy_failed(uuid, text, boolean) from public, anon, authenticated;
grant execute on function internal.mark_report_snapshot_asset_copy_failed(uuid, text, boolean) to service_role;

revoke all on function internal.submit_content_report(text, text, text, uuid, uuid, boolean, boolean, uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.submit_content_report(text, text, text, uuid, uuid, boolean, boolean, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.infer_report_target_for_moderation(uuid) from public, anon, authenticated;
grant execute on function internal.infer_report_target_for_moderation(uuid) to service_role;

revoke all on function internal.apply_report_moderation_action(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function internal.apply_report_moderation_action(uuid, text, text, text, text, text) to service_role;

revoke all on function internal.tombstone_content_report_target() from public, anon, authenticated;
grant execute on function internal.tombstone_content_report_target() to service_role;

revoke all on function public.submit_content_report(text, text, text, uuid, uuid, boolean, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.submit_content_report(text, text, text, uuid, uuid, boolean, uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.submit_leave_and_report(text, text, text, uuid, uuid, boolean, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.submit_leave_and_report(text, text, text, uuid, uuid, boolean, uuid, uuid, bigint, timestamptz) to authenticated, service_role;
