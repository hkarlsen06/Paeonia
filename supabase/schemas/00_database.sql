


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "internal";


ALTER SCHEMA "internal" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage_private";


ALTER SCHEMA "storage_private" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date" DEFAULT NULL::"date") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  invite_row public.pairing_invites%rowtype;
  resolved_pair_id uuid;
  created_couple_id uuid;
  invite_code_hash bytea;
  request_hash bytea;
  replayed_response jsonb;
  code_prefix text;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  code_prefix = left(pg_catalog.encode(invite_code_hash, 'hex'), 12);

  perform internal.assert_pairing_invite_attempt_allowed(current_user_id, code_prefix);

  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'accept_pairing_invite',
      pg_catalog.encode(invite_code_hash, 'hex'),
      coalesce(p_started_on::text, 'unset')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'accept_pairing_invite',
    'pairing_invites',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'couple_id')::uuid;
  end if;

  select invite.*
  into invite_row
  from internal.pairing_invite_secrets secret
  join public.pairing_invites invite
    on invite.id = secret.invite_id
  where secret.code_hash = invite_code_hash
  for update of invite;

  if not found then
    insert into internal.pairing_invite_attempts (code_hash_prefix, user_id, success, failure_reason)
    values (code_prefix, current_user_id, false, 'not_found');

    raise exception 'pairing invite is not available'
      using errcode = '22023';
  end if;

  if invite_row.created_by_user_id = current_user_id then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'self_accept'
    );

    raise exception 'users cannot accept their own invite'
      using errcode = '23514';
  end if;

  if invite_row.status <> 'pending' then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'not_pending'
    );

    raise exception 'pairing invite is not pending'
      using errcode = '22023';
  end if;

  if invite_row.expires_at <= now() then
    update public.pairing_invites
    set status = 'expired'
    where id = invite_row.id;

    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'expired'
    );

    raise exception 'pairing invite is expired'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id in (current_user_id, invite_row.created_by_user_id)
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'active_couple'
    );

    raise exception 'one of the users already has an active couple'
      using errcode = '23505';
  end if;

  resolved_pair_id = internal.get_or_create_relationship_pair(
    invite_row.created_by_user_id,
    current_user_id
  );

  if (select internal.has_active_relationship_block(resolved_pair_id)) then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'active_block'
    );

    raise exception 'pairing is blocked for this pair'
      using errcode = '42501';
  end if;

  insert into public.couples (pair_id, started_on, created_by_user_id)
  values (resolved_pair_id, p_started_on, invite_row.created_by_user_id)
  returning id into created_couple_id;

  insert into public.couple_members (couple_id, user_id, role)
  values
    (created_couple_id, invite_row.created_by_user_id, 'creator'),
    (created_couple_id, current_user_id, 'partner');

  update public.pairing_invites
  set
    status = 'accepted',
    accepted_by_user_id = current_user_id,
    accepted_at = now(),
    couple_id = created_couple_id
  where id = invite_row.id;

  perform internal.create_relationship_sync_event(
    invite_row.created_by_user_id,
    created_couple_id,
    current_user_id,
    'relationship_started',
    'pairing_invite_accepted',
    'active',
    'active',
    null,
    null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );

  perform internal.create_relationship_sync_event(
    current_user_id,
    created_couple_id,
    current_user_id,
    'relationship_started',
    'pairing_invite_accepted',
    'active',
    'active',
    null,
    null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );

  insert into internal.pairing_invite_attempts (
    code_hash_prefix,
    matched_invite_id,
    user_id,
    success
  ) values (
    code_prefix,
    invite_row.id,
    current_user_id,
    true
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('couple_id', created_couple_id)
  );

  return created_couple_id;
end;
$$;


ALTER FUNCTION "internal"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."apply_couple_activity"("p_couple_id" "uuid", "p_user_id" "uuid", "p_couple_day_id" "uuid", "p_activity_kind" "text", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_day_row public.couple_days%rowtype;
  inserted_event_id uuid;
  existing_state public.streak_states%rowtype;
  qualified_at timestamptz;
  previous_qualified_at timestamptz;
  previous_observed_at timestamptz;
  previous_deadline timestamptz;
  resolved_deadline timestamptz;
  next_current_count integer;
  next_restorable_count integer;
  next_restorable_through_date date;
  next_restore_deadline timestamptz;
begin
  if p_activity_kind not in ('daily_challenge_completed', 'widget_drawing_saved', 'memory_created', 'memory_updated', 'thread_message_sent') then
    raise exception 'couple activity kind is not supported'
      using errcode = '23514';
  end if;

  p_occurred_at = coalesce(p_occurred_at, now());

  if p_dedupe_key is null or char_length(btrim(p_dedupe_key)) not between 1 and 240 then
    raise exception 'couple activity dedupe key is required'
      using errcode = '23514';
  end if;

  p_metadata = coalesce(p_metadata, '{}'::jsonb);

  select *
  into couple_day_row
  from public.couple_days
  where id = p_couple_day_id;

  if not found or couple_day_row.couple_id <> p_couple_id then
    raise exception 'couple activity day is invalid'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = p_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'couple activity user must be an active couple member'
      using errcode = '23514';
  end if;

  -- Serialize both partners' events on the couple row. Without this lock, two
  -- simultaneous first contributions could each miss the other's uncommitted
  -- event and leave an otherwise-qualified day uncounted.
  perform 1
  from public.couples couple
  where couple.id = p_couple_id
  for update;

  insert into public.couple_activity_events (
    couple_id, user_id, couple_day_id, activity_kind, occurred_at, dedupe_key, metadata
  ) values (
    p_couple_id, p_user_id, p_couple_day_id, p_activity_kind, p_occurred_at,
    btrim(p_dedupe_key), p_metadata
  )
  on conflict (dedupe_key) do nothing
  returning id into inserted_event_id;

  if inserted_event_id is null then
    select event.id
    into inserted_event_id
    from public.couple_activity_events event
    where event.dedupe_key = btrim(p_dedupe_key);

    return inserted_event_id;
  end if;

  qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    p_couple_day_id
  );

  -- One person can contribute more than once, but no streak state changes until
  -- the other active member has also shown up during this couple day.
  if qualified_at is null then
    return inserted_event_id;
  end if;

  select *
  into existing_state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  resolved_deadline = internal.resolve_next_activity_deadline_at(
    p_couple_id,
    qualified_at
  );

  if not found then
    insert into public.streak_states (
      couple_id,
      current_count,
      longest_count,
      last_qualified_date,
      last_qualified_couple_day_id,
      restore_available,
      next_activity_deadline_at
    ) values (
      p_couple_id,
      1,
      1,
      couple_day_row.local_date,
      couple_day_row.id,
      false,
      resolved_deadline
    );

    return inserted_event_id;
  end if;

  previous_qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    existing_state.last_qualified_couple_day_id
  );

  previous_observed_at = previous_qualified_at;
  if previous_observed_at is null then
    -- A legacy streak may point at a day that only one partner completed. Its
    -- latest event still provides a stable ordering/deadline anchor so a late
    -- older two-person day cannot move the ledger backwards.
    select max(event.occurred_at)
    into previous_observed_at
    from public.couple_activity_events event
    where event.couple_id = p_couple_id
      and event.couple_day_id = existing_state.last_qualified_couple_day_id;
  end if;

  if previous_observed_at is not null then
    previous_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      previous_observed_at
    );
  else
    previous_deadline = existing_state.next_activity_deadline_at;
  end if;

  if couple_day_row.id = existing_state.last_qualified_couple_day_id then
    update public.streak_states
    set next_activity_deadline_at = resolved_deadline
    where couple_id = p_couple_id;

    return inserted_event_id;
  end if;

  -- Keep a late-arriving historical day in the audit trail without allowing it
  -- to reorder the current streak ledger.
  if previous_observed_at is not null and qualified_at <= previous_observed_at then
    return inserted_event_id;
  end if;

  if previous_deadline is not null and qualified_at < previous_deadline then
    next_current_count = existing_state.current_count + 1;
    next_restorable_count = 0;
    next_restorable_through_date = null;
    next_restore_deadline = null;
  else
    next_current_count = 1;
    next_restorable_count = greatest(
      existing_state.restorable_count,
      existing_state.current_count
    );
    next_restorable_through_date = coalesce(
      existing_state.restorable_through_date,
      existing_state.last_qualified_date
    );
    next_restore_deadline = coalesce(
      existing_state.restore_deadline,
      previous_deadline + interval '24 hours'
    );
  end if;

  update public.streak_states
  set
    current_count = next_current_count,
    longest_count = greatest(longest_count, next_current_count),
    last_qualified_date = couple_day_row.local_date,
    last_qualified_couple_day_id = couple_day_row.id,
    restore_available = next_restorable_count > 0 and next_restore_deadline > now(),
    next_activity_deadline_at = resolved_deadline,
    restorable_count = next_restorable_count,
    restorable_through_date = next_restorable_through_date,
    restore_deadline = next_restore_deadline
  where couple_id = p_couple_id;

  return inserted_event_id;
end;
$$;


ALTER FUNCTION "internal"."apply_couple_activity"("p_couple_id" "uuid", "p_user_id" "uuid", "p_couple_day_id" "uuid", "p_activity_kind" "text", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."apply_report_moderation_action"("p_report_id" "uuid", "p_action_kind" "text", "p_operator_kind" "text", "p_operator_identifier" "text", "p_reason" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."apply_report_moderation_action"("p_report_id" "uuid", "p_action_kind" "text", "p_operator_kind" "text", "p_operator_identifier" "text", "p_reason" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."apply_streak_restore"("p_couple_id" "uuid", "p_purchaser_user_id" "uuid", "p_product_id" "uuid", "p_environment" "text", "p_transaction_id" "text", "p_original_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_raw_payload_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  existing_restoration internal.streak_restorations%rowtype;
  state public.streak_states%rowtype;
  today_couple_day_id uuid;
  today_couple_day public.couple_days%rowtype;
  yesterday_couple_day_id uuid;
  yesterday_couple_day public.couple_days%rowtype;
  today_qualified_at timestamptz;
  resolved_count integer;
  resolved_last_date date;
  resolved_last_couple_day_id uuid;
  resolved_deadline timestamptz;
begin
  select *
  into existing_restoration
  from internal.streak_restorations
  where environment = p_environment
    and transaction_id = p_transaction_id;

  if found then
    return jsonb_build_object(
      'ok', true,
      'restoredCount', existing_restoration.restored_count,
      'replayed', true
    );
  end if;

  select *
  into state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  if not found
    or coalesce(state.restorable_count, 0) <= 0
    or state.restore_deadline is null
    or state.restore_deadline <= now() then
    return jsonb_build_object(
      'ok', false,
      'error', 'No streak is available to restore',
      'status', 409
    );
  end if;

  today_couple_day_id = internal.get_or_create_couple_day_at(p_couple_id, now());

  select *
  into today_couple_day
  from public.couple_days
  where id = today_couple_day_id;

  today_qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    today_couple_day_id
  );

  -- A restore adds today only when both partners have contributed. One person's
  -- pending contribution stays in the audit trail and can qualify the day when
  -- the other partner later joins them.
  if today_qualified_at is not null then
    resolved_count = state.restorable_count + 1;
    resolved_last_date = today_couple_day.local_date;
    resolved_last_couple_day_id = today_couple_day_id;
    resolved_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      today_qualified_at
    );
  else
    resolved_count = state.restorable_count;
    yesterday_couple_day_id = internal.get_or_create_couple_day_at(
      p_couple_id,
      now() - interval '1 day'
    );

    select *
    into yesterday_couple_day
    from public.couple_days
    where id = yesterday_couple_day_id;

    resolved_last_date = yesterday_couple_day.local_date;
    resolved_last_couple_day_id = yesterday_couple_day_id;
    resolved_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      yesterday_couple_day.starts_at
    );
  end if;

  update public.streak_states
  set
    current_count = resolved_count,
    longest_count = greatest(longest_count, resolved_count),
    last_qualified_date = resolved_last_date,
    last_qualified_couple_day_id = resolved_last_couple_day_id,
    next_activity_deadline_at = resolved_deadline,
    restore_available = false,
    restorable_count = 0,
    restorable_through_date = null,
    restore_deadline = null,
    restored_at = now(),
    last_restore_transaction_id = p_transaction_id
  where couple_id = p_couple_id;

  insert into internal.streak_restorations (
    couple_id,
    purchaser_user_id,
    product_id,
    environment,
    transaction_id,
    original_transaction_id,
    restored_count,
    restorable_through_date,
    purchased_at,
    raw_payload_id,
    status
  ) values (
    p_couple_id,
    p_purchaser_user_id,
    p_product_id,
    p_environment,
    p_transaction_id,
    p_original_transaction_id,
    resolved_count,
    state.restorable_through_date,
    p_purchased_at,
    p_raw_payload_id,
    'applied'
  );

  return jsonb_build_object(
    'ok', true,
    'restoredCount', resolved_count,
    'replayed', false
  );
end;
$$;


ALTER FUNCTION "internal"."apply_streak_restore"("p_couple_id" "uuid", "p_purchaser_user_id" "uuid", "p_product_id" "uuid", "p_environment" "text", "p_transaction_id" "text", "p_original_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_raw_payload_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_active_question_collection_ready"("p_collection_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  collection_row public.question_collections%rowtype;
  active_question_count integer;
  active_question_id uuid;
begin
  select *
  into collection_row
  from public.question_collections
  where id = p_collection_id;

  if not found then
    return;
  end if;

  if collection_row.status = 'active' then
    select count(*)
    into active_question_count
    from public.questions question
    where question.collection_id = p_collection_id
      and question.status = 'active';

    if active_question_count < 1 then
      raise exception 'active collections require active questions'
        using errcode = '23514';
    end if;

    for active_question_id in
      select question.id
      from public.questions question
      where question.collection_id = p_collection_id
        and question.status = 'active'
    loop
      perform internal.assert_active_question_ready(active_question_id);
    end loop;
  end if;
end;
$$;


ALTER FUNCTION "internal"."assert_active_question_collection_ready"("p_collection_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_active_question_ready"("p_question_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  question_row record;
  active_version_id uuid;
begin
  select
    question.id,
    question.status as question_status,
    collection.kind as collection_kind,
    collection.status as collection_status
  into question_row
  from public.questions question
  join public.question_collections collection
    on collection.id = question.collection_id
  where question.id = p_question_id;

  if not found then
    return;
  end if;

  if question_row.collection_status = 'active'
    and question_row.question_status = 'active' then
    select version.id
    into active_version_id
    from public.question_versions version
    where version.question_id = p_question_id
      and version.status = 'active'
    order by version.version_number desc
    limit 1;

    if active_version_id is null then
      raise exception 'active questions require an active version'
        using errcode = '23514';
    end if;

    perform internal.assert_active_question_version_ready(active_version_id);
  end if;
end;
$$;


ALTER FUNCTION "internal"."assert_active_question_ready"("p_question_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_active_question_version_ready"("p_question_version_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  version_row record;
  localized_locale_count integer;
  answer_kind_count integer;
begin
  select
    version.id as question_version_id,
    version.status as question_version_status,
    question.id as question_id,
    question.status as question_status,
    collection.id as collection_id,
    collection.kind as collection_kind,
    collection.status as collection_status
  into version_row
  from public.question_versions version
  join public.questions question
    on question.id = version.question_id
  join public.question_collections collection
    on collection.id = question.collection_id
  where version.id = p_question_version_id;

  if not found then
    return;
  end if;

  select count(*)
  into answer_kind_count
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = p_question_version_id;

  if answer_kind_count > 2 then
    raise exception 'question versions can have at most two answer kinds'
      using errcode = '23514';
  end if;

  if version_row.collection_status = 'active'
    and version_row.question_status = 'active'
    and version_row.question_version_status = 'active' then
    select count(*)
    into localized_locale_count
    from public.question_version_localizations localization
    where localization.question_version_id = p_question_version_id
      and localization.locale in ('en', 'nb');

    if localized_locale_count <> 2 then
      raise exception 'active question versions require en and nb localizations'
        using errcode = '23514';
    end if;

    if answer_kind_count < 1 then
      raise exception 'active question versions require at least one answer kind'
        using errcode = '23514';
    end if;
  end if;
end;
$$;


ALTER FUNCTION "internal"."assert_active_question_version_ready"("p_question_version_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_conversation_thread_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = new.couple_id
      and member.user_id = new.created_by_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'thread creator must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_conversation_thread_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_answer_media_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  answer_row public.daily_question_answers%rowtype;
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  asset_row public.media_assets%rowtype;
  required_answer_kind text;
begin
  select *
  into answer_row
  from public.daily_question_answers
  where id = new.answer_id;

  select *
  into instance_row
  from public.daily_question_instances
  where id = answer_row.instance_id;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  select *
  into asset_row
  from public.media_assets
  where id = new.media_asset_id;

  required_answer_kind = case asset_row.media_type
    when 'image' then 'photo'
    when 'voice' then 'voice'
    else null
  end;

  if answer_row.id is null
    or instance_row.id is null
    or couple_day_row.id is null
    or asset_row.id is null
    or required_answer_kind is null
    or asset_row.owner_user_id <> answer_row.user_id
    or asset_row.couple_id <> couple_day_row.couple_id
    or asset_row.reserved_parent_kind <> 'daily_answer_media'
    or asset_row.reserved_parent_id <> answer_row.id
    or asset_row.upload_purpose not in ('daily_answer_media', 'voice_note')
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'daily answer media asset is not usable for this answer'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.question_answer_kinds answer_kind
    where answer_kind.question_version_id = instance_row.question_version_id
      and answer_kind.answer_kind = required_answer_kind
  ) then
    raise exception 'media answer kind is not allowed for this question'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_answer_media_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_answer_partner_choice_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.daily_question_answers answer
  join public.daily_question_instances instance
    on instance.id = answer.instance_id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join public.question_answer_kinds answer_kind
    on answer_kind.question_version_id = instance.question_version_id
  where answer.id = new.answer_id
    and answer_kind.answer_kind = 'partner_choice';

  if resolved_couple_id is null then
    raise exception 'partner choice answers are not allowed for this question'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.selected_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'partner choice must select an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_answer_partner_choice_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_answer_text_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not exists (
    select 1
    from public.daily_question_answers answer
    join public.daily_question_instances instance
      on instance.id = answer.instance_id
    join public.question_answer_kinds answer_kind
      on answer_kind.question_version_id = instance.question_version_id
    where answer.id = new.answer_id
      and answer_kind.answer_kind = 'text'
  ) then
    raise exception 'text answers are not allowed for this question'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_answer_text_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_challenge_member"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.couple_days couple_day
  where couple_day.id = new.couple_day_id;

  if resolved_couple_id is null or not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'daily challenge user must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_challenge_member"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_question_answer_member"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.daily_question_instances instance
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  where instance.id = new.instance_id;

  if resolved_couple_id is null or not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'daily answer user must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_question_answer_member"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_question_instance_member"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  select couple_day.couple_id
  into resolved_couple_id
  from public.couple_days couple_day
  where couple_day.id = new.couple_day_id;

  if resolved_couple_id is null or not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = resolved_couple_id
      and member.user_id = new.seeded_for_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'daily question instance user must be an active couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_question_instance_member"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_question_shuffle_valid"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_day_row public.couple_days%rowtype;
  skipped_row public.daily_question_instances%rowtype;
  replacement_row public.daily_question_instances%rowtype;
  skipped_question_id uuid;
begin
  select *
  into couple_day_row
  from public.couple_days
  where id = new.couple_day_id;

  select *
  into skipped_row
  from public.daily_question_instances
  where id = new.skipped_instance_id;

  select *
  into replacement_row
  from public.daily_question_instances
  where id = new.replacement_instance_id;

  select version.question_id
  into skipped_question_id
  from public.question_versions version
  where version.id = skipped_row.question_version_id;

  if couple_day_row.id is null
    or couple_day_row.couple_id <> new.couple_id
    or skipped_row.id is null
    or replacement_row.id is null
    or skipped_row.couple_day_id <> new.couple_day_id
    or replacement_row.couple_day_id <> new.couple_day_id
    or skipped_row.seeded_for_user_id <> new.user_id
    or replacement_row.seeded_for_user_id <> new.user_id
    or skipped_row.slot_number <> new.slot_number
    or replacement_row.slot_number <> new.slot_number
    or skipped_question_id <> new.question_id then
    raise exception 'daily question shuffle rows must match skipped and replacement instances'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_question_shuffle_valid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_daily_question_thread_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  thread_row public.conversation_threads%rowtype;
  instance_couple_id uuid;
begin
  select *
  into thread_row
  from public.conversation_threads
  where id = new.thread_id;

  if not found then
    raise exception 'thread was not found'
      using errcode = '23503';
  end if;

  if thread_row.kind <> 'daily_question' then
    raise exception 'daily question thread must use daily_question kind'
      using errcode = '23514';
  end if;

  select couple_day.couple_id
  into instance_couple_id
  from public.daily_question_instances instance
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  where instance.id = new.instance_id;

  if instance_couple_id is null then
    raise exception 'daily question instance was not found'
      using errcode = '23503';
  end if;

  if instance_couple_id <> thread_row.couple_id then
    raise exception 'daily question thread couple mismatch'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_daily_question_thread_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_memory_media_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  memory_row public.memories%rowtype;
  asset_row public.media_assets%rowtype;
begin
  select *
  into memory_row
  from public.memories
  where id = new.memory_id;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible' then
    raise exception 'visible memory was not found for media attachment'
      using errcode = '23503';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.media_asset_id;

  if not found
    or asset_row.owner_user_id <> new.owner_user_id
    or asset_row.couple_id <> memory_row.couple_id
    or asset_row.reserved_parent_kind <> 'memory_media'
    or asset_row.reserved_parent_id <> new.id
    or asset_row.upload_purpose not in ('memory_photo', 'voice_note')
    or asset_row.media_type not in ('image', 'voice')
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'memory media asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_memory_media_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_memory_member_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not exists (
    select 1
    from public.couple_members created_member
    join public.couple_members edited_member
      on edited_member.couple_id = created_member.couple_id
    join public.couples couple
      on couple.id = created_member.couple_id
    where created_member.couple_id = new.couple_id
      and created_member.user_id = new.created_by_user_id
      and created_member.status = 'active'
      and edited_member.user_id = new.last_edited_by_user_id
      and edited_member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'memory users must be active couple members'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_memory_member_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_memory_note_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not exists (
    select 1
    from public.memories memory
    join public.couple_members member
      on member.couple_id = memory.couple_id
    join public.couples couple
      on couple.id = memory.couple_id
    where memory.id = new.memory_id
      and memory.deleted_at is null
      and memory.moderation_status = 'visible'
      and member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'memory note user must be an active memory couple member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_memory_note_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_memory_thread_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  thread_kind text;
begin
  select thread.kind
  into thread_kind
  from public.conversation_threads thread
  where thread.id = new.thread_id;

  if thread_kind is null then
    raise exception 'thread was not found'
      using errcode = '23503';
  end if;

  if thread_kind <> 'memory' then
    raise exception 'memory thread must use memory kind'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_memory_thread_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_notification_payload_safe"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not internal.notification_payload_is_safe(new.payload) then
    raise exception 'notification payload contains sensitive or unsupported fields'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_notification_payload_safe"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_pairing_invite_attempt_allowed"("p_user_id" "uuid", "p_code_hash_prefix" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if exists (
    select 1
    from internal.pairing_invite_attempts attempt
    where attempt.user_id = p_user_id
      and attempt.attempted_at > now() - interval '10 minutes'
    group by attempt.user_id
    having count(*) >= 30
  ) then
    raise exception 'too many invite attempts'
      using errcode = '53300';
  end if;

  if exists (
    select 1
    from internal.pairing_invite_attempts attempt
    where attempt.user_id = p_user_id
      and attempt.code_hash_prefix = p_code_hash_prefix
      and attempt.success = false
      and attempt.attempted_at > now() - interval '10 minutes'
    group by attempt.user_id, attempt.code_hash_prefix
    having count(*) >= 10
  ) then
    raise exception 'too many invite attempts for this code'
      using errcode = '53300';
  end if;
end;
$$;


ALTER FUNCTION "internal"."assert_pairing_invite_attempt_allowed"("p_user_id" "uuid", "p_code_hash_prefix" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_profile_photo_asset_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  asset_row public.media_assets%rowtype;
  candidate_asset_id uuid;
begin
  if new.deleted_at is not null then
    new.profile_photo_asset_id = null;
    new.provider_profile_photo_asset_id = null;
    new.provider_profile_photo_source = null;
    return new;
  end if;

  if (new.provider_profile_photo_asset_id is null)
    <> (new.provider_profile_photo_source is null) then
    raise exception 'provider profile photo asset and source must be set together'
      using errcode = '23514';
  end if;

  if new.provider_profile_photo_source is not null
    and new.provider_profile_photo_source <> 'google' then
    raise exception 'provider profile photo source is not supported'
      using errcode = '23514';
  end if;

  foreach candidate_asset_id in array array[
    new.profile_photo_asset_id,
    new.provider_profile_photo_asset_id
  ]
  loop
    if candidate_asset_id is null then
      continue;
    end if;

    select *
    into asset_row
    from public.media_assets
    where id = candidate_asset_id;

    if not found then
      raise exception 'profile photo asset was not found'
        using errcode = '23503';
    end if;

    if asset_row.owner_user_id <> new.user_id
      or asset_row.bucket <> 'profile-photos'
      or asset_row.media_type <> 'image'
      or asset_row.upload_status <> 'finalized'
      or asset_row.storage_delete_status <> 'none'
      or asset_row.moderation_status <> 'visible'
      or asset_row.deleted_at is not null then
      raise exception 'profile photo asset is not usable'
        using errcode = '23514';
    end if;
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_profile_photo_asset_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_question_collection_ready_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if tg_op = 'DELETE' then
    perform internal.assert_active_question_collection_ready(old.id);
  else
    perform internal.assert_active_question_collection_ready(new.id);
  end if;

  return null;
end;
$$;


ALTER FUNCTION "internal"."assert_question_collection_ready_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_question_ready_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if tg_op = 'DELETE' then
    perform internal.assert_active_question_collection_ready(old.collection_id);
    return null;
  end if;

  perform internal.assert_active_question_ready(new.id);

  if new.collection_id is not null then
    perform internal.assert_active_question_collection_ready(new.collection_id);
  end if;

  if tg_op = 'UPDATE'
    and old.collection_id is not null
    and old.collection_id is distinct from new.collection_id then
    perform internal.assert_active_question_collection_ready(old.collection_id);
  end if;

  return null;
end;
$$;


ALTER FUNCTION "internal"."assert_question_ready_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_question_version_child_ready_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_question_id uuid;
  resolved_question_version_id uuid;
begin
  if tg_op = 'DELETE' then
    resolved_question_version_id = old.question_version_id;
  else
    resolved_question_version_id = new.question_version_id;
  end if;

  perform internal.assert_active_question_version_ready(resolved_question_version_id);

  select version.question_id
  into resolved_question_id
  from public.question_versions version
  where version.id = resolved_question_version_id;

  if resolved_question_id is not null then
    perform internal.assert_active_question_ready(resolved_question_id);
  end if;

  return null;
end;
$$;


ALTER FUNCTION "internal"."assert_question_version_child_ready_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_question_version_ready_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if tg_op = 'DELETE' then
    perform internal.assert_active_question_ready(old.question_id);
    return null;
  end if;

  perform internal.assert_active_question_version_ready(new.id);

  if new.question_id is not null then
    perform internal.assert_active_question_ready(new.question_id);
  end if;

  if tg_op = 'UPDATE'
    and old.question_id is not null
    and old.question_id is distinct from new.question_id then
    perform internal.assert_active_question_ready(old.question_id);
  end if;

  return null;
end;
$$;


ALTER FUNCTION "internal"."assert_question_version_ready_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_relationship_block_pair_members"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  pair_low_user_id uuid;
  pair_high_user_id uuid;
begin
  select user_low_id, user_high_id
  into pair_low_user_id, pair_high_user_id
  from public.relationship_pairs
  where id = new.pair_id;

  if not found then
    raise exception 'relationship pair not found'
      using errcode = '23503';
  end if;

  if not (
    new.blocked_by_user_id in (pair_low_user_id, pair_high_user_id)
    and new.blocked_user_id in (pair_low_user_id, pair_high_user_id)
    and new.blocked_by_user_id <> new.blocked_user_id
  ) then
    raise exception 'relationship block users must match the pair'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_relationship_block_pair_members"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_thread_message_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not exists (
    select 1
    from public.conversation_threads thread
    join public.couple_members member
      on member.couple_id = thread.couple_id
    join public.couples couple
      on couple.id = thread.couple_id
    where thread.id = new.thread_id
      and thread.deleted_at is null
      and thread.moderation_status = 'visible'
      and member.user_id = new.sender_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'message sender must be an active visible thread member'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_thread_message_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_thread_message_media_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  message_row public.thread_messages%rowtype;
  thread_row public.conversation_threads%rowtype;
  asset_row public.media_assets%rowtype;
begin
  select *
  into message_row
  from public.thread_messages
  where id = new.message_id;

  if not found then
    raise exception 'thread message was not found'
      using errcode = '23503';
  end if;

  select *
  into thread_row
  from public.conversation_threads
  where id = message_row.thread_id;

  if not found then
    raise exception 'conversation thread was not found'
      using errcode = '23503';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.media_asset_id;

  if not found
    or asset_row.owner_user_id <> message_row.sender_user_id
    or asset_row.couple_id <> thread_row.couple_id
    or asset_row.reserved_parent_kind <> 'thread_message_media'
    or asset_row.reserved_parent_id <> new.message_id
    or asset_row.upload_purpose not in ('thread_media', 'voice_note')
    or asset_row.media_type not in ('image', 'voice')
    or asset_row.upload_status <> 'finalized'
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'thread message media asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_thread_message_media_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_widget_canvas_active_revision_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if new.active_revision_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.widget_drawing_revisions revision
    where revision.id = new.active_revision_id
      and revision.canvas_id = new.id
      and revision.deleted_at is null
      and revision.moderation_status = 'visible'
  ) then
    raise exception 'active widget revision must be a visible revision for the same canvas'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_widget_canvas_active_revision_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_widget_canvas_couple_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if not exists (
    select 1
    from public.couples couple
    where couple.id = new.couple_id
      and couple.status = 'active'
  ) then
    raise exception 'widget canvas requires an active couple'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_widget_canvas_couple_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."assert_widget_drawing_revision_allowed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  canvas_row public.widget_canvases%rowtype;
  parent_canvas_id uuid;
  asset_row public.media_assets%rowtype;
  expected_storage_path text;
begin
  select *
  into canvas_row
  from public.widget_canvases
  where id = new.canvas_id;

  if not found
    or canvas_row.deleted_at is not null
    or not internal.can_access_couple_content(canvas_row.couple_id) then
    raise exception 'active entitled widget canvas access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = canvas_row.couple_id
      and member.user_id = new.author_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'widget revision author must be an active couple member'
      using errcode = '23514';
  end if;

  if new.parent_revision_id is not null then
    select parent.canvas_id
    into parent_canvas_id
    from public.widget_drawing_revisions parent
    where parent.id = new.parent_revision_id;

    if parent_canvas_id is distinct from new.canvas_id then
      raise exception 'parent widget revision must belong to the same canvas'
        using errcode = '23514';
    end if;
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = new.payload_media_asset_id;

  expected_storage_path = canvas_row.couple_id::text || '/'
    || new.canvas_id::text
    || '/revisions/'
    || new.id::text
    || '/drawing.pkdrawing';

  if not found
    or asset_row.owner_user_id <> new.author_user_id
    or asset_row.couple_id <> canvas_row.couple_id
    or asset_row.reserved_parent_kind <> 'widget_drawing_revision'
    or asset_row.reserved_parent_id <> new.id
    or asset_row.bucket <> 'widget-drawings'
    or asset_row.storage_path <> expected_storage_path
    or asset_row.media_type <> 'drawing_payload'
    or asset_row.upload_purpose <> 'widget_drawing_payload'
    or asset_row.expected_media_type <> 'drawing_payload'
    or asset_row.expected_bucket <> 'widget-drawings'
    or asset_row.upload_status <> 'finalized'
    or asset_row.upload_finalized_at is null
    or asset_row.byte_size <> new.payload_bytes
    or asset_row.byte_size > 2097152
    or asset_row.sha256 is null
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'widget drawing payload asset is not usable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."assert_widget_drawing_revision_allowed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"[]
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  media_ids uuid[];
  inserted_media_ids uuid[];
  request_hash bytea;
  replayed_response jsonb;
begin
  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);

  if cardinality(media_ids) = 0 then
    raise exception 'memory media asset ids are required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'attach_memory_media',
      p_memory_id::text,
      media_ids::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'attach_memory_media',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return (
      select coalesce(array_agg(value::uuid order by ordinality), array[]::uuid[])
      from jsonb_array_elements_text(replayed_response -> 'memory_media_ids')
        with ordinality as values(value, ordinality)
    );
  end if;

  inserted_media_ids = internal.attach_memory_media_assets(p_memory_id, media_ids);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('memory_media_ids', inserted_media_ids)
  );

  return inserted_media_ids;
end;
$$;


ALTER FUNCTION "internal"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."attach_memory_media_assets"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[]) RETURNS "uuid"[]
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  media_ids uuid[];
  media_count integer;
  unique_media_count integer;
  active_image_count integer;
  next_sort_order smallint;
  inserted_media_ids uuid[] := array[]::uuid[];
  media_row record;
  asset_row public.media_assets%rowtype;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);
  media_count = cardinality(media_ids);

  if media_count = 0 then
    return inserted_media_ids;
  end if;

  if media_count > 10 then
    raise exception 'a memory can attach at most 10 media assets at once'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from unnest(media_ids) as media_id(id)
    where media_id.id is null
  ) then
    raise exception 'memory media asset id cannot be null'
      using errcode = '23514';
  end if;

  select count(distinct media_id.id)
  into unique_media_count
  from unnest(media_ids) as media_id(id);

  if unique_media_count <> media_count then
    raise exception 'memory media asset ids must be unique'
      using errcode = '23514';
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'memory_media:' || p_memory_id::text || ':' || current_user_id::text,
      0
    )
  );

  select count(*)
  into active_image_count
  from public.memory_media memory_media
  join public.media_assets asset
    on asset.id = memory_media.media_asset_id
  where memory_media.memory_id = p_memory_id
    and memory_media.owner_user_id = current_user_id
    and memory_media.deleted_at is null
    and memory_media.moderation_status = 'visible'
    and asset.media_type = 'image'
    and asset.deleted_at is null
    and asset.moderation_status = 'visible';

  select coalesce(max(memory_media.sort_order), 0)::smallint + 1
  into next_sort_order
  from public.memory_media memory_media
  where memory_media.memory_id = p_memory_id
    and memory_media.owner_user_id = current_user_id
    and memory_media.deleted_at is null;

  for media_row in
    select
      media_item.value as media_asset_id,
      media_item.ordinality::smallint as ordinal_position
    from unnest(media_ids) with ordinality as media_item(value, ordinality)
  loop
    select *
    into asset_row
    from public.media_assets
    where id = media_row.media_asset_id
    for update;

    if not found
      or asset_row.owner_user_id <> current_user_id
      or asset_row.couple_id <> memory_row.couple_id
      or asset_row.reserved_parent_kind <> 'memory_media'
      or asset_row.upload_purpose not in ('memory_photo', 'voice_note')
      or asset_row.media_type not in ('image', 'voice')
      or asset_row.upload_status <> 'finalized'
      or asset_row.storage_delete_status <> 'none'
      or asset_row.moderation_status <> 'visible'
      or asset_row.deleted_at is not null then
      raise exception 'memory media asset is not usable'
        using errcode = '23514';
    end if;

    if asset_row.media_type = 'image' then
      active_image_count = active_image_count + 1;

      if active_image_count > 5 then
        raise exception 'each partner can add at most 5 photos to a memory'
          using errcode = '23514';
      end if;
    end if;

    insert into public.memory_media (
      id,
      memory_id,
      media_asset_id,
      owner_user_id,
      sort_order
    ) values (
      asset_row.reserved_parent_id,
      memory_row.id,
      asset_row.id,
      current_user_id,
      next_sort_order + media_row.ordinal_position - 1
    );

    inserted_media_ids = array_append(inserted_media_ids, asset_row.reserved_parent_id);
  end loop;

  return inserted_media_ids;
end;
$$;


ALTER FUNCTION "internal"."attach_memory_media_assets"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."auth_metadata_display_name"("raw_user_meta_data" "jsonb") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'pg_catalog'
    AS $$
  select left(
    nullif(
      btrim(
        coalesce(
          raw_user_meta_data ->> 'display_name',
          raw_user_meta_data ->> 'full_name',
          raw_user_meta_data ->> 'name',
          ''
        )
      ),
      ''
    ),
    80
  );
$$;


ALTER FUNCTION "internal"."auth_metadata_display_name"("raw_user_meta_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."begin_client_operation"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_operation_kind" "text", "p_idempotency_scope" "text", "p_request_hash" "bytea") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  operation_row internal.client_operations%rowtype;
  inserted_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_client_operation_id is null or p_client_id is null then
    raise exception 'client operation identifiers are required'
      using errcode = '23514';
  end if;

  insert into internal.client_operations (
    user_id,
    client_operation_id,
    client_id,
    client_sequence,
    local_created_at,
    operation_kind,
    idempotency_scope,
    request_hash
  ) values (
    current_user_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_operation_kind,
    p_idempotency_scope,
    p_request_hash
  )
  on conflict (user_id, client_operation_id) do nothing;

  get diagnostics inserted_rows = row_count;

  select *
  into operation_row
  from internal.client_operations
  where user_id = current_user_id
    and client_operation_id = p_client_operation_id
  for update;

  if operation_row.request_hash <> p_request_hash then
    raise exception 'client operation replay hash mismatch'
      using errcode = '23505';
  end if;

  if operation_row.status = 'succeeded' then
    return operation_row.stored_response;
  end if;

  if inserted_rows = 0 then
    raise exception 'client operation is already in progress'
      using errcode = '55P03';
  end if;

  if operation_row.status <> 'started' then
    raise exception 'client operation cannot be replayed'
      using errcode = '23505';
  end if;

  return null;
end;
$$;


ALTER FUNCTION "internal"."begin_client_operation"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_operation_kind" "text", "p_idempotency_scope" "text", "p_request_hash" "bytea") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."block_relationship"("p_blocked_user_id" "uuid", "p_source_report_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_pair_id uuid;
  relationship_block_id uuid;
  valid_source_report_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_blocked_user_id is null or p_blocked_user_id = current_user_id then
    raise exception 'blocked user must be a different user'
      using errcode = '23514';
  end if;

  select couple.pair_id
  into resolved_pair_id
  from public.couple_members self_member
  join public.couple_members blocked_member
    on blocked_member.couple_id = self_member.couple_id
    and blocked_member.user_id = p_blocked_user_id
  join public.couples couple
    on couple.id = self_member.couple_id
  where self_member.user_id = current_user_id
    and (
      couple.status = 'active'
      or (couple.status = 'ended' and couple.delete_after > now())
    )
  order by
    case when couple.status = 'active' then 0 else 1 end,
    couple.created_at desc
  limit 1;

  if resolved_pair_id is null then
    raise exception 'blocked user must be a current or recently ended partner'
      using errcode = '42501';
  end if;

  if p_source_report_id is not null then
    select report.id
    into valid_source_report_id
    from public.content_reports report
    where report.id = p_source_report_id
      and report.reporter_user_id = current_user_id
      and report.reported_user_id = p_blocked_user_id
      and report.pair_id = resolved_pair_id;

    if valid_source_report_id is null then
      raise exception 'source report does not belong to this block'
        using errcode = '42501';
    end if;
  end if;

  insert into public.relationship_blocks (
    pair_id,
    blocked_by_user_id,
    blocked_user_id,
    source_report_id
  ) values (
    resolved_pair_id,
    current_user_id,
    p_blocked_user_id,
    p_source_report_id
  )
  on conflict (pair_id, blocked_by_user_id, blocked_user_id)
    where revoked_at is null
  do update set source_report_id = coalesce(public.relationship_blocks.source_report_id, excluded.source_report_id)
  returning id into relationship_block_id;

  if p_source_report_id is not null then
    insert into internal.pair_safety_warning_flags (pair_id, source_report_id)
    values (resolved_pair_id, p_source_report_id)
    on conflict (pair_id, source_report_id)
      where source_report_id is not null
    do nothing;
  end if;

  perform internal.end_relationship_for_pair(resolved_pair_id, current_user_id, 'blocked');

  return relationship_block_id;
end;
$$;


ALTER FUNCTION "internal"."block_relationship"("p_blocked_user_id" "uuid", "p_source_report_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."bump_revision"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  new.revision = old.revision + 1;
  return new;
end;
$$;


ALTER FUNCTION "internal"."bump_revision"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."can_access_couple_content"("p_couple_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.is_active_entitled_couple_member(p_couple_id);
$$;


ALTER FUNCTION "internal"."can_access_couple_content"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."can_access_visible_memory"("p_memory_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.memories memory
    where memory.id = p_memory_id
      and memory.deleted_at is null
      and memory.moderation_status = 'visible'
      and internal.can_access_couple_content(memory.couple_id)
  );
$$;


ALTER FUNCTION "internal"."can_access_visible_memory"("p_memory_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."can_read_media_object"("p_bucket" "text", "p_storage_path" "text") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.media_assets asset
    where asset.bucket = p_bucket
      and asset.storage_path = p_storage_path
      and asset.bucket <> 'report-snapshots'
      and asset.upload_status = 'finalized'
      and asset.upload_finalized_at is not null
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
      and (
        (
          asset.bucket = 'profile-photos'
          and asset.couple_id is null
          and asset.reserved_parent_kind = 'profile_photo'
          and (
            asset.owner_user_id = (select auth.uid())
            or exists (
              select 1
              from public.profiles profile
              join public.couple_members owner_member
                on owner_member.user_id = profile.user_id
              join public.couple_members viewer_member
                on viewer_member.couple_id = owner_member.couple_id
              join public.couples couple
                on couple.id = viewer_member.couple_id
              where (
                  profile.profile_photo_asset_id = asset.id
                  or profile.provider_profile_photo_asset_id = asset.id
                )
                and profile.user_id = asset.owner_user_id
                and profile.moderation_status = 'visible'
                and profile.deleted_at is null
                and owner_member.status = 'active'
                and viewer_member.user_id = (select auth.uid())
                and viewer_member.status = 'active'
                and couple.status = 'active'
                and internal.can_access_couple_content(couple.id)
            )
          )
        )
        or (
          asset.reserved_parent_kind = 'daily_answer_media'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.daily_answer_media answer_media
            join public.daily_question_answers answer
              on answer.id = answer_media.answer_id
            where answer_media.media_asset_id = asset.id
              and internal.can_view_daily_answer(answer.id)
          )
        )
        or (
          asset.reserved_parent_kind = 'thread_message_media'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.thread_message_media message_media
            join public.thread_messages message
              on message.id = message_media.message_id
            join public.conversation_threads thread
              on thread.id = message.thread_id
            where message_media.media_asset_id = asset.id
              and asset.reserved_parent_id = message.id
              and message.deleted_at is null
              and message.moderation_status = 'visible'
              and thread.deleted_at is null
              and thread.moderation_status = 'visible'
              and thread.couple_id = asset.couple_id
              and internal.can_access_couple_content(thread.couple_id)
              and (
                thread.kind <> 'memory'
                or exists (
                  select 1
                  from public.memory_threads parent_memory_thread
                  join public.memories memory
                    on memory.id = parent_memory_thread.memory_id
                  where parent_memory_thread.thread_id = thread.id
                    and memory.deleted_at is null
                    and memory.moderation_status = 'visible'
                )
              )
          )
        )
        or (
          asset.reserved_parent_kind = 'memory_media'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.memory_media memory_media
            join public.memories memory
              on memory.id = memory_media.memory_id
            where memory_media.media_asset_id = asset.id
              and asset.reserved_parent_id = memory_media.id
              and memory_media.deleted_at is null
              and memory_media.moderation_status = 'visible'
              and memory.deleted_at is null
              and memory.moderation_status = 'visible'
              and memory.couple_id = asset.couple_id
              and internal.can_access_couple_content(memory.couple_id)
          )
        )
        or (
          asset.reserved_parent_kind = 'widget_drawing_revision'
          and asset.bucket = 'widget-drawings'
          and asset.couple_id is not null
          and exists (
            select 1
            from public.widget_drawing_revisions revision
            join public.widget_canvases canvas
              on canvas.id = revision.canvas_id
            where revision.payload_media_asset_id = asset.id
              and asset.reserved_parent_id = revision.id
              and revision.deleted_at is null
              and revision.moderation_status = 'visible'
              and canvas.deleted_at is null
              and canvas.couple_id = asset.couple_id
              and internal.can_access_couple_content(canvas.couple_id)
          )
        )
      )
  );
$$;


ALTER FUNCTION "internal"."can_read_media_object"("p_bucket" "text", "p_storage_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."can_report_relationship_content"("p_couple_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."can_report_relationship_content"("p_couple_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."can_upload_reserved_media_object"("p_bucket" "text", "p_storage_path" "text") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.media_assets asset
    where asset.bucket = p_bucket
      and asset.storage_path = p_storage_path
      and asset.bucket <> 'report-snapshots'
      and asset.owner_user_id = (select auth.uid())
      and asset.upload_status = 'pending'
      and asset.upload_expires_at > now()
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
      and (
        asset.couple_id is null
        or internal.can_access_couple_content(asset.couple_id)
      )
  );
$$;


ALTER FUNCTION "internal"."can_upload_reserved_media_object"("p_bucket" "text", "p_storage_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."can_view_daily_answer"("p_answer_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.daily_question_answers target_answer
    join public.daily_question_instances instance
      on instance.id = target_answer.instance_id
    join public.couple_days couple_day
      on couple_day.id = instance.couple_day_id
    where target_answer.id = p_answer_id
      and target_answer.deleted_at is null
      and target_answer.moderation_status = 'visible'
      and internal.can_access_couple_content(couple_day.couple_id)
      and (
        target_answer.user_id = (select auth.uid())
        or exists (
          select 1
          from public.daily_question_answers viewer_answer
          where viewer_answer.instance_id = target_answer.instance_id
            and viewer_answer.user_id = (select auth.uid())
            and viewer_answer.deleted_at is null
            and viewer_answer.moderation_status = 'visible'
        )
      )
  );
$$;


ALTER FUNCTION "internal"."can_view_daily_answer"("p_answer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_account_deletion_jobs"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 10, "p_retry_after" interval DEFAULT '00:05:00'::interval, "p_max_attempts" integer DEFAULT 10, "p_job_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("job_id" "uuid", "request_id" "uuid", "user_id" "uuid", "auth_provider" "text", "provider_revocation_status" "text", "auth_delete_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if p_limit not between 1 and 100 then
    raise exception 'invalid account deletion claim limit'
      using errcode = '23514';
  end if;

  if p_retry_after < interval '30 seconds'
     or p_retry_after > interval '1 day' then
    raise exception 'invalid account deletion retry interval'
      using errcode = '23514';
  end if;

  if p_max_attempts not between 1 and 100 then
    raise exception 'invalid account deletion max attempts'
      using errcode = '23514';
  end if;

  return query
  with claimable as (
    select job.id
    from internal.account_deletion_jobs job
    where (p_job_id is null or job.id = p_job_id)
      and job.auth_delete_attempts < p_max_attempts
      and (
        (
          job.status = 'ready_for_auth_delete'
          and (
            p_job_id is not null
            or (
              job.next_attempt_at is not null
              and job.next_attempt_at <= p_now
            )
          )
        )
        or (
          job.status = 'processing_auth_delete'
          and job.claimed_at <= p_now - p_retry_after
        )
      )
    order by job.next_attempt_at nulls first, job.id
    limit p_limit
    for update skip locked
  )
  update internal.account_deletion_jobs job
  set
    status = 'processing_auth_delete',
    claimed_at = p_now,
    auth_delete_attempts = job.auth_delete_attempts + 1,
    last_auth_delete_error_code = null
  from claimable
  where job.id = claimable.id
  returning
    job.id,
    job.request_id,
    job.user_id,
    job.auth_provider,
    job.provider_revocation_status,
    job.auth_delete_attempts;
end;
$$;


ALTER FUNCTION "internal"."claim_account_deletion_jobs"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer, "p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_due_notifications"("p_limit" integer DEFAULT 100) RETURNS TABLE("outbox_id" "uuid", "recipient_user_id" "uuid", "target_device_id" "uuid", "push_token" "text", "push_token_hash" "bytea", "apns_environment" "text", "kind" "text", "payload_version" integer, "redaction_level" "text", "payload" "jsonb", "apns_push_type" "text", "apns_collapse_id" "text", "attempt_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'notification claim limit is out of range'
      using errcode = '23514';
  end if;

  update internal.notification_outbox outbox
  set
    failed_at = now(),
    last_attempt_at = now(),
    last_error = 'notification target is no longer eligible'
  from public.user_devices device
  left join public.notification_preferences preference
    on preference.user_id = device.user_id
  where outbox.target_device_id = device.id
    and outbox.scheduled_for <= now()
    and outbox.sent_at is null
    and outbox.failed_at is null
    and (
      device.disabled_at is not null
      or not coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then preference.widget_updates_enabled
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          when 'thread_message_sent' then preference.messages_enabled
          else true
        end,
        false
      )
    );

  return query
  with picked as (
    select outbox.id
    from internal.notification_outbox outbox
    join public.user_devices device
      on device.id = outbox.target_device_id
    left join public.notification_preferences preference
      on preference.user_id = device.user_id
    where outbox.scheduled_for <= now()
      and outbox.sent_at is null
      and outbox.failed_at is null
      and device.disabled_at is null
      and coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then preference.widget_updates_enabled
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          when 'thread_message_sent' then preference.messages_enabled
          else true
        end,
        false
      )
    order by outbox.scheduled_for, outbox.created_at, outbox.id
    for update of outbox skip locked
    limit p_limit
  ),
  claimed as (
    update internal.notification_outbox outbox
    set
      attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now(),
      last_error = null
    from picked
    where outbox.id = picked.id
    returning outbox.*
  )
  select
    claimed.id,
    claimed.recipient_user_id,
    claimed.target_device_id,
    device.push_token,
    claimed.push_token_hash,
    claimed.apns_environment,
    claimed.kind,
    claimed.payload_version,
    claimed.redaction_level,
    claimed.payload,
    claimed.apns_push_type,
    claimed.apns_collapse_id,
    claimed.attempt_count
  from claimed
  join public.user_devices device
    on device.id = claimed.target_device_id
  where device.disabled_at is null;
end;
$$;


ALTER FUNCTION "internal"."claim_due_notifications"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_expired_pending_uploads"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100) RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "storage_delete_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."claim_expired_pending_uploads"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_media_storage_deletes"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100, "p_retry_after" interval DEFAULT '00:15:00'::interval, "p_max_attempts" integer DEFAULT 5) RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "storage_delete_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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
      and not internal.media_asset_has_live_reference(asset.id)
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


ALTER FUNCTION "internal"."claim_media_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_notification_batch"("p_limit" integer DEFAULT 50) RETURNS TABLE("outbox_id" "uuid", "target_device_id" "uuid", "push_token" "text", "apns_environment" "text", "apns_push_type" "text", "apns_collapse_id" "text", "title" "text", "body" "text", "payload" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.fail_exhausted_notification_claims();

  update internal.notification_outbox outbox
  set
    failed_at = now(),
    last_attempt_at = now(),
    last_error = 'notification target is no longer eligible'
  from public.user_devices device
  left join public.notification_preferences preference
    on preference.user_id = device.user_id
  where outbox.target_device_id = device.id
    and outbox.scheduled_for <= now()
    and outbox.sent_at is null
    and outbox.failed_at is null
    and (
      device.disabled_at is not null
      or not coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then (outbox.apns_push_type <> 'alert' or preference.widget_updates_enabled)
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          when 'thread_message_sent' then preference.messages_enabled
          else true
        end,
        false
      )
    );

  return query
  with claimed as (
    select outbox.id, outbox.target_device_id
    from internal.notification_outbox outbox
    join public.user_devices device
      on device.id = outbox.target_device_id
    left join public.notification_preferences preference
      on preference.user_id = device.user_id
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      and device.disabled_at is null
      and coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then (outbox.apns_push_type <> 'alert' or preference.widget_updates_enabled)
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          when 'thread_message_sent' then preference.messages_enabled
          else true
        end,
        false
      )
    order by outbox.scheduled_for, outbox.created_at, outbox.id
    for update of outbox skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.notification_outbox outbox
  set attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now(),
      last_error = null,
      -- Lease: a concurrent drain skips this row until the lease elapses, so a
      -- failed send still retries after 30s but cannot be double-sent meanwhile.
      scheduled_for = now() + interval '30 seconds'
  from claimed
  join public.user_devices device
    on device.id = claimed.target_device_id
  where outbox.id = claimed.id
  returning
    outbox.id,
    outbox.target_device_id,
    device.push_token,
    outbox.apns_environment,
    outbox.apns_push_type,
    outbox.apns_collapse_id,
    outbox.title,
    outbox.body,
    outbox.payload;
end;
$$;


ALTER FUNCTION "internal"."claim_notification_batch"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_report_snapshot_asset_copies"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100, "p_retry_after" interval DEFAULT '00:15:00'::interval, "p_max_attempts" integer DEFAULT 5) RETURNS TABLE("snapshot_asset_id" "uuid", "report_id" "uuid", "source_bucket" "text", "source_storage_path" "text", "destination_bucket" "text", "destination_storage_path" "text", "copy_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."claim_report_snapshot_asset_copies"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100, "p_retry_after" interval DEFAULT '00:15:00'::interval, "p_max_attempts" integer DEFAULT 5) RETURNS TABLE("snapshot_asset_id" "uuid", "report_id" "uuid", "bucket" "text", "storage_path" "text", "storage_delete_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_storekit_transactions_for_reconciliation"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100, "p_reconcile_after" interval DEFAULT '06:00:00'::interval, "p_retry_after" interval DEFAULT '00:15:00'::interval, "p_max_attempts" integer DEFAULT 10) RETURNS TABLE("transaction_id" "uuid", "user_id" "uuid", "product_id" "uuid", "environment" "text", "app_account_token" "uuid", "original_transaction_id" "text", "storekit_transaction_id" "text", "status" "text", "expires_at" timestamp with time zone, "reconciliation_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."claim_storekit_transactions_for_reconciliation"("p_now" timestamp with time zone, "p_limit" integer, "p_reconcile_after" interval, "p_retry_after" interval, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."claim_widget_push_batch"("p_limit" integer DEFAULT 50) RETURNS TABLE("outbox_id" "uuid", "target_widget_device_id" "uuid", "widget_push_token" "text", "apns_environment" "text", "apns_collapse_id" "text", "payload" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.fail_exhausted_widget_push_claims();

  return query
  with claimed as (
    select outbox.id, outbox.target_widget_device_id
    from internal.widget_push_outbox outbox
    join public.widget_push_devices device
      on device.id = outbox.target_widget_device_id
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      and device.disabled_at is null
    order by outbox.scheduled_for, outbox.id
    for update of outbox skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.widget_push_outbox outbox
  set
    attempt_count = outbox.attempt_count + 1,
    last_attempt_at = now()
  from claimed
  join public.widget_push_devices device
    on device.id = claimed.target_widget_device_id
  where outbox.id = claimed.id
  returning
    outbox.id,
    device.id,
    device.widget_push_token,
    outbox.apns_environment,
    outbox.apns_collapse_id,
    outbox.payload;
end;
$$;


ALTER FUNCTION "internal"."claim_widget_push_batch"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."cleanup_attempt_logs"("p_now" timestamp with time zone DEFAULT "now"(), "p_pairing_retention" interval DEFAULT '30 days'::interval, "p_review_retention" interval DEFAULT '30 days'::interval, "p_limit" integer DEFAULT 1000) RETURNS TABLE("pairing_attempts_deleted" integer, "review_attempts_deleted" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."cleanup_attempt_logs"("p_now" timestamp with time zone, "p_pairing_retention" interval, "p_review_retention" interval, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."cleanup_expired_relationship_content"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 25) RETURNS TABLE("couple_id" "uuid", "queued_media_count" integer, "sync_event_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."cleanup_expired_relationship_content"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."complete_client_operation"("p_client_operation_id" "uuid", "p_stored_response" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update internal.client_operations
  set
    status = 'succeeded',
    completed_at = now(),
    stored_response = p_stored_response,
    response_hash = extensions.digest(coalesce(p_stored_response, '{}'::jsonb)::text, 'sha256')
  where user_id = current_user_id
    and client_operation_id = p_client_operation_id
    and status = 'started';
end;
$$;


ALTER FUNCTION "internal"."complete_client_operation"("p_client_operation_id" "uuid", "p_stored_response" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."complete_review_access_session"("p_review_session_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update internal.review_access_sessions
  set completed_at = coalesce(completed_at, now())
  where id = p_review_session_id
    and user_id = current_user_id;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."complete_review_access_session"("p_review_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("thread_id" "uuid", "message_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  resolved_thread_id uuid;
  resolved_message_id uuid;
  visible_answer_count integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_daily_question_thread_with_message',
      p_instance_id::text,
      coalesce(nullif(btrim(coalesce(p_body, '')), ''), ''),
      coalesce(p_media_asset_ids::text, '{}')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_daily_question_thread_with_message',
    'conversation_threads',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'thread_id')::uuid,
      (replayed_response ->> 'message_id')::uuid;
    return;
  end if;

  select *
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found or instance_row.status = 'shuffled' then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.daily_question_answers answer
    where answer.instance_id = instance_row.id
      and answer.user_id = current_user_id
      and answer.deleted_at is null
      and answer.moderation_status = 'visible'
  ) then
    raise exception 'you must answer this daily question before starting its thread'
      using errcode = '42501';
  end if;

  select count(distinct answer.user_id)
  into visible_answer_count
  from public.daily_question_answers answer
  where answer.instance_id = instance_row.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible';

  if visible_answer_count < 2 then
    raise exception 'daily question thread requires both partners to answer'
      using errcode = '23514';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'daily_question_thread:' || instance_row.id::text,
      0
    )
  );

  select existing_thread.thread_id
  into resolved_thread_id
  from public.daily_question_threads existing_thread
  where existing_thread.instance_id = instance_row.id;

  if resolved_thread_id is null then
    insert into public.conversation_threads (
      couple_id,
      kind,
      created_by_user_id
    ) values (
      couple_day_row.couple_id,
      'daily_question',
      current_user_id
    )
    returning id into resolved_thread_id;

    insert into public.daily_question_threads (
      instance_id,
      thread_id
    ) values (
      instance_row.id,
      resolved_thread_id
    );
  end if;

  resolved_message_id = internal.insert_thread_message(
    resolved_thread_id,
    p_body,
    p_media_asset_ids
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'thread_id', resolved_thread_id,
      'message_id', resolved_message_id
    )
  );

  return query
  select resolved_thread_id, resolved_message_id;
end;
$$;


ALTER FUNCTION "internal"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  normalized_title text;
  normalized_note_body text;
  media_ids uuid[];
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_title = internal.normalize_memory_title(p_title);

  if p_memory_id is null then
    raise exception 'memory id is required'
      using errcode = '23514';
  end if;

  if p_memory_date is null then
    raise exception 'memory date is required'
      using errcode = '23514';
  end if;

  normalized_note_body = nullif(btrim(coalesce(p_note_body, '')), '');
  if normalized_note_body is not null and char_length(normalized_note_body) > 4000 then
    raise exception 'memory note body is too long'
      using errcode = '23514';
  end if;

  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);

  if normalized_note_body is null and cardinality(media_ids) = 0 then
    raise exception 'memory must include a note or media'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_memory',
      p_memory_id::text,
      normalized_title,
      p_memory_date::text,
      coalesce(normalized_note_body, ''),
      media_ids::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_memory',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'memory_id')::uuid;
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();
  insert into public.memories (
    id,
    couple_id,
    title,
    memory_date,
    created_by_user_id,
    last_edited_by_user_id
  ) values (
    p_memory_id,
    resolved_couple_id,
    normalized_title,
    p_memory_date,
    current_user_id,
    current_user_id
  );

  if normalized_note_body is not null then
    insert into public.memory_notes (
      memory_id,
      user_id,
      body
    ) values (
      p_memory_id,
      current_user_id,
      normalized_note_body
    );
  end if;

  perform internal.attach_memory_media_assets(p_memory_id, media_ids);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('memory_id', p_memory_id)
  );

  return p_memory_id;
end;
$$;


ALTER FUNCTION "internal"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("thread_id" "uuid", "message_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  resolved_thread_id uuid;
  resolved_message_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_memory_thread_with_message',
      p_memory_id::text,
      coalesce(nullif(btrim(coalesce(p_body, '')), ''), ''),
      coalesce(p_media_asset_ids::text, '{}')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_memory_thread_with_message',
    'conversation_threads',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'thread_id')::uuid,
      (replayed_response ->> 'message_id')::uuid;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'memory_thread:' || memory_row.id::text,
      0
    )
  );

  select existing_thread.thread_id
  into resolved_thread_id
  from public.memory_threads existing_thread
  where existing_thread.memory_id = memory_row.id;

  if resolved_thread_id is null then
    insert into public.conversation_threads (
      couple_id,
      kind,
      created_by_user_id
    ) values (
      memory_row.couple_id,
      'memory',
      current_user_id
    )
    returning id into resolved_thread_id;

    insert into public.memory_threads (
      memory_id,
      thread_id
    ) values (
      memory_row.id,
      resolved_thread_id
    );
  end if;

  resolved_message_id = internal.insert_thread_message(
    resolved_thread_id,
    p_body,
    p_media_asset_ids
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'thread_id', resolved_thread_id,
      'message_id', resolved_message_id
    )
  );

  return query
  select resolved_thread_id, resolved_message_id;
end;
$$;


ALTER FUNCTION "internal"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval)) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  invite_code_hash bytea;
  request_hash bytea;
  invite_id uuid;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'create_pairing_invite',
      pg_catalog.encode(invite_code_hash, 'hex'),
      p_expires_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_pairing_invite',
    'pairing_invites',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'invite_id')::uuid;
  end if;

  if p_expires_at <= now() or p_expires_at > now() + interval '30 days' then
    raise exception 'invite expiration is out of range'
      using errcode = '23514';
  end if;

  if not (select internal.user_has_direct_entitlement(current_user_id)) then
    raise exception 'direct entitlement is required to create an invite'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = current_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'user already has an active couple'
      using errcode = '23505';
  end if;

  insert into public.pairing_invites (created_by_user_id, expires_at)
  values (current_user_id, p_expires_at)
  returning id into invite_id;

  insert into internal.pairing_invite_secrets (invite_id, code_hash)
  values (invite_id, invite_code_hash);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('invite_id', invite_id)
  );

  return invite_id;
end;
$$;


ALTER FUNCTION "internal"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid" DEFAULT NULL::"uuid", "p_upload_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_path_context" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "upload_expires_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  new_media_asset_id uuid;
  normalized_extension text;
  resolved_bucket text;
  resolved_storage_path text;
  resolved_couple_id uuid;
  resolved_upload_expires_at timestamptz;
  expiry_hash_component text;
  canvas_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_reserved_parent_id is null then
    raise exception 'reserved parent id is required'
      using errcode = '23514';
  end if;

  if p_path_context is null then
    p_path_context = '{}'::jsonb;
  end if;

  if jsonb_typeof(p_path_context) <> 'object' then
    raise exception 'path context must be an object'
      using errcode = '23514';
  end if;

  normalized_extension = internal.normalize_media_file_extension(p_file_extension);

  if not internal.media_extension_matches_type(p_media_type, normalized_extension) then
    raise exception 'file extension does not match media type'
      using errcode = '23514';
  end if;

  resolved_upload_expires_at = coalesce(p_upload_expires_at, now() + interval '1 hour');
  expiry_hash_component = case
    when p_upload_expires_at is null then 'server_generated'
    else resolved_upload_expires_at::text
  end;

  if resolved_upload_expires_at <= now() + interval '5 minutes'
    or resolved_upload_expires_at > now() + interval '24 hours' then
    raise exception 'upload expiration is out of range'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'create_pending_media_upload',
      p_reserved_parent_kind,
      p_reserved_parent_id::text,
      p_upload_purpose,
      p_media_type,
      normalized_extension,
      coalesce(p_couple_id::text, ''),
      expiry_hash_component,
      p_path_context::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_pending_media_upload',
    'media_assets',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'media_asset_id')::uuid,
      replayed_response ->> 'bucket',
      replayed_response ->> 'storage_path',
      (replayed_response ->> 'upload_expires_at')::timestamptz;
    return;
  end if;

  new_media_asset_id = extensions.gen_random_uuid();

  if p_upload_purpose = 'profile_photo' then
    if p_reserved_parent_kind <> 'profile_photo'
      or p_reserved_parent_id <> current_user_id
      or p_media_type <> 'image'
      or p_couple_id is not null then
      raise exception 'profile photo upload contract is invalid'
        using errcode = '23514';
    end if;

    resolved_bucket = 'profile-photos';
    resolved_couple_id = null;
    resolved_storage_path = current_user_id::text || '/' || new_media_asset_id::text || '.' || normalized_extension;
  elsif p_upload_purpose in ('memory_photo', 'voice_note', 'daily_answer_media', 'thread_media') then
    if p_couple_id is null then
      raise exception 'relationship media requires a couple id'
        using errcode = '23514';
    end if;

    if not internal.can_access_couple_content(p_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;

    if (
      p_upload_purpose = 'memory_photo'
      and not (p_reserved_parent_kind = 'memory_media' and p_media_type = 'image')
    ) or (
      p_upload_purpose = 'voice_note'
      and not (
        p_reserved_parent_kind in ('memory_media', 'daily_answer_media', 'thread_message_media')
        and p_media_type = 'voice'
      )
    ) or (
      p_upload_purpose = 'daily_answer_media'
      and not (p_reserved_parent_kind = 'daily_answer_media' and p_media_type = 'image')
    ) or (
      p_upload_purpose = 'thread_media'
      and not (p_reserved_parent_kind = 'thread_message_media' and p_media_type = 'image')
    ) then
      raise exception 'relationship media upload contract is invalid'
        using errcode = '23514';
    end if;

    resolved_bucket = 'couple-media';
    resolved_couple_id = p_couple_id;
    resolved_storage_path = p_couple_id::text || '/' || p_media_type || '/' || new_media_asset_id::text || '.' || normalized_extension;
  elsif p_upload_purpose = 'widget_drawing_payload' then
    if p_reserved_parent_kind <> 'widget_drawing_revision'
      or p_media_type <> 'drawing_payload'
      or p_couple_id is null then
      raise exception 'widget drawing upload contract is invalid'
        using errcode = '23514';
    end if;

    if not internal.can_access_couple_content(p_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;

    canvas_id = nullif(p_path_context ->> 'canvas_id', '')::uuid;

    if canvas_id is null then
      raise exception 'widget drawing uploads require a canvas id'
        using errcode = '23514';
    end if;

    resolved_bucket = 'widget-drawings';
    resolved_couple_id = p_couple_id;
    resolved_storage_path = p_couple_id::text || '/' || canvas_id::text || '/revisions/' || p_reserved_parent_id::text || '/drawing.' || normalized_extension;
  elsif p_upload_purpose = 'report_snapshot' then
    raise exception 'report snapshot uploads require a trusted service path'
      using errcode = '42501';
  else
    raise exception 'upload purpose is not supported'
      using errcode = '23514';
  end if;

  insert into public.media_assets (
    id,
    owner_user_id,
    couple_id,
    reserved_parent_kind,
    reserved_parent_id,
    reserved_by_client_operation_id,
    bucket,
    storage_path,
    media_type,
    upload_purpose,
    expected_media_type,
    expected_bucket,
    upload_status,
    upload_expires_at
  ) values (
    new_media_asset_id,
    current_user_id,
    resolved_couple_id,
    p_reserved_parent_kind,
    p_reserved_parent_id,
    p_client_operation_id,
    resolved_bucket,
    resolved_storage_path,
    p_media_type,
    p_upload_purpose,
    p_media_type,
    resolved_bucket,
    'pending',
    resolved_upload_expires_at
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'media_asset_id', new_media_asset_id,
      'bucket', resolved_bucket,
      'storage_path', resolved_storage_path,
      'upload_expires_at', resolved_upload_expires_at
    )
  );

  return query
  select
    new_media_asset_id,
    resolved_bucket,
    resolved_storage_path,
    resolved_upload_expires_at;
end;
$$;


ALTER FUNCTION "internal"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_profile_for_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    internal.auth_metadata_display_name(new.raw_user_meta_data)
  )
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "internal"."create_profile_for_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."create_relationship_sync_event"("p_user_id" "uuid", "p_couple_id" "uuid", "p_initiated_by_user_id" "uuid", "p_event_kind" "text", "p_reason" "text", "p_relationship_status" "text", "p_member_status" "text", "p_ended_at" timestamp with time zone, "p_delete_after" timestamp with time zone, "p_local_purge_scope" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  event_id uuid;
begin
  insert into public.relationship_sync_events (
    user_id,
    couple_id,
    initiated_by_user_id,
    event_kind,
    reason,
    relationship_status,
    member_status,
    ended_at,
    delete_after,
    local_purge_scope
  ) values (
    p_user_id,
    p_couple_id,
    p_initiated_by_user_id,
    p_event_kind,
    p_reason,
    p_relationship_status,
    p_member_status,
    p_ended_at,
    p_delete_after,
    coalesce(p_local_purge_scope, '{}'::jsonb)
  )
  returning id into event_id;

  return event_id;
end;
$$;


ALTER FUNCTION "internal"."create_relationship_sync_event"("p_user_id" "uuid", "p_couple_id" "uuid", "p_initiated_by_user_id" "uuid", "p_event_kind" "text", "p_reason" "text", "p_relationship_status" "text", "p_member_status" "text", "p_ended_at" timestamp with time zone, "p_delete_after" timestamp with time zone, "p_local_purge_scope" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."current_user_id"() RETURNS "uuid"
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select auth.uid();
$$;


ALTER FUNCTION "internal"."current_user_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."delete_latest_locations_on_preference_disable"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if not new.is_enabled then
    delete from public.latest_partner_locations latest
    where latest.couple_id = new.couple_id
      and latest.user_id = new.user_id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."delete_latest_locations_on_preference_disable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."delete_latest_locations_on_relationship_end"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if old.status = 'active' and new.status <> 'active' then
    delete from public.latest_partner_locations latest
    where latest.couple_id = new.id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."delete_latest_locations_on_relationship_end"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."detect_streak_break"("p_couple_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_deadline timestamptz;
begin
  resolved_deadline = internal.refresh_streak_deadline(p_couple_id);

  update public.streak_states
  set
    restorable_count = current_count,
    restorable_through_date = last_qualified_date,
    restore_deadline = resolved_deadline + interval '24 hours',
    restore_available = resolved_deadline + interval '24 hours' > now()
  where couple_id = p_couple_id
    and current_count > 0
    and restorable_count = 0
    and resolved_deadline is not null
    and now() >= resolved_deadline;
end;
$$;


ALTER FUNCTION "internal"."detect_streak_break"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."disable_user_device"("p_device_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update public.user_devices
  set disabled_at = coalesce(disabled_at, now())
  where id = p_device_id
    and user_id = current_user_id;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."disable_user_device"("p_device_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."end_relationship_for_pair"("p_pair_id" "uuid", "p_initiated_by_user_id" "uuid", "p_reason" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_row public.couples%rowtype;
  member_row record;
  changed_rows integer;
  cleanup_deadline timestamptz;
begin
  select *
  into couple_row
  from public.couples
  where pair_id = p_pair_id
    and status = 'active'
  order by created_at desc
  limit 1
  for update;

  if not found then
    return false;
  end if;

  cleanup_deadline = now() + interval '30 days';

  update public.couples
  set
    status = 'ended',
    ended_at = now(),
    delete_after = cleanup_deadline
  where id = couple_row.id;

  update public.couple_members
  set
    status = 'left',
    left_at = now()
  where couple_id = couple_row.id
    and user_id = p_initiated_by_user_id
    and status = 'active';

  get diagnostics changed_rows = row_count;

  if changed_rows <> 1 then
    raise exception 'initiating user is not an active member of the relationship'
      using errcode = '42501';
  end if;

  update public.couple_members
  set status = 'ended_notice_pending'
  where couple_id = couple_row.id
    and user_id <> p_initiated_by_user_id
    and status = 'active';

  for member_row in
    select user_id, status
    from public.couple_members
    where couple_id = couple_row.id
  loop
    perform internal.create_relationship_sync_event(
      member_row.user_id,
      couple_row.id,
      p_initiated_by_user_id,
      'relationship_ended',
      p_reason,
      'ended',
      member_row.status,
      now(),
      cleanup_deadline,
      '{"relationship_content":"hide","location":"purge","widget_cache":"purge","pending_uploads":"review"}'::jsonb
    );
  end loop;

  return true;
end;
$$;


ALTER FUNCTION "internal"."end_relationship_for_pair"("p_pair_id" "uuid", "p_initiated_by_user_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_due_streak_reminders"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  queued_rows integer := 0;
  streak_row record;
  missing_member record;
  current_couple_day_id uuid;
begin
  for streak_row in
    select streak.couple_id
    from public.streak_states streak
    join public.couples couple
      on couple.id = streak.couple_id
    where couple.status = 'active'
      and streak.current_count > 0
      and streak.restorable_count = 0
  loop
    perform internal.refresh_streak_deadline(streak_row.couple_id);
  end loop;

  for streak_row in
    select
      streak.couple_id,
      streak.current_count,
      streak.last_qualified_date,
      streak.next_activity_deadline_at
    from public.streak_states streak
    join public.couples couple
      on couple.id = streak.couple_id
    where couple.status = 'active'
      and streak.restorable_count = 0
      and streak.next_activity_deadline_at > p_now
      and streak.next_activity_deadline_at <= p_now + interval '1 hour'
  loop
    current_couple_day_id = internal.get_or_create_couple_day_at(
      streak_row.couple_id,
      p_now
    );

    for missing_member in
      select member.user_id
      from public.couple_members member
      where member.couple_id = streak_row.couple_id
        and member.status = 'active'
        and not exists (
          select 1
          from public.couple_activity_events event
          where event.couple_id = streak_row.couple_id
            and event.couple_day_id = current_couple_day_id
            and event.user_id = member.user_id
        )
    loop
      queued_rows = queued_rows + internal.enqueue_notification_for_user(
        missing_member.user_id,
        'streak_reminder',
        jsonb_build_object(
          'type', 'streak_reminder',
          'couple_id', streak_row.couple_id::text,
          'current_count', streak_row.current_count,
          'last_qualified_date', streak_row.last_qualified_date,
          'next_activity_deadline_at', streak_row.next_activity_deadline_at,
          'contribution_needed', true,
          'route', 'streak',
          'deeplink', 'paeonia://streak'
        ),
        'streak_reminder:' || streak_row.couple_id::text || ':'
          || streak_row.last_qualified_date::text || ':'
          || missing_member.user_id::text,
        'private',
        'alert',
        'streak:' || streak_row.couple_id::text,
        p_now
      );
    end loop;
  end loop;

  return queued_rows;
end;
$$;


ALTER FUNCTION "internal"."enqueue_due_streak_reminders"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_memory_created_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if new.deleted_at is not null or new.moderation_status <> 'visible' then
    return new;
  end if;

  perform internal.enqueue_partner_notification(
    new.couple_id,
    new.created_by_user_id,
    'memory_created',
    jsonb_build_object(
      'type', 'memory_created',
      'couple_id', new.couple_id::text,
      'memory_id', new.id::text,
      'actor_user_id', new.created_by_user_id::text,
      'route', 'memories',
      'deeplink', 'paeonia://memories'
    ),
    'memory_created:' || new.id::text,
    'private',
    'alert',
    'memory:' || new.id::text,
    now()
  );

  return new;
end;
$$;


ALTER FUNCTION "internal"."enqueue_memory_created_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_notification_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text" DEFAULT NULL::"text", "p_redaction_level" "text" DEFAULT 'private'::"text", "p_apns_push_type" "text" DEFAULT 'alert'::"text", "p_apns_collapse_id" "text" DEFAULT NULL::"text", "p_scheduled_for" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  queued_rows integer;
begin
  if p_recipient_user_id is null then
    raise exception 'notification recipient is required'
      using errcode = '23514';
  end if;

  if p_kind not in (
    'streak_reminder',
    'daily_challenge_completed',
    'partner_answered',
    'widget_updated',
    'location_updated',
    'relationship_ended',
    'entitlement_changed',
    'subscription_trial_reminder',
    'memory_created',
    'thread_message_sent'
  ) then
    raise exception 'notification kind is not supported'
      using errcode = '23514';
  end if;

  if p_redaction_level <> 'private' then
    raise exception 'only private notification payloads are supported for MVP'
      using errcode = '23514';
  end if;

  if not internal.notification_payload_is_safe(p_payload) then
    raise exception 'notification payload contains sensitive or unsupported fields'
      using errcode = '23514';
  end if;

  insert into internal.notification_outbox (
    recipient_user_id,
    target_device_id,
    push_token_hash,
    apns_environment,
    kind,
    redaction_level,
    payload,
    dedupe_key,
    apns_push_type,
    apns_collapse_id,
    title,
    body,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.push_token_hash,
    device.apns_environment,
    p_kind,
    p_redaction_level,
    p_payload,
    case
      when nullif(btrim(coalesce(p_dedupe_key, '')), '') is null then null
      else btrim(p_dedupe_key) || ':' || device.id::text
    end,
    p_apns_push_type,
    nullif(btrim(coalesce(p_apns_collapse_id, '')), ''),
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_title(
          p_kind,
          p_payload || jsonb_build_object(
            'lock_screen_detail_level',
            preference.lock_screen_detail_level
          ),
          device.locale
        )
      else null
    end,
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_body(
          p_kind,
          p_payload || jsonb_build_object(
            'lock_screen_detail_level',
            preference.lock_screen_detail_level
          ),
          device.locale
        )
      else null
    end,
    coalesce(p_scheduled_for, now())
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = p_recipient_user_id
    and device.disabled_at is null
    and (
      case p_kind
        when 'streak_reminder' then preference.streak_reminders_enabled
        when 'daily_challenge_completed' then preference.daily_challenge_enabled
        when 'partner_answered' then preference.partner_answered_enabled
        when 'widget_updated' then
          (p_apns_push_type <> 'alert' or preference.widget_updates_enabled)
        when 'location_updated' then preference.location_updates_enabled
        when 'memory_created' then preference.memories_enabled
        when 'thread_message_sent' then preference.messages_enabled
        else true
      end
    )
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;


ALTER FUNCTION "internal"."enqueue_notification_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_redaction_level" "text", "p_apns_push_type" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_partner_answered_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  recipient_user_id uuid;
  visible_answer_count integer;
begin
  if new.deleted_at is not null or new.moderation_status <> 'visible' then
    return new;
  end if;

  select *
  into instance_row
  from public.daily_question_instances
  where id = new.instance_id;

  if not found then
    return new;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if not found then
    return new;
  end if;

  select count(*)
  into visible_answer_count
  from public.daily_question_answers answer
  where answer.instance_id = new.instance_id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible';

  if visible_answer_count <> 2 then
    return new;
  end if;

  select answer.user_id
  into recipient_user_id
  from public.daily_question_answers answer
  where answer.instance_id = new.instance_id
    and answer.user_id <> new.user_id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  limit 1;

  if recipient_user_id is null then
    return new;
  end if;

  perform internal.enqueue_notification_for_user(
    recipient_user_id,
    'partner_answered',
    jsonb_build_object(
      'type', 'partner_answered',
      'couple_id', couple_day_row.couple_id::text,
      'couple_day_id', instance_row.couple_day_id::text,
      'instance_id', new.instance_id::text,
      'actor_user_id', new.user_id::text,
      'route', 'daily',
      'deeplink', 'paeonia://daily/reveal?instanceId=' || new.instance_id::text || '&coupleDayId=' || instance_row.couple_day_id::text
    ),
    'partner_answered:' || new.instance_id::text || ':' || new.user_id::text || ':' || recipient_user_id::text,
    'private',
    'alert',
    'daily:' || couple_day_row.couple_id::text,
    now()
  );

  return new;
end;
$$;


ALTER FUNCTION "internal"."enqueue_partner_answered_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_partner_notification"("p_couple_id" "uuid", "p_actor_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text" DEFAULT NULL::"text", "p_redaction_level" "text" DEFAULT 'private'::"text", "p_apns_push_type" "text" DEFAULT 'alert'::"text", "p_apns_collapse_id" "text" DEFAULT NULL::"text", "p_scheduled_for" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  queued_rows integer := 0;
  partner_row record;
begin
  for partner_row in
    select member.user_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id <> p_actor_user_id
      and member.status = 'active'
      and couple.status = 'active'
  loop
    queued_rows = queued_rows + internal.enqueue_notification_for_user(
      partner_row.user_id,
      p_kind,
      p_payload,
      p_dedupe_key,
      p_redaction_level,
      p_apns_push_type,
      p_apns_collapse_id,
      p_scheduled_for
    );
  end loop;

  return queued_rows;
end;
$$;


ALTER FUNCTION "internal"."enqueue_partner_notification"("p_couple_id" "uuid", "p_actor_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_redaction_level" "text", "p_apns_push_type" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_report_snapshot_assets"("p_report_id" "uuid", "p_target_snapshot" "jsonb") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $_$
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
$_$;


ALTER FUNCTION "internal"."enqueue_report_snapshot_assets"("p_report_id" "uuid", "p_target_snapshot" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_widget_push_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_dedupe_key" "text" DEFAULT NULL::"text", "p_apns_collapse_id" "text" DEFAULT NULL::"text", "p_scheduled_for" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  queued_rows integer;
begin
  if p_recipient_user_id is null then
    raise exception 'widget push recipient required'
      using errcode = '23514';
  end if;

  if p_kind <> 'widget_updated' then
    raise exception 'unsupported widget push kind'
      using errcode = '23514';
  end if;

  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'widget push payload must be an object'
      using errcode = '23514';
  end if;

  insert into internal.widget_push_outbox (
    recipient_user_id,
    target_widget_device_id,
    widget_push_token_hash,
    apns_environment,
    kind,
    payload,
    dedupe_key,
    apns_collapse_id,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.widget_push_token_hash,
    device.apns_environment,
    p_kind,
    coalesce(p_payload, '{}'::jsonb),
    p_dedupe_key,
    p_apns_collapse_id,
    coalesce(p_scheduled_for, now())
  from public.widget_push_devices device
  where device.user_id = p_recipient_user_id
    and device.widget_kind = 'PaeoniaWidget'
    and device.disabled_at is null
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;


ALTER FUNCTION "internal"."enqueue_widget_push_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."enqueue_widget_update_alert"("p_couple_id" "uuid", "p_author_user_id" "uuid", "p_canvas_id" "uuid", "p_revision_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  recipient_user_id uuid;
  author_name text;
  queued_rows integer;
begin
  select member.user_id
  into recipient_user_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.couple_id = p_couple_id
    and member.user_id <> p_author_user_id
    and member.status = 'active'
    and couple.status = 'active'
  limit 1;

  if recipient_user_id is null then
    return 0;
  end if;

  select nullif(btrim(profile.display_name), '')
  into author_name
  from public.profiles profile
  where profile.user_id = p_author_user_id;

  insert into internal.notification_outbox (
    recipient_user_id,
    target_device_id,
    push_token_hash,
    apns_environment,
    kind,
    redaction_level,
    payload,
    dedupe_key,
    apns_push_type,
    apns_collapse_id,
    title,
    body,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.push_token_hash,
    device.apns_environment,
    'widget_updated',
    'private',
    jsonb_build_object(
      'type', 'widget_updated',
      'couple_id', p_couple_id::text,
      'canvas_id', p_canvas_id::text,
      'revision_id', p_revision_id::text,
      'actor_user_id', p_author_user_id::text,
      'sender_user_id', p_author_user_id::text,
      'route', 'widget',
      'deeplink', 'paeonia://widget/drawing'
    ),
    'widget_updated_alert:' || p_revision_id::text || ':' || device.id::text,
    'alert',
    'widget-alert:' || p_couple_id::text,
    coalesce(author_name, 'Paeonia'),
    internal.notification_alert_body('widget_updated', '{}'::jsonb, device.locale),
    now()
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = recipient_user_id
    and device.disabled_at is null
    and preference.widget_updates_enabled
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;


ALTER FUNCTION "internal"."enqueue_widget_update_alert"("p_couple_id" "uuid", "p_author_user_id" "uuid", "p_canvas_id" "uuid", "p_revision_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."ensure_daily_challenge_slots"("p_couple_day_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_day_row public.couple_days%rowtype;
  member_row record;
  picked_question_version_id uuid;
begin
  select *
  into couple_day_row
  from public.couple_days
  where id = p_couple_day_id
  for update;

  if not found then
    raise exception 'couple day was not found'
      using errcode = '22023';
  end if;

  for member_row in
    select member.user_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = couple_day_row.couple_id
      and member.status = 'active'
      and couple.status = 'active'
    order by member.joined_at, member.user_id
  loop
    insert into public.daily_challenges (couple_day_id, user_id)
    values (p_couple_day_id, member_row.user_id)
    on conflict (couple_day_id, user_id) do nothing;

    for current_slot_number in 1..3 loop
      if not exists (
        select 1
        from public.daily_question_instances instance
        where instance.couple_day_id = p_couple_day_id
          and instance.seeded_for_user_id = member_row.user_id
          and instance.slot_number = current_slot_number
          and instance.status in ('active', 'answered')
      ) then
        picked_question_version_id = internal.pick_daily_question_version(
          p_couple_day_id,
          member_row.user_id,
          null
        );

        insert into public.daily_question_instances (
          couple_day_id,
          question_version_id,
          seeded_for_user_id,
          slot_number
        ) values (
          p_couple_day_id,
          picked_question_version_id,
          member_row.user_id,
          current_slot_number
        );
      end if;
    end loop;
  end loop;
end;
$$;


ALTER FUNCTION "internal"."ensure_daily_challenge_slots"("p_couple_day_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  insert into public.profiles (
    user_id, display_name, time_zone_id, time_zone_updated_at, onboarding_completed_at
  )
  values (p_user_id, p_display_name, 'Europe/Oslo', now(), now())
  on conflict (user_id) do update
  set
    display_name = excluded.display_name,
    time_zone_id = coalesce(public.profiles.time_zone_id, excluded.time_zone_id),
    time_zone_updated_at = coalesce(public.profiles.time_zone_updated_at, excluded.time_zone_updated_at),
    onboarding_completed_at = coalesce(public.profiles.onboarding_completed_at, excluded.onboarding_completed_at),
    moderation_status = 'visible',
    deleted_at = null;
end;
$$;


ALTER FUNCTION "internal"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."expire_stale_entitlements"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 500) RETURNS TABLE("storekit_transactions_expired" integer, "entitlement_grants_expired" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."expire_stale_entitlements"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."expire_stale_invites_and_review_codes"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 500) RETURNS TABLE("pairing_invites_expired" integer, "review_codes_expired" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."expire_stale_invites_and_review_codes"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."fail_exhausted_notification_claims"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  update internal.notification_outbox
  set failed_at = now(),
      last_error = coalesce(
        nullif(last_error, ''),
        'delivery attempt budget exhausted before a result was recorded'
      )
  where sent_at is null
    and failed_at is null
    and attempt_count >= 5;
end;
$$;


ALTER FUNCTION "internal"."fail_exhausted_notification_claims"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."fail_exhausted_widget_push_claims"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  update internal.widget_push_outbox
  set
    failed_at = now(),
    last_error = coalesce(last_error, 'attempts exhausted')
  where sent_at is null
    and failed_at is null
    and attempt_count >= 5;
end;
$$;


ALTER FUNCTION "internal"."fail_exhausted_widget_push_claims"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer DEFAULT NULL::integer, "p_height" integer DEFAULT NULL::integer, "p_duration_ms" integer DEFAULT NULL::integer) RETURNS TABLE("media_asset_id" "uuid", "upload_status" "text", "upload_finalized_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $_$
declare
  current_user_id uuid;
  asset_row public.media_assets%rowtype;
  normalized_mime_type text;
  sha256_bytes bytea;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_sha256_hex is null or p_sha256_hex !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'sha256 must be a 64 character hex string'
      using errcode = '22023';
  end if;

  sha256_bytes = decode(lower(p_sha256_hex), 'hex');
  normalized_mime_type = lower(btrim(coalesce(p_mime_type, '')));

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'finalize_media_upload',
      p_media_asset_id::text,
      p_reserved_by_client_operation_id::text,
      p_bucket,
      p_storage_path,
      p_reserved_parent_kind,
      p_reserved_parent_id::text,
      p_upload_purpose,
      p_media_type,
      normalized_mime_type,
      p_byte_size::text,
      encode(sha256_bytes, 'hex'),
      coalesce(p_width::text, ''),
      coalesce(p_height::text, ''),
      coalesce(p_duration_ms::text, '')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'finalize_media_upload',
    'media_assets',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'media_asset_id')::uuid,
      replayed_response ->> 'upload_status',
      (replayed_response ->> 'upload_finalized_at')::timestamptz;
    return;
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = p_media_asset_id
  for update;

  if not found then
    raise exception 'media asset was not found'
      using errcode = '22023';
  end if;

  if asset_row.owner_user_id <> current_user_id then
    raise exception 'media asset is owned by another user'
      using errcode = '42501';
  end if;

  if asset_row.couple_id is not null
    and not internal.can_access_couple_content(asset_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  if asset_row.reserved_by_client_operation_id <> p_reserved_by_client_operation_id
    or asset_row.bucket <> p_bucket
    or asset_row.storage_path <> p_storage_path
    or asset_row.reserved_parent_kind <> p_reserved_parent_kind
    or asset_row.reserved_parent_id <> p_reserved_parent_id
    or asset_row.upload_purpose <> p_upload_purpose
    or asset_row.expected_media_type <> p_media_type
    or asset_row.expected_bucket <> p_bucket then
    raise exception 'finalize request does not match the reserved upload'
      using errcode = '23514';
  end if;

  if p_byte_size is null or p_byte_size <= 0 or p_byte_size > internal.media_byte_limit(p_media_type) then
    raise exception 'byte size is out of range'
      using errcode = '23514';
  end if;

  if not internal.media_mime_matches_type(p_media_type, normalized_mime_type) then
    raise exception 'mime type does not match media type'
      using errcode = '23514';
  end if;

  if p_media_type = 'image' and (p_width is null or p_height is null) then
    raise exception 'image uploads require dimensions'
      using errcode = '23514';
  end if;

  if p_media_type = 'voice' and p_duration_ms is null then
    raise exception 'voice uploads require duration'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from storage.objects object
    where object.bucket_id = asset_row.bucket
      and object.name = asset_row.storage_path
  ) then
    raise exception 'reserved storage object was not found'
      using errcode = '22023';
  end if;

  if asset_row.upload_status = 'finalized' then
    if asset_row.byte_size = p_byte_size
      and asset_row.mime_type = normalized_mime_type
      and asset_row.sha256 = sha256_bytes
      and asset_row.width is not distinct from p_width
      and asset_row.height is not distinct from p_height
      and asset_row.duration_ms is not distinct from p_duration_ms then
      perform internal.complete_client_operation(
        p_client_operation_id,
        jsonb_build_object(
          'media_asset_id', asset_row.id,
          'upload_status', asset_row.upload_status,
          'upload_finalized_at', asset_row.upload_finalized_at
        )
      );

      return query
      select asset_row.id, asset_row.upload_status, asset_row.upload_finalized_at;
      return;
    end if;

    raise exception 'finalized media metadata cannot be changed'
      using errcode = '23505';
  end if;

  if asset_row.upload_status <> 'pending' then
    raise exception 'media asset is not pending upload'
      using errcode = '23514';
  end if;

  if asset_row.upload_expires_at <= now() then
    update public.media_assets
    set upload_status = 'expired'
    where id = asset_row.id;

    raise exception 'media upload reservation is expired'
      using errcode = '22023';
  end if;

  if asset_row.deleted_at is not null or asset_row.storage_delete_status <> 'none' then
    raise exception 'media asset is queued for deletion'
      using errcode = '23514';
  end if;

  update public.media_assets
  set
    upload_status = 'finalized',
    mime_type = normalized_mime_type,
    byte_size = p_byte_size,
    sha256 = sha256_bytes,
    width = p_width,
    height = p_height,
    duration_ms = p_duration_ms,
    upload_finalized_at = now()
  where id = asset_row.id
  returning * into asset_row;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'media_asset_id', asset_row.id,
      'upload_status', asset_row.upload_status,
      'upload_finalized_at', asset_row.upload_finalized_at
    )
  );

  return query
  select asset_row.id, asset_row.upload_status, asset_row.upload_finalized_at;
end;
$_$;


ALTER FUNCTION "internal"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "internal"."review_access_codes" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "code_hash" "bytea" NOT NULL,
    "seeded_partner_user_id" "uuid",
    "scenario" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "expires_at" timestamp with time zone,
    "max_redemptions" integer DEFAULT 1 NOT NULL,
    "redemption_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "review_access_codes_code_hash_check" CHECK (("octet_length"("code_hash") = 32)),
    CONSTRAINT "review_access_codes_prepaired_partner_check" CHECK ((("scenario" <> ALL (ARRAY['pre_paired_entitled'::"text", 'pre_paired_paywalled'::"text"])) OR ("seeded_partner_user_id" IS NOT NULL))),
    CONSTRAINT "review_access_codes_redemption_count_check" CHECK ((("redemption_count" >= 0) AND ("max_redemptions" > 0) AND ("redemption_count" <= "max_redemptions"))),
    CONSTRAINT "review_access_codes_revoked_state_check" CHECK (((("status" = 'revoked'::"text") AND ("revoked_at" IS NOT NULL)) OR ("status" <> 'revoked'::"text"))),
    CONSTRAINT "review_access_codes_scenario_check" CHECK (("scenario" = ANY (ARRAY['pre_paired_entitled'::"text", 'purchase_flow_unentitled'::"text", 'pre_paired_paywalled'::"text"]))),
    CONSTRAINT "review_access_codes_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'revoked'::"text", 'expired'::"text"])))
);


ALTER TABLE "internal"."review_access_codes" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."find_active_review_access_code"("p_code" "text") RETURNS "internal"."review_access_codes"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.review_access_codes
  where code_hash = internal.hash_review_access_code(p_code)
    and status = 'active'
    and (expires_at is null or expires_at > now())
  limit 1;
$$;


ALTER FUNCTION "internal"."find_active_review_access_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."find_relationship_pair_id"("p_first_user_id" "uuid", "p_second_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  low_user_id uuid;
  high_user_id uuid;
  existing_pair_id uuid;
begin
  if p_first_user_id is null or p_second_user_id is null or p_first_user_id = p_second_user_id then
    return null;
  end if;

  if p_first_user_id < p_second_user_id then
    low_user_id = p_first_user_id;
    high_user_id = p_second_user_id;
  else
    low_user_id = p_second_user_id;
    high_user_id = p_first_user_id;
  end if;

  select id
  into existing_pair_id
  from public.relationship_pairs
  where user_low_id = low_user_id
    and user_high_id = high_user_id;

  return existing_pair_id;
end;
$$;


ALTER FUNCTION "internal"."find_relationship_pair_id"("p_first_user_id" "uuid", "p_second_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."find_reportable_relationship_between"("p_reporter_user_id" "uuid", "p_reported_user_id" "uuid") RETURNS TABLE("couple_id" "uuid", "pair_id" "uuid")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."find_reportable_relationship_between"("p_reporter_user_id" "uuid", "p_reported_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_access_snapshot"() RETURNS TABLE("user_entitlement" "jsonb", "couple_entitlement" "jsonb", "relationship_state" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with user_entitlement_row as (
    select *
    from internal.resolve_user_entitlement((select auth.uid()))
  ),
  couple_entitlement_row as (
    select *
    from internal.resolve_current_couple_entitlement()
  ),
  relationship_state_row as (
    select *
    from internal.get_current_relationship_state()
  )
  select
    (select to_jsonb(user_entitlement_row) from user_entitlement_row) as user_entitlement,
    (select to_jsonb(couple_entitlement_row) from couple_entitlement_row) as couple_entitlement,
    (select to_jsonb(relationship_state_row) from relationship_state_row) as relationship_state;
$$;


ALTER FUNCTION "internal"."get_access_snapshot"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_active_question_catalog"("p_locale" "text" DEFAULT NULL::"text") RETURNS TABLE("collection_id" "uuid", "question_id" "uuid", "question_key" "text", "question_version_id" "uuid", "version_number" integer, "locale" "text", "prompt" "text", "short_prompt" "text", "answer_kinds" "text"[], "resurfaceable" boolean, "resurface_after_months" smallint)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with active_versions as (
    select
      collection.id as collection_id,
      question.id as question_id,
      question.key as question_key,
      version.id as question_version_id,
      version.version_number,
      question.resurfaceable,
      question.resurface_after_months,
      array_agg(answer_kind.answer_kind order by answer_kind.answer_kind) as answer_kinds
    from public.question_collections collection
    join public.questions question
      on question.collection_id = collection.id
    join public.question_versions version
      on version.question_id = question.id
    join public.question_answer_kinds answer_kind
      on answer_kind.question_version_id = version.id
    where collection.kind = 'system'
      and collection.status = 'active'
      and question.status = 'active'
      and version.status = 'active'
      and exists (
        select 1
        from public.question_version_localizations en_localization
        where en_localization.question_version_id = version.id
          and en_localization.locale = 'en'
      )
      and exists (
        select 1
        from public.question_version_localizations nb_localization
        where nb_localization.question_version_id = version.id
          and nb_localization.locale = 'nb'
      )
    group by
      collection.id,
      question.id,
      question.key,
      version.id,
      version.version_number,
      question.resurfaceable,
      question.resurface_after_months
    having count(*) between 1 and 2
  )
  select
    active_versions.collection_id,
    active_versions.question_id,
    active_versions.question_key,
    active_versions.question_version_id,
    active_versions.version_number,
    localization.locale,
    localization.prompt,
    localization.short_prompt,
    active_versions.answer_kinds,
    active_versions.resurfaceable,
    active_versions.resurface_after_months
  from active_versions
  join public.question_version_localizations localization
    on localization.question_version_id = active_versions.question_version_id
  where p_locale is null or localization.locale = p_locale
  order by active_versions.question_key, localization.locale;
$$;


ALTER FUNCTION "internal"."get_active_question_catalog"("p_locale" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_conversation_threads"() RETURNS TABLE("thread_id" "uuid", "couple_id" "uuid", "kind" "text", "daily_question_instance_id" "uuid", "memory_id" "uuid", "created_by_user_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "deleted_at" timestamp with time zone, "moderation_status" "text", "last_message_id" "uuid", "last_message_at" timestamp with time zone, "last_message_sender_user_id" "uuid", "last_message_deleted_at" timestamp with time zone, "last_message_moderation_status" "text", "last_message_body" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_couple as (
    select internal.get_current_entitled_couple_id() as couple_id
  )
  select
    thread.id,
    thread.couple_id,
    thread.kind,
    daily_thread.instance_id,
    memory_thread.memory_id,
    thread.created_by_user_id,
    thread.created_at,
    thread.updated_at,
    thread.deleted_at,
    thread.moderation_status,
    last_message.id,
    last_message.created_at,
    last_message.sender_user_id,
    last_message.deleted_at,
    last_message.moderation_status,
    case
      when thread.deleted_at is null
        and thread.moderation_status = 'visible'
        and last_message.deleted_at is null
        and last_message.moderation_status = 'visible'
        then last_message.body
      else null
    end
  from current_couple
  join public.conversation_threads thread
    on thread.couple_id = current_couple.couple_id
  left join public.daily_question_threads daily_thread
    on daily_thread.thread_id = thread.id
  left join public.memory_threads memory_thread
    on memory_thread.thread_id = thread.id
  left join lateral (
    select message.*
    from public.thread_messages message
    where message.thread_id = thread.id
    order by message.created_at desc, message.id desc
    limit 1
  ) last_message
    on true
  where internal.can_access_couple_content(thread.couple_id)
  order by last_message.created_at desc, thread.created_at desc, thread.id;
$$;


ALTER FUNCTION "internal"."get_conversation_threads"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_couple_day_streak_qualified_at"("p_couple_id" "uuid", "p_couple_day_id" "uuid") RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with active_members as materialized (
    select member.user_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.status = 'active'
      and couple.status = 'active'
  ),
  first_contributions as materialized (
    select
      member.user_id,
      min(event.occurred_at) as first_occurred_at
    from active_members member
    left join public.couple_activity_events event
      on event.couple_id = p_couple_id
      and event.couple_day_id = p_couple_day_id
      and event.user_id = member.user_id
    group by member.user_id
  )
  select case
    when count(*) >= 2
      and count(first_contributions.first_occurred_at) = count(*)
      then max(first_contributions.first_occurred_at)
    else null
  end
  from first_contributions;
$$;


ALTER FUNCTION "internal"."get_couple_day_streak_qualified_at"("p_couple_id" "uuid", "p_couple_day_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "internal"."get_couple_day_streak_qualified_at"("p_couple_id" "uuid", "p_couple_day_id" "uuid") IS 'Returns when every active partner first had a qualifying event in the couple day; null until both contribute.';



CREATE OR REPLACE FUNCTION "internal"."get_couple_streak"() RETURNS TABLE("current_count" integer, "longest_count" integer, "last_qualified_date" "date", "restore_available" boolean, "restorable_count" integer, "restore_deadline" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  resolved_couple_id = internal.get_current_entitled_couple_id();

  return query
  select
    streak.current_count,
    streak.longest_count,
    streak.last_qualified_date,
    streak.restore_available,
    streak.restorable_count,
    streak.restore_deadline
  from internal.get_couple_streak_for_couple(resolved_couple_id) streak;
end;
$$;


ALTER FUNCTION "internal"."get_couple_streak"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_couple_streak_for_couple"("p_couple_id" "uuid") RETURNS TABLE("current_count" integer, "longest_count" integer, "last_qualified_date" "date", "restore_available" boolean, "restorable_count" integer, "restore_deadline" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if p_couple_id is null then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  perform internal.detect_streak_break(p_couple_id);

  return query
  select
    case
      when streak.next_activity_deadline_at is not null
        and now() >= streak.next_activity_deadline_at
        then 0
      else coalesce(streak.current_count, 0)
    end,
    coalesce(streak.longest_count, 0),
    streak.last_qualified_date,
    (
      coalesce(streak.restorable_count, 0) > 0
      and streak.restore_deadline is not null
      and streak.restore_deadline > now()
    ),
    coalesce(streak.restorable_count, 0),
    streak.restore_deadline
  from (select p_couple_id as couple_id) resolved
  left join public.streak_states streak
    on streak.couple_id = resolved.couple_id;
end;
$$;


ALTER FUNCTION "internal"."get_couple_streak_for_couple"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_couple_streak_participation_for_user"("p_couple_id" "uuid", "p_current_user_id" "uuid", "p_observed_at" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("current_user_contributed_today" boolean, "partner_contributed_today" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_day as materialized (
    select couple_day.id
    from public.couple_days couple_day
    where couple_day.couple_id = p_couple_id
      and p_observed_at >= couple_day.starts_at
      and p_observed_at < couple_day.ends_at
    order by couple_day.starts_at desc
    limit 1
  )
  select
    exists (
      select 1
      from current_day
      join public.couple_activity_events event
        on event.couple_day_id = current_day.id
      where event.couple_id = p_couple_id
        and event.user_id = p_current_user_id
    ),
    exists (
      select 1
      from current_day
      join public.couple_activity_events event
        on event.couple_day_id = current_day.id
      join public.couple_members member
        on member.couple_id = event.couple_id
        and member.user_id = event.user_id
      where event.couple_id = p_couple_id
        and event.user_id <> p_current_user_id
        and member.status = 'active'
    );
$$;


ALTER FUNCTION "internal"."get_couple_streak_participation_for_user"("p_couple_id" "uuid", "p_current_user_id" "uuid", "p_observed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_current_entitled_couple_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  select couple.id
  into resolved_couple_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
    and exists (
      select 1
      from public.couple_members entitled_member
      join internal.resolve_user_entitlement(entitled_member.user_id) entitlement
        on entitlement.is_entitled
      where entitled_member.couple_id = couple.id
        and entitled_member.status = 'active'
    )
  order by couple.created_at desc
  limit 1;

  if resolved_couple_id is null then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  return resolved_couple_id;
end;
$$;


ALTER FUNCTION "internal"."get_current_entitled_couple_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_current_relationship_state"() RETURNS TABLE("couple_id" "uuid", "pair_id" "uuid", "relationship_status" "text", "member_status" "text", "partner_user_id" "uuid", "partner_display_name" "text", "partner_profile_photo_asset_id" "uuid", "started_on" "date", "ended_at" timestamp with time zone, "delete_after" timestamp with time zone, "ended_notice_seen_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    couple.id,
    couple.pair_id,
    couple.status,
    self_member.status,
    partner_member.user_id,
    case
      when partner_profile.moderation_status = 'visible' then partner_profile.display_name
      else null
    end,
    case
      when partner_profile.moderation_status = 'visible' then coalesce(
        partner_profile.profile_photo_asset_id,
        partner_profile.provider_profile_photo_asset_id
      )
      else null
    end,
    couple.started_on,
    couple.ended_at,
    couple.delete_after,
    self_member.ended_notice_seen_at
  from public.couple_members self_member
  join public.couples couple
    on couple.id = self_member.couple_id
  left join public.couple_members partner_member
    on partner_member.couple_id = self_member.couple_id
    and partner_member.user_id <> self_member.user_id
  left join public.profiles partner_profile
    on partner_profile.user_id = partner_member.user_id
  where self_member.user_id = (select auth.uid())
    and (
      (couple.status = 'active' and self_member.status = 'active')
      or (
        couple.status = 'ended'
        and self_member.status in ('ended_notice_pending', 'ended_notice_seen', 'left')
      )
    )
  order by
    case when couple.status = 'active' and self_member.status = 'active' then 0 else 1 end,
    couple.created_at desc
  limit 1;
$$;


ALTER FUNCTION "internal"."get_current_relationship_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_answer_details"("p_couple_day_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = (select auth.uid()),
    internal.can_view_daily_answer(answer.id),
    case
      when internal.can_view_daily_answer(answer.id) then answer_text.body
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then partner_choice.selected_user_id
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from public.couple_days couple_day
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where couple_day.id = p_couple_day_id
    and internal.can_access_couple_content(couple_day.couple_id)
  order by instance.slot_number, answer.created_at;
$$;


ALTER FUNCTION "internal"."get_daily_answer_details"("p_couple_day_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_answer_details_for_context"("p_couple_day_ids" "uuid"[], "p_current_user_id" "uuid", "p_couple_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = p_current_user_id,
    visibility.can_view_answer,
    case
      when visibility.can_view_answer then answer_text.body
      else null
    end,
    case
      when visibility.can_view_answer then partner_choice.selected_user_id
      else null
    end,
    case
      when visibility.can_view_answer then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from public.couple_days couple_day
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  left join public.daily_question_answers viewer_answer
    on viewer_answer.instance_id = answer.instance_id
    and viewer_answer.user_id = p_current_user_id
    and viewer_answer.deleted_at is null
    and viewer_answer.moderation_status = 'visible'
  cross join lateral (
    select answer.user_id = p_current_user_id or viewer_answer.id is not null as can_view_answer
  ) visibility
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where couple_day.id = any(coalesce(p_couple_day_ids, array[]::uuid[]))
    and couple_day.couple_id = p_couple_id
  order by couple_day.starts_at desc, instance.slot_number, answer.created_at, answer.id;
$$;


ALTER FUNCTION "internal"."get_daily_answer_details_for_context"("p_couple_day_ids" "uuid"[], "p_current_user_id" "uuid", "p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_context as materialized (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  )
  select details.*
  from current_context context
  cross join lateral internal.get_daily_answer_details_for_context(
    p_couple_day_ids,
    context.current_user_id,
    context.couple_id
  ) details;
$$;


ALTER FUNCTION "internal"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_answer_history_details"() RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with context as (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  )
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = context.current_user_id,
    internal.can_view_daily_answer(answer.id),
    case
      when internal.can_view_daily_answer(answer.id) then answer_text.body
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then partner_choice.selected_user_id
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from context
  join public.couple_days couple_day
    on couple_day.couple_id = context.couple_id
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where internal.can_access_couple_content(couple_day.couple_id)
    -- Only return details for exchanges the viewer engaged with — both their own
    -- answer and the partner's revealed reply for instances they answered.
    and exists (
      select 1
      from public.daily_question_answers viewer_answer
      where viewer_answer.instance_id = instance.id
        and viewer_answer.user_id = context.current_user_id
        and viewer_answer.deleted_at is null
        and viewer_answer.moderation_status = 'visible'
    )
  order by couple_day.starts_at desc, instance.slot_number, answer.created_at;
$$;


ALTER FUNCTION "internal"."get_daily_answer_history_details"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = (select auth.uid()),
    internal.can_view_daily_answer(answer.id)
  from public.couple_days couple_day
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  where couple_day.id = p_couple_day_id
    and internal.can_access_couple_content(couple_day.couple_id)
  order by instance.slot_number, answer.created_at;
$$;


ALTER FUNCTION "internal"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_questions_for_couple_day"("p_couple_day_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with target_day as (
    select couple_day.*
    from public.couple_days couple_day
    where couple_day.id = p_couple_day_id
      and internal.can_access_couple_content(couple_day.couple_id)
  )
  select
    target_day.id,
    target_day.couple_id,
    target_day.local_date,
    target_day.starts_at,
    target_day.ends_at,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.status,
    question.id,
    version.id,
    question.key,
    en_localization.prompt,
    en_localization.short_prompt,
    nb_localization.prompt,
    nb_localization.short_prompt,
    (
      select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ),
    own_answer.id,
    own_answer.created_at,
    partner_answer.id,
    partner_answer.created_at,
    coalesce(internal.can_view_daily_answer(partner_answer.id), false)
  from target_day
  join public.daily_question_instances instance
    on instance.couple_day_id = target_day.id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  join public.question_version_localizations en_localization
    on en_localization.question_version_id = version.id
    and en_localization.locale = 'en'
  join public.question_version_localizations nb_localization
    on nb_localization.question_version_id = version.id
    and nb_localization.locale = 'nb'
  left join public.daily_question_answers own_answer
    on own_answer.instance_id = instance.id
    and own_answer.user_id = (select auth.uid())
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> (select auth.uid())
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where instance.status in ('active', 'answered')
    and (
      instance.seeded_for_user_id = (select auth.uid())
      or partner_answer.id is not null
    )
  order by instance.seeded_for_user_id = (select auth.uid()) desc,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.created_at;
$$;


ALTER FUNCTION "internal"."get_daily_questions_for_couple_day"("p_couple_day_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_daily_questions_history"() RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "effective_local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with context as (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  ),
  anchor as (
    select resolved.anchor_time_zone_id as time_zone_id
    from context
    cross join lateral internal.resolve_couple_day_anchor(context.couple_id) resolved
  )
  select
    couple_day.id,
    couple_day.couple_id,
    couple_day.local_date,
    -- The latest answer's couple-local date. own_answer always exists here (inner
    -- join below); greatest() ignores a null partner answer. Aliased so ORDER BY can
    -- reference it.
    (greatest(own_answer.created_at, partner_answer.created_at) at time zone anchor.time_zone_id)::date
      as effective_local_date,
    couple_day.starts_at,
    couple_day.ends_at,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.status,
    question.id,
    version.id,
    question.key,
    en_localization.prompt,
    en_localization.short_prompt,
    nb_localization.prompt,
    nb_localization.short_prompt,
    (
      select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ),
    own_answer.id,
    own_answer.created_at,
    partner_answer.id,
    partner_answer.created_at,
    coalesce(internal.can_view_daily_answer(partner_answer.id), false)
  from context
  cross join anchor
  join public.couple_days couple_day
    on couple_day.couple_id = context.couple_id
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  join public.question_version_localizations en_localization
    on en_localization.question_version_id = version.id
    and en_localization.locale = 'en'
  join public.question_version_localizations nb_localization
    on nb_localization.question_version_id = version.id
    and nb_localization.locale = 'nb'
  -- Inner join: only questions the viewer has actually answered surface in history,
  -- so every row has the viewer's own answer to show.
  join public.daily_question_answers own_answer
    on own_answer.instance_id = instance.id
    and own_answer.user_id = context.current_user_id
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> context.current_user_id
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where instance.status in ('active', 'answered')
    and internal.can_access_couple_content(couple_day.couple_id)
  order by effective_local_date desc, instance.slot_number, instance.created_at;
$$;


ALTER FUNCTION "internal"."get_daily_questions_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_entitled_couple_id_for_user"("p_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select couple.id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = p_user_id
    and member.status = 'active'
    and couple.status = 'active'
    and exists (
      select 1
      from public.couple_members any_member
      join internal.resolve_user_entitlement(any_member.user_id) entitlement
        on entitlement.is_entitled
      where any_member.couple_id = couple.id
        and any_member.status = 'active'
    )
  order by couple.created_at desc
  limit 1;
$$;


ALTER FUNCTION "internal"."get_entitled_couple_id_for_user"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer DEFAULT 900) RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "expires_in_seconds" integer, "signed_url_expires_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  asset_row public.media_assets%rowtype;
  resolved_expires_in_seconds integer;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  resolved_expires_in_seconds = coalesce(p_expires_in_seconds, 900);

  if resolved_expires_in_seconds < 60 or resolved_expires_in_seconds > 3600 then
    raise exception 'signed URL expiration is out of range'
      using errcode = '23514';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = p_media_asset_id;

  if not found or not internal.can_read_media_object(asset_row.bucket, asset_row.storage_path) then
    raise exception 'media asset is not available'
      using errcode = '42501';
  end if;

  return query
  select
    asset_row.id,
    asset_row.bucket,
    asset_row.storage_path,
    resolved_expires_in_seconds,
    now() + make_interval(secs => resolved_expires_in_seconds);
end;
$$;


ALTER FUNCTION "internal"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_memories"("p_updated_after" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_cursor_memory_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 100) RETURNS TABLE("memory_id" "uuid", "couple_id" "uuid", "title" "text", "memory_date" "date", "created_by_user_id" "uuid", "last_edited_by_user_id" "uuid", "revision" integer, "moderation_status" "text", "deleted_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "sync_updated_at" timestamp with time zone, "own_note_id" "uuid", "own_note_body" "text", "own_note_revision" integer, "own_note_updated_at" timestamp with time zone, "own_note_deleted_at" timestamp with time zone, "own_note_moderation_status" "text", "partner_note_id" "uuid", "partner_note_user_id" "uuid", "partner_note_body" "text", "partner_note_revision" integer, "partner_note_updated_at" timestamp with time zone, "partner_note_deleted_at" timestamp with time zone, "partner_note_moderation_status" "text", "memory_media_ids" "uuid"[], "media_asset_ids" "uuid"[], "memory_media_states" "jsonb", "thread_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'memory read limit is out of range'
      using errcode = '23514';
  end if;

  return query
  with current_couple as (
    select internal.get_current_entitled_couple_id() as couple_id
  ),
  memory_rows as (
  select
    memory.id as memory_id,
    memory.couple_id,
    case
      when memory.deleted_at is null and memory.moderation_status = 'visible' then memory.title
      else null
    end as title,
    memory.memory_date,
    memory.created_by_user_id,
    memory.last_edited_by_user_id,
    memory.revision,
    memory.moderation_status,
    memory.deleted_at,
    memory.created_at,
    memory.updated_at,
    greatest(
      memory.updated_at,
      coalesce(own_note.updated_at, '-infinity'::timestamptz),
      coalesce(partner_note.updated_at, '-infinity'::timestamptz),
      coalesce(media.media_updated_at, '-infinity'::timestamptz)
    ) as sync_updated_at,
    own_note.id,
    case
      when memory.deleted_at is null
        and memory.moderation_status = 'visible'
        and own_note.deleted_at is null
        and own_note.moderation_status = 'visible'
        then own_note.body
      else null
    end as own_note_body,
    own_note.revision,
    own_note.updated_at,
    own_note.deleted_at,
    own_note.moderation_status,
    partner_note.id,
    partner_note.user_id,
    case
      when memory.deleted_at is null
        and memory.moderation_status = 'visible'
        and partner_note.deleted_at is null
        and partner_note.moderation_status = 'visible'
        then partner_note.body
      else null
    end as partner_note_body,
    partner_note.revision,
    partner_note.updated_at,
    partner_note.deleted_at,
    partner_note.moderation_status,
    coalesce(media.memory_media_ids, array[]::uuid[]),
    coalesce(media.media_asset_ids, array[]::uuid[]),
    coalesce(media.memory_media_states, '[]'::jsonb),
    memory_thread.thread_id
  from current_couple
  join public.memories memory
    on memory.couple_id = current_couple.couple_id
  left join public.memory_notes own_note
    on own_note.memory_id = memory.id
    and own_note.user_id = (select auth.uid())
  left join public.memory_notes partner_note
    on partner_note.memory_id = memory.id
    and partner_note.user_id <> (select auth.uid())
  left join lateral (
    select
      array_agg(memory_media.id order by memory_media.owner_user_id, memory_media.sort_order, memory_media.id)
        filter (
          where memory.deleted_at is null
            and memory_media.deleted_at is null
            and memory_media.moderation_status = 'visible'
            and asset.reserved_parent_kind = 'memory_media'
            and asset.reserved_parent_id = memory_media.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        ) as memory_media_ids,
      array_agg(memory_media.media_asset_id order by memory_media.owner_user_id, memory_media.sort_order, memory_media.id)
        filter (
          where memory.deleted_at is null
            and memory_media.deleted_at is null
            and memory_media.moderation_status = 'visible'
            and asset.reserved_parent_kind = 'memory_media'
            and asset.reserved_parent_id = memory_media.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        ) as media_asset_ids,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'memory_media_id', memory_media.id,
            'media_asset_id', memory_media.media_asset_id,
            'owner_user_id', memory_media.owner_user_id,
            'sort_order', memory_media.sort_order,
            'deleted_at', memory_media.deleted_at,
            'moderation_status', memory_media.moderation_status,
            'asset_deleted_at', asset.deleted_at,
            'asset_moderation_status', asset.moderation_status,
            'asset_storage_delete_status', asset.storage_delete_status,
            'updated_at', greatest(memory_media.updated_at, asset.updated_at)
          )
          order by memory_media.owner_user_id, memory_media.sort_order, memory_media.id
        ),
        '[]'::jsonb
      ) as memory_media_states,
      max(greatest(memory_media.updated_at, asset.updated_at)) as media_updated_at
    from public.memory_media memory_media
    join public.media_assets asset
      on asset.id = memory_media.media_asset_id
    where memory_media.memory_id = memory.id
  ) media
    on true
  left join public.memory_threads memory_thread
    on memory_thread.memory_id = memory.id
  )
  select *
  from memory_rows memory_page
  where p_updated_after is null
    or memory_page.sync_updated_at > p_updated_after
    or (
      memory_page.sync_updated_at = p_updated_after
      and memory_page.memory_id > coalesce(p_cursor_memory_id, '00000000-0000-0000-0000-000000000000'::uuid)
    )
  order by memory_page.sync_updated_at, memory_page.memory_id
  limit p_limit;
end;
$$;


ALTER FUNCTION "internal"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_or_create_app_account_token"("p_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_token uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null or p_user_id is distinct from current_user_id then
    raise exception 'not authorized'
      using errcode = '42501';
  end if;

  select app_token.token
  into resolved_token
  from internal.app_account_tokens app_token
  where app_token.user_id = p_user_id;

  if resolved_token is null then
    insert into internal.app_account_tokens (user_id)
    values (p_user_id)
    on conflict (user_id) do update
      set updated_at = now()
    returning token into resolved_token;
  end if;

  return resolved_token;
end;
$$;


ALTER FUNCTION "internal"."get_or_create_app_account_token"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_or_create_couple_day_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  anchor_row record;
  resolved_couple_day_id uuid;
begin
  if p_observed_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  select id
  into resolved_couple_day_id
  from public.couple_days
  where couple_id = p_couple_id
    and p_observed_at >= starts_at
    and p_observed_at < ends_at
  order by starts_at desc
  limit 1;

  if resolved_couple_day_id is not null then
    return resolved_couple_day_id;
  end if;

  select *
  into anchor_row
  from internal.resolve_couple_day_anchor_at(p_couple_id, p_observed_at);

  insert into public.couple_days (
    couple_id,
    local_date,
    anchor_time_zone_id,
    starts_at,
    ends_at
  ) values (
    p_couple_id,
    anchor_row.local_date,
    anchor_row.anchor_time_zone_id,
    anchor_row.starts_at,
    anchor_row.ends_at
  )
  on conflict (couple_id, local_date) do nothing
  returning id into resolved_couple_day_id;

  if resolved_couple_day_id is null then
    select id
    into resolved_couple_day_id
    from public.couple_days
    where couple_id = p_couple_id
      and local_date = anchor_row.local_date;
  end if;

  return resolved_couple_day_id;
end;
$$;


ALTER FUNCTION "internal"."get_or_create_couple_day_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_or_create_relationship_pair"("p_first_user_id" "uuid", "p_second_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  low_user_id uuid;
  high_user_id uuid;
  existing_pair_id uuid;
begin
  if p_first_user_id is null or p_second_user_id is null or p_first_user_id = p_second_user_id then
    raise exception 'relationship pair requires two distinct users'
      using errcode = '23514';
  end if;

  if p_first_user_id < p_second_user_id then
    low_user_id = p_first_user_id;
    high_user_id = p_second_user_id;
  else
    low_user_id = p_second_user_id;
    high_user_id = p_first_user_id;
  end if;

  insert into public.relationship_pairs (user_low_id, user_high_id)
  values (low_user_id, high_user_id)
  on conflict (user_low_id, user_high_id) do nothing
  returning id into existing_pair_id;

  if existing_pair_id is null then
    select id
    into existing_pair_id
    from public.relationship_pairs
    where user_low_id = low_user_id
      and user_high_id = high_user_id;
  end if;

  return existing_pair_id;
end;
$$;


ALTER FUNCTION "internal"."get_or_create_relationship_pair"("p_first_user_id" "uuid", "p_second_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_or_create_today_couple_day"("p_couple_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.get_or_create_couple_day_at(p_couple_id, now());
$$;


ALTER FUNCTION "internal"."get_or_create_today_couple_day"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_or_create_widget_canvas"("p_couple_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("canvas_id" "uuid", "couple_id" "uuid", "active_revision_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  if p_couple_id is null then
    resolved_couple_id = internal.get_current_entitled_couple_id();
  else
    resolved_couple_id = p_couple_id;

    if not internal.can_access_couple_content(resolved_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'widget_canvas:' || resolved_couple_id::text,
      0
    )
  );

  insert into public.widget_canvases (couple_id)
  values (resolved_couple_id)
  on conflict on constraint widget_canvases_couple_id_unique do nothing;

  return query
  select
    canvas.id,
    canvas.couple_id,
    canvas.active_revision_id,
    canvas.created_at,
    canvas.updated_at
  from public.widget_canvases canvas
  where canvas.couple_id = resolved_couple_id
    and canvas.deleted_at is null;
end;
$$;


ALTER FUNCTION "internal"."get_or_create_widget_canvas"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_partner_location_visibility"("p_couple_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("couple_id" "uuid", "viewer_user_id" "uuid", "partner_user_id" "uuid", "visibility_state" "text", "viewer_sharing_enabled" boolean, "partner_sharing_enabled" boolean, "partner_location_latitude" numeric, "partner_location_longitude" numeric, "partner_location_accuracy_m" numeric, "partner_location_captured_at" timestamp with time zone, "partner_location_is_stale" boolean, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  couple_status text;
  viewer_member_status text;
  partner_member_user_id uuid;
  viewer_enabled boolean := false;
  partner_enabled boolean := false;
  partner_location public.latest_partner_locations%rowtype;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_couple_id is null then
    resolved_couple_id = internal.get_current_entitled_couple_id();
  else
    resolved_couple_id = p_couple_id;
  end if;

  select couple.status, member.status
  into couple_status, viewer_member_status
  from public.couples couple
  join public.couple_members member
    on member.couple_id = couple.id
  where couple.id = resolved_couple_id
    and member.user_id = current_user_id
    and member.status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen');

  if not found then
    raise exception 'relationship was not found'
      using errcode = '42501';
  end if;

  select member.user_id
  into partner_member_user_id
  from public.couple_members member
  where member.couple_id = resolved_couple_id
    and member.user_id <> current_user_id
    and member.status = 'active'
  order by member.joined_at desc, member.user_id
  limit 1;

  if couple_status <> 'active'
    or viewer_member_status <> 'active'
    or partner_member_user_id is null then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'relationship_ended'::text,
      false,
      false,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  if not internal.can_access_couple_content(resolved_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  select coalesce(preference.is_enabled, false)
  into viewer_enabled
  from public.location_sharing_preferences preference
  where preference.couple_id = resolved_couple_id
    and preference.user_id = current_user_id;

  viewer_enabled = coalesce(viewer_enabled, false);

  select coalesce(preference.is_enabled, false)
  into partner_enabled
  from public.location_sharing_preferences preference
  where preference.couple_id = resolved_couple_id
    and preference.user_id = partner_member_user_id;

  partner_enabled = coalesce(partner_enabled, false);

  if not viewer_enabled then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'disabled'::text,
      false,
      partner_enabled,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  if not partner_enabled then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'not_sharing'::text,
      true,
      false,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  select *
  into partner_location
  from public.latest_partner_locations latest
  where latest.couple_id = resolved_couple_id
    and latest.user_id = partner_member_user_id;

  if not found then
    return query
    select
      resolved_couple_id,
      current_user_id,
      partner_member_user_id,
      'not_sharing'::text,
      true,
      true,
      null::numeric,
      null::numeric,
      null::numeric,
      null::timestamptz,
      false,
      now();
    return;
  end if;

  return query
  select
    resolved_couple_id,
    current_user_id,
    partner_member_user_id,
    'visible'::text,
    true,
    true,
    partner_location.latitude,
    partner_location.longitude,
    partner_location.accuracy_m,
    partner_location.captured_at,
    partner_location.captured_at < now() - interval '24 hours',
    partner_location.updated_at;
end;
$$;


ALTER FUNCTION "internal"."get_partner_location_visibility"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_question_answer_history"("p_question_id" "uuid") RETURNS TABLE("question_id" "uuid", "question_version_id" "uuid", "couple_day_id" "uuid", "local_date" "date", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    question.id,
    version.id,
    couple_day.id,
    couple_day.local_date,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    internal.can_view_daily_answer(answer.id),
    case
      when internal.can_view_daily_answer(answer.id) then answer_text.body
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then partner_choice.selected_user_id
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from public.daily_question_answers answer
  join public.daily_question_instances instance
    on instance.id = answer.instance_id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where question.id = p_question_id
    and question.resurfaceable
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
    and internal.can_access_couple_content(couple_day.couple_id)
  order by couple_day.local_date desc, answer.created_at desc, answer.id;
$$;


ALTER FUNCTION "internal"."get_question_answer_history"("p_question_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_thread_messages"("p_thread_id" "uuid") RETURNS TABLE("thread_id" "uuid", "message_id" "uuid", "sender_user_id" "uuid", "body" "text", "created_at" timestamp with time zone, "edited_at" timestamp with time zone, "deleted_at" timestamp with time zone, "moderation_status" "text", "media_asset_ids" "uuid"[], "media_states" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    thread.id,
    message.id,
    message.sender_user_id,
    case
      when thread.deleted_at is null
        and thread.moderation_status = 'visible'
        and message.deleted_at is null
        and message.moderation_status = 'visible'
        then message.body
      else null
    end,
    message.created_at,
    message.edited_at,
    message.deleted_at,
    message.moderation_status,
    coalesce(media.media_asset_ids, array[]::uuid[]),
    coalesce(media.media_states, '[]'::jsonb)
  from public.conversation_threads thread
  join public.thread_messages message
    on message.thread_id = thread.id
  left join lateral (
    select
      array_agg(message_media.media_asset_id order by message_media.sort_order)
        filter (
          where thread.deleted_at is null
            and thread.moderation_status = 'visible'
            and message.deleted_at is null
            and message.moderation_status = 'visible'
            and asset.reserved_parent_kind = 'thread_message_media'
            and asset.reserved_parent_id = message.id
            and asset.upload_status = 'finalized'
            and asset.storage_delete_status = 'none'
            and asset.moderation_status = 'visible'
            and asset.deleted_at is null
        ) as media_asset_ids,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'media_asset_id', message_media.media_asset_id,
            'sort_order', message_media.sort_order,
            'asset_deleted_at', asset.deleted_at,
            'asset_moderation_status', asset.moderation_status,
            'asset_storage_delete_status', asset.storage_delete_status,
            'updated_at', asset.updated_at
          )
          order by message_media.sort_order, message_media.media_asset_id
        ),
        '[]'::jsonb
      ) as media_states
    from public.thread_message_media message_media
    join public.media_assets asset
      on asset.id = message_media.media_asset_id
    where message_media.message_id = message.id
  ) media
    on true
  where thread.id = p_thread_id
    and internal.can_access_couple_content(thread.couple_id)
  order by message.created_at, message.id;
$$;


ALTER FUNCTION "internal"."get_thread_messages"("p_thread_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_today_daily_challenge_snapshot"() RETURNS TABLE("questions" "jsonb", "answer_details" "jsonb", "streak" "jsonb", "generated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_context as materialized (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  ),
  question_rows as materialized (
    select questions.*
    from current_context context
    cross join lateral internal.get_today_daily_questions_for_context(
      context.current_user_id,
      context.couple_id
    ) questions
  ),
  answer_detail_rows as materialized (
    select details.*
    from current_context context
    cross join lateral internal.get_daily_answer_details_for_context(
      coalesce(
        (select array_agg(distinct question_rows.couple_day_id) from question_rows),
        array[]::uuid[]
      ),
      context.current_user_id,
      context.couple_id
    ) details
  ),
  streak_rows as materialized (
    select streak.*
    from current_context context
    cross join lateral internal.get_couple_streak_for_couple(context.couple_id) streak
  ),
  participation_rows as materialized (
    select participation.*
    from current_context context
    cross join lateral internal.get_couple_streak_participation_for_user(
      context.couple_id,
      context.current_user_id,
      now()
    ) participation
  )
  select
    coalesce(
      (
        select jsonb_agg(to_jsonb(question_rows) order by
          question_rows.is_current_day desc nulls last,
          question_rows.starts_at desc,
          question_rows.seeded_for_user_id,
          question_rows.slot_number,
          question_rows.instance_id
        )
        from question_rows
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(answer_detail_rows) order by
          answer_detail_rows.couple_day_id,
          answer_detail_rows.slot_number,
          answer_detail_rows.answered_at,
          answer_detail_rows.answer_id
        )
        from answer_detail_rows
      ),
      '[]'::jsonb
    ),
    (
      select to_jsonb(streak_rows) || to_jsonb(participation_rows)
      from streak_rows
      cross join participation_rows
      limit 1
    ),
    now();
$$;


ALTER FUNCTION "internal"."get_today_daily_challenge_snapshot"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_today_daily_questions"() RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean, "is_current_day" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_context as materialized (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  )
  select questions.*
  from current_context context
  cross join lateral internal.get_today_daily_questions_for_context(
    context.current_user_id,
    context.couple_id
  ) questions;
$$;


ALTER FUNCTION "internal"."get_today_daily_questions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_today_daily_questions_for_context"("p_current_user_id" "uuid", "p_couple_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean, "is_current_day" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_context as (
    select
      p_current_user_id as current_user_id,
      p_couple_id as couple_id
  ),
  anchor as (
    select resolved.anchor_time_zone_id as time_zone_id
    from current_context
    cross join lateral internal.resolve_couple_day_anchor(current_context.couple_id) resolved
  ),
  current_day as (
    select couple_day.id, couple_day.starts_at
    from public.couple_days couple_day
    join current_context context
      on context.couple_id = couple_day.couple_id
    where now() >= couple_day.starts_at
      and now() < couple_day.ends_at
    order by couple_day.starts_at desc
    limit 1
  ),
  selected_instances as (
    select instance.id, true as is_current_day
    from current_day
    join public.daily_question_instances instance
      on instance.couple_day_id = current_day.id
    where instance.status in ('active', 'answered')

    union

    select instance.id, false as is_current_day
    from current_context context
    cross join anchor
    join public.couple_days couple_day
      on couple_day.couple_id = context.couple_id
    join public.daily_question_instances instance
      on instance.couple_day_id = couple_day.id
    left join public.daily_question_answers viewer_answer
      on viewer_answer.instance_id = instance.id
      and viewer_answer.user_id = context.current_user_id
      and viewer_answer.deleted_at is null
      and viewer_answer.moderation_status = 'visible'
    left join public.daily_question_answers seeded_answer
      on seeded_answer.instance_id = instance.id
      and seeded_answer.user_id = instance.seeded_for_user_id
      and seeded_answer.deleted_at is null
      and seeded_answer.moderation_status = 'visible'
    left join public.daily_question_answers other_answer
      on other_answer.instance_id = instance.id
      and other_answer.user_id <> context.current_user_id
      and other_answer.deleted_at is null
      and other_answer.moderation_status = 'visible'
    where instance.status in ('active', 'answered')
      and not exists (
        select 1
        from current_day
        where current_day.id = couple_day.id
      )
      and couple_day.starts_at < coalesce((select current_day.starts_at from current_day), now())
      and (
        (
          instance.seeded_for_user_id <> context.current_user_id
          and seeded_answer.id is not null
          and viewer_answer.id is null
        )
        or (
          instance.seeded_for_user_id = context.current_user_id
          and viewer_answer.id is not null
          and other_answer.id is null
        )
        or (
          greatest(viewer_answer.created_at, other_answer.created_at) is not null
          and (greatest(viewer_answer.created_at, other_answer.created_at) at time zone anchor.time_zone_id)::date
            = (now() at time zone anchor.time_zone_id)::date
        )
      )
  )
  select
    couple_day.id,
    couple_day.couple_id,
    couple_day.local_date,
    couple_day.starts_at,
    couple_day.ends_at,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.status,
    question.id,
    version.id,
    question.key,
    en_localization.prompt,
    en_localization.short_prompt,
    nb_localization.prompt,
    nb_localization.short_prompt,
    (
      select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ),
    own_answer.id,
    own_answer.created_at,
    partner_answer.id,
    partner_answer.created_at,
    partner_answer.id is not null and own_answer.id is not null,
    selected_instances.is_current_day
  from selected_instances
  join public.daily_question_instances instance
    on instance.id = selected_instances.id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join current_context context
    on context.couple_id = couple_day.couple_id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  join public.question_version_localizations en_localization
    on en_localization.question_version_id = version.id
    and en_localization.locale = 'en'
  join public.question_version_localizations nb_localization
    on nb_localization.question_version_id = version.id
    and nb_localization.locale = 'nb'
  left join public.daily_question_answers own_answer
    on own_answer.instance_id = instance.id
    and own_answer.user_id = context.current_user_id
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> context.current_user_id
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where selected_instances.is_current_day = false
    or instance.seeded_for_user_id = context.current_user_id
    or partner_answer.id is not null
  order by
    selected_instances.is_current_day desc,
    couple_day.starts_at desc,
    instance.seeded_for_user_id = context.current_user_id desc,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.created_at;
$$;


ALTER FUNCTION "internal"."get_today_daily_questions_for_context"("p_current_user_id" "uuid", "p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_user_id_by_app_account_token"("p_token" "uuid") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select app_token.user_id
  from internal.app_account_tokens app_token
  where app_token.token = p_token;
$$;


ALTER FUNCTION "internal"."get_user_id_by_app_account_token"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_widget_canvas"("p_couple_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("canvas_id" "uuid", "couple_id" "uuid", "active_revision_id" "uuid", "active_revision_moderation_status" "text", "active_revision_deleted_at" timestamp with time zone, "active_revision_author_user_id" "uuid", "payload_media_asset_id" "uuid", "payload_bucket" "text", "payload_storage_path" "text", "payload_sha256_hex" "text", "payload_bytes" bigint, "uncompressed_bytes" bigint, "compression" "text", "stroke_count" integer, "point_count" integer, "bounds" "jsonb", "format" "text", "format_version" integer, "renderer_version" integer, "client_decode_validated_at" timestamp with time zone, "client_renderer_version" "text", "client_validation_version" "text", "revision_created_at" timestamp with time zone, "canvas_created_at" timestamp with time zone, "canvas_updated_at" timestamp with time zone, "sync_updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
begin
  if p_couple_id is null then
    resolved_couple_id = internal.get_current_entitled_couple_id();
  else
    resolved_couple_id = p_couple_id;

    if not internal.can_access_couple_content(resolved_couple_id) then
      raise exception 'active entitled couple access is required'
        using errcode = '42501';
    end if;
  end if;

  return query
  select
    canvas.id,
    canvas.couple_id,
    canvas.active_revision_id,
    revision.moderation_status,
    revision.deleted_at,
    case when visible_payload.is_visible then revision.author_user_id end,
    case when visible_payload.is_visible then revision.payload_media_asset_id end,
    case when visible_payload.is_visible then asset.bucket end,
    case when visible_payload.is_visible then asset.storage_path end,
    case when visible_payload.is_visible then encode(asset.sha256, 'hex') end,
    case when visible_payload.is_visible then revision.payload_bytes end,
    case when visible_payload.is_visible then revision.uncompressed_bytes end,
    case when visible_payload.is_visible then revision.compression end,
    case when visible_payload.is_visible then revision.stroke_count end,
    case when visible_payload.is_visible then revision.point_count end,
    case when visible_payload.is_visible then revision.bounds end,
    case when visible_payload.is_visible then revision.format end,
    case when visible_payload.is_visible then revision.format_version end,
    case when visible_payload.is_visible then revision.renderer_version end,
    case when visible_payload.is_visible then revision.client_decode_validated_at end,
    case when visible_payload.is_visible then revision.client_renderer_version end,
    case when visible_payload.is_visible then revision.client_validation_version end,
    case when visible_payload.is_visible then revision.created_at end,
    canvas.created_at,
    canvas.updated_at,
    greatest(
      canvas.updated_at,
      coalesce(revision.updated_at, '-infinity'::timestamptz),
      coalesce(asset.updated_at, '-infinity'::timestamptz)
    )
  from public.widget_canvases canvas
  left join public.widget_drawing_revisions revision
    on revision.id = canvas.active_revision_id
  left join public.media_assets asset
    on asset.id = revision.payload_media_asset_id
  cross join lateral (
    select coalesce(
      revision.id is not null
      and revision.deleted_at is null
      and revision.moderation_status = 'visible'
      and asset.id is not null
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null,
      false
    ) as is_visible
  ) visible_payload
  where canvas.couple_id = resolved_couple_id
    and canvas.deleted_at is null;
end;
$$;


ALTER FUNCTION "internal"."get_widget_canvas"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_limit" integer DEFAULT 100, "p_updated_after_revision_id" "uuid" DEFAULT NULL::"uuid", "p_created_before" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_created_before_revision_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("canvas_id" "uuid", "revision_id" "uuid", "author_user_id" "uuid", "parent_revision_id" "uuid", "moderation_status" "text", "deleted_at" timestamp with time zone, "payload_media_asset_id" "uuid", "payload_bucket" "text", "payload_storage_path" "text", "payload_sha256_hex" "text", "payload_bytes" bigint, "uncompressed_bytes" bigint, "compression" "text", "stroke_count" integer, "point_count" integer, "bounds" "jsonb", "format" "text", "format_version" integer, "renderer_version" integer, "client_decode_validated_at" timestamp with time zone, "client_renderer_version" "text", "client_validation_version" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "sync_updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'widget drawing revision read limit is out of range'
      using errcode = '23514';
  end if;

  if p_updated_after is not null and p_created_before is not null then
    raise exception 'widget drawing sync and history cursors cannot be combined'
      using errcode = '23514';
  end if;

  if (p_updated_after is null) <> (p_updated_after_revision_id is null) then
    raise exception 'widget drawing sync cursor requires timestamp and revision id'
      using errcode = '23514';
  end if;

  if (p_created_before is null) <> (p_created_before_revision_id is null) then
    raise exception 'widget drawing history cursor requires timestamp and revision id'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.widget_canvases canvas
    where canvas.id = p_canvas_id
      and canvas.deleted_at is null
      and internal.can_access_couple_content(canvas.couple_id)
  ) then
    raise exception 'active entitled widget canvas access is required'
      using errcode = '42501';
  end if;

  if p_updated_after is not null then
    return query
    with revision_rows as (
      select
        revision.canvas_id as row_canvas_id,
        revision.id as row_revision_id,
        revision.author_user_id as row_author_user_id,
        revision.parent_revision_id as row_parent_revision_id,
        revision.moderation_status as row_moderation_status,
        revision.deleted_at as row_deleted_at,
        case when visible_payload.is_visible then revision.payload_media_asset_id end as row_payload_media_asset_id,
        case when visible_payload.is_visible then asset.bucket end as row_payload_bucket,
        case when visible_payload.is_visible then asset.storage_path end as row_payload_storage_path,
        case when visible_payload.is_visible then encode(asset.sha256, 'hex') end as row_payload_sha256_hex,
        case when visible_payload.is_visible then revision.payload_bytes end as row_payload_bytes,
        case when visible_payload.is_visible then revision.uncompressed_bytes end as row_uncompressed_bytes,
        case when visible_payload.is_visible then revision.compression end as row_compression,
        case when visible_payload.is_visible then revision.stroke_count end as row_stroke_count,
        case when visible_payload.is_visible then revision.point_count end as row_point_count,
        case when visible_payload.is_visible then revision.bounds end as row_bounds,
        case when visible_payload.is_visible then revision.format end as row_format,
        case when visible_payload.is_visible then revision.format_version end as row_format_version,
        case when visible_payload.is_visible then revision.renderer_version end as row_renderer_version,
        case when visible_payload.is_visible then revision.client_decode_validated_at end as row_client_decode_validated_at,
        case when visible_payload.is_visible then revision.client_renderer_version end as row_client_renderer_version,
        case when visible_payload.is_visible then revision.client_validation_version end as row_client_validation_version,
        revision.created_at as row_created_at,
        revision.updated_at as row_updated_at,
        greatest(revision.updated_at, coalesce(asset.updated_at, '-infinity'::timestamptz)) as row_sync_updated_at
      from public.widget_drawing_revisions revision
      join public.media_assets asset
        on asset.id = revision.payload_media_asset_id
      cross join lateral (
        select (
          revision.deleted_at is null
          and revision.moderation_status = 'visible'
          and asset.upload_status = 'finalized'
          and asset.storage_delete_status = 'none'
          and asset.moderation_status = 'visible'
          and asset.deleted_at is null
        ) as is_visible
      ) visible_payload
      where revision.canvas_id = p_canvas_id
    )
    select
      row_canvas_id,
      row_revision_id,
      row_author_user_id,
      row_parent_revision_id,
      row_moderation_status,
      row_deleted_at,
      row_payload_media_asset_id,
      row_payload_bucket,
      row_payload_storage_path,
      row_payload_sha256_hex,
      row_payload_bytes,
      row_uncompressed_bytes,
      row_compression,
      row_stroke_count,
      row_point_count,
      row_bounds,
      row_format,
      row_format_version,
      row_renderer_version,
      row_client_decode_validated_at,
      row_client_renderer_version,
      row_client_validation_version,
      row_created_at,
      row_updated_at,
      row_sync_updated_at
    from revision_rows
    where row_sync_updated_at > p_updated_after
      or (
        row_sync_updated_at = p_updated_after
        and row_revision_id > p_updated_after_revision_id
      )
    order by row_sync_updated_at, row_revision_id
    limit p_limit;

    return;
  end if;

  return query
  with revision_rows as (
    select
      revision.canvas_id as row_canvas_id,
      revision.id as row_revision_id,
      revision.author_user_id as row_author_user_id,
      revision.parent_revision_id as row_parent_revision_id,
      revision.moderation_status as row_moderation_status,
      revision.deleted_at as row_deleted_at,
      case when visible_payload.is_visible then revision.payload_media_asset_id end as row_payload_media_asset_id,
      case when visible_payload.is_visible then asset.bucket end as row_payload_bucket,
      case when visible_payload.is_visible then asset.storage_path end as row_payload_storage_path,
      case when visible_payload.is_visible then encode(asset.sha256, 'hex') end as row_payload_sha256_hex,
      case when visible_payload.is_visible then revision.payload_bytes end as row_payload_bytes,
      case when visible_payload.is_visible then revision.uncompressed_bytes end as row_uncompressed_bytes,
      case when visible_payload.is_visible then revision.compression end as row_compression,
      case when visible_payload.is_visible then revision.stroke_count end as row_stroke_count,
      case when visible_payload.is_visible then revision.point_count end as row_point_count,
      case when visible_payload.is_visible then revision.bounds end as row_bounds,
      case when visible_payload.is_visible then revision.format end as row_format,
      case when visible_payload.is_visible then revision.format_version end as row_format_version,
      case when visible_payload.is_visible then revision.renderer_version end as row_renderer_version,
      case when visible_payload.is_visible then revision.client_decode_validated_at end as row_client_decode_validated_at,
      case when visible_payload.is_visible then revision.client_renderer_version end as row_client_renderer_version,
      case when visible_payload.is_visible then revision.client_validation_version end as row_client_validation_version,
      revision.created_at as row_created_at,
      revision.updated_at as row_updated_at,
      greatest(revision.updated_at, coalesce(asset.updated_at, '-infinity'::timestamptz)) as row_sync_updated_at
    from public.widget_drawing_revisions revision
    join public.media_assets asset
      on asset.id = revision.payload_media_asset_id
    cross join lateral (
      select (
        revision.deleted_at is null
        and revision.moderation_status = 'visible'
        and asset.upload_status = 'finalized'
        and asset.storage_delete_status = 'none'
        and asset.moderation_status = 'visible'
        and asset.deleted_at is null
      ) as is_visible
    ) visible_payload
    where revision.canvas_id = p_canvas_id
  )
  select
    row_canvas_id,
    row_revision_id,
    row_author_user_id,
    row_parent_revision_id,
    row_moderation_status,
    row_deleted_at,
    row_payload_media_asset_id,
    row_payload_bucket,
    row_payload_storage_path,
    row_payload_sha256_hex,
    row_payload_bytes,
    row_uncompressed_bytes,
    row_compression,
    row_stroke_count,
    row_point_count,
    row_bounds,
    row_format,
    row_format_version,
    row_renderer_version,
    row_client_decode_validated_at,
    row_client_renderer_version,
    row_client_validation_version,
    row_created_at,
    row_updated_at,
    row_sync_updated_at
  from revision_rows
  where p_created_before is null
    or row_created_at < p_created_before
    or (
      row_created_at = p_created_before
      and row_revision_id < p_created_before_revision_id
    )
  order by row_created_at desc, row_revision_id desc
  limit p_limit;
end;
$$;


ALTER FUNCTION "internal"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_daily_challenge_completed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_day_row public.couple_days%rowtype;
begin
  if new.completed_at is null
    or old.completed_at is not null then
    return new;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = new.couple_day_id;

  if found then
    perform internal.apply_couple_activity(
      couple_day_row.couple_id,
      new.user_id,
      new.couple_day_id,
      'daily_challenge_completed',
      new.completed_at,
      'daily_challenge_completed:' || new.couple_day_id::text || ':' || new.user_id::text,
      jsonb_build_object('source', 'daily_challenge')
    );

    perform internal.enqueue_partner_notification(
      couple_day_row.couple_id,
      new.user_id,
      'daily_challenge_completed',
      jsonb_build_object(
        'type', 'daily_challenge_completed',
        'couple_id', couple_day_row.couple_id::text,
        'couple_day_id', new.couple_day_id::text,
        'actor_user_id', new.user_id::text,
        'route', 'daily',
        'deeplink', 'paeonia://daily/today?coupleDayId=' || new.couple_day_id::text
      ),
      'daily_challenge_completed:' || new.couple_day_id::text || ':' || new.user_id::text,
      'private',
      'alert',
      'daily:' || couple_day_row.couple_id::text,
      now()
    );

    new.partner_notified_at = coalesce(new.partner_notified_at, now());
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."handle_daily_challenge_completed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_thread_message_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
  resolved_instance_id uuid;
  resolved_memory_id uuid;
  notification_payload jsonb;
begin
  if new.deleted_at is not null or new.moderation_status <> 'visible' then
    return new;
  end if;

  select
    thread.couple_id,
    daily_thread.instance_id,
    memory_thread.memory_id
  into
    resolved_couple_id,
    resolved_instance_id,
    resolved_memory_id
  from public.conversation_threads thread
  left join public.daily_question_threads daily_thread
    on daily_thread.thread_id = thread.id
  left join public.memory_threads memory_thread
    on memory_thread.thread_id = thread.id
  where thread.id = new.thread_id
    and thread.deleted_at is null
    and thread.moderation_status = 'visible';

  if resolved_couple_id is null
    or (resolved_instance_id is null and resolved_memory_id is null) then
    return new;
  end if;

  perform internal.apply_couple_activity(
    resolved_couple_id,
    new.sender_user_id,
    internal.get_or_create_couple_day_at(resolved_couple_id, new.created_at),
    'thread_message_sent',
    new.created_at,
    'thread_message_sent:' || new.id::text,
    jsonb_build_object('thread_id', new.thread_id)
  );

  notification_payload = jsonb_build_object(
    'type', 'thread_message_sent',
    'couple_id', resolved_couple_id::text,
    'thread_id', new.thread_id::text,
    'message_id', new.id::text,
    'actor_user_id', new.sender_user_id::text
  );

  if resolved_instance_id is not null then
    notification_payload = notification_payload || jsonb_build_object(
      'route', 'daily',
      'deeplink', 'paeonia://daily/chat?instanceId=' || resolved_instance_id::text,
      'instance_id', resolved_instance_id::text
    );
  else
    notification_payload = notification_payload || jsonb_build_object(
      'route', 'memories',
      'deeplink', 'paeonia://memories',
      'memory_id', resolved_memory_id::text
    );
  end if;

  -- Push delivery must never make sending a message fail.
  begin
    perform internal.enqueue_partner_notification(
      resolved_couple_id,
      new.sender_user_id,
      'thread_message_sent',
      notification_payload,
      'thread_message_sent:' || new.id::text,
      'private',
      'alert',
      'thread:' || new.thread_id::text,
      now()
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;


ALTER FUNCTION "internal"."handle_thread_message_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_widget_drawing_revision_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  canvas_row public.widget_canvases%rowtype;
  couple_day_id uuid;
  recipient_user_id uuid;
begin
  select *
  into canvas_row
  from public.widget_canvases
  where id = new.canvas_id;

  if not found then
    return new;
  end if;

  couple_day_id = internal.get_or_create_couple_day_at(canvas_row.couple_id, new.created_at);

  perform internal.apply_couple_activity(
    canvas_row.couple_id,
    new.author_user_id,
    couple_day_id,
    'widget_drawing_saved',
    new.created_at,
    'widget_drawing_saved:' || new.id::text,
    jsonb_build_object('canvas_id', new.canvas_id)
  );

  select member.user_id
  into recipient_user_id
  from public.couple_members member
  where member.couple_id = canvas_row.couple_id
    and member.user_id <> new.author_user_id
    and member.status = 'active'
  limit 1;

  if recipient_user_id is not null then
    -- WidgetKit push delivery must never make saving a drawing fail.
    begin
      perform internal.enqueue_widget_push_for_user(
        recipient_user_id,
        'widget_updated',
        jsonb_build_object(
          'type', 'widget_updated',
          'couple_id', canvas_row.couple_id,
          'canvas_id', new.canvas_id,
          'revision_id', new.id,
          'actor_user_id', new.author_user_id,
          'route', 'widget',
          'deeplink', 'paeonia://widget/drawing'
        ),
        'widgetkit:' || new.id::text,
        'widget:' || canvas_row.couple_id::text,
        null
      );
    exception when others then
      null;
    end;
  end if;

  -- Silent refresh: wakes partner's app to pull the new drawing.
  perform internal.enqueue_partner_notification(
    canvas_row.couple_id,
    new.author_user_id,
    'widget_updated',
    jsonb_build_object(
      'type', 'widget_updated',
      'couple_id', canvas_row.couple_id,
      'canvas_id', new.canvas_id,
      'revision_id', new.id,
      'actor_user_id', new.author_user_id,
      'route', 'widget',
      'deeplink', 'paeonia://widget/drawing'
    ),
    'widget_updated:' || new.id::text,
    'private',
    'background',
    'widget:' || canvas_row.couple_id::text,
    now()
  );

  -- Alert: lock-screen banner, gated on the partner's alert toggle.
  perform internal.enqueue_widget_update_alert(
    canvas_row.couple_id,
    new.author_user_id,
    new.canvas_id,
    new.id
  );

  return new;
end;
$$;


ALTER FUNCTION "internal"."handle_widget_drawing_revision_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."has_active_relationship_block"("p_pair_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.relationship_blocks block
    where block.pair_id = p_pair_id
      and block.revoked_at is null
  );
$$;


ALTER FUNCTION "internal"."has_active_relationship_block"("p_pair_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."has_due_account_deletion_work"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from internal.account_deletion_jobs job
    where (
      job.status = 'ready_for_auth_delete'
      and job.next_attempt_at is not null
      and job.next_attempt_at <= p_now
    )
    or (
      job.status = 'processing_auth_delete'
      and job.claimed_at <= p_now - interval '5 minutes'
    )
  );
$$;


ALTER FUNCTION "internal"."has_due_account_deletion_work"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."has_due_push_notification_work"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from internal.notification_outbox outbox
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= p_now
      and outbox.attempt_count < 5
  )
  or exists (
    select 1
    from internal.widget_push_outbox outbox
    join public.widget_push_devices device
      on device.id = outbox.target_widget_device_id
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= p_now
      and outbox.attempt_count < 5
      and device.disabled_at is null
  );
$$;


ALTER FUNCTION "internal"."has_due_push_notification_work"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."hash_pairing_invite_code"("p_invite_code" "text") RETURNS "bytea"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $_$
declare
  invite_code_pepper text;
begin
  if p_invite_code is null or p_invite_code !~ '^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$' then
    raise exception 'invalid invite code'
      using errcode = '23514';
  end if;

  invite_code_pepper = nullif(current_setting('app.invite_code_pepper', true), '');

  if invite_code_pepper is null then
    select nullif(secret.secret_value, '')
    into invite_code_pepper
    from internal.app_runtime_secrets secret
    where secret.secret_name = 'invite_code_pepper';
  end if;

  if invite_code_pepper is null then
    raise exception 'invite code pepper is not configured'
      using errcode = '22023';
  end if;

  return extensions.hmac(p_invite_code, invite_code_pepper, 'sha256');
end;
$_$;


ALTER FUNCTION "internal"."hash_pairing_invite_code"("p_invite_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."hash_review_access_code"("p_code" "text") RETURNS "bytea"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select extensions.digest(p_code, 'sha256');
$$;


ALTER FUNCTION "internal"."hash_review_access_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("memory_id" "uuid", "revision" integer, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'expected memory revision is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'hide_memory',
      p_memory_id::text,
      p_expected_revision::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'hide_memory',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'memory_id')::uuid,
      (replayed_response ->> 'revision')::integer,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  if memory_row.revision <> p_expected_revision then
    raise exception 'memory revision conflict'
      using errcode = '40001';
  end if;

  update public.memories
  set
    deleted_at = now(),
    last_edited_by_user_id = current_user_id
  where id = memory_row.id
  returning public.memories.id, public.memories.revision, public.memories.updated_at
  into memory_id, revision, updated_at;

  update public.conversation_threads thread
  set deleted_at = coalesce(thread.deleted_at, now())
  from public.memory_threads memory_thread
  where memory_thread.thread_id = thread.id
    and memory_thread.memory_id = memory_row.id
    and thread.deleted_at is null;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'memory_id', memory_id,
      'revision', revision,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;


ALTER FUNCTION "internal"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."infer_report_target_for_moderation"("p_report_id" "uuid") RETURNS TABLE("target_kind" "text", "target_id" "uuid", "target_aux_id" "uuid")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."infer_report_target_for_moderation"("p_report_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."insert_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  thread_row public.conversation_threads%rowtype;
  normalized_body text;
  media_ids uuid[];
  media_count integer;
  unique_media_count integer;
  resolved_message_id uuid;
  first_asset public.media_assets%rowtype;
  media_row record;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  select *
  into thread_row
  from public.conversation_threads
  where id = p_thread_id
  for update;

  if not found
    or thread_row.deleted_at is not null
    or thread_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(thread_row.couple_id) then
    raise exception 'active entitled thread access is required'
      using errcode = '42501';
  end if;

  media_ids = coalesce(p_media_asset_ids, array[]::uuid[]);
  media_count = cardinality(media_ids);

  if media_count > 10 then
    raise exception 'thread messages can include at most 10 media assets'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from unnest(media_ids) as media_id(id)
    where media_id.id is null
  ) then
    raise exception 'thread message media asset id cannot be null'
      using errcode = '23514';
  end if;

  select count(distinct media_id.id)
  into unique_media_count
  from unnest(media_ids) as media_id(id);

  if unique_media_count <> media_count then
    raise exception 'thread message media asset ids must be unique'
      using errcode = '23514';
  end if;

  normalized_body = nullif(btrim(coalesce(p_body, '')), '');

  if normalized_body is not null and char_length(normalized_body) > 4000 then
    raise exception 'thread message body is too long'
      using errcode = '23514';
  end if;

  if normalized_body is null and media_count = 0 then
    raise exception 'thread message must include text or media'
      using errcode = '23514';
  end if;

  if media_count > 0 then
    select *
    into first_asset
    from public.media_assets
    where id = media_ids[1];

    if not found then
      raise exception 'thread message media asset is not usable'
        using errcode = '23514';
    end if;

    resolved_message_id = first_asset.reserved_parent_id;
  else
    resolved_message_id = extensions.gen_random_uuid();
  end if;

  insert into public.thread_messages (
    id,
    thread_id,
    sender_user_id,
    body
  ) values (
    resolved_message_id,
    thread_row.id,
    current_user_id,
    normalized_body
  );

  for media_row in
    select
      media_item.value as media_asset_id,
      media_item.ordinality::smallint as sort_order
    from unnest(media_ids) with ordinality as media_item(value, ordinality)
  loop
    insert into public.thread_message_media (
      message_id,
      media_asset_id,
      sort_order
    ) values (
      resolved_message_id,
      media_row.media_asset_id,
      media_row.sort_order
    );
  end loop;

  return resolved_message_id;
end;
$$;


ALTER FUNCTION "internal"."insert_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."invalidate_subscription_trial_reminder"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  subscription_id uuid;
begin
  if tg_op = 'DELETE' then
    subscription_id := old.id;
  else
    subscription_id := new.id;
  end if;

  if tg_op = 'DELETE' then
    delete from internal.notification_outbox outbox
    where outbox.kind = 'subscription_trial_reminder'
      and outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.payload ->> 'subscription_id' = subscription_id::text;

    return old;
  end if;

  if old.status is distinct from new.status
    or old.expires_at is distinct from new.expires_at then
    delete from internal.notification_outbox outbox
    where outbox.kind = 'subscription_trial_reminder'
      and outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.payload ->> 'subscription_id' = subscription_id::text;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."invalidate_subscription_trial_reminder"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."invoke_account_deletion_drain"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.request_account_deletion_drain(
    tg_table_schema || '.' || tg_table_name
  );
  return null;
end;
$$;


ALTER FUNCTION "internal"."invoke_account_deletion_drain"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."invoke_media_storage_cleanup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.media_storage_cleanup_queued', true) = '1' then
    return null;
  end if;

  if not exists (
    select 1
    from public.media_assets asset
    where asset.storage_delete_status = 'pending'
  ) then
    return null;
  end if;

  perform set_config('paeonia.media_storage_cleanup_queued', '1', true);

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in ('media_storage_cleanup_secret', 'widget_drain_secret')
  order by case name
    when 'media_storage_cleanup_secret' then 0
    else 1
  end
  limit 1;

  if coalesce(drain_secret, '') <> '' then
    perform net.http_post(
      url := 'https://api.paeonia.no/functions/v1/cleanup-media-storage',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-drain-secret', drain_secret
      ),
      body := '{}'::jsonb
    );
  end if;

  return null;
end;
$$;


ALTER FUNCTION "internal"."invoke_media_storage_cleanup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."invoke_push_notification_drain"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.request_push_notification_drain(
    tg_table_schema || '.' || tg_table_name
  );
  return null;
end;
$$;


ALTER FUNCTION "internal"."invoke_push_notification_drain"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."is_active_couple_member"("p_couple_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = (select auth.uid())
      and member.status = 'active'
      and couple.status = 'active'
  );
$$;


ALTER FUNCTION "internal"."is_active_couple_member"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."is_active_entitled_couple_member"("p_couple_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = (select auth.uid())
      and member.status = 'active'
      and couple.status = 'active'
      and exists (
        select 1
        from public.couple_members any_member
        join internal.resolve_user_entitlement(any_member.user_id) entitlement
          on entitlement.is_entitled
        where any_member.couple_id = p_couple_id
          and any_member.status = 'active'
      )
  );
$$;


ALTER FUNCTION "internal"."is_active_entitled_couple_member"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."is_admin"() RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select false;
$$;


ALTER FUNCTION "internal"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."is_couple_pair_member"("p_pair_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where couple.pair_id = p_pair_id
      and member.user_id = (select auth.uid())
      and member.status in ('active', 'ended_notice_pending', 'ended_notice_seen', 'left')
  );
$$;


ALTER FUNCTION "internal"."is_couple_pair_member"("p_pair_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text" DEFAULT 'pre_paired_paywalled'::"text", "p_expires_at" timestamp with time zone DEFAULT ("now"() + '30 days'::interval), "p_max_redemptions" integer DEFAULT 1) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  new_id uuid;
begin
  insert into internal.review_access_codes (
    code_hash, seeded_partner_user_id, scenario, status, expires_at, max_redemptions
  ) values (
    internal.hash_review_access_code(p_code),
    p_seeded_partner_user_id,
    p_scenario,
    'active',
    p_expires_at,
    p_max_redemptions
  )
  returning id into new_id;

  return new_id;
end;
$$;


ALTER FUNCTION "internal"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text", "p_expires_at" timestamp with time zone, "p_max_redemptions" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  active_pair_id uuid;
  request_hash bytea;
  replayed_response jsonb;
  left_relationship boolean;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest('leave_relationship', 'sha256');

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'leave_relationship',
    'relationship_lifecycle',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'left')::boolean;
  end if;

  select couple.pair_id
  into active_pair_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
  order by couple.created_at desc
  limit 1;

  if active_pair_id is null then
    perform internal.complete_client_operation(
      p_client_operation_id,
      jsonb_build_object('left', false)
    );

    return false;
  end if;

  left_relationship = internal.end_relationship_for_pair(active_pair_id, current_user_id, 'user_left');

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('left', left_relationship)
  );

  return left_relationship;
end;
$$;


ALTER FUNCTION "internal"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."list_review_demo_partners"() RETURNS TABLE("slot" smallint, "user_id" "uuid", "display_name" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select slot, user_id, display_name
  from internal.review_demo_partners
  order by slot;
$$;


ALTER FUNCTION "internal"."list_review_demo_partners"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer DEFAULT 10) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  job_row internal.account_deletion_jobs%rowtype;
begin
  if p_error_code is null
     or char_length(p_error_code) not between 1 and 120 then
    raise exception 'invalid Auth deletion error code'
      using errcode = '23514';
  end if;

  update internal.account_deletion_jobs job
  set
    status = case
      when job.auth_delete_attempts >= p_max_attempts then 'attention_required'
      else 'ready_for_auth_delete'
    end,
    next_attempt_at = case
      when job.auth_delete_attempts >= p_max_attempts then null
      else now() + least(
        interval '6 hours',
        interval '30 seconds' * power(2::numeric, least(job.auth_delete_attempts, 10))
      )
    end,
    claimed_at = null,
    last_auth_delete_error_code = p_error_code
  where job.id = p_job_id
    and job.status = 'processing_auth_delete'
  returning * into job_row;

  if not found then
    return false;
  end if;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  ) values (
    job_row.request_id,
    null,
    'auth_delete_failed',
    jsonb_build_object(
      'error_code', p_error_code,
      'attempt', job_row.auth_delete_attempts,
      'requires_attention', job_row.status = 'attention_required'
    )
  );

  return true;
end;
$$;


ALTER FUNCTION "internal"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_account_deletion_completed"("p_job_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  job_row internal.account_deletion_jobs%rowtype;
begin
  select job.*
  into job_row
  from internal.account_deletion_jobs job
  where job.id = p_job_id
  for update;

  if not found then
    return false;
  end if;

  if job_row.status = 'completed' then
    return true;
  end if;

  update internal.account_deletion_jobs job
  set
    status = 'completed',
    next_attempt_at = null,
    claimed_at = null,
    last_auth_delete_error_code = null,
    completed_at = now()
  where job.id = p_job_id
  returning * into job_row;

  update public.privacy_requests request
  set
    status = 'completed',
    completed_at = now(),
    cancelled_at = null,
    visible_status_message = 'Your Paeonia account has been deleted.'
  where request.id = job_row.request_id;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  ) values (
    job_row.request_id,
    null,
    'auth_user_deleted',
    jsonb_build_object(
      'attempts', job_row.auth_delete_attempts,
      'provider_revocation_status', job_row.provider_revocation_status
    )
  );

  return true;
end;
$$;


ALTER FUNCTION "internal"."mark_account_deletion_completed"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  job_row internal.account_deletion_jobs%rowtype;
  event_kind text;
begin
  if p_status not in ('succeeded', 'manual_required', 'not_required') then
    raise exception 'invalid provider revocation status'
      using errcode = '23514';
  end if;

  if p_error_code is not null
     and char_length(p_error_code) not between 1 and 120 then
    raise exception 'invalid provider revocation error code'
      using errcode = '23514';
  end if;

  update internal.account_deletion_jobs job
  set
    provider_revocation_status = p_status,
    provider_revocation_attempted_at = now(),
    provider_revocation_error_code = p_error_code,
    status = case
      when job.status = 'completed' then 'completed'
      when job.status = 'processing_auth_delete' then 'processing_auth_delete'
      else 'ready_for_auth_delete'
    end,
    next_attempt_at = case
      when job.status = 'completed' then null
      when p_status in ('succeeded', 'not_required') then now()
      else now()
    end,
    claimed_at = case
      when job.status = 'processing_auth_delete' then job.claimed_at
      else null
    end
  where job.id = p_job_id
  returning * into job_row;

  if not found then
    return false;
  end if;

  event_kind = case p_status
    when 'succeeded' then 'provider_revocation_succeeded'
    when 'not_required' then 'provider_revocation_not_required'
    else 'provider_revocation_manual_required'
  end;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  ) values (
    job_row.request_id,
    null,
    event_kind,
    jsonb_strip_nulls(
      jsonb_build_object(
        'provider', job_row.auth_provider,
        'error_code', p_error_code
      )
    )
  );

  return true;
end;
$$;


ALTER FUNCTION "internal"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_media_for_deletion"("p_media_asset_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update public.media_assets asset
  set
    deleted_at = coalesce(asset.deleted_at, now()),
    storage_delete_status = case
      when asset.storage_delete_status = 'deleted' then 'deleted'
      when asset.storage_delete_status in ('pending', 'retrying') then asset.storage_delete_status
      else 'pending'
    end,
    last_storage_delete_error = null
  where asset.id = p_media_asset_id
    and asset.owner_user_id = current_user_id
    and asset.bucket = 'profile-photos'
    and asset.couple_id is null
    and asset.reserved_parent_kind = 'profile_photo'
    and asset.bucket <> 'report-snapshots'
    and asset.storage_delete_status <> 'deleted'
    and not internal.media_asset_has_live_reference(asset.id);

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."mark_media_for_deletion"("p_media_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_media_storage_deleted"("p_media_asset_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_media_storage_deleted"("p_media_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_notification_failed"("p_outbox_id" "uuid", "p_error" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  changed_rows integer;
begin
  update internal.notification_outbox
  set
    last_error = left(nullif(btrim(coalesce(p_error, '')), ''), 2000),
    failed_at = case when coalesce(p_terminal, false) then now() else null end
  where id = p_outbox_id
    and sent_at is null;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."mark_notification_failed"("p_outbox_id" "uuid", "p_error" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text" DEFAULT NULL::"text", "p_error" "text" DEFAULT NULL::"text", "p_invalid_token" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if p_success then
    update internal.notification_outbox
    set sent_at = now(),
        provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
        last_error = null
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  else
    update internal.notification_outbox
    set last_error = left(coalesce(nullif(btrim(p_error), ''), 'delivery failed'), 2000),
        failed_at = case when p_invalid_token or attempt_count >= 5 then now() else null end
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  end if;
end;
$$;


ALTER FUNCTION "internal"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_notification_sent"("p_outbox_id" "uuid", "p_provider_message_id" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  changed_rows integer;
begin
  update internal.notification_outbox
  set
    provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
    sent_at = now(),
    failed_at = null,
    last_error = null
  where id = p_outbox_id
    and sent_at is null;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."mark_notification_sent"("p_outbox_id" "uuid", "p_provider_message_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update public.couple_members
  set
    status = 'ended_notice_seen',
    ended_notice_seen_at = now()
  where couple_id = p_couple_id
    and user_id = current_user_id
    and status = 'ended_notice_pending';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_report_snapshot_asset_copied"("p_snapshot_asset_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_report_snapshot_asset_copied"("p_snapshot_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_report_snapshot_asset_copy_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_report_snapshot_asset_copy_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_storekit_transaction_reconciled"("p_transaction_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_storekit_transaction_reconciled"("p_transaction_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_storekit_transaction_reconciliation_failed"("p_transaction_id" "uuid", "p_error" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."mark_storekit_transaction_reconciliation_failed"("p_transaction_id" "uuid", "p_error" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  changed_rows integer;
begin
  update internal.streak_restorations
  set
    status = 'refunded',
    refunded_at = now()
  where environment = p_environment
    and transaction_id = p_transaction_id
    and status <> 'refunded';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text" DEFAULT NULL::"text", "p_error" "text" DEFAULT NULL::"text", "p_invalid_token" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  update internal.widget_push_outbox
  set
    sent_at = case when p_success then now() else sent_at end,
    provider_message_id = case when p_success then p_provider_message_id else provider_message_id end,
    failed_at = case
      when p_success then failed_at
      when p_invalid_token or attempt_count >= 5 then now()
      else failed_at
    end,
    last_error = case when p_success then null else p_error end
  where id = p_outbox_id;
end;
$$;


ALTER FUNCTION "internal"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."media_asset_has_live_reference"("p_media_asset_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select exists (
    select 1
    from public.profiles profile
    where (
        profile.profile_photo_asset_id = p_media_asset_id
        or profile.provider_profile_photo_asset_id = p_media_asset_id
      )
      and profile.deleted_at is null
  )
  or exists (
    select 1
    from public.daily_answer_media answer_media
    join public.daily_question_answers answer
      on answer.id = answer_media.answer_id
    where answer_media.media_asset_id = p_media_asset_id
      and answer.deleted_at is null
  )
  or exists (
    select 1
    from public.memory_media memory_media
    join public.memories memory
      on memory.id = memory_media.memory_id
    where memory_media.media_asset_id = p_media_asset_id
      and memory_media.deleted_at is null
      and memory.deleted_at is null
  )
  or exists (
    select 1
    from public.thread_message_media message_media
    join public.thread_messages message
      on message.id = message_media.message_id
    join public.conversation_threads thread
      on thread.id = message.thread_id
    where message_media.media_asset_id = p_media_asset_id
      and message.deleted_at is null
      and thread.deleted_at is null
  )
  or exists (
    select 1
    from public.widget_drawing_revisions revision
    join public.widget_canvases canvas
      on canvas.id = revision.canvas_id
    where revision.payload_media_asset_id = p_media_asset_id
      and revision.deleted_at is null
      and canvas.deleted_at is null
  );
$$;


ALTER FUNCTION "internal"."media_asset_has_live_reference"("p_media_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."media_byte_limit"("p_media_type" "text") RETURNS bigint
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select case p_media_type
    when 'image' then 10485760::bigint
    when 'voice' then 52428800::bigint
    when 'drawing_payload' then 10485760::bigint
    when 'report_snapshot' then 52428800::bigint
    else 0::bigint
  end;
$$;


ALTER FUNCTION "internal"."media_byte_limit"("p_media_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."media_extension_matches_type"("p_media_type" "text", "p_file_extension" "text") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select case p_media_type
    when 'image' then p_file_extension in ('jpg', 'png', 'heic', 'heif', 'webp')
    when 'voice' then p_file_extension in ('m4a', 'mp4', 'aac', 'caf', 'wav', 'mp3')
    when 'drawing_payload' then p_file_extension = 'pkdrawing'
    when 'report_snapshot' then p_file_extension in ('jpg', 'png', 'pdf', 'json')
    else false
  end;
$$;


ALTER FUNCTION "internal"."media_extension_matches_type"("p_media_type" "text", "p_file_extension" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."media_mime_matches_type"("p_media_type" "text", "p_mime_type" "text") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select case p_media_type
    when 'image' then lower(btrim(p_mime_type)) in (
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/heif',
      'image/webp'
    )
    when 'voice' then lower(btrim(p_mime_type)) in (
      'audio/mp4',
      'audio/mpeg',
      'audio/aac',
      'audio/wav',
      'audio/x-caf'
    )
    when 'drawing_payload' then lower(btrim(p_mime_type)) in (
      'application/octet-stream',
      'application/x-pkdrawing'
    )
    when 'report_snapshot' then lower(btrim(p_mime_type)) in (
      'image/jpeg',
      'image/png',
      'application/pdf',
      'application/json'
    )
    else false
  end;
$$;


ALTER FUNCTION "internal"."media_mime_matches_type"("p_media_type" "text", "p_mime_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."normalize_media_file_extension"("p_file_extension" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $_$
declare
  normalized_extension text;
begin
  normalized_extension = lower(btrim(coalesce(p_file_extension, '')));
  normalized_extension = regexp_replace(normalized_extension, '^\.+', '');

  if normalized_extension !~ '^[a-z0-9]{1,16}$' then
    raise exception 'file extension is not supported'
      using errcode = '22023';
  end if;

  if normalized_extension = 'jpeg' then
    return 'jpg';
  end if;

  return normalized_extension;
end;
$_$;


ALTER FUNCTION "internal"."normalize_media_file_extension"("p_file_extension" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."normalize_memory_note_body"("p_body" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  normalized_body text;
begin
  normalized_body = nullif(btrim(coalesce(p_body, '')), '');

  if normalized_body is null then
    raise exception 'memory note body is required'
      using errcode = '23514';
  end if;

  if char_length(normalized_body) > 4000 then
    raise exception 'memory note body is too long'
      using errcode = '23514';
  end if;

  return normalized_body;
end;
$$;


ALTER FUNCTION "internal"."normalize_memory_note_body"("p_body" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."normalize_memory_title"("p_title" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  normalized_title text;
begin
  normalized_title = nullif(btrim(coalesce(p_title, '')), '');

  if normalized_title is null then
    raise exception 'memory title is required'
      using errcode = '23514';
  end if;

  if char_length(normalized_title) > 160 then
    raise exception 'memory title is too long'
      using errcode = '23514';
  end if;

  return normalized_title;
end;
$$;


ALTER FUNCTION "internal"."normalize_memory_title"("p_title" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."notification_actor_display_name"("p_payload" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  actor_id_text text;
  actor_id uuid;
  actor_name text;
begin
  actor_id_text = coalesce(
    nullif(btrim(coalesce(p_payload ->> 'actor_user_id', '')), ''),
    nullif(btrim(coalesce(p_payload ->> 'sender_user_id', '')), '')
  );

  if actor_id_text is null then
    return null;
  end if;

  begin
    actor_id = actor_id_text::uuid;
  exception
    when invalid_text_representation then
      return null;
  end;

  select nullif(btrim(profile.display_name), '')
  into actor_name
  from public.profiles profile
  where profile.user_id = actor_id;

  return actor_name;
end;
$$;


ALTER FUNCTION "internal"."notification_actor_display_name"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."notification_alert_body"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'pg_catalog'
    AS $_$
declare
  language_code text := internal.notification_locale_language(p_locale);
  days_left integer := greatest(
    case
      when p_payload ->> 'days_left' ~ '^[0-9]+$'
        then (p_payload ->> 'days_left')::integer
      else 2
    end,
    1
  );
begin
  return case p_kind
    when 'widget_updated' then case language_code
      when 'nb' then 'La til en ny tegning'
      else 'Added a new drawing'
    end
    when 'partner_answered' then case language_code
      when 'nb' then 'Åpne Paeonia for å se hva partneren din skrev.'
      else 'Open Paeonia to reveal what they wrote.'
    end
    when 'daily_challenge_completed' then case language_code
      when 'nb' then 'Åpne Paeonia for å svare og se hva partneren din skrev.'
      else 'Open Paeonia to answer and reveal what they wrote.'
    end
    when 'memory_created' then case language_code
      when 'nb' then 'Åpne Paeonia for å se det.'
      else 'Open Paeonia to see it.'
    end
    when 'thread_message_sent' then case
      when p_payload ->> 'lock_screen_detail_level' = 'descriptive' then
        case language_code
          when 'nb' then 'Åpne Paeonia for å svare.'
          else 'Open Paeonia to reply.'
        end
      else case language_code
        when 'nb' then 'Åpne Paeonia for å se hva som er nytt.'
        else 'Open Paeonia to see what''s new.'
      end
    end
    when 'streak_reminder' then case language_code
      when 'nb' then 'Gjør én liten ting i dag. Rekken fortsetter når dere begge har sjekket inn.'
      else 'Do one small thing today. Your streak continues once both of you have checked in.'
    end
    when 'subscription_trial_reminder' then case language_code
      when 'nb' then
        days_left::text || case when days_left = 1 then ' dag igjen. ' else ' dager igjen. ' end ||
        'Se over abonnementet ditt i App Store.'
      else
        days_left::text || case when days_left = 1 then ' day left. ' else ' days left. ' end ||
        'Review your subscription in the App Store.'
    end
    else null
  end;
end;
$_$;


ALTER FUNCTION "internal"."notification_alert_body"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."notification_alert_title"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  language_code text := internal.notification_locale_language(p_locale);
  actor_name text := coalesce(internal.notification_actor_display_name(p_payload), 'Paeonia');
begin
  return case p_kind
    when 'widget_updated' then actor_name
    when 'partner_answered' then case language_code
      when 'nb' then actor_name || ' svarte på samme spørsmål!'
      else actor_name || ' answered the same question!'
    end
    when 'daily_challenge_completed' then case language_code
      when 'nb' then actor_name || ' fullførte dagens spørsmål'
      else actor_name || ' finished today''s questions'
    end
    when 'memory_created' then case language_code
      when 'nb' then actor_name || ' la til et nytt minne'
      else actor_name || ' added a new memory'
    end
    when 'thread_message_sent' then case
      when p_payload ->> 'lock_screen_detail_level' = 'descriptive' then
        case language_code
          when 'nb' then
            coalesce(internal.notification_actor_display_name(p_payload), 'Partneren din') ||
            ' sendte deg en melding'
          else
            coalesce(internal.notification_actor_display_name(p_payload), 'Your partner') ||
            ' sent you a message'
        end
      else 'Paeonia'
    end
    when 'streak_reminder' then case language_code
      when 'nb' then 'Sjekk inn før tiden går ut'
      else 'Check in before time runs out'
    end
    when 'subscription_trial_reminder' then case language_code
      when 'nb' then 'Prøveperioden avsluttes snart'
      else 'Your free trial ends soon'
    end
    else 'Paeonia'
  end;
end;
$$;


ALTER FUNCTION "internal"."notification_alert_title"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."notification_locale_language"("p_locale" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'pg_catalog'
    AS $$
  select case
    when split_part(lower(replace(nullif(btrim(coalesce(p_locale, '')), ''), '_', '-')), '-', 1)
      in ('no', 'nb', 'nn') then 'nb'
    else 'en'
  end;
$$;


ALTER FUNCTION "internal"."notification_locale_language"("p_locale" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."notification_payload_is_safe"("p_payload" "jsonb") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select p_payload is not null
    and jsonb_typeof(p_payload) = 'object'
    and octet_length(p_payload::text) <= 4096
    and p_payload::text !~* '"(answer_body|note_body|message_body|body_text|voice_transcript|media_url|signed_url|latitude|longitude|coordinate|invite_code|report_detail|precise_location)"';
$$;


ALTER FUNCTION "internal"."notification_payload_is_safe"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."pick_daily_question_version"("p_couple_day_id" "uuid", "p_user_id" "uuid", "p_excluded_question_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  picked_question_version_id uuid;
begin
  select version.id
  into picked_question_version_id
  from public.question_versions version
  join public.questions question
    on question.id = version.question_id
  join public.question_collections collection
    on collection.id = question.collection_id
  where collection.kind = 'system'
    and collection.status = 'active'
    and question.status = 'active'
    and version.status = 'active'
    and (p_excluded_question_id is null or question.id <> p_excluded_question_id)
    and exists (
      select 1
      from public.question_version_localizations localization
      where localization.question_version_id = version.id
        and localization.locale = 'en'
    )
    and exists (
      select 1
      from public.question_version_localizations localization
      where localization.question_version_id = version.id
        and localization.locale = 'nb'
    )
    and (
      select count(*)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ) between 1 and 2
    and not exists (
      select 1
      from public.daily_question_instances existing_instance
      join public.question_versions existing_version
        on existing_version.id = existing_instance.question_version_id
      where existing_instance.couple_day_id = p_couple_day_id
        and existing_instance.seeded_for_user_id = p_user_id
        and existing_instance.status = 'active'
        and existing_version.question_id = question.id
    )
    and not exists (
      select 1
      from public.daily_question_shuffles shuffle
      where shuffle.user_id = p_user_id
        and shuffle.question_id = question.id
        and shuffle.exclude_until > now()
    )
    and (
      (
        select max(answer.created_at)
        from public.daily_question_answers answer
        join public.daily_question_instances answered_instance
          on answered_instance.id = answer.instance_id
        join public.question_versions answered_version
          on answered_version.id = answered_instance.question_version_id
        where answer.user_id = p_user_id
          and answer.deleted_at is null
          and answered_version.question_id = question.id
      ) is null
      or (
        question.resurfaceable
        and (
          select max(answer.created_at)
          from public.daily_question_answers answer
          join public.daily_question_instances answered_instance
            on answered_instance.id = answer.instance_id
          join public.question_versions answered_version
            on answered_version.id = answered_instance.question_version_id
          where answer.user_id = p_user_id
            and answer.deleted_at is null
            and answered_version.question_id = question.id
        ) <= now() - make_interval(months => coalesce(question.resurface_after_months, 6)::integer)
      )
    )
  order by random()
  limit 1;

  if picked_question_version_id is null then
    raise exception 'no eligible daily questions are available'
      using errcode = '22023';
  end if;

  return picked_question_version_id;
end;
$$;


ALTER FUNCTION "internal"."pick_daily_question_version"("p_couple_day_id" "uuid", "p_user_id" "uuid", "p_excluded_question_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."preview_pairing_invite"("p_invite_code" "text") RETURNS TABLE("invite_id" "uuid", "inviter_user_id" "uuid", "inviter_display_name" "text", "expires_at" timestamp with time zone, "has_safety_warning" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  found_invite record;
  resolved_pair_id uuid;
  invite_code_hash bytea;
  code_prefix text;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  code_prefix = left(pg_catalog.encode(invite_code_hash, 'hex'), 12);

  perform internal.assert_pairing_invite_attempt_allowed(current_user_id, code_prefix);

  select invite.id,
    invite.created_by_user_id,
    invite.expires_at,
    profile.display_name,
    profile.moderation_status
  into found_invite
  from internal.pairing_invite_secrets secret
  join public.pairing_invites invite
    on invite.id = secret.invite_id
  left join public.profiles profile
    on profile.user_id = invite.created_by_user_id
  where secret.code_hash = invite_code_hash
    and invite.status = 'pending'
    and invite.expires_at > now();

  if not found then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      current_user_id,
      false,
      'not_found'
    );

    return;
  end if;

  resolved_pair_id = internal.find_relationship_pair_id(current_user_id, found_invite.created_by_user_id);

  if resolved_pair_id is not null and (select internal.has_active_relationship_block(resolved_pair_id)) then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      found_invite.id,
      current_user_id,
      false,
      'active_block'
    );

    return;
  end if;

  insert into internal.pairing_invite_attempts (
    code_hash_prefix,
    matched_invite_id,
    user_id,
    success
  ) values (
    code_prefix,
    found_invite.id,
    current_user_id,
    true
  );

  return query
  select
    found_invite.id,
    found_invite.created_by_user_id,
    case
      when found_invite.moderation_status = 'visible' then found_invite.display_name
      else null
    end,
    found_invite.expires_at,
    exists (
      select 1
      from internal.pair_safety_warning_flags warning
      where warning.pair_id = resolved_pair_id
    );
end;
$$;


ALTER FUNCTION "internal"."preview_pairing_invite"("p_invite_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."purge_deleted_relationship_content"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 25) RETURNS TABLE("couple_id" "uuid", "media_rows_deleted" integer, "content_rows_deleted" integer, "sync_event_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."purge_deleted_relationship_content"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."purge_deleted_report_snapshots"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100) RETURNS TABLE("snapshot_asset_rows_deleted" integer, "snapshot_rows_deleted" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."purge_deleted_report_snapshots"("p_now" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_daily_answer_media_assets_if_orphaned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  media_row record;
begin
  for media_row in
    select answer_media.media_asset_id
    from public.daily_answer_media answer_media
    where answer_media.answer_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."queue_daily_answer_media_assets_if_orphaned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_memory_media_assets_if_orphaned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  media_row record;
begin
  for media_row in
    select memory_media.media_asset_id
    from public.memory_media memory_media
    where memory_media.memory_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."queue_memory_media_assets_if_orphaned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_old_media_asset_if_orphaned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  old_media_asset_id uuid;
begin
  if TG_TABLE_SCHEMA <> 'public' then
    raise exception 'orphaned media trigger is not configured for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
      using errcode = '23514';
  end if;

  if TG_TABLE_NAME = 'profiles' then
    perform internal.queue_orphaned_media_asset_for_delete(old.profile_photo_asset_id);
    perform internal.queue_orphaned_media_asset_for_delete(
      old.provider_profile_photo_asset_id
    );

    if TG_OP = 'DELETE' then
      return old;
    end if;
    return new;
  elsif TG_TABLE_NAME in ('daily_answer_media', 'memory_media', 'thread_message_media') then
    old_media_asset_id = old.media_asset_id;
  elsif TG_TABLE_NAME = 'widget_drawing_revisions' then
    old_media_asset_id = old.payload_media_asset_id;
  else
    raise exception 'orphaned media trigger is not configured for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
      using errcode = '23514';
  end if;

  perform internal.queue_orphaned_media_asset_for_delete(old_media_asset_id);

  if TG_OP = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."queue_old_media_asset_if_orphaned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_orphaned_media_asset_for_delete"("p_media_asset_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  changed_rows integer;
begin
  if p_media_asset_id is null then
    return false;
  end if;

  update public.media_assets asset
  set
    deleted_at = coalesce(asset.deleted_at, now()),
    storage_delete_status = case
      when asset.storage_delete_status = 'deleted' then 'deleted'
      when asset.storage_delete_status in ('pending', 'retrying') then asset.storage_delete_status
      else 'pending'
    end,
    last_storage_delete_error = null
  where asset.id = p_media_asset_id
    and asset.bucket <> 'report-snapshots'
    and asset.upload_status = 'finalized'
    and asset.upload_finalized_at is not null
    and asset.storage_delete_status in ('none', 'failed')
    and not internal.media_asset_has_live_reference(asset.id);

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."queue_orphaned_media_asset_for_delete"("p_media_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_orphaned_media_assets_for_delete"("p_limit" integer DEFAULT 500) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  queued_count integer;
begin
  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'orphaned media queue limit is out of range'
      using errcode = '23514';
  end if;

  with picked as (
    select asset.id
    from public.media_assets asset
    where asset.bucket <> 'report-snapshots'
      and asset.upload_status = 'finalized'
      and asset.upload_finalized_at is not null
      and asset.storage_delete_status in ('none', 'failed')
      and not internal.media_asset_has_live_reference(asset.id)
    order by asset.updated_at, asset.id
    for update skip locked
    limit p_limit
  ),
  queued as (
    update public.media_assets asset
    set
      deleted_at = coalesce(asset.deleted_at, now()),
      storage_delete_status = case
        when asset.storage_delete_status in ('pending', 'retrying') then asset.storage_delete_status
        else 'pending'
      end,
      last_storage_delete_error = null
    from picked
    where asset.id = picked.id
    returning asset.id
  )
  select count(*)::integer
  into queued_count
  from queued;

  return queued_count;
end;
$$;


ALTER FUNCTION "internal"."queue_orphaned_media_assets_for_delete"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_subscription_trial_reminders"("p_batch_size" integer DEFAULT 500) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  reminder_days_before_end constant integer := 2;
  reminder_interval interval;
  trial_row record;
  inserted_count integer := 0;
begin
  reminder_interval := reminder_days_before_end * interval '1 day';

  for trial_row in
    select
      tx.id as subscription_id,
      tx.user_id,
      tx.expires_at
    from internal.storekit_transactions tx
    join public.subscription_products product
      on product.id = tx.product_id
    join internal.storekit_payloads payload
      on payload.id = tx.raw_payload_id
    where tx.status in ('active', 'grace')
      and tx.expires_at is not null
      and tx.expires_at > now()
      and product.kind = 'couple_subscription'
      and product.is_active
      and payload.payload_json #>> '{transactionInfo,offerType}' = '1'
      and upper(payload.payload_json #>> '{transactionInfo,offerDiscountType}') = 'FREE_TRIAL'
      and tx.transaction_id = tx.original_transaction_id
      -- Queue only shortly before delivery. This keeps a future reminder from
      -- lingering for days after Apple revokes or changes the trial period.
      and tx.expires_at - reminder_interval <= now() + interval '1 hour'
      and exists (
        select 1
        from public.user_devices device
        join public.notification_preferences preference
          on preference.user_id = device.user_id
        where device.user_id = tx.user_id
          and device.disabled_at is null
          and not exists (
            select 1
            from internal.notification_outbox outbox
            where outbox.dedupe_key =
              'subscription_trial_reminder:' || tx.id::text || ':' ||
              device.id::text
          )
      )
    order by tx.expires_at
    limit greatest(coalesce(p_batch_size, 500), 1)
    for update of tx skip locked
  loop
    inserted_count := inserted_count + internal.enqueue_notification_for_user(
      trial_row.user_id,
      'subscription_trial_reminder',
      jsonb_build_object(
        'type', 'subscription_trial_reminder',
        'route', 'subscription',
        'deeplink', 'paeonia://settings/subscription',
        'subscription_id', trial_row.subscription_id,
        'trial_ends_at', trial_row.expires_at,
        'days_left', reminder_days_before_end
      ),
      'subscription_trial_reminder:' || trial_row.subscription_id::text,
      'private',
      'alert',
      'subscription-trial',
      greatest(now(), trial_row.expires_at - reminder_interval)
    );
  end loop;

  return inserted_count;
end;
$$;


ALTER FUNCTION "internal"."queue_subscription_trial_reminders"("p_batch_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_thread_media_assets_if_orphaned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  media_row record;
begin
  for media_row in
    select message_media.media_asset_id
    from public.thread_message_media message_media
    join public.thread_messages message
      on message.id = message_media.message_id
    where message.thread_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."queue_thread_media_assets_if_orphaned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_thread_message_media_assets_if_orphaned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  media_row record;
begin
  for media_row in
    select message_media.media_asset_id
    from public.thread_message_media message_media
    where message_media.message_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(media_row.media_asset_id);
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."queue_thread_message_media_assets_if_orphaned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."queue_widget_payloads_if_orphaned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  revision_row record;
begin
  for revision_row in
    select revision.payload_media_asset_id
    from public.widget_drawing_revisions revision
    where revision.canvas_id = old.id
  loop
    perform internal.queue_orphaned_media_asset_for_delete(
      revision_row.payload_media_asset_id
    );
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."queue_widget_payloads_if_orphaned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."record_couple_activity"("p_activity_kind" "text", "p_couple_day_id" "uuid", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  resolved_couple_day_id uuid;
  resolved_occurred_at timestamptz;
  event_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  resolved_occurred_at = coalesce(p_occurred_at, now());
  resolved_couple_id = internal.get_current_entitled_couple_id();
  resolved_couple_day_id = coalesce(
    p_couple_day_id,
    internal.get_or_create_couple_day_at(resolved_couple_id, resolved_occurred_at)
  );

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'record_couple_activity',
      resolved_couple_id::text,
      current_user_id::text,
      resolved_couple_day_id::text,
      p_activity_kind,
      resolved_occurred_at::text,
      p_dedupe_key
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'record_couple_activity',
    'activity',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'activity_event_id')::uuid;
  end if;

  event_id = internal.apply_couple_activity(
    resolved_couple_id,
    current_user_id,
    resolved_couple_day_id,
    p_activity_kind,
    resolved_occurred_at,
    p_dedupe_key,
    '{}'::jsonb
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('activity_event_id', event_id)
  );

  return event_id;
end;
$$;


ALTER FUNCTION "internal"."record_couple_activity"("p_activity_kind" "text", "p_couple_day_id" "uuid", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  notification_payload_id uuid;
  notification_event_id uuid;
  notification_payload_hash bytea;
  token_user_id uuid;
  existing_user_id uuid;
  resolved_user_id uuid;
  record_result jsonb;
  record_error text;
begin
  if p_notification_uuid is null then
    return jsonb_build_object('ok', false, 'error', 'Invalid notification UUID', 'status', 400);
  end if;

  if p_notification_type is null or char_length(btrim(p_notification_type)) not between 1 and 120 then
    return jsonb_build_object('ok', false, 'error', 'Invalid notification type', 'status', 400);
  end if;

  if p_environment not in ('sandbox', 'production') then
    return jsonb_build_object('ok', false, 'error', 'Invalid StoreKit environment', 'status', 400);
  end if;

  if p_payload_json is null or jsonb_typeof(p_payload_json) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'Invalid notification payload', 'status', 400);
  end if;

  notification_payload_hash = case
    when p_signed_notification_payload is null then null
    else extensions.digest(p_signed_notification_payload, 'sha256')
  end;

  insert into internal.storekit_payloads (
    payload_kind,
    environment,
    original_transaction_id,
    transaction_id,
    notification_uuid,
    signed_payload,
    payload_json,
    sha256
  )
  values (
    'server_notification',
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_notification_uuid,
    p_signed_notification_payload,
    p_payload_json,
    notification_payload_hash
  )
  on conflict (environment, sha256)
  where sha256 is not null
  do update set received_at = internal.storekit_payloads.received_at
  returning id into notification_payload_id;

  insert into internal.storekit_notification_events (
    notification_uuid,
    notification_type,
    subtype,
    environment,
    original_transaction_id,
    raw_payload_id,
    signed_payload
  )
  values (
    p_notification_uuid,
    p_notification_type,
    nullif(btrim(p_subtype), ''),
    p_environment,
    p_original_transaction_id,
    notification_payload_id,
    p_signed_notification_payload
  )
  on conflict (notification_uuid) do nothing
  returning id into notification_event_id;

  if notification_event_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'processed', false);
  end if;

  if p_notification_type = 'TEST' then
    update internal.storekit_notification_events event
    set processed_at = now(),
        processing_error = null
    where event.id = notification_event_id;

    return jsonb_build_object('ok', true, 'duplicate', false, 'processed', true, 'test', true);
  end if;

  if p_transaction_id is null or p_original_transaction_id is null then
    update internal.storekit_notification_events event
    set processing_error = 'Apple notification did not include transaction info'
    where event.id = notification_event_id;

    return jsonb_build_object('ok', true, 'duplicate', false, 'processed', false, 'status', 202);
  end if;

  if p_app_account_token is not null then
    select app_token.user_id
    into token_user_id
    from internal.app_account_tokens app_token
    where app_token.token = p_app_account_token;
  end if;

  select tx.user_id
  into existing_user_id
  from internal.storekit_transactions tx
  where tx.environment = p_environment
    and (
      tx.transaction_id = p_transaction_id
      or tx.original_transaction_id = p_original_transaction_id
    )
  order by
    case when tx.transaction_id = p_transaction_id then 0 else 1 end,
    tx.updated_at desc
  limit 1;

  if token_user_id is not null
    and existing_user_id is not null
    and token_user_id is distinct from existing_user_id then
    record_error = 'Apple notification purchase owner does not match existing transaction owner';

    update internal.storekit_notification_events event
    set processing_error = record_error
    where event.id = notification_event_id;

    return jsonb_build_object('ok', false, 'error', record_error, 'status', 409);
  end if;

  resolved_user_id = coalesce(token_user_id, existing_user_id);

  if resolved_user_id is null then
    record_error = 'Could not resolve Apple notification purchase owner';

    update internal.storekit_notification_events event
    set processing_error = record_error
    where event.id = notification_event_id;

    return jsonb_build_object('ok', true, 'duplicate', false, 'processed', false, 'status', 202);
  end if;

  record_result = internal.record_verified_storekit_transaction(
    resolved_user_id,
    p_app_account_token,
    p_apple_product_id,
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_web_order_line_item_id,
    p_status,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_revocation_reason,
    p_signed_transaction_info,
    p_payload_json || jsonb_build_object(
      'notificationPayloadId',
      notification_payload_id,
      'notificationEventId',
      notification_event_id
    )
  );

  if coalesce((record_result ->> 'ok')::boolean, false) then
    update internal.storekit_notification_events event
    set processed_at = now(),
        processing_error = null
    where event.id = notification_event_id;

    return jsonb_build_object(
      'ok',
      true,
      'duplicate',
      false,
      'processed',
      true,
      'transaction',
      record_result
    );
  end if;

  record_error = coalesce(record_result ->> 'error', 'Could not record StoreKit transaction');

  update internal.storekit_notification_events event
  set processing_error = left(record_error, 4000)
  where event.id = notification_event_id;

  return jsonb_build_object(
    'ok',
    false,
    'error',
    record_error,
    'status',
    coalesce((record_result ->> 'status')::integer, 500)
  );
end;
$$;


ALTER FUNCTION "internal"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_user_id uuid;
  resolved_product_id uuid;
  existing_user_id uuid;
  payload_id uuid;
  storekit_transaction_id uuid;
begin
  if p_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Invalid user',
      'status', 401
    );
  end if;

  if p_app_account_token is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple transaction is missing appAccountToken',
      'status', 403
    );
  end if;

  select app_token.user_id
  into resolved_user_id
  from internal.app_account_tokens app_token
  where app_token.token = p_app_account_token;

  if resolved_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple appAccountToken is not registered',
      'status', 403
    );
  end if;

  if resolved_user_id is distinct from p_user_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple transaction belongs to a different user',
      'status', 403
    );
  end if;

  select product.id
  into resolved_product_id
  from public.subscription_products product
  where product.apple_product_id = p_apple_product_id
    and product.is_active
  limit 1;

  if resolved_product_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple product is not active in Paeonia',
      'status', 400
    );
  end if;

  select tx.user_id
  into existing_user_id
  from internal.storekit_transactions tx
  where tx.environment = p_environment
    and tx.transaction_id = p_transaction_id;

  if existing_user_id is not null and existing_user_id is distinct from p_user_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple transaction belongs to a different user',
      'status', 403
    );
  end if;

  insert into internal.storekit_payloads (
    payload_kind,
    environment,
    original_transaction_id,
    transaction_id,
    signed_payload,
    payload_json
  )
  values (
    'transaction',
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_signed_payload,
    p_payload_json
  )
  returning id into payload_id;

  insert into internal.storekit_transactions (
    user_id,
    product_id,
    environment,
    app_account_token,
    original_transaction_id,
    transaction_id,
    web_order_line_item_id,
    status,
    purchased_at,
    expires_at,
    revoked_at,
    revocation_reason,
    raw_payload_id,
    last_reconciled_at,
    reconciliation_claimed_at,
    reconciliation_attempts,
    last_reconciliation_error
  )
  values (
    p_user_id,
    resolved_product_id,
    p_environment,
    p_app_account_token,
    p_original_transaction_id,
    p_transaction_id,
    p_web_order_line_item_id,
    p_status,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_revocation_reason,
    payload_id,
    now(),
    null,
    0,
    null
  )
  on conflict (environment, transaction_id)
  do update set
    user_id = excluded.user_id,
    product_id = excluded.product_id,
    app_account_token = excluded.app_account_token,
    original_transaction_id = excluded.original_transaction_id,
    web_order_line_item_id = excluded.web_order_line_item_id,
    status = excluded.status,
    purchased_at = excluded.purchased_at,
    expires_at = excluded.expires_at,
    revoked_at = excluded.revoked_at,
    revocation_reason = excluded.revocation_reason,
    raw_payload_id = excluded.raw_payload_id,
    last_reconciled_at = excluded.last_reconciled_at,
    reconciliation_claimed_at = excluded.reconciliation_claimed_at,
    reconciliation_attempts = excluded.reconciliation_attempts,
    last_reconciliation_error = excluded.last_reconciliation_error
  returning id into storekit_transaction_id;

  return jsonb_build_object(
    'ok', true,
    'productId', resolved_product_id,
    'payloadId', payload_id,
    'transactionId', storekit_transaction_id
  );
end;
$$;


ALTER FUNCTION "internal"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_user_id uuid;
  resolved_product_id uuid;
  resolved_couple_id uuid;
  payload_id uuid;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'Invalid user', 'status', 401);
  end if;

  if p_app_account_token is null then
    return jsonb_build_object('ok', false, 'error', 'Apple transaction is missing appAccountToken', 'status', 403);
  end if;

  select app_token.user_id
  into resolved_user_id
  from internal.app_account_tokens app_token
  where app_token.token = p_app_account_token;

  if resolved_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'Apple appAccountToken is not registered', 'status', 403);
  end if;

  if resolved_user_id is distinct from p_user_id then
    return jsonb_build_object('ok', false, 'error', 'Apple transaction belongs to a different user', 'status', 403);
  end if;

  select product.id
  into resolved_product_id
  from public.subscription_products product
  where product.apple_product_id = p_apple_product_id
    and product.kind = 'streak_restore'
    and product.is_active
  limit 1;

  if resolved_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'Apple product is not active in Paeonia', 'status', 400);
  end if;

  resolved_couple_id = internal.get_entitled_couple_id_for_user(p_user_id);

  if resolved_couple_id is null then
    return jsonb_build_object('ok', false, 'error', 'No entitled couple for this user', 'status', 403);
  end if;

  insert into internal.storekit_payloads (
    payload_kind,
    environment,
    original_transaction_id,
    transaction_id,
    signed_payload,
    payload_json
  ) values (
    'transaction',
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_signed_payload,
    p_payload_json
  )
  returning id into payload_id;

  return internal.apply_streak_restore(
    resolved_couple_id,
    p_user_id,
    resolved_product_id,
    p_environment,
    p_transaction_id,
    p_original_transaction_id,
    p_purchased_at,
    payload_id
  );
end;
$$;


ALTER FUNCTION "internal"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."redeem_review_access"("p_code_id" "uuid", "p_reviewer_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  code_row internal.review_access_codes%rowtype;
  partner_id uuid;
  existing_couple_id uuid;
  resolved_pair_id uuid;
  created_couple_id uuid;
  couple_subscription_product_id uuid;
  demo_started_on date := current_date - 180;
  demo_restorable_count integer := 12;
  code_prefix text;
begin
  if p_reviewer_user_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  select *
  into code_row
  from internal.review_access_codes
  where id = p_code_id
  for update;

  -- A revoked, expired, or unknown code is never redeemable -- not even as a
  -- replay. The redemption ceiling is deliberately NOT checked here; it is
  -- enforced further down, after the idempotent-replay lookup, so a reviewer who
  -- already redeemed can still be returned to their couple once the code is fully
  -- consumed (replay does not consume a redemption).
  if not found
    or code_row.status <> 'active'
    or (code_row.expires_at is not null and code_row.expires_at <= now()) then
    raise exception 'review access code is not available' using errcode = '22023';
  end if;

  partner_id := code_row.seeded_partner_user_id;

  if partner_id is null then
    raise exception 'review access code has no seeded partner' using errcode = '23514';
  end if;

  if partner_id = p_reviewer_user_id then
    raise exception 'reviewer cannot be the seeded partner' using errcode = '23514';
  end if;

  -- Replay: reuse this reviewer's still-active couple from a prior redemption.
  -- Runs before the redemption-ceiling check below so an already-paired reviewer
  -- can always get back into their couple, even after the code is exhausted.
  select session.couple_id
  into existing_couple_id
  from internal.review_access_sessions session
  join public.couples couple
    on couple.id = session.couple_id and couple.status = 'active'
  join public.couple_members member
    on member.couple_id = couple.id
    and member.user_id = p_reviewer_user_id
    and member.status = 'active'
  where session.code_id = p_code_id
    and session.user_id = p_reviewer_user_id
  order by session.redeemed_at desc
  limit 1;

  if existing_couple_id is not null then
    return existing_couple_id;
  end if;

  -- Only a genuinely new redemption consumes capacity, so enforce the ceiling
  -- here rather than up front. A reviewer's replay (handled above) is never
  -- blocked by an exhausted code.
  if code_row.redemption_count >= code_row.max_redemptions then
    raise exception 'review access code is not available' using errcode = '22023';
  end if;

  -- Neither party may already hold an active couple (unique index enforces this;
  -- mint's reset clears the partner). Fail clearly rather than hit the index.
  if exists (
    select 1 from public.couple_members
    where user_id = p_reviewer_user_id and status = 'active'
  ) then
    raise exception 'reviewer already has an active couple' using errcode = '23505';
  end if;

  if exists (
    select 1 from public.couple_members
    where user_id = partner_id and status = 'active'
  ) then
    raise exception 'seeded partner still has an active couple; run reset before minting'
      using errcode = '23505';
  end if;

  resolved_pair_id := internal.get_or_create_relationship_pair(partner_id, p_reviewer_user_id);

  if internal.has_active_relationship_block(resolved_pair_id) then
    raise exception 'review pair is blocked' using errcode = '42501';
  end if;

  -- The couple. created_by = partner mirrors "the partner invited the reviewer".
  insert into public.couples (pair_id, status, started_on, created_by_user_id)
  values (resolved_pair_id, 'active', demo_started_on, partner_id)
  returning id into created_couple_id;

  insert into public.couple_members (couple_id, user_id, role, status)
  values
    (created_couple_id, partner_id, 'creator', 'active'),
    (created_couple_id, p_reviewer_user_id, 'partner', 'active');

  -- Partner location so the map shows a pin (central Oslo).
  insert into public.latest_partner_locations (
    couple_id, user_id, latitude, longitude, accuracy_m, captured_at,
    source, client_operation_id, client_id, client_sequence
  ) values (
    created_couple_id, partner_id, 59.913900, 10.752300, 25, now(),
    'settings_toggle', extensions.gen_random_uuid(), extensions.gen_random_uuid(), 1
  );

  insert into public.location_sharing_preferences (
    couple_id, user_id, is_enabled, enabled_at, disabled_at, consent_version, source
  ) values (
    created_couple_id, partner_id, true, now(), null, '1', 'settings_toggle'
  );

  -- Broken streak with a long restore window so streak-restore is reachable
  -- during review (well past the normal 24h). current_count = 0 keeps the
  -- last_qualified/next-deadline columns null per streak_states constraints.
  insert into public.streak_states (
    couple_id, current_count, longest_count,
    last_qualified_date, last_qualified_couple_day_id,
    restore_available, next_activity_deadline_at,
    restorable_count, restorable_through_date, restore_deadline
  ) values (
    created_couple_id, 0, demo_restorable_count,
    null, null,
    true, null,
    demo_restorable_count, current_date - 2, now() + interval '30 days'
  );

  -- Optional realism: an expired partner subscription so the paywall reads like a
  -- lapsed subscriber. The paywall itself triggers from the couple having no
  -- active entitlement, so this is skipped safely if no product is configured.
  select id
  into couple_subscription_product_id
  from public.subscription_products
  where kind = 'couple_subscription' and is_active
  order by created_at
  limit 1;

  if couple_subscription_product_id is not null then
    insert into internal.storekit_transactions (
      user_id, product_id, environment,
      original_transaction_id, transaction_id, status,
      purchased_at, expires_at
    ) values (
      partner_id, couple_subscription_product_id, 'sandbox',
      'review-demo-' || created_couple_id::text,
      'review-demo-' || created_couple_id::text,
      'expired',
      now() - interval '60 days', now() - interval '30 days'
    )
    on conflict (environment, transaction_id) do nothing;
  end if;

  -- Mirror real pairing so local-first clients refresh into the paired state.
  perform internal.create_relationship_sync_event(
    partner_id, created_couple_id, p_reviewer_user_id,
    'relationship_started', 'review_access_redeemed',
    'active', 'active', null, null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );
  perform internal.create_relationship_sync_event(
    p_reviewer_user_id, created_couple_id, p_reviewer_user_id,
    'relationship_started', 'review_access_redeemed',
    'active', 'active', null, null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );

  -- Record the session + a success attempt, and consume one redemption.
  code_prefix := left(encode(code_row.code_hash, 'hex'), 12);

  insert into internal.review_access_sessions (
    code_id, user_id, seeded_partner_user_id, couple_id, scenario, auth_verified_at
  ) values (
    p_code_id, p_reviewer_user_id, partner_id, created_couple_id, code_row.scenario, now()
  );

  insert into internal.review_access_attempts (
    user_id, code_hash_prefix, matched_code_id, success
  ) values (
    p_reviewer_user_id, code_prefix, p_code_id, true
  );

  update internal.review_access_codes
  set redemption_count = redemption_count + 1
  where id = p_code_id;

  return created_couple_id;
end;
$$;


ALTER FUNCTION "internal"."redeem_review_access"("p_code_id" "uuid", "p_reviewer_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."refresh_streak_after_device_time_zone_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_row record;
begin
  if tg_op = 'UPDATE'
    and new.time_zone_id is not distinct from old.time_zone_id
    and new.last_seen_at is not distinct from old.last_seen_at
    and new.disabled_at is not distinct from old.disabled_at then
    return new;
  end if;

  for couple_row in
    select member.couple_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  loop
    perform internal.detect_streak_break(couple_row.couple_id);
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."refresh_streak_after_device_time_zone_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."refresh_streak_after_profile_time_zone_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  couple_row record;
begin
  if new.time_zone_id is not distinct from old.time_zone_id then
    return new;
  end if;

  for couple_row in
    select member.couple_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  loop
    perform internal.detect_streak_break(couple_row.couple_id);
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "internal"."refresh_streak_after_profile_time_zone_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."refresh_streak_deadline"("p_couple_id" "uuid") RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  state public.streak_states%rowtype;
  qualified_at timestamptz;
  resolved_deadline timestamptz;
begin
  select *
  into state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  if not found
    or state.current_count <= 0
    or coalesce(state.restorable_count, 0) > 0 then
    return state.next_activity_deadline_at;
  end if;

  qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    state.last_qualified_couple_day_id
  );

  -- Rows created before this migration may have counted a one-person day. Use
  -- the same latest-event anchor those rows used before this migration, rather
  -- than shortening their shipped deadline to the couple-day start.
  if qualified_at is null then
    select max(event.occurred_at)
    into qualified_at
    from public.couple_activity_events event
    where event.couple_id = p_couple_id
      and event.couple_day_id = state.last_qualified_couple_day_id;
  end if;

  if qualified_at is null then
    return state.next_activity_deadline_at;
  end if;

  resolved_deadline = internal.resolve_next_activity_deadline_at(
    p_couple_id,
    qualified_at
  );

  update public.streak_states
  set next_activity_deadline_at = resolved_deadline
  where couple_id = p_couple_id
    and next_activity_deadline_at is distinct from resolved_deadline;

  return resolved_deadline;
end;
$$;


ALTER FUNCTION "internal"."refresh_streak_deadline"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  insert into internal.review_demo_partners (slot, user_id, display_name)
  values (p_slot, p_user_id, p_display_name)
  on conflict (slot) do update
  set user_id = excluded.user_id,
      display_name = excluded.display_name,
      updated_at = now();

  perform internal.ensure_review_partner(p_user_id, p_display_name);
end;
$$;


ALTER FUNCTION "internal"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text" DEFAULT NULL::"text", "p_time_zone_id" "text" DEFAULT NULL::"text", "p_app_version" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  token_hash bytea;
  registered_device_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_platform is null or p_platform not in ('ios', 'ipados') then
    raise exception 'unsupported device platform'
      using errcode = '23514';
  end if;

  if p_push_token is null or char_length(p_push_token) not between 20 and 4096 then
    raise exception 'invalid push token'
      using errcode = '23514';
  end if;

  if p_apns_environment is null or p_apns_environment not in ('sandbox', 'production') then
    raise exception 'unsupported APNs environment'
      using errcode = '23514';
  end if;

  token_hash = extensions.digest(p_push_token, 'sha256');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.encode(token_hash, 'hex') || ':' || p_apns_environment,
      0
    )
  );

  update public.user_devices
  set disabled_at = now()
  where push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and user_id <> current_user_id
    and disabled_at is null;

  select id
  into registered_device_id
  from public.user_devices
  where user_id = current_user_id
    and push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and disabled_at is null
  order by updated_at desc, id
  limit 1
  for update;

  if registered_device_id is null then
    insert into public.user_devices (
      user_id,
      platform,
      push_token,
      push_token_hash,
      apns_environment,
      locale,
      time_zone_id,
      app_version,
      last_seen_at
    ) values (
      current_user_id,
      p_platform,
      p_push_token,
      token_hash,
      p_apns_environment,
      nullif(btrim(p_locale), ''),
      nullif(btrim(p_time_zone_id), ''),
      nullif(btrim(p_app_version), ''),
      now()
    )
    returning id into registered_device_id;
  else
    update public.user_devices
    set
      platform = p_platform,
      push_token = p_push_token,
      push_token_hash = token_hash,
      apns_environment = p_apns_environment,
      locale = nullif(btrim(p_locale), ''),
      time_zone_id = nullif(btrim(p_time_zone_id), ''),
      app_version = nullif(btrim(p_app_version), ''),
      last_seen_at = now(),
      disabled_at = null
    where id = registered_device_id;
  end if;

  return registered_device_id;
end;
$$;


ALTER FUNCTION "internal"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text" DEFAULT NULL::"text", "p_time_zone_id" "text" DEFAULT NULL::"text", "p_app_version" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  token_hash bytea;
  registered_device_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_widget_kind is null or char_length(btrim(p_widget_kind)) not between 1 and 128 then
    raise exception 'invalid widget kind'
      using errcode = '23514';
  end if;

  if p_widget_push_token is null or char_length(p_widget_push_token) not between 20 and 4096 then
    raise exception 'invalid widget push token'
      using errcode = '23514';
  end if;

  if p_apns_environment is null or p_apns_environment not in ('sandbox', 'production') then
    raise exception 'unsupported APNs environment'
      using errcode = '23514';
  end if;

  token_hash = extensions.digest(p_widget_push_token, 'sha256');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.encode(token_hash, 'hex') || ':' || p_apns_environment || ':' || p_widget_kind,
      0
    )
  );

  update public.widget_push_devices
  set disabled_at = now()
  where widget_push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and widget_kind = p_widget_kind
    and user_id <> current_user_id
    and disabled_at is null;

  select id
  into registered_device_id
  from public.widget_push_devices
  where user_id = current_user_id
    and widget_push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and widget_kind = p_widget_kind
  order by updated_at desc, id
  limit 1
  for update;

  if registered_device_id is null then
    insert into public.widget_push_devices (
      user_id,
      widget_kind,
      widget_push_token,
      widget_push_token_hash,
      apns_environment,
      locale,
      time_zone_id,
      app_version
    )
    values (
      current_user_id,
      btrim(p_widget_kind),
      p_widget_push_token,
      token_hash,
      p_apns_environment,
      nullif(btrim(p_locale), ''),
      nullif(btrim(p_time_zone_id), ''),
      nullif(btrim(p_app_version), '')
    )
    returning id into registered_device_id;
  else
    update public.widget_push_devices
    set
      widget_push_token = p_widget_push_token,
      locale = nullif(btrim(p_locale), ''),
      time_zone_id = nullif(btrim(p_time_zone_id), ''),
      app_version = nullif(btrim(p_app_version), ''),
      last_seen_at = now(),
      disabled_at = null
    where id = registered_device_id;
  end if;

  return registered_device_id;
end;
$$;


ALTER FUNCTION "internal"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."reject_pending_account_client_operation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if exists (
    select 1
    from internal.account_deletion_jobs job
    where job.user_id = new.user_id
  ) then
    raise exception 'account deletion is in progress'
      using errcode = '42501';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "internal"."reject_pending_account_client_operation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  memory_media_row public.memory_media%rowtype;
  memory_row public.memories%rowtype;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'remove_memory_media',
      p_memory_media_id::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'remove_memory_media',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'memory_media_id')::uuid;
  end if;

  select *
  into memory_media_row
  from public.memory_media
  where id = p_memory_media_id
  for update;

  if not found
    or memory_media_row.deleted_at is not null
    or memory_media_row.moderation_status <> 'visible'
    or memory_media_row.owner_user_id <> current_user_id then
    raise exception 'memory media is not removable'
      using errcode = '42501';
  end if;

  select *
  into memory_row
  from public.memories
  where id = memory_media_row.memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  update public.memory_media
  set deleted_at = now()
  where id = memory_media_row.id;

  update public.media_assets
  set
    storage_delete_status = case
      when storage_delete_status = 'none' then 'pending'
      else storage_delete_status
    end,
    deleted_at = coalesce(deleted_at, now())
  where id = memory_media_row.media_asset_id
    and owner_user_id = current_user_id
    and storage_delete_status <> 'deleted';

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('memory_media_id', memory_media_row.id)
  );

  return memory_media_row.id;
end;
$$;


ALTER FUNCTION "internal"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."request_account_deletion"() RETURNS TABLE("id" "uuid", "status" "text", "requested_at" timestamp with time zone, "deletion_job_id" "uuid", "auth_provider" "text", "provider_revocation_status" "text", "auth_delete_status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
#variable_conflict use_column
declare
  current_user_id uuid;
  request_row public.privacy_requests%rowtype;
  job_row internal.account_deletion_jobs%rowtype;
  created_request boolean := false;
  resolved_provider text;
  active_pair_id uuid;
  relationship_ended boolean := false;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  -- Serialize duplicate taps, multiple devices, and Edge Function retries for
  -- one account without holding locks for any external network work.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('account-deletion:' || current_user_id::text, 0)
  );

  -- Once the first-stage transaction has committed, every retry must return
  -- that durable tombstone instead of replaying destructive work or creating a
  -- second privacy request. This also closes the window where an already-issued
  -- access JWT can call this RPC after the Auth user has been hard-deleted.
  select job.*
  into job_row
  from internal.account_deletion_jobs job
  where job.user_id = current_user_id
  for update;

  if job_row.id is not null then
    select request.*
    into request_row
    from public.privacy_requests request
    where request.id = job_row.request_id;

    if request_row.id is null then
      raise exception 'account deletion request tombstone is missing';
    end if;

    return query
    select
      request_row.id,
      request_row.status,
      request_row.requested_at,
      job_row.id,
      job_row.auth_provider,
      job_row.provider_revocation_status,
      job_row.status;
    return;
  end if;

  resolved_provider = case
    -- Prefer Apple when identities are linked because its provider grant has a
    -- separate revocation obligation even if Google was used most recently.
    -- Read the canonical identity table as well as JWT metadata: a token issued
    -- on another device before identity linking can have a stale providers list.
    when exists (
      select 1
      from auth.identities identity
      where identity.user_id = current_user_id
        and identity.provider = 'apple'
    )
      or lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '')) = 'apple'
      or coalesce(auth.jwt() -> 'app_metadata' -> 'providers', '[]'::jsonb)
        @> '["apple"]'::jsonb
      then 'apple'
    when exists (
      select 1
      from auth.identities identity
      where identity.user_id = current_user_id
        and identity.provider = 'google'
    )
      or lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'provider', '')) = 'google'
      or coalesce(auth.jwt() -> 'app_metadata' -> 'providers', '[]'::jsonb)
        @> '["google"]'::jsonb
      then 'google'
    else 'unknown'
  end;

  select request.*
  into request_row
  from public.privacy_requests request
  where request.user_id = current_user_id
    and request.request_kind = 'deletion'
    and request.status in ('submitted', 'verifying', 'processing')
  order by request.requested_at desc, request.id
  limit 1
  for update;

  if request_row.id is null then
    insert into public.privacy_requests (
      user_id,
      request_kind,
      status,
      verified_at,
      visible_status_message
    ) values (
      current_user_id,
      'deletion',
      'processing',
      now(),
      'Your account deletion is in progress.'
    )
    on conflict (user_id)
      where request_kind = 'deletion'
        and status in ('submitted', 'verifying', 'processing')
    do nothing
    returning *
    into request_row;

    created_request = request_row.id is not null;
  end if;

  if request_row.id is null then
    select request.*
    into request_row
    from public.privacy_requests request
    where request.user_id = current_user_id
      and request.request_kind = 'deletion'
      and request.status in ('submitted', 'verifying', 'processing')
    order by request.requested_at desc, request.id
    limit 1
    for update;
  else
    update public.privacy_requests request
    set
      status = 'processing',
      verified_at = coalesce(request.verified_at, now()),
      visible_status_message = 'Your account deletion is in progress.'
    where request.id = request_row.id
    returning request.* into request_row;
  end if;

  if request_row.id is null then
    raise exception 'could not create account deletion request';
  end if;

  if created_request then
    insert into internal.privacy_request_events (
      request_id,
      actor_user_id,
      event_kind,
      metadata
    ) values (
      request_row.id,
      current_user_id,
      'deletion_requested',
      jsonb_build_object('source', 'ios_app')
    );
  end if;

  -- Reuse the canonical leave transition so the remaining partner receives the
  -- same ended notice and the same 30-day relationship cleanup schedule.
  select couple.pair_id
  into active_pair_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
  order by couple.created_at desc
  limit 1;

  if active_pair_id is not null then
    relationship_ended = internal.end_relationship_for_pair(
      active_pair_id,
      current_user_id,
      'account_deletion'
    );
  end if;

  -- An unaccepted invite must not let a deleted identity create a relationship
  -- later. Accepted/revoked history remains as an audit snapshot.
  update public.pairing_invites
  set
    status = 'revoked',
    revoked_at = coalesce(revoked_at, now())
  where created_by_user_id = current_user_id
    and status = 'pending';

  -- Remove every delivery and location path before the Auth job runs. Delete
  -- outbox rows first to keep this migration correct even on environments that
  -- have not yet replayed the FK cascade reconciliation above.
  delete from internal.widget_push_outbox outbox
  where outbox.recipient_user_id = current_user_id
     or outbox.target_widget_device_id in (
       select device.id
       from public.widget_push_devices device
       where device.user_id = current_user_id
     );

  delete from internal.notification_outbox outbox
  where outbox.recipient_user_id = current_user_id
     or outbox.target_device_id in (
       select device.id
       from public.user_devices device
       where device.user_id = current_user_id
     );

  delete from public.widget_push_devices
  where user_id = current_user_id;

  delete from public.user_devices
  where user_id = current_user_id;

  delete from public.notification_preferences
  where user_id = current_user_id;

  delete from public.latest_partner_locations
  where user_id = current_user_id;

  delete from public.location_sharing_preferences
  where user_id = current_user_id;

  -- Revocable test/review access should not outlive the account. StoreKit and
  -- streak-purchase ledgers remain as restricted audit records keyed by UUID.
  update internal.entitlement_grants grant_row
  set
    status = 'revoked',
    revoked_at = coalesce(grant_row.revoked_at, now()),
    revoked_reason = coalesce(grant_row.revoked_reason, 'account_deleted')
  where grant_row.user_id = current_user_id
    and grant_row.status = 'active';

  update internal.review_access_sessions review_session
  set completed_at = coalesce(review_session.completed_at, now())
  where review_session.user_id = current_user_id;

  -- Clearing the profile-photo reference invokes the existing orphan trigger,
  -- which queues the actual bytes for deletion through the Storage API.
  update public.profiles profile
  set
    display_name = null,
    profile_photo_asset_id = null,
    time_zone_id = null,
    time_zone_updated_at = null,
    onboarding_completed_at = null,
    moderation_status = 'hidden',
    deleted_at = coalesce(profile.deleted_at, now())
  where profile.user_id = current_user_id;

  -- Also queue abandoned uploads and every profile-photo object owned by this
  -- user. Finalized relationship media follows the normal ended-couple window;
  -- report snapshots follow their separate retention policy.
  update public.media_assets asset
  set
    deleted_at = coalesce(asset.deleted_at, now()),
    storage_delete_status = 'pending',
    storage_deleted_at = null,
    last_storage_delete_error = null
  where asset.owner_user_id = current_user_id
    and asset.storage_delete_status <> 'deleted'
    and asset.upload_purpose <> 'report_snapshot'
    and (
      asset.upload_purpose = 'profile_photo'
      or asset.upload_status <> 'finalized'
    );

  -- Supabase Auth refuses hard deletion while Storage objects still name the
  -- user as owner. Detach only ownership metadata here; do not delete bytes or
  -- object rows. Existing trusted Storage-API cleanup still performs physical
  -- deletion at the correct profile/relationship/report retention deadline.
  update storage.objects object_row
  set
    owner = null,
    owner_id = null
  where object_row.owner = current_user_id
     or object_row.owner_id = current_user_id::text;

  insert into internal.account_deletion_jobs (
    request_id,
    user_id,
    auth_provider,
    status,
    provider_revocation_status,
    next_attempt_at
  ) values (
    request_row.id,
    current_user_id,
    resolved_provider,
    'ready_for_auth_delete',
    case resolved_provider
      when 'apple' then 'manual_required'
      else 'not_required'
    end,
    -- Give the authenticated Edge request a short reservation window before
    -- the generic drain may claim the job. A targeted claim ignores this due
    -- time and still performs the normal deletion immediately.
    now() + interval '30 seconds'
  )
  on conflict (user_id) do update
  set
    request_id = excluded.request_id,
    auth_provider = excluded.auth_provider,
    provider_revocation_status = case
      when internal.account_deletion_jobs.provider_revocation_status = 'succeeded'
        then 'succeeded'
      else excluded.provider_revocation_status
    end,
    status = case
      when internal.account_deletion_jobs.status = 'completed' then 'completed'
      else internal.account_deletion_jobs.status
    end,
    next_attempt_at = case
      when internal.account_deletion_jobs.provider_revocation_status = 'succeeded'
        then least(internal.account_deletion_jobs.next_attempt_at, now())
      else internal.account_deletion_jobs.next_attempt_at
    end
  returning * into job_row;

  insert into internal.privacy_request_events (
    request_id,
    actor_user_id,
    event_kind,
    metadata
  )
  select
    request_row.id,
    current_user_id,
    'account_data_removed',
    jsonb_build_object(
      'relationship_ended', relationship_ended,
      'auth_provider', resolved_provider,
      'provider_revocation_status', job_row.provider_revocation_status
    )
  where not exists (
    select 1
    from internal.privacy_request_events event
    where event.request_id = request_row.id
      and event.event_kind = 'account_data_removed'
  );

  return query
  select
    request_row.id,
    request_row.status,
    request_row.requested_at,
    job_row.id,
    job_row.auth_provider,
    job_row.provider_revocation_status,
    job_row.status;
end;
$$;


ALTER FUNCTION "internal"."request_account_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."request_account_deletion_drain"("p_source" "text" DEFAULT 'manual'::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.account_deletion_drain_queued', true) = '1' then
    return true;
  end if;

  if not internal.has_due_account_deletion_work(now()) then
    return false;
  end if;

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in (
    'account_deletion_drain_secret',
    'media_storage_cleanup_secret',
    'widget_drain_secret'
  )
  order by case name
    when 'account_deletion_drain_secret' then 0
    when 'media_storage_cleanup_secret' then 1
    else 2
  end
  limit 1;

  if coalesce(drain_secret, '') = '' then
    return false;
  end if;

  perform set_config('paeonia.account_deletion_drain_queued', '1', true);

  perform net.http_post(
    url := 'https://api.paeonia.no/functions/v1/delete-account',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-drain-secret', drain_secret
    ),
    body := jsonb_build_object(
      'source', coalesce(nullif(btrim(p_source), ''), 'manual'),
      'triggered_at', now()
    )
  );

  return true;
end;
$$;


ALTER FUNCTION "internal"."request_account_deletion_drain"("p_source" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."request_push_notification_drain"("p_source" "text" DEFAULT 'manual'::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.push_notification_drain_queued', true) = '1' then
    return true;
  end if;

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in ('push_notification_drain_secret', 'widget_drain_secret')
  order by case name
    when 'push_notification_drain_secret' then 0
    else 1
  end
  limit 1;

  if coalesce(drain_secret, '') = '' then
    return false;
  end if;

  perform set_config('paeonia.push_notification_drain_queued', '1', true);

  perform net.http_post(
    url := 'https://api.paeonia.no/functions/v1/send-push-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-drain-secret', drain_secret
    ),
    body := jsonb_build_object(
      'source', coalesce(nullif(btrim(p_source), ''), 'manual'),
      'triggered_at', now()
    )
  );

  return true;
end;
$$;


ALTER FUNCTION "internal"."request_push_notification_drain"("p_source" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."reset_review_demo"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  partner_id uuid;
  removed integer;
  deleted_couples integer := 0;
begin
  for partner_id in
    select user_id
    from internal.review_demo_partners
  loop
    with removed_couples as (
      delete from public.couples
      where id in (
        select couple_id
        from public.couple_members
        where user_id = partner_id
      )
      returning 1
    )
    select count(*) into removed from removed_couples;
    deleted_couples := deleted_couples + removed;

    -- The expired demo subscription is keyed by user, not couple, so it does not
    -- cascade with the couple. Clear it explicitly.
    delete from internal.storekit_transactions where user_id = partner_id;
  end loop;

  return deleted_couples;
end;
$$;


ALTER FUNCTION "internal"."reset_review_demo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_content_report_target"("p_reporter_user_id" "uuid", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("target_kind" "text", "reported_user_id" "uuid", "couple_id" "uuid", "pair_id" "uuid", "snapshot" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."resolve_content_report_target"("p_reporter_user_id" "uuid", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_couple_day_anchor"("p_couple_id" "uuid") RETURNS TABLE("local_date" "date", "anchor_time_zone_id" "text", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.resolve_couple_day_anchor_at(p_couple_id, now());
$$;


ALTER FUNCTION "internal"."resolve_couple_day_anchor"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_couple_day_anchor_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) RETURNS TABLE("local_date" "date", "anchor_time_zone_id" "text", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  anchor_row record;
begin
  if p_observed_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  select
    coalesce(timezone_name.name, 'UTC') as resolved_time_zone_id,
    p_observed_at at time zone coalesce(timezone_name.name, 'UTC') as local_observed_at
  into anchor_row
  from public.couple_members member
  left join public.profiles profile
    on profile.user_id = member.user_id
  left join pg_timezone_names timezone_name
    on timezone_name.name = profile.time_zone_id
  where member.couple_id = p_couple_id
    and member.status = 'active'
  order by (p_observed_at at time zone coalesce(timezone_name.name, 'UTC')) asc,
    coalesce(timezone_name.name, 'UTC') asc
  limit 1;

  if anchor_row.resolved_time_zone_id is null then
    raise exception 'active couple members are required'
      using errcode = '23514';
  end if;

  local_date = anchor_row.local_observed_at::date;
  anchor_time_zone_id = anchor_row.resolved_time_zone_id;
  starts_at = local_date::timestamp at time zone anchor_time_zone_id;
  ends_at = (local_date::timestamp + interval '1 day') at time zone anchor_time_zone_id;

  return next;
end;
$$;


ALTER FUNCTION "internal"."resolve_couple_day_anchor_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_current_couple_entitlement"() RETURNS TABLE("couple_id" "uuid", "is_entitled" boolean, "covering_user_id" "uuid", "source" "text", "status" "text", "product_id" "uuid", "current_period_end" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_couple as (
    select couple.id as couple_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = (select auth.uid())
      and member.status = 'active'
      and couple.status = 'active'
    order by couple.created_at desc
    limit 1
  ),
  member_entitlements as (
    select
      current_couple.couple_id,
      member.user_id,
      entitlement.is_entitled,
      entitlement.source,
      entitlement.status,
      entitlement.product_id,
      entitlement.current_period_end,
      entitlement.updated_at
    from current_couple
    join public.couple_members member
      on member.couple_id = current_couple.couple_id
      and member.status = 'active'
    join internal.resolve_user_entitlement(member.user_id) entitlement
      on true
  ),
  entitlement_summary as (
    select
      current_couple.couple_id,
      coalesce(bool_or(member_entitlements.is_entitled), false) as is_entitled
    from current_couple
    left join member_entitlements
      on member_entitlements.couple_id = current_couple.couple_id
    group by current_couple.couple_id
  ),
  best_entitlement as (
    select
      candidate.couple_id,
      candidate.user_id,
      candidate.source,
      candidate.status,
      candidate.product_id,
      candidate.current_period_end,
      candidate.updated_at
    from member_entitlements candidate
    where candidate.is_entitled
    order by
      case candidate.status
        when 'lifetime' then 0
        when 'active' then 1
        when 'grace' then 2
        else 3
      end,
      candidate.current_period_end desc nulls first,
      candidate.updated_at desc
    limit 1
  )
  select
    entitlement_summary.couple_id,
    entitlement_summary.is_entitled,
    best_entitlement.user_id,
    best_entitlement.source,
    best_entitlement.status,
    best_entitlement.product_id,
    best_entitlement.current_period_end,
    best_entitlement.updated_at
  from entitlement_summary
  left join best_entitlement
    on best_entitlement.couple_id = entitlement_summary.couple_id;
$$;


ALTER FUNCTION "internal"."resolve_current_couple_entitlement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_next_activity_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.resolve_streak_deadline_at(p_couple_id, p_observed_at, 2);
$$;


ALTER FUNCTION "internal"."resolve_next_activity_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_streak_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone, "p_local_days_after" integer) RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_deadline timestamptz;
begin
  if p_couple_id is null or p_observed_at is null then
    raise exception 'couple and observed timestamp are required'
      using errcode = '23514';
  end if;

  if p_local_days_after not between 1 and 2 then
    raise exception 'local deadline offset must be one or two days'
      using errcode = '23514';
  end if;

  select max(
    (
      (
        (
          p_observed_at at time zone coalesce(
            latest_device_time_zone.name,
            profile_time_zone.name,
            'UTC'
          )
        )::date
        + p_local_days_after
      )::timestamp
      at time zone coalesce(
        latest_device_time_zone.name,
        profile_time_zone.name,
        'UTC'
      )
    )
  )
  into resolved_deadline
  from public.couple_members member
  left join public.profiles profile
    on profile.user_id = member.user_id
  left join pg_timezone_names profile_time_zone
    on profile_time_zone.name = profile.time_zone_id
  left join lateral (
    select timezone_name.name
    from public.user_devices device
    join pg_timezone_names timezone_name
      on timezone_name.name = device.time_zone_id
    where device.user_id = member.user_id
      and device.disabled_at is null
    order by device.last_seen_at desc, device.updated_at desc, device.id
    limit 1
  ) latest_device_time_zone on true
  where member.couple_id = p_couple_id
    and member.status = 'active';

  if resolved_deadline is null then
    raise exception 'active couple members are required'
      using errcode = '23514';
  end if;

  return resolved_deadline;
end;
$$;


ALTER FUNCTION "internal"."resolve_streak_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone, "p_local_days_after" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."resolve_user_entitlement"("p_user_id" "uuid") RETURNS TABLE("user_id" "uuid", "is_entitled" boolean, "source" "text", "status" "text", "product_id" "uuid", "current_period_end" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with ranked_entitlements as (
    select
      ent.user_id,
      ent.source,
      ent.status,
      ent.product_id,
      ent.current_period_end,
      ent.updated_at,
      case
        when ent.source = 'storekit' then
          ent.status in ('active', 'grace')
          and ent.current_period_end is not null
          and ent.current_period_end > now()
        when ent.source = 'lifetime_grant' then
          ent.status = 'lifetime'
          and (ent.current_period_end is null or ent.current_period_end > now())
        else
          ent.status = 'active'
          and ent.current_period_end is not null
          and ent.current_period_end > now()
      end as grants_access
    from public.user_entitlements ent
    where ent.user_id = p_user_id
  ),
  entitlement_summary as (
    select coalesce(bool_or(grants_access), false) as is_entitled
    from ranked_entitlements
  ),
  best_entitlement as (
    select
      ranked.source,
      ranked.status,
      ranked.product_id,
      ranked.current_period_end,
      ranked.updated_at
    from ranked_entitlements ranked
    order by
      ranked.grants_access desc,
      case ranked.status
        when 'lifetime' then 0
        when 'active' then 1
        when 'grace' then 2
        else 3
      end,
      ranked.current_period_end desc nulls first,
      ranked.updated_at desc
    limit 1
  )
  select
    p_user_id,
    entitlement_summary.is_entitled,
    best_entitlement.source,
    best_entitlement.status,
    best_entitlement.product_id,
    best_entitlement.current_period_end,
    best_entitlement.updated_at
  from entitlement_summary
  left join best_entitlement on true;
$$;


ALTER FUNCTION "internal"."resolve_user_entitlement"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."retry_account_deletion_job"("p_job_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  changed_rows integer;
begin
  update internal.account_deletion_jobs
  set
    status = 'ready_for_auth_delete',
    -- An attention-required job has exhausted the normal claim budget. Reset
    -- the per-run attempt counter so an explicit operator retry is claimable;
    -- prior failure events retain the audit history.
    auth_delete_attempts = 0,
    next_attempt_at = now(),
    claimed_at = null,
    last_auth_delete_error_code = null
  where id = p_job_id
    and status = 'attention_required';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."retry_account_deletion_job"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."revoke_pairing_invite"("p_invite_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update public.pairing_invites
  set
    status = 'revoked',
    revoked_at = now()
  where id = p_invite_id
    and created_by_user_id = current_user_id
    and status = 'pending';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;


ALTER FUNCTION "internal"."revoke_pairing_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."revoke_review_access_codes"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  changed_rows integer;
begin
  update internal.review_access_codes
  set status = 'revoked', revoked_at = now()
  where status = 'active';

  get diagnostics changed_rows = row_count;
  return changed_rows;
end;
$$;


ALTER FUNCTION "internal"."revoke_review_access_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval)) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid := auth.uid();
  current_invite_row public.pairing_invites%rowtype;
  invite_code_hash bytea;
  new_invite_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_current_invite_id is null then
    raise exception 'current invite id is required'
      using errcode = '23514';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'rotate_pairing_invite',
      p_current_invite_id::text,
      pg_catalog.encode(invite_code_hash, 'hex'),
      p_expires_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'rotate_pairing_invite',
    'pairing_invites',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'invite_id')::uuid;
  end if;

  if p_expires_at <= now() or p_expires_at > now() + interval '30 days' then
    raise exception 'invite expiration is out of range'
      using errcode = '23514';
  end if;

  if not (select internal.user_has_direct_entitlement(current_user_id)) then
    raise exception 'direct entitlement is required to create an invite'
      using errcode = '42501';
  end if;

  select invite.*
  into current_invite_row
  from public.pairing_invites invite
  where invite.id = p_current_invite_id
    and invite.created_by_user_id = current_user_id
  for update of invite;

  if not found then
    raise exception 'current invite is not available'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = current_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'user already has an active couple'
      using errcode = '23505';
  end if;

  insert into public.pairing_invites (created_by_user_id, expires_at)
  values (current_user_id, p_expires_at)
  returning id into new_invite_id;

  insert into internal.pairing_invite_secrets (invite_id, code_hash)
  values (new_invite_id, invite_code_hash);

  update public.pairing_invites invite
  set
    status = 'revoked',
    revoked_at = coalesce(invite.revoked_at, now()),
    updated_at = now()
  where invite.id = current_invite_row.id
    and invite.status = 'pending';

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('invite_id', new_invite_id)
  );

  return new_invite_id;
end;
$$;


ALTER FUNCTION "internal"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."run_scheduled_push_notification_jobs"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  queued_streak_reminders integer;
  due_work boolean;
  drain_requested boolean := false;
begin
  queued_streak_reminders = internal.enqueue_due_streak_reminders(p_now);
  due_work = internal.has_due_push_notification_work(p_now);

  if due_work then
    drain_requested = internal.request_push_notification_drain(
      'cron.push_notification_drain'
    );
  end if;

  return jsonb_build_object(
    'queued_streak_reminders', queued_streak_reminders,
    'due_work', due_work,
    'drain_requested', drain_requested
  );
end;
$$;


ALTER FUNCTION "internal"."run_scheduled_push_notification_jobs"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("thread_id" "uuid", "message_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_message_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  request_hash = extensions.digest(
    concat_ws(
      '|',
      'send_thread_message',
      p_thread_id::text,
      coalesce(nullif(btrim(coalesce(p_body, '')), ''), ''),
      coalesce(p_media_asset_ids::text, '{}')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'send_thread_message',
    'conversation_threads',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'thread_id')::uuid,
      (replayed_response ->> 'message_id')::uuid;
    return;
  end if;

  resolved_message_id = internal.insert_thread_message(
    p_thread_id,
    p_body,
    p_media_asset_ids
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'thread_id', p_thread_id,
      'message_id', resolved_message_id
    )
  );

  return query
  select p_thread_id, resolved_message_id;
end;
$$;


ALTER FUNCTION "internal"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "date"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid := auth.uid();
  resolved_couple_id uuid;
  replayed_response jsonb;
  request_hash bytea;
  member_row record;
  operation_scope text;
  current_started_on date;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_started_on is null
    or p_started_on > internal.user_local_date(current_user_id, now()) then
    raise exception 'relationship start date must be today or earlier'
      using errcode = '23514';
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();
  operation_scope = 'couple:' || resolved_couple_id::text || ':started_on';
  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'set_couple_started_on',
      resolved_couple_id::text,
      p_started_on::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'set_couple_started_on',
    operation_scope,
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'started_on')::date;
  end if;

  -- A delayed retry from this client must not overwrite a newer edit that the
  -- same client already completed. Cross-device/partner edits intentionally keep
  -- ordinary server-arrival ordering because device clocks are not authoritative.
  if exists (
    select 1
    from internal.client_operations later_operation
    where later_operation.user_id = current_user_id
      and later_operation.client_id = p_client_id
      and later_operation.client_sequence > p_client_sequence
      and later_operation.operation_kind = 'set_couple_started_on'
      and later_operation.idempotency_scope = operation_scope
      and later_operation.status = 'succeeded'
  ) then
    select couple.started_on
    into current_started_on
    from public.couples couple
    where couple.id = resolved_couple_id;

    perform internal.complete_client_operation(
      p_client_operation_id,
      jsonb_build_object(
        'couple_id', resolved_couple_id,
        'started_on', current_started_on,
        'superseded', true
      )
    );

    return current_started_on;
  end if;

  update public.couples
  set started_on = p_started_on
  where id = resolved_couple_id
    and status = 'active';

  if not found then
    raise exception 'active relationship not found'
      using errcode = 'P0002';
  end if;

  for member_row in
    select member.user_id, member.status
    from public.couple_members member
    where member.couple_id = resolved_couple_id
      and member.status = 'active'
  loop
    perform internal.create_relationship_sync_event(
      member_row.user_id,
      resolved_couple_id,
      current_user_id,
      'relationship_updated',
      'relationship_start_date_changed',
      'active',
      member_row.status,
      null,
      null,
      '{"relationship":"refresh"}'::jsonb
    );
  end loop;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'couple_id', resolved_couple_id,
      'started_on', p_started_on
    )
  );

  return p_started_on;
end;
$$;


ALTER FUNCTION "internal"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "internal"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  resolved_couple_day_id uuid;
  active_instance_row public.daily_question_instances%rowtype;
  skipped_question_id uuid;
  picked_question_version_id uuid;
  replacement_instance_id uuid;
  shuffle_count integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_slot_number not between 1 and 3 then
    raise exception 'slot number is out of range'
      using errcode = '23514';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'shuffle_daily_question',
      resolved_couple_id::text,
      current_user_id::text,
      p_slot_number::text,
      p_local_created_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'shuffle_daily_question',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'replacement_instance_id')::uuid;
  end if;

  resolved_couple_day_id = internal.get_or_create_couple_day_at(
    resolved_couple_id,
    p_local_created_at
  );
  perform internal.ensure_daily_challenge_slots(resolved_couple_day_id);

  perform 1
  from public.daily_challenges challenge
  where challenge.couple_day_id = resolved_couple_day_id
    and challenge.user_id = current_user_id
  for update;

  select count(*)
  into shuffle_count
  from public.daily_question_shuffles shuffle
  where shuffle.couple_day_id = resolved_couple_day_id
    and shuffle.user_id = current_user_id;

  if shuffle_count >= 30 then
    raise exception 'daily shuffle limit reached'
      using errcode = '23514';
  end if;

  select *
  into active_instance_row
  from public.daily_question_instances instance
  where instance.couple_day_id = resolved_couple_day_id
    and instance.seeded_for_user_id = current_user_id
    and instance.slot_number = p_slot_number
    and instance.status = 'active'
  for update;

  if not found then
    raise exception 'active daily question slot was not found'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.daily_question_answers answer
    where answer.instance_id = active_instance_row.id
      and answer.user_id = current_user_id
      and answer.deleted_at is null
  ) then
    raise exception 'answered daily questions cannot be shuffled'
      using errcode = '23514';
  end if;

  select version.question_id
  into skipped_question_id
  from public.question_versions version
  where version.id = active_instance_row.question_version_id;

  picked_question_version_id = internal.pick_daily_question_version(
    resolved_couple_day_id,
    current_user_id,
    skipped_question_id
  );

  update public.daily_question_instances
  set
    status = 'shuffled',
    replaced_at = now()
  where id = active_instance_row.id;

  insert into public.daily_question_instances (
    couple_day_id,
    question_version_id,
    seeded_for_user_id,
    slot_number
  ) values (
    resolved_couple_day_id,
    picked_question_version_id,
    current_user_id,
    p_slot_number
  )
  returning id into replacement_instance_id;

  update public.daily_question_instances
  set replaced_by_instance_id = replacement_instance_id
  where id = active_instance_row.id;

  insert into public.daily_question_shuffles (
    couple_id,
    couple_day_id,
    user_id,
    question_id,
    skipped_instance_id,
    replacement_instance_id,
    slot_number,
    exclude_until
  ) values (
    resolved_couple_id,
    resolved_couple_day_id,
    current_user_id,
    skipped_question_id,
    active_instance_row.id,
    replacement_instance_id,
    p_slot_number,
    now() + interval '14 days'
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('replacement_instance_id', replacement_instance_id)
  );

  return replacement_instance_id;
end;
$$;


ALTER FUNCTION "internal"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  resolved_couple_id uuid;
  resolved_couple_day_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  resolved_couple_id = internal.get_current_entitled_couple_id();

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'start_daily_challenge',
      resolved_couple_id::text,
      p_local_created_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'start_daily_challenge',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'couple_day_id')::uuid;
  end if;

  resolved_couple_day_id = internal.get_or_create_couple_day_at(
    resolved_couple_id,
    p_local_created_at
  );

  perform internal.ensure_daily_challenge_slots(resolved_couple_day_id);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('couple_day_id', resolved_couple_day_id)
  );

  return resolved_couple_day_id;
end;
$$;


ALTER FUNCTION "internal"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_leave_relationship" boolean, "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_leave_relationship" boolean, "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  resolved_answer_id uuid;
  text_body text;
  selected_partner_user_id uuid;
  allowed_kinds text[];
  provided_kinds text[] := array[]::text[];
  provided_kind text;
  media_row record;
  asset_row public.media_assets%rowtype;
  media_kind text;
  completed_own_slots integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'answer payload must be an object'
      using errcode = '23514';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'submit_daily_answer',
      p_instance_id::text,
      p_payload::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'submit_daily_answer',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'answer_id')::uuid;
  end if;

  select *
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  if instance_row.status = 'shuffled' then
    raise exception 'shuffled daily questions cannot be answered'
      using errcode = '23514';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if p_local_created_at < couple_day_row.starts_at
    or (
      current_user_id = instance_row.seeded_for_user_id
      and p_local_created_at >= couple_day_row.ends_at
    ) then
    raise exception 'daily answer timestamp is outside the question day'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    where member.couple_id = couple_day_row.couple_id
      and member.user_id = current_user_id
      and member.status = 'active'
  ) then
    raise exception 'answer user must be an active couple member'
      using errcode = '42501';
  end if;

  if current_user_id <> instance_row.seeded_for_user_id
    and not exists (
      select 1
      from public.daily_question_answers seeded_answer
      where seeded_answer.instance_id = instance_row.id
        and seeded_answer.user_id = instance_row.seeded_for_user_id
        and seeded_answer.deleted_at is null
        and seeded_answer.moderation_status = 'visible'
    ) then
    raise exception 'partner-seeded questions can be answered after your partner answers'
      using errcode = '42501';
  end if;

  select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
  into allowed_kinds
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = instance_row.question_version_id;

  text_body = nullif(btrim(coalesce(p_payload ->> 'text', '')), '');

  if text_body is not null then
    if char_length(text_body) > 2000 then
      raise exception 'answer text is too long'
        using errcode = '23514';
    end if;

    provided_kinds = array_append(provided_kinds, 'text');
  end if;

  if nullif(p_payload ->> 'partner_choice_user_id', '') is not null then
    selected_partner_user_id = (p_payload ->> 'partner_choice_user_id')::uuid;
    provided_kinds = array_append(provided_kinds, 'partner_choice');
  end if;

  if p_payload ? 'media_asset_ids'
    and jsonb_typeof(p_payload -> 'media_asset_ids') <> 'array' then
    raise exception 'media_asset_ids must be an array'
      using errcode = '23514';
  end if;

  for media_row in
    select
      media_item.value::uuid as media_asset_id,
      media_item.ordinality::smallint as sort_order
    from jsonb_array_elements_text(coalesce(p_payload -> 'media_asset_ids', '[]'::jsonb))
      with ordinality as media_item(value, ordinality)
  loop
    select *
    into asset_row
    from public.media_assets
    where id = media_row.media_asset_id;

    media_kind = case asset_row.media_type
      when 'image' then 'photo'
      when 'voice' then 'voice'
      else null
    end;

    if asset_row.id is null
      or media_kind is null
      or asset_row.owner_user_id <> current_user_id
      or asset_row.couple_id <> couple_day_row.couple_id
      or asset_row.reserved_parent_kind <> 'daily_answer_media'
      or asset_row.upload_status <> 'finalized'
      or asset_row.storage_delete_status <> 'none'
      or asset_row.moderation_status <> 'visible'
      or asset_row.deleted_at is not null then
      raise exception 'daily answer media asset is not usable'
        using errcode = '23514';
    end if;

    if not media_kind = any(provided_kinds) then
      provided_kinds = array_append(provided_kinds, media_kind);
    end if;
  end loop;

  if cardinality(provided_kinds) = 0 then
    raise exception 'answer payload must include at least one answer kind'
      using errcode = '23514';
  end if;

  foreach provided_kind in array provided_kinds loop
    if not provided_kind = any(coalesce(allowed_kinds, array[]::text[])) then
      raise exception 'answer kind is not allowed for this question'
        using errcode = '23514';
    end if;
  end loop;

  resolved_answer_id = coalesce(
    nullif(p_payload ->> 'answer_id', '')::uuid,
    extensions.gen_random_uuid()
  );

  insert into public.daily_question_answers (
    id,
    instance_id,
    user_id
  ) values (
    resolved_answer_id,
    instance_row.id,
    current_user_id
  );

  if text_body is not null then
    insert into public.daily_answer_text (answer_id, body)
    values (resolved_answer_id, text_body);
  end if;

  if selected_partner_user_id is not null then
    insert into public.daily_answer_partner_choice (
      answer_id,
      selected_user_id
    ) values (
      resolved_answer_id,
      selected_partner_user_id
    );
  end if;

  for media_row in
    select
      media_item.value::uuid as media_asset_id,
      media_item.ordinality::smallint as sort_order
    from jsonb_array_elements_text(coalesce(p_payload -> 'media_asset_ids', '[]'::jsonb))
      with ordinality as media_item(value, ordinality)
  loop
    insert into public.daily_answer_media (
      answer_id,
      media_asset_id,
      sort_order
    ) values (
      resolved_answer_id,
      media_row.media_asset_id,
      media_row.sort_order
    );
  end loop;

  if current_user_id = instance_row.seeded_for_user_id then
    update public.daily_question_instances
    set status = 'answered'
    where id = instance_row.id
      and status = 'active';

    select count(*)
    into completed_own_slots
    from public.daily_question_instances own_instance
    where own_instance.couple_day_id = instance_row.couple_day_id
      and own_instance.seeded_for_user_id = current_user_id
      and own_instance.status = 'answered';

    if completed_own_slots = 3 then
      update public.daily_challenges
      set completed_at = coalesce(completed_at, now())
      where couple_day_id = instance_row.couple_day_id
        and user_id = current_user_id;
    end if;
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('answer_id', resolved_answer_id)
  );

  return resolved_answer_id;
end;
$$;


ALTER FUNCTION "internal"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("canvas_id" "uuid", "revision_id" "uuid", "active_revision_id" "uuid", "payload_media_asset_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $_$
declare
  current_user_id uuid;
  canvas_row public.widget_canvases%rowtype;
  asset_row public.media_assets%rowtype;
  inserted_revision public.widget_drawing_revisions%rowtype;
  resolved_revision_id uuid;
  normalized_compression text;
  normalized_client_renderer_version text;
  normalized_client_validation_version text;
  resolved_uncompressed_bytes bigint;
  sha256_bytes bytea;
  expected_storage_path text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_canvas_id is null or p_payload_media_asset_id is null then
    raise exception 'widget canvas and payload asset are required'
      using errcode = '23514';
  end if;

  normalized_compression = lower(btrim(coalesce(p_compression, 'none')));
  if normalized_compression not in ('none', 'gzip') then
    raise exception 'widget drawing compression is not supported'
      using errcode = '23514';
  end if;

  if p_payload_bytes is null or p_payload_bytes <= 0 or p_payload_bytes > 2097152 then
    raise exception 'widget drawing payload bytes are out of range'
      using errcode = '23514';
  end if;

  resolved_uncompressed_bytes = coalesce(p_uncompressed_bytes, p_payload_bytes);

  if resolved_uncompressed_bytes <= 0 or resolved_uncompressed_bytes > 2097152 then
    raise exception 'widget drawing uncompressed bytes are out of range'
      using errcode = '23514';
  end if;

  if (
    normalized_compression = 'none'
    and resolved_uncompressed_bytes <> p_payload_bytes
  ) or (
    normalized_compression = 'gzip'
    and resolved_uncompressed_bytes < p_payload_bytes
  ) then
    raise exception 'widget drawing compression metadata is invalid'
      using errcode = '23514';
  end if;

  if p_stroke_count is not null and (p_stroke_count < 0 or p_stroke_count > 5000) then
    raise exception 'widget drawing stroke count is out of range'
      using errcode = '23514';
  end if;

  if p_point_count is not null and (p_point_count < 0 or p_point_count > 200000) then
    raise exception 'widget drawing point count is out of range'
      using errcode = '23514';
  end if;

  if p_bounds is not null
    and (
      jsonb_typeof(p_bounds) <> 'object'
      or octet_length(p_bounds::text) > 2048
    ) then
    raise exception 'widget drawing bounds metadata is invalid'
      using errcode = '23514';
  end if;

  if p_sha256_hex is null or p_sha256_hex !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'widget drawing sha256 must be a 64 character hex string'
      using errcode = '22023';
  end if;

  sha256_bytes = decode(lower(p_sha256_hex), 'hex');
  normalized_client_renderer_version = nullif(btrim(coalesce(p_client_renderer_version, '')), '');
  normalized_client_validation_version = nullif(btrim(coalesce(p_client_validation_version, '')), '');

  if normalized_client_renderer_version is null
    or char_length(normalized_client_renderer_version) > 80
    or normalized_client_validation_version is null
    or char_length(normalized_client_validation_version) > 80 then
    raise exception 'widget drawing client validation metadata is invalid'
      using errcode = '23514';
  end if;

  if p_client_decode_validated_at is null
    or p_client_decode_validated_at > now() + interval '5 minutes' then
    raise exception 'widget drawing client decode validation timestamp is invalid'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'submit_widget_drawing_revision',
      p_canvas_id::text,
      p_payload_media_asset_id::text,
      coalesce(p_parent_revision_id::text, ''),
      p_payload_bytes::text,
      resolved_uncompressed_bytes::text,
      normalized_compression,
      coalesce(p_stroke_count::text, ''),
      coalesce(p_point_count::text, ''),
      coalesce(p_bounds::text, ''),
      encode(sha256_bytes, 'hex'),
      p_client_decode_validated_at::text,
      normalized_client_renderer_version,
      normalized_client_validation_version
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'submit_widget_drawing_revision',
    'widget',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'canvas_id')::uuid,
      (replayed_response ->> 'revision_id')::uuid,
      (replayed_response ->> 'active_revision_id')::uuid,
      (replayed_response ->> 'payload_media_asset_id')::uuid,
      (replayed_response ->> 'created_at')::timestamptz,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into canvas_row
  from public.widget_canvases
  where id = p_canvas_id
  for update;

  if not found
    or canvas_row.deleted_at is not null
    or not internal.can_access_couple_content(canvas_row.couple_id) then
    raise exception 'active entitled widget canvas access is required'
      using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'widget_canvas_revision:' || canvas_row.id::text,
      0
    )
  );

  if canvas_row.active_revision_id is distinct from p_parent_revision_id then
    raise exception 'widget drawing parent revision conflict'
      using errcode = '40001';
  end if;

  select *
  into asset_row
  from public.media_assets
  where id = p_payload_media_asset_id
  for update;

  if not found then
    raise exception 'widget drawing payload asset was not found'
      using errcode = '22023';
  end if;

  resolved_revision_id = asset_row.reserved_parent_id;
  expected_storage_path = canvas_row.couple_id::text || '/'
    || canvas_row.id::text
    || '/revisions/'
    || resolved_revision_id::text
    || '/drawing.pkdrawing';

  if asset_row.owner_user_id <> current_user_id
    or asset_row.couple_id <> canvas_row.couple_id
    or asset_row.reserved_parent_kind <> 'widget_drawing_revision'
    or asset_row.bucket <> 'widget-drawings'
    or asset_row.storage_path <> expected_storage_path
    or asset_row.media_type <> 'drawing_payload'
    or asset_row.upload_purpose <> 'widget_drawing_payload'
    or asset_row.expected_media_type <> 'drawing_payload'
    or asset_row.expected_bucket <> 'widget-drawings'
    or asset_row.upload_status <> 'finalized'
    or asset_row.upload_finalized_at is null
    or asset_row.byte_size <> p_payload_bytes
    or asset_row.byte_size > 2097152
    or asset_row.mime_type not in ('application/octet-stream', 'application/x-pkdrawing')
    or asset_row.sha256 <> sha256_bytes
    or asset_row.storage_delete_status <> 'none'
    or asset_row.moderation_status <> 'visible'
    or asset_row.deleted_at is not null then
    raise exception 'widget drawing payload asset is not usable'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.widget_drawing_revisions existing_revision
    where existing_revision.id = resolved_revision_id
      or existing_revision.payload_media_asset_id = asset_row.id
  ) then
    raise exception 'widget drawing payload asset was already saved'
      using errcode = '23505';
  end if;

  insert into public.widget_drawing_revisions (
    id,
    canvas_id,
    author_user_id,
    parent_revision_id,
    payload_media_asset_id,
    payload_bytes,
    uncompressed_bytes,
    compression,
    stroke_count,
    point_count,
    bounds,
    client_decode_validated_at,
    client_renderer_version,
    client_validation_version
  ) values (
    resolved_revision_id,
    canvas_row.id,
    current_user_id,
    p_parent_revision_id,
    asset_row.id,
    p_payload_bytes,
    resolved_uncompressed_bytes,
    normalized_compression,
    p_stroke_count,
    p_point_count,
    p_bounds,
    p_client_decode_validated_at,
    normalized_client_renderer_version,
    normalized_client_validation_version
  )
  returning * into inserted_revision;

  update public.widget_canvases canvas
  set active_revision_id = inserted_revision.id
  where canvas.id = canvas_row.id
  returning canvas.active_revision_id, canvas.updated_at
  into active_revision_id, updated_at;

  canvas_id = canvas_row.id;
  revision_id = inserted_revision.id;
  payload_media_asset_id = inserted_revision.payload_media_asset_id;
  created_at = inserted_revision.created_at;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'canvas_id', canvas_id,
      'revision_id', revision_id,
      'active_revision_id', active_revision_id,
      'payload_media_asset_id', payload_media_asset_id,
      'created_at', created_at,
      'updated_at', updated_at
    )
  );

  return next;
end;
$_$;


ALTER FUNCTION "internal"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."sync_profile_display_name_from_auth_metadata"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  metadata_display_name text;
begin
  metadata_display_name = internal.auth_metadata_display_name(new.raw_user_meta_data);

  update public.profiles
  set display_name = metadata_display_name
  where user_id = new.id
    and display_name is distinct from metadata_display_name;

  return new;
end;
$$;


ALTER FUNCTION "internal"."sync_profile_display_name_from_auth_metadata"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."tombstone_content_report_target"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "internal"."tombstone_content_report_target"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."touch_updated_at_and_revision"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  new.updated_at = now();
  new.revision = old.revision + 1;
  return new;
end;
$$;


ALTER FUNCTION "internal"."touch_updated_at_and_revision"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."unblock_pair"("p_pair_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update public.relationship_blocks
  set
    revoked_at = now(),
    revoked_by_user_id = current_user_id,
    revoke_reason = 'user_unblocked'
  where pair_id = p_pair_id
    and blocked_by_user_id = current_user_id
    and revoked_at is null;

  get diagnostics changed_rows = row_count;
  return changed_rows > 0;
end;
$$;


ALTER FUNCTION "internal"."unblock_pair"("p_pair_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  answer_row public.daily_question_answers%rowtype;
  allowed_kinds text[];
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  if p_selected_user_id is null then
    raise exception 'partner choice selection is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_daily_answer_partner_choice',
      p_instance_id::text,
      p_selected_user_id::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_daily_answer_partner_choice',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'answer_id')::uuid;
  end if;

  -- Lock the instance so a partner answering concurrently cannot slip past the
  -- "still private" check below.
  select *
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  if instance_row.status = 'shuffled' then
    raise exception 'shuffled daily questions cannot be edited'
      using errcode = '23514';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if p_local_created_at < couple_day_row.starts_at
    or p_local_created_at >= couple_day_row.ends_at then
    raise exception 'daily answer timestamp is outside the question day'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  -- The answer being edited must already exist and belong to the current user.
  select *
  into answer_row
  from public.daily_question_answers
  where instance_id = instance_row.id
    and user_id = current_user_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'there is no answer to edit'
      using errcode = '22023';
  end if;

  -- Once the partner has answered the same instance the answer is revealed, so it
  -- can no longer be changed.
  if exists (
    select 1
    from public.daily_question_answers other_answer
    where other_answer.instance_id = instance_row.id
      and other_answer.user_id <> current_user_id
      and other_answer.deleted_at is null
      and other_answer.moderation_status = 'visible'
  ) then
    raise exception 'answers cannot be edited after your partner has answered'
      using errcode = '23514';
  end if;

  select array_agg(answer_kind.answer_kind)
  into allowed_kinds
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = instance_row.question_version_id;

  if not ('partner_choice' = any(coalesce(allowed_kinds, array[]::text[]))) then
    raise exception 'answer kind is not allowed for this question'
      using errcode = '23514';
  end if;

  insert into public.daily_answer_partner_choice (answer_id, selected_user_id)
  values (answer_row.id, p_selected_user_id)
  on conflict (answer_id) do update
    set selected_user_id = excluded.selected_user_id;

  -- Re-state the answer's effective time so the shown "answered at" follows the edit.
  update public.daily_question_answers
  set created_at = now()
  where id = answer_row.id;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('answer_id', answer_row.id)
  );

  return answer_row.id;
end;
$$;


ALTER FUNCTION "internal"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  answer_row public.daily_question_answers%rowtype;
  allowed_kinds text[];
  text_body text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  text_body = nullif(btrim(coalesce(p_text, '')), '');

  if text_body is null then
    raise exception 'answer text is required'
      using errcode = '23514';
  end if;

  if char_length(text_body) > 2000 then
    raise exception 'answer text is too long'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_daily_answer_text',
      p_instance_id::text,
      text_body
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_daily_answer_text',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'answer_id')::uuid;
  end if;

  -- Lock the instance so a partner answering concurrently cannot slip past the
  -- "still private" check below.
  select *
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  if instance_row.status = 'shuffled' then
    raise exception 'shuffled daily questions cannot be edited'
      using errcode = '23514';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if p_local_created_at < couple_day_row.starts_at
    or p_local_created_at >= couple_day_row.ends_at then
    raise exception 'daily answer timestamp is outside the question day'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  -- The answer being edited must already exist and belong to the current user.
  select *
  into answer_row
  from public.daily_question_answers
  where instance_id = instance_row.id
    and user_id = current_user_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'there is no answer to edit'
      using errcode = '22023';
  end if;

  -- Once the partner has answered the same instance the answer is revealed, so it
  -- can no longer be changed.
  if exists (
    select 1
    from public.daily_question_answers other_answer
    where other_answer.instance_id = instance_row.id
      and other_answer.user_id <> current_user_id
      and other_answer.deleted_at is null
      and other_answer.moderation_status = 'visible'
  ) then
    raise exception 'answers cannot be edited after your partner has answered'
      using errcode = '23514';
  end if;

  select array_agg(answer_kind.answer_kind)
  into allowed_kinds
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = instance_row.question_version_id;

  if not ('text' = any(coalesce(allowed_kinds, array[]::text[]))) then
    raise exception 'answer kind is not allowed for this question'
      using errcode = '23514';
  end if;

  insert into public.daily_answer_text (answer_id, body)
  values (answer_row.id, text_body)
  on conflict (answer_id) do update
    set body = excluded.body;

  -- Re-state the answer's effective time so the shown "answered at" follows the edit.
  update public.daily_question_answers
  set created_at = now()
  where id = answer_row.id;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('answer_id', answer_row.id)
  );

  return answer_row.id;
end;
$$;


ALTER FUNCTION "internal"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_id" "uuid", "user_id" "uuid", "latitude" numeric, "longitude" numeric, "accuracy_m" numeric, "captured_at" timestamp with time zone, "received_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_source text;
  existing_location public.latest_partner_locations%rowtype;
  changed_rows integer;
  location_was_stored boolean = false;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if not internal.can_access_couple_content(p_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  resolved_source = lower(btrim(coalesce(p_source, 'foreground_open')));

  if resolved_source not in ('foreground_open', 'manual_refresh', 'settings_toggle') then
    raise exception 'location source is not supported'
      using errcode = '23514';
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90
    or p_longitude is null or p_longitude < -180 or p_longitude > 180
    or p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 100000)
    or p_captured_at is null
    or p_captured_at > now() + interval '5 minutes' then
    raise exception 'location payload is out of range'
      using errcode = '23514';
  end if;

  perform 1
    from public.location_sharing_preferences preference
    where preference.couple_id = p_couple_id
      and preference.user_id = current_user_id
      and preference.is_enabled
    for update;

  if not found then
    raise exception 'location sharing must be enabled before updating location'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_latest_partner_location',
      p_couple_id::text,
      current_user_id::text,
      p_latitude::text,
      p_longitude::text,
      coalesce(p_accuracy_m::text, ''),
      p_captured_at::text,
      resolved_source
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_latest_partner_location',
    'location',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'couple_id')::uuid,
      (replayed_response ->> 'user_id')::uuid,
      (replayed_response ->> 'latitude')::numeric,
      (replayed_response ->> 'longitude')::numeric,
      (replayed_response ->> 'accuracy_m')::numeric,
      (replayed_response ->> 'captured_at')::timestamptz,
      (replayed_response ->> 'received_at')::timestamptz,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into existing_location
  from public.latest_partner_locations latest
  where latest.couple_id = p_couple_id
    and latest.user_id = current_user_id
  for update;

  if found and existing_location.captured_at > p_captured_at then
    couple_id = existing_location.couple_id;
    user_id = existing_location.user_id;
    latitude = existing_location.latitude;
    longitude = existing_location.longitude;
    accuracy_m = existing_location.accuracy_m;
    captured_at = existing_location.captured_at;
    received_at = existing_location.received_at;
    updated_at = existing_location.updated_at;
  else
    insert into public.latest_partner_locations (
      couple_id,
      user_id,
      latitude,
      longitude,
      accuracy_m,
      captured_at,
      received_at,
      source,
      client_operation_id,
      client_id,
      client_sequence
    ) values (
      p_couple_id,
      current_user_id,
      p_latitude,
      p_longitude,
      p_accuracy_m,
      p_captured_at,
      now(),
      resolved_source,
      p_client_operation_id,
      p_client_id,
      p_client_sequence
    )
    on conflict on constraint latest_partner_locations_primary_key do update
    set
      latitude = excluded.latitude,
      longitude = excluded.longitude,
      accuracy_m = excluded.accuracy_m,
      captured_at = excluded.captured_at,
      received_at = excluded.received_at,
      source = excluded.source,
      client_operation_id = excluded.client_operation_id,
      client_id = excluded.client_id,
      client_sequence = excluded.client_sequence
    where public.latest_partner_locations.captured_at <= excluded.captured_at
    returning
      public.latest_partner_locations.couple_id,
      public.latest_partner_locations.user_id,
      public.latest_partner_locations.latitude,
      public.latest_partner_locations.longitude,
      public.latest_partner_locations.accuracy_m,
      public.latest_partner_locations.captured_at,
      public.latest_partner_locations.received_at,
      public.latest_partner_locations.updated_at
    into
      couple_id,
      user_id,
      latitude,
      longitude,
      accuracy_m,
      captured_at,
      received_at,
      updated_at;

    get diagnostics changed_rows = row_count;

    if changed_rows = 0 then
      select *
      into existing_location
      from public.latest_partner_locations latest
      where latest.couple_id = p_couple_id
        and latest.user_id = current_user_id
      for update;

      if not found then
        raise exception 'stale location update could not be resolved'
          using errcode = '40001';
      end if;

      couple_id = existing_location.couple_id;
      user_id = existing_location.user_id;
      latitude = existing_location.latitude;
      longitude = existing_location.longitude;
      accuracy_m = existing_location.accuracy_m;
      captured_at = existing_location.captured_at;
      received_at = existing_location.received_at;
      updated_at = existing_location.updated_at;
    else
      location_was_stored = true;
    end if;
  end if;

  if location_was_stored and exists (
    select 1
    from public.couple_members partner_member
    join public.location_sharing_preferences partner_preference
      on partner_preference.couple_id = partner_member.couple_id
      and partner_preference.user_id = partner_member.user_id
    where partner_member.couple_id = p_couple_id
      and partner_member.user_id <> current_user_id
      and partner_member.status = 'active'
      and partner_preference.is_enabled
  ) then
    perform internal.enqueue_partner_notification(
      p_couple_id,
      current_user_id,
      'location_updated',
      jsonb_build_object(
        'type', 'location_updated',
        'couple_id', p_couple_id,
        'actor_user_id', current_user_id,
        'captured_at', captured_at,
        'route', 'location'
      ),
      'location_updated:' || p_couple_id::text || ':' || current_user_id::text || ':' || captured_at::text,
      'private',
      'background',
      'location:' || p_couple_id::text,
      now()
    );
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'couple_id', couple_id,
      'user_id', user_id,
      'latitude', latitude,
      'longitude', longitude,
      'accuracy_m', accuracy_m,
      'captured_at', captured_at,
      'received_at', received_at,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;


ALTER FUNCTION "internal"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_id" "uuid", "user_id" "uuid", "is_enabled" boolean, "enabled_at" timestamp with time zone, "disabled_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  resolved_source text;
  normalized_consent_version text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_is_enabled is null then
    raise exception 'location sharing state is required'
      using errcode = '23514';
  end if;

  resolved_source = lower(btrim(coalesce(p_source, 'settings_toggle')));

  if resolved_source not in ('foreground_open', 'manual_refresh', 'settings_toggle') then
    raise exception 'location source is not supported'
      using errcode = '23514';
  end if;

  normalized_consent_version = nullif(btrim(coalesce(p_consent_version, '')), '');

  if p_is_enabled
    and (
      normalized_consent_version is null
      or char_length(normalized_consent_version) > 80
    ) then
    raise exception 'location sharing consent version is required'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(p_couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_location_sharing_preference',
      p_couple_id::text,
      current_user_id::text,
      p_is_enabled::text,
      coalesce(normalized_consent_version, ''),
      resolved_source
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_location_sharing_preference',
    'location',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'couple_id')::uuid,
      (replayed_response ->> 'user_id')::uuid,
      (replayed_response ->> 'is_enabled')::boolean,
      (replayed_response ->> 'enabled_at')::timestamptz,
      (replayed_response ->> 'disabled_at')::timestamptz,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  insert into public.location_sharing_preferences (
    couple_id,
    user_id,
    is_enabled,
    enabled_at,
    disabled_at,
    consent_version,
    source
  ) values (
    p_couple_id,
    current_user_id,
    p_is_enabled,
    case when p_is_enabled then now() else null end,
    case when p_is_enabled then null else now() end,
    case when p_is_enabled then normalized_consent_version else null end,
    resolved_source
  )
  on conflict on constraint location_sharing_preferences_primary_key do update
  set
    is_enabled = excluded.is_enabled,
    enabled_at = case when excluded.is_enabled then now() else location_sharing_preferences.enabled_at end,
    disabled_at = case when excluded.is_enabled then null else now() end,
    consent_version = case when excluded.is_enabled then excluded.consent_version else location_sharing_preferences.consent_version end,
    source = excluded.source
  returning
    public.location_sharing_preferences.couple_id,
    public.location_sharing_preferences.user_id,
    public.location_sharing_preferences.is_enabled,
    public.location_sharing_preferences.enabled_at,
    public.location_sharing_preferences.disabled_at,
    public.location_sharing_preferences.updated_at
  into
    couple_id,
    user_id,
    is_enabled,
    enabled_at,
    disabled_at,
    updated_at;

  if not p_is_enabled then
    delete from public.latest_partner_locations latest
    where latest.couple_id = p_couple_id
      and latest.user_id = current_user_id;
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'couple_id', couple_id,
      'user_id', user_id,
      'is_enabled', is_enabled,
      'enabled_at', enabled_at,
      'disabled_at', disabled_at,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;


ALTER FUNCTION "internal"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("memory_id" "uuid", "revision" integer, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  normalized_title text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'expected memory revision is required'
      using errcode = '23514';
  end if;

  normalized_title = internal.normalize_memory_title(p_title);

  if p_memory_date is null then
    raise exception 'memory date is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_memory',
      p_memory_id::text,
      p_expected_revision::text,
      normalized_title,
      p_memory_date::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_memory',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'memory_id')::uuid,
      (replayed_response ->> 'revision')::integer,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  if memory_row.revision <> p_expected_revision then
    raise exception 'memory revision conflict'
      using errcode = '40001';
  end if;

  update public.memories
  set
    title = normalized_title,
    memory_date = p_memory_date,
    last_edited_by_user_id = current_user_id
  where id = memory_row.id
  returning public.memories.id, public.memories.revision, public.memories.updated_at
  into memory_id, revision, updated_at;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'memory_id', memory_id,
      'revision', revision,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;


ALTER FUNCTION "internal"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("note_id" "uuid", "revision" integer, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  memory_row public.memories%rowtype;
  note_row public.memory_notes%rowtype;
  normalized_body text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_body = internal.normalize_memory_note_body(p_body);

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'upsert_memory_note',
      p_memory_id::text,
      coalesce(p_expected_revision::text, ''),
      normalized_body
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'upsert_memory_note',
    'memories',
    request_hash
  );

  if replayed_response is not null then
    return query
    select
      (replayed_response ->> 'note_id')::uuid,
      (replayed_response ->> 'revision')::integer,
      (replayed_response ->> 'updated_at')::timestamptz;
    return;
  end if;

  select *
  into memory_row
  from public.memories
  where id = p_memory_id
  for update;

  if not found
    or memory_row.deleted_at is not null
    or memory_row.moderation_status <> 'visible'
    or not internal.can_access_couple_content(memory_row.couple_id) then
    raise exception 'active entitled memory access is required'
      using errcode = '42501';
  end if;

  select *
  into note_row
  from public.memory_notes
  where memory_id = p_memory_id
    and user_id = current_user_id
  for update;

  if found then
    if note_row.deleted_at is not null or note_row.moderation_status <> 'visible' then
      raise exception 'memory note is not editable'
        using errcode = '42501';
    end if;

    if p_expected_revision is null or note_row.revision <> p_expected_revision then
      raise exception 'memory note revision conflict'
        using errcode = '40001';
    end if;

    update public.memory_notes
    set body = normalized_body
    where id = note_row.id
    returning public.memory_notes.id, public.memory_notes.revision, public.memory_notes.updated_at
    into note_id, revision, updated_at;
  else
    if p_expected_revision is not null and p_expected_revision <> 0 then
      raise exception 'memory note revision conflict'
        using errcode = '40001';
    end if;

    insert into public.memory_notes (
      memory_id,
      user_id,
      body
    ) values (
      p_memory_id,
      current_user_id,
      normalized_body
    )
    returning public.memory_notes.id, public.memory_notes.revision, public.memory_notes.updated_at
    into note_id, revision, updated_at;
  end if;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'note_id', note_id,
      'revision', revision,
      'updated_at', updated_at
    )
  );

  return next;
end;
$$;


ALTER FUNCTION "internal"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."user_has_direct_entitlement"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select coalesce((
    select resolved.is_entitled
    from internal.resolve_user_entitlement(p_user_id) resolved
  ), false);
$$;


ALTER FUNCTION "internal"."user_has_direct_entitlement"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."user_local_date"("p_user_id" "uuid", "p_observed_at" timestamp with time zone) RETURNS "date"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select (
    p_observed_at at time zone coalesce(
      (
        select timezone_name.name
        from public.profiles profile
        join pg_catalog.pg_timezone_names timezone_name
          on timezone_name.name = profile.time_zone_id
        where profile.user_id = p_user_id
      ),
      'UTC'
    )
  )::date;
$$;


ALTER FUNCTION "internal"."user_local_date"("p_user_id" "uuid", "p_observed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") RETURNS TABLE("invite_id" "uuid", "status" "text", "expires_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid := auth.uid();
  invite_row public.pairing_invites%rowtype;
  invite_code_hash bytea;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_invite_id is null or p_invite_code is null or btrim(p_invite_code) = '' then
    return query
    select
      null::uuid,
      'not_found'::text,
      null::timestamptz;
    return;
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);

  select invite.*
  into invite_row
  from public.pairing_invites invite
  join internal.pairing_invite_secrets secret
    on secret.invite_id = invite.id
  where invite.id = p_invite_id
    and invite.created_by_user_id = current_user_id
    and secret.code_hash = invite_code_hash
  for update of invite;

  if not found then
    return query
    select
      null::uuid,
      'not_found'::text,
      null::timestamptz;
    return;
  end if;

  if invite_row.status = 'pending' and invite_row.expires_at <= now() then
    update public.pairing_invites invite
    set
      status = 'expired',
      updated_at = now()
    where invite.id = invite_row.id
    returning invite.* into invite_row;
  end if;

  return query
  select
    invite_row.id,
    invite_row.status,
    invite_row.expires_at;
end;
$$;


ALTER FUNCTION "internal"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."widget_updated_notification_body"("p_locale" "text") RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  return internal.notification_alert_body('widget_updated', '{}'::jsonb, p_locale);
end;
$$;


ALTER FUNCTION "internal"."widget_updated_notification_body"("p_locale" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date" DEFAULT NULL::"date") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid := auth.uid();
  review_code internal.review_access_codes%rowtype;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  review_code := internal.find_active_review_access_code(p_invite_code);

  if review_code.id is not null then
    return internal.redeem_review_access(review_code.id, current_user_id);
  end if;

  return internal.accept_pairing_invite(
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_started_on
  );
end;
$$;


ALTER FUNCTION "public"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"[]
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.attach_memory_media(
    p_memory_id,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."block_relationship"("p_blocked_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.block_relationship(p_blocked_user_id, null);
$$;


ALTER FUNCTION "public"."block_relationship"("p_blocked_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_account_deletion_jobs"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 10, "p_retry_after" interval DEFAULT '00:05:00'::interval, "p_max_attempts" integer DEFAULT 10, "p_job_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("job_id" "uuid", "request_id" "uuid", "user_id" "uuid", "auth_provider" "text", "provider_revocation_status" "text", "auth_delete_attempts" integer)
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.claim_account_deletion_jobs(
    p_now,
    p_limit,
    p_retry_after,
    p_max_attempts,
    p_job_id
  );
$$;


ALTER FUNCTION "public"."claim_account_deletion_jobs"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer, "p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_media_storage_deletes"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100, "p_retry_after" interval DEFAULT '00:15:00'::interval, "p_max_attempts" integer DEFAULT 5) RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "storage_delete_attempts" integer)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.claim_media_storage_deletes(
    p_now,
    p_limit,
    p_retry_after,
    p_max_attempts
  );
$$;


ALTER FUNCTION "public"."claim_media_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_notification_batch"("p_limit" integer DEFAULT 50) RETURNS TABLE("outbox_id" "uuid", "target_device_id" "uuid", "push_token" "text", "apns_environment" "text", "apns_push_type" "text", "apns_collapse_id" "text", "title" "text", "body" "text", "payload" "jsonb")
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.claim_notification_batch(p_limit);
$$;


ALTER FUNCTION "public"."claim_notification_batch"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100, "p_retry_after" interval DEFAULT '00:15:00'::interval, "p_max_attempts" integer DEFAULT 5) RETURNS TABLE("snapshot_asset_id" "uuid", "report_id" "uuid", "bucket" "text", "storage_path" "text", "storage_delete_attempts" integer)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.claim_report_snapshot_storage_deletes(
    p_now,
    p_limit,
    p_retry_after,
    p_max_attempts
  );
$$;


ALTER FUNCTION "public"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_widget_push_batch"("p_limit" integer DEFAULT 50) RETURNS TABLE("outbox_id" "uuid", "target_widget_device_id" "uuid", "widget_push_token" "text", "apns_environment" "text", "apns_collapse_id" "text", "payload" "jsonb")
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select * from internal.claim_widget_push_batch(p_limit);
$$;


ALTER FUNCTION "public"."claim_widget_push_batch"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_review_access_session"("p_review_session_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.complete_review_access_session(p_review_session_id);
$$;


ALTER FUNCTION "public"."complete_review_access_session"("p_review_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("thread_id" "uuid", "message_id" "uuid")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.create_daily_question_thread_with_message(
    p_instance_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.create_memory(
    p_memory_id,
    p_title,
    p_memory_date,
    p_note_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("thread_id" "uuid", "message_id" "uuid")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.create_memory_thread_with_message(
    p_memory_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval)) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.create_pairing_invite(
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_expires_at
  );
$$;


ALTER FUNCTION "public"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid" DEFAULT NULL::"uuid", "p_upload_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_path_context" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "upload_expires_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.create_pending_media_upload(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_reserved_parent_kind,
    p_reserved_parent_id,
    p_upload_purpose,
    p_media_type,
    p_file_extension,
    p_couple_id,
    p_upload_expires_at,
    p_path_context
  );
$$;


ALTER FUNCTION "public"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."disable_user_device"("p_device_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.disable_user_device(p_device_id);
$$;


ALTER FUNCTION "public"."disable_user_device"("p_device_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.ensure_review_partner(p_user_id, p_display_name);
$$;


ALTER FUNCTION "public"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer DEFAULT NULL::integer, "p_height" integer DEFAULT NULL::integer, "p_duration_ms" integer DEFAULT NULL::integer) RETURNS TABLE("media_asset_id" "uuid", "upload_status" "text", "upload_finalized_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.finalize_media_upload(
    p_media_asset_id,
    p_reserved_by_client_operation_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_bucket,
    p_storage_path,
    p_reserved_parent_kind,
    p_reserved_parent_id,
    p_upload_purpose,
    p_media_type,
    p_mime_type,
    p_byte_size,
    p_sha256_hex,
    p_width,
    p_height,
    p_duration_ms
  );
$$;


ALTER FUNCTION "public"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_access_snapshot"() RETURNS TABLE("user_entitlement" "jsonb", "couple_entitlement" "jsonb", "relationship_state" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_access_snapshot();
$$;


ALTER FUNCTION "public"."get_access_snapshot"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_active_question_catalog"("p_locale" "text" DEFAULT NULL::"text") RETURNS TABLE("collection_id" "uuid", "question_id" "uuid", "question_key" "text", "question_version_id" "uuid", "version_number" integer, "locale" "text", "prompt" "text", "short_prompt" "text", "answer_kinds" "text"[], "resurfaceable" boolean, "resurface_after_months" smallint)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_active_question_catalog(p_locale);
$$;


ALTER FUNCTION "public"."get_active_question_catalog"("p_locale" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_conversation_threads"() RETURNS TABLE("thread_id" "uuid", "couple_id" "uuid", "kind" "text", "daily_question_instance_id" "uuid", "memory_id" "uuid", "created_by_user_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "deleted_at" timestamp with time zone, "moderation_status" "text", "last_message_id" "uuid", "last_message_at" timestamp with time zone, "last_message_sender_user_id" "uuid", "last_message_deleted_at" timestamp with time zone, "last_message_moderation_status" "text", "last_message_body" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_conversation_threads();
$$;


ALTER FUNCTION "public"."get_conversation_threads"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_couple_streak"() RETURNS TABLE("current_count" integer, "longest_count" integer, "last_qualified_date" "date", "restore_available" boolean, "restorable_count" integer, "restore_deadline" timestamp with time zone, "current_user_contributed_today" boolean, "partner_contributed_today" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  with current_context as materialized (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  )
  select
    streak.current_count,
    streak.longest_count,
    streak.last_qualified_date,
    streak.restore_available,
    streak.restorable_count,
    streak.restore_deadline,
    participation.current_user_contributed_today,
    participation.partner_contributed_today
  from current_context context
  cross join lateral internal.get_couple_streak_for_couple(context.couple_id) streak
  cross join lateral internal.get_couple_streak_participation_for_user(
    context.couple_id,
    context.current_user_id,
    now()
  ) participation;
$$;


ALTER FUNCTION "public"."get_couple_streak"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_relationship_state"() RETURNS TABLE("couple_id" "uuid", "pair_id" "uuid", "relationship_status" "text", "member_status" "text", "partner_user_id" "uuid", "partner_display_name" "text", "partner_profile_photo_asset_id" "uuid", "started_on" "date", "ended_at" timestamp with time zone, "delete_after" timestamp with time zone, "ended_notice_seen_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_current_relationship_state();
$$;


ALTER FUNCTION "public"."get_current_relationship_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_answer_details"("p_couple_day_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_daily_answer_details(p_couple_day_id);
$$;


ALTER FUNCTION "public"."get_daily_answer_details"("p_couple_day_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_daily_answer_details_for_couple_days(p_couple_day_ids);
$$;


ALTER FUNCTION "public"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_answer_history_details"() RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_daily_answer_history_details();
$$;


ALTER FUNCTION "public"."get_daily_answer_history_details"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") RETURNS TABLE("couple_day_id" "uuid", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "is_own_answer" boolean, "can_view_answer" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_daily_answer_reveal_state(p_couple_day_id);
$$;


ALTER FUNCTION "public"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_questions_history"() RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "effective_local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_daily_questions_history();
$$;


ALTER FUNCTION "public"."get_daily_questions_history"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer DEFAULT 900) RETURNS TABLE("media_asset_id" "uuid", "bucket" "text", "storage_path" "text", "expires_in_seconds" integer, "signed_url_expires_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_media_signed_url(p_media_asset_id, p_expires_in_seconds);
$$;


ALTER FUNCTION "public"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) IS 'Authorizes the caller for a media asset and returns its private Storage bucket/path. Supabase Storage downloads and signed URL creation are gated by the matching storage.objects SELECT policy.';



CREATE OR REPLACE FUNCTION "public"."get_memories"("p_updated_after" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_cursor_memory_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 100) RETURNS TABLE("memory_id" "uuid", "couple_id" "uuid", "title" "text", "memory_date" "date", "created_by_user_id" "uuid", "last_edited_by_user_id" "uuid", "revision" integer, "moderation_status" "text", "deleted_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "sync_updated_at" timestamp with time zone, "own_note_id" "uuid", "own_note_body" "text", "own_note_revision" integer, "own_note_updated_at" timestamp with time zone, "own_note_deleted_at" timestamp with time zone, "own_note_moderation_status" "text", "partner_note_id" "uuid", "partner_note_user_id" "uuid", "partner_note_body" "text", "partner_note_revision" integer, "partner_note_updated_at" timestamp with time zone, "partner_note_deleted_at" timestamp with time zone, "partner_note_moderation_status" "text", "memory_media_ids" "uuid"[], "media_asset_ids" "uuid"[], "memory_media_states" "jsonb", "thread_id" "uuid")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_memories(p_updated_after, p_cursor_memory_id, p_limit);
$$;


ALTER FUNCTION "public"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_couple_entitlement"() RETURNS TABLE("couple_id" "uuid", "is_entitled" boolean, "covering_user_id" "uuid", "source" "text", "status" "text", "product_id" "uuid", "current_period_end" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.resolve_current_couple_entitlement();
$$;


ALTER FUNCTION "public"."get_my_couple_entitlement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_entitlement"() RETURNS TABLE("user_id" "uuid", "is_entitled" boolean, "source" "text", "status" "text", "product_id" "uuid", "current_period_end" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.resolve_user_entitlement((select auth.uid()));
$$;


ALTER FUNCTION "public"."get_my_entitlement"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_app_account_token"("p_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.get_or_create_app_account_token(p_user_id);
$$;


ALTER FUNCTION "public"."get_or_create_app_account_token"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_widget_canvas"("p_couple_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("canvas_id" "uuid", "couple_id" "uuid", "active_revision_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_or_create_widget_canvas(p_couple_id);
$$;


ALTER FUNCTION "public"."get_or_create_widget_canvas"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_partner_location_visibility"("p_couple_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("couple_id" "uuid", "viewer_user_id" "uuid", "partner_user_id" "uuid", "visibility_state" "text", "viewer_sharing_enabled" boolean, "partner_sharing_enabled" boolean, "partner_location_latitude" numeric, "partner_location_longitude" numeric, "partner_location_accuracy_m" numeric, "partner_location_captured_at" timestamp with time zone, "partner_location_is_stale" boolean, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_partner_location_visibility(p_couple_id);
$$;


ALTER FUNCTION "public"."get_partner_location_visibility"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_question_answer_history"("p_question_id" "uuid") RETURNS TABLE("question_id" "uuid", "question_version_id" "uuid", "couple_day_id" "uuid", "local_date" "date", "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "answer_user_id" "uuid", "answer_id" "uuid", "answered_at" timestamp with time zone, "can_view_answer" boolean, "text_body" "text", "selected_user_id" "uuid", "media_asset_ids" "uuid"[])
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_question_answer_history(p_question_id);
$$;


ALTER FUNCTION "public"."get_question_answer_history"("p_question_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_thread_messages"("p_thread_id" "uuid") RETURNS TABLE("thread_id" "uuid", "message_id" "uuid", "sender_user_id" "uuid", "body" "text", "created_at" timestamp with time zone, "edited_at" timestamp with time zone, "deleted_at" timestamp with time zone, "moderation_status" "text", "media_asset_ids" "uuid"[], "media_states" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_thread_messages(p_thread_id);
$$;


ALTER FUNCTION "public"."get_thread_messages"("p_thread_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_today_daily_challenge_snapshot"() RETURNS TABLE("questions" "jsonb", "answer_details" "jsonb", "streak" "jsonb", "generated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_today_daily_challenge_snapshot();
$$;


ALTER FUNCTION "public"."get_today_daily_challenge_snapshot"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_today_daily_questions"() RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean, "is_current_day" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_today_daily_questions();
$$;


ALTER FUNCTION "public"."get_today_daily_questions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_widget_canvas"("p_couple_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("canvas_id" "uuid", "couple_id" "uuid", "active_revision_id" "uuid", "active_revision_moderation_status" "text", "active_revision_deleted_at" timestamp with time zone, "active_revision_author_user_id" "uuid", "payload_media_asset_id" "uuid", "payload_bucket" "text", "payload_storage_path" "text", "payload_sha256_hex" "text", "payload_bytes" bigint, "uncompressed_bytes" bigint, "compression" "text", "stroke_count" integer, "point_count" integer, "bounds" "jsonb", "format" "text", "format_version" integer, "renderer_version" integer, "client_decode_validated_at" timestamp with time zone, "client_renderer_version" "text", "client_validation_version" "text", "revision_created_at" timestamp with time zone, "canvas_created_at" timestamp with time zone, "canvas_updated_at" timestamp with time zone, "sync_updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_widget_canvas(p_couple_id);
$$;


ALTER FUNCTION "public"."get_widget_canvas"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_limit" integer DEFAULT 100, "p_updated_after_revision_id" "uuid" DEFAULT NULL::"uuid", "p_created_before" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_created_before_revision_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("canvas_id" "uuid", "revision_id" "uuid", "author_user_id" "uuid", "parent_revision_id" "uuid", "moderation_status" "text", "deleted_at" timestamp with time zone, "payload_media_asset_id" "uuid", "payload_bucket" "text", "payload_storage_path" "text", "payload_sha256_hex" "text", "payload_bytes" bigint, "uncompressed_bytes" bigint, "compression" "text", "stroke_count" integer, "point_count" integer, "bounds" "jsonb", "format" "text", "format_version" integer, "renderer_version" integer, "client_decode_validated_at" timestamp with time zone, "client_renderer_version" "text", "client_validation_version" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "sync_updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.get_widget_drawing_revisions(
    p_canvas_id,
    p_updated_after,
    p_limit,
    p_updated_after_revision_id,
    p_created_before,
    p_created_before_revision_id
  );
$$;


ALTER FUNCTION "public"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("memory_id" "uuid", "revision" integer, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.hide_memory(
    p_memory_id,
    p_expected_revision,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text" DEFAULT 'pre_paired_paywalled'::"text", "p_expires_at" timestamp with time zone DEFAULT ("now"() + '30 days'::interval), "p_max_redemptions" integer DEFAULT 1) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.issue_review_access_code(
    p_code,
    p_seeded_partner_user_id,
    p_scenario,
    p_expires_at,
    p_max_redemptions
  );
$$;


ALTER FUNCTION "public"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text", "p_expires_at" timestamp with time zone, "p_max_redemptions" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.leave_relationship(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_review_demo_partners"() RETURNS TABLE("slot" smallint, "user_id" "uuid", "display_name" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select * from internal.list_review_demo_partners();
$$;


ALTER FUNCTION "public"."list_review_demo_partners"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer DEFAULT 10) RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_account_deletion_auth_failed(
    p_job_id,
    p_error_code,
    p_max_attempts
  );
$$;


ALTER FUNCTION "public"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_account_deletion_completed"("p_job_id" "uuid") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_account_deletion_completed(p_job_id);
$$;


ALTER FUNCTION "public"."mark_account_deletion_completed"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_account_deletion_provider_result(
    p_job_id,
    p_status,
    p_error_code
  );
$$;


ALTER FUNCTION "public"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_media_for_deletion"("p_media_asset_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_media_for_deletion(p_media_asset_id);
$$;


ALTER FUNCTION "public"."mark_media_for_deletion"("p_media_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_media_storage_delete_failed(
    p_media_asset_id,
    p_error,
    p_terminal
  );
$$;


ALTER FUNCTION "public"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_media_storage_deleted"("p_media_asset_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_media_storage_deleted(p_media_asset_id);
$$;


ALTER FUNCTION "public"."mark_media_storage_deleted"("p_media_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text" DEFAULT NULL::"text", "p_error" "text" DEFAULT NULL::"text", "p_invalid_token" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_notification_result(
    p_outbox_id,
    p_success,
    p_provider_message_id,
    p_error,
    p_invalid_token
  );
$$;


ALTER FUNCTION "public"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_relationship_ended_notice_seen(p_couple_id);
$$;


ALTER FUNCTION "public"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_report_snapshot_storage_delete_failed(
    p_snapshot_asset_id,
    p_error,
    p_terminal
  );
$$;


ALTER FUNCTION "public"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_report_snapshot_storage_deleted(p_snapshot_asset_id);
$$;


ALTER FUNCTION "public"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_streak_restore_refunded(p_environment, p_transaction_id);
$$;


ALTER FUNCTION "public"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text" DEFAULT NULL::"text", "p_error" "text" DEFAULT NULL::"text", "p_invalid_token" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.mark_widget_push_result(
    p_outbox_id,
    p_success,
    p_provider_message_id,
    p_error,
    p_invalid_token
  );
$$;


ALTER FUNCTION "public"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."preview_pairing_invite"("p_invite_code" "text") RETURNS TABLE("invite_id" "uuid", "inviter_user_id" "uuid", "inviter_display_name" "text", "expires_at" timestamp with time zone, "has_safety_warning" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  review_code internal.review_access_codes%rowtype;
  partner_profile public.profiles%rowtype;
begin
  review_code := internal.find_active_review_access_code(p_invite_code);

  if review_code.id is not null then
    select *
    into partner_profile
    from public.profiles
    where user_id = review_code.seeded_partner_user_id;

    return query
    select
      review_code.id,
      review_code.seeded_partner_user_id,
      case
        when partner_profile.moderation_status = 'visible' then partner_profile.display_name
        else null
      end,
      coalesce(review_code.expires_at, now() + interval '1 day'),
      false;
    return;
  end if;

  return query
  select * from internal.preview_pairing_invite(p_invite_code);
end;
$$;


ALTER FUNCTION "public"."preview_pairing_invite"("p_invite_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.record_storekit_server_notification(
    p_notification_uuid,
    p_notification_type,
    p_subtype,
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_app_account_token,
    p_apple_product_id,
    p_web_order_line_item_id,
    p_status,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_revocation_reason,
    p_signed_notification_payload,
    p_signed_transaction_info,
    p_payload_json
  );
$$;


ALTER FUNCTION "public"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.record_verified_storekit_transaction(
    p_user_id,
    p_app_account_token,
    p_apple_product_id,
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_web_order_line_item_id,
    p_status,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_revocation_reason,
    p_signed_payload,
    p_payload_json
  );
$$;


ALTER FUNCTION "public"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.record_verified_streak_restore(
    p_user_id,
    p_app_account_token,
    p_apple_product_id,
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_purchased_at,
    p_signed_payload,
    p_payload_json
  );
$$;


ALTER FUNCTION "public"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.register_review_demo_partner(p_slot, p_user_id, p_display_name);
$$;


ALTER FUNCTION "public"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text" DEFAULT NULL::"text", "p_time_zone_id" "text" DEFAULT NULL::"text", "p_app_version" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.register_user_device(
    p_platform,
    p_push_token,
    p_apns_environment,
    p_locale,
    p_time_zone_id,
    p_app_version
  );
$$;


ALTER FUNCTION "public"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text" DEFAULT NULL::"text", "p_time_zone_id" "text" DEFAULT NULL::"text", "p_app_version" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.register_widget_push_device(
    p_widget_kind,
    p_widget_push_token,
    p_apns_environment,
    p_locale,
    p_time_zone_id,
    p_app_version
  );
$$;


ALTER FUNCTION "public"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.remove_memory_media(
    p_memory_media_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_account_deletion"() RETURNS TABLE("id" "uuid", "status" "text", "requested_at" timestamp with time zone, "deletion_job_id" "uuid", "auth_provider" "text", "provider_revocation_status" "text", "auth_delete_status" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select
    deletion_request.id,
    deletion_request.status,
    deletion_request.requested_at,
    deletion_request.deletion_job_id,
    deletion_request.auth_provider,
    deletion_request.provider_revocation_status,
    deletion_request.auth_delete_status
  from internal.request_account_deletion() as deletion_request;
$$;


ALTER FUNCTION "public"."request_account_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_daily_challenge_for_testing"("p_couple_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_couple_day_id uuid;
  v_reset_count integer := 0;
  v_thread_ids uuid[];
begin
  if p_couple_id is null then
    raise exception 'p_couple_id is required'
      using errcode = '22023';
  end if;

  for v_couple_day_id in
    select id
    from public.couple_days
    where couple_id = p_couple_id
      and now() >= starts_at
      and now() < ends_at
  loop
    -- 1. Tear down any conversation threads attached to this day's instances
    --    (defensive — the answering flow does not create these today).
    select array_agg(thread.thread_id)
    into v_thread_ids
    from public.daily_question_threads thread
    where thread.instance_id in (
      select instance.id
      from public.daily_question_instances instance
      where instance.couple_day_id = v_couple_day_id
    );

    if v_thread_ids is not null then
      delete from public.thread_message_media
      where message_id in (
        select id from public.thread_messages where thread_id = any(v_thread_ids)
      );
      delete from public.thread_messages where thread_id = any(v_thread_ids);
      delete from public.daily_question_threads where thread_id = any(v_thread_ids);
      delete from public.conversation_threads where id = any(v_thread_ids);
    end if;

    -- 2. Remove every answer (and its detail rows) for this day's instances.
    --    Linked media assets are left in place; moderation reports null out via FK.
    delete from public.daily_answer_media
    where answer_id in (
      select answer.id
      from public.daily_question_answers answer
      join public.daily_question_instances instance
        on instance.id = answer.instance_id
      where instance.couple_day_id = v_couple_day_id
    );

    delete from public.daily_answer_text
    where answer_id in (
      select answer.id
      from public.daily_question_answers answer
      join public.daily_question_instances instance
        on instance.id = answer.instance_id
      where instance.couple_day_id = v_couple_day_id
    );

    delete from public.daily_answer_partner_choice
    where answer_id in (
      select answer.id
      from public.daily_question_answers answer
      join public.daily_question_instances instance
        on instance.id = answer.instance_id
      where instance.couple_day_id = v_couple_day_id
    );

    delete from public.daily_question_answers
    where instance_id in (
      select instance.id
      from public.daily_question_instances instance
      where instance.couple_day_id = v_couple_day_id
    );

    -- 3. Reset all skips for the day.
    delete from public.daily_question_shuffles
    where couple_day_id = v_couple_day_id;

    -- 4. Wipe the instances. Clear the self-referential "replaced by" links first so
    --    the rows can all be deleted. Status is left as-is — flipping shuffled rows to
    --    'active' would collide with the active-slot unique index; nulling only the
    --    link still satisfies the shuffled-state check (which needs replaced_at set).
    update public.daily_question_instances
    set replaced_by_instance_id = null
    where couple_day_id = v_couple_day_id
      and replaced_by_instance_id is not null;

    delete from public.daily_question_instances
    where couple_day_id = v_couple_day_id;

    -- 5. Clear completion so the card returns to its active state.
    update public.daily_challenges
    set completed_at = null,
        partner_notified_at = null
    where couple_day_id = v_couple_day_id;

    -- 6. Re-seed three fresh active slots per partner.
    perform internal.ensure_daily_challenge_slots(v_couple_day_id);

    v_reset_count := v_reset_count + 1;
  end loop;

  return v_reset_count;
end;
$$;


ALTER FUNCTION "public"."reset_daily_challenge_for_testing"("p_couple_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_review_demo"() RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.reset_review_demo();
$$;


ALTER FUNCTION "public"."reset_review_demo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."retry_account_deletion_job"("p_job_id" "uuid") RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.retry_account_deletion_job(p_job_id);
$$;


ALTER FUNCTION "public"."retry_account_deletion_job"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_pairing_invite"("p_invite_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.revoke_pairing_invite(p_invite_id);
$$;


ALTER FUNCTION "public"."revoke_pairing_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_review_access_codes"() RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.revoke_review_access_codes();
$$;


ALTER FUNCTION "public"."revoke_review_access_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval)) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.rotate_pairing_invite(
    p_current_invite_id,
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_expires_at
  );
$$;


ALTER FUNCTION "public"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("thread_id" "uuid", "message_id" "uuid")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.send_thread_message(
    p_thread_id,
    p_body,
    p_media_asset_ids,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "date"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.set_couple_started_on(
    p_started_on,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_own_provider_profile_photo"("p_profile_photo_asset_id" "uuid", "p_source" "text") RETURNS TABLE("user_id" "uuid", "display_name" "text", "time_zone_id" "text", "time_zone_updated_at" timestamp with time zone, "onboarding_completed_at" timestamp with time zone, "profile_photo_asset_id" "uuid", "provider_profile_photo_asset_id" "uuid", "provider_profile_photo_source" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
begin
  current_user_id = (select auth.uid());
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_profile_photo_asset_id is null or p_source is distinct from 'google' then
    raise exception 'provider profile photo input is invalid'
      using errcode = '23514';
  end if;

  return query
  update public.profiles profile
  set
    provider_profile_photo_asset_id = p_profile_photo_asset_id,
    provider_profile_photo_source = p_source
  where profile.user_id = current_user_id
    and profile.deleted_at is null
  returning
    profile.user_id,
    profile.display_name,
    profile.time_zone_id,
    profile.time_zone_updated_at,
    profile.onboarding_completed_at,
    profile.profile_photo_asset_id,
    profile.provider_profile_photo_asset_id,
    profile.provider_profile_photo_source;

  if not found then
    raise exception 'active profile was not found'
      using errcode = 'P0002';
  end if;
end;
$$;


ALTER FUNCTION "public"."set_own_provider_profile_photo"("p_profile_photo_asset_id" "uuid", "p_source" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_own_provider_profile_photo"("p_profile_photo_asset_id" "uuid", "p_source" "text") IS 'Links a private, owner-scoped OAuth photo as the authenticated user provider fallback.';



CREATE OR REPLACE FUNCTION "public"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean, "is_current_day" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.shuffle_daily_question(
    p_slot_number,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_questions();
end;
$$;


ALTER FUNCTION "public"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."shuffle_daily_question_snapshot"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("questions" "jsonb", "answer_details" "jsonb", "streak" "jsonb", "generated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.shuffle_daily_question(
    p_slot_number,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_challenge_snapshot();
end;
$$;


ALTER FUNCTION "public"."shuffle_daily_question_snapshot"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_day_id" "uuid", "couple_id" "uuid", "local_date" "date", "starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "instance_id" "uuid", "seeded_for_user_id" "uuid", "slot_number" smallint, "instance_status" "text", "question_id" "uuid", "question_version_id" "uuid", "question_key" "text", "prompt_en" "text", "short_prompt_en" "text", "prompt_nb" "text", "short_prompt_nb" "text", "answer_kinds" "text"[], "own_answer_id" "uuid", "own_answered_at" timestamp with time zone, "partner_answer_id" "uuid", "partner_answered_at" timestamp with time zone, "can_view_partner_answer" boolean, "is_current_day" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.start_daily_challenge(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_questions();
end;
$$;


ALTER FUNCTION "public"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_daily_challenge_snapshot"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("questions" "jsonb", "answer_details" "jsonb", "streak" "jsonb", "generated_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  perform internal.start_daily_challenge(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_challenge_snapshot();
end;
$$;


ALTER FUNCTION "public"."start_daily_challenge_snapshot"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "public"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.submit_daily_answer(
    p_instance_id,
    p_payload,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_leave_and_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
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


ALTER FUNCTION "public"."submit_leave_and_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("canvas_id" "uuid", "revision_id" "uuid", "active_revision_id" "uuid", "payload_media_asset_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.submit_widget_drawing_revision(
    p_canvas_id,
    p_payload_media_asset_id,
    p_parent_revision_id,
    p_payload_bytes,
    p_uncompressed_bytes,
    p_compression,
    p_stroke_count,
    p_point_count,
    p_bounds,
    p_sha256_hex,
    p_client_decode_validated_at,
    p_client_renderer_version,
    p_client_validation_version,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unblock_pair"("p_pair_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.unblock_pair(p_pair_id);
$$;


ALTER FUNCTION "public"."unblock_pair"("p_pair_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.update_daily_answer_partner_choice(
    p_instance_id,
    p_selected_user_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.update_daily_answer_text(
    p_instance_id,
    p_text,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_id" "uuid", "user_id" "uuid", "latitude" numeric, "longitude" numeric, "accuracy_m" numeric, "captured_at" timestamp with time zone, "received_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.update_latest_partner_location(
    p_couple_id,
    p_latitude,
    p_longitude,
    null::numeric,
    p_captured_at,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_id" "uuid", "user_id" "uuid", "latitude" numeric, "longitude" numeric, "accuracy_m" numeric, "captured_at" timestamp with time zone, "received_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.update_latest_partner_location(
    p_couple_id,
    p_latitude,
    p_longitude,
    p_accuracy_m,
    p_captured_at,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_id" "uuid", "user_id" "uuid", "is_enabled" boolean, "enabled_at" timestamp with time zone, "disabled_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.update_location_sharing_preference(
    p_couple_id,
    p_is_enabled,
    null::text,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("couple_id" "uuid", "user_id" "uuid", "is_enabled" boolean, "enabled_at" timestamp with time zone, "disabled_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.update_location_sharing_preference(
    p_couple_id,
    p_is_enabled,
    p_consent_version,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("memory_id" "uuid", "revision" integer, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.update_memory(
    p_memory_id,
    p_expected_revision,
    p_title,
    p_memory_date,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_own_profile"("p_display_name" "text", "p_profile_photo_asset_id" "uuid") RETURNS TABLE("user_id" "uuid", "display_name" "text", "time_zone_id" "text", "time_zone_updated_at" timestamp with time zone, "onboarding_completed_at" timestamp with time zone, "profile_photo_asset_id" "uuid", "provider_profile_photo_asset_id" "uuid", "provider_profile_photo_source" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  current_user_id uuid;
  normalized_display_name text;
begin
  current_user_id = (select auth.uid());
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  normalized_display_name = btrim(coalesce(p_display_name, ''));
  if char_length(normalized_display_name) not between 1 and 80
    or normalized_display_name ~ '[[:space:]]' then
    raise exception 'display name must be one name between 1 and 80 characters'
      using errcode = '23514';
  end if;

  return query
  update public.profiles profile
  set
    display_name = normalized_display_name,
    profile_photo_asset_id = p_profile_photo_asset_id
  where profile.user_id = current_user_id
    and profile.deleted_at is null
  returning
    profile.user_id,
    profile.display_name,
    profile.time_zone_id,
    profile.time_zone_updated_at,
    profile.onboarding_completed_at,
    profile.profile_photo_asset_id,
    profile.provider_profile_photo_asset_id,
    profile.provider_profile_photo_source;

  if not found then
    raise exception 'active profile was not found'
      using errcode = 'P0002';
  end if;
end;
$$;


ALTER FUNCTION "public"."update_own_profile"("p_display_name" "text", "p_profile_photo_asset_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_own_profile"("p_display_name" "text", "p_profile_photo_asset_id" "uuid") IS 'Atomically updates the authenticated user profile display name and optional custom-photo override; the provider fallback is preserved.';



CREATE OR REPLACE FUNCTION "public"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) RETURNS TABLE("note_id" "uuid", "revision" integer, "updated_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.upsert_memory_note(
    p_memory_id,
    p_expected_revision,
    p_body,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;


ALTER FUNCTION "public"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") RETURNS TABLE("invite_id" "uuid", "status" "text", "expires_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select *
  from internal.validate_my_pairing_invite(p_invite_id, p_invite_code);
$$;


ALTER FUNCTION "public"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage_private"."paeonia_can_read_media_object"("p_bucket_id" "text", "p_name" "text") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.can_read_media_object(p_bucket_id, p_name);
$$;


ALTER FUNCTION "storage_private"."paeonia_can_read_media_object"("p_bucket_id" "text", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage_private"."paeonia_can_upload_reserved_media_object"("p_bucket_id" "text", "p_name" "text") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select internal.can_upload_reserved_media_object(p_bucket_id, p_name);
$$;


ALTER FUNCTION "storage_private"."paeonia_can_upload_reserved_media_object"("p_bucket_id" "text", "p_name" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."account_deletion_jobs" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "auth_provider" "text" NOT NULL,
    "status" "text" DEFAULT 'ready_for_auth_delete'::"text" NOT NULL,
    "provider_revocation_status" "text" NOT NULL,
    "provider_revocation_attempted_at" timestamp with time zone,
    "provider_revocation_error_code" "text",
    "auth_delete_attempts" integer DEFAULT 0 NOT NULL,
    "next_attempt_at" timestamp with time zone,
    "claimed_at" timestamp with time zone,
    "last_auth_delete_error_code" "text",
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "account_deletion_jobs_auth_delete_attempts_check" CHECK (("auth_delete_attempts" >= 0)),
    CONSTRAINT "account_deletion_jobs_auth_error_check" CHECK ((("last_auth_delete_error_code" IS NULL) OR (("char_length"("last_auth_delete_error_code") >= 1) AND ("char_length"("last_auth_delete_error_code") <= 120)))),
    CONSTRAINT "account_deletion_jobs_auth_provider_check" CHECK (("auth_provider" = ANY (ARRAY['apple'::"text", 'google'::"text", 'unknown'::"text"]))),
    CONSTRAINT "account_deletion_jobs_completed_state_check" CHECK (((("status" = 'completed'::"text") AND ("completed_at" IS NOT NULL) AND ("next_attempt_at" IS NULL)) OR (("status" <> 'completed'::"text") AND ("completed_at" IS NULL)))),
    CONSTRAINT "account_deletion_jobs_provider_error_check" CHECK ((("provider_revocation_error_code" IS NULL) OR (("char_length"("provider_revocation_error_code") >= 1) AND ("char_length"("provider_revocation_error_code") <= 120)))),
    CONSTRAINT "account_deletion_jobs_provider_revocation_status_check" CHECK (("provider_revocation_status" = ANY (ARRAY['not_required'::"text", 'succeeded'::"text", 'manual_required'::"text"]))),
    CONSTRAINT "account_deletion_jobs_status_check" CHECK (("status" = ANY (ARRAY['ready_for_auth_delete'::"text", 'processing_auth_delete'::"text", 'attention_required'::"text", 'completed'::"text"])))
);


ALTER TABLE "internal"."account_deletion_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."app_account_tokens" (
    "user_id" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "internal"."app_account_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."app_runtime_secrets" (
    "secret_name" "text" NOT NULL,
    "secret_value" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "app_runtime_secrets_name_check" CHECK (("secret_name" ~ '^[a-z0-9_]+$'::"text")),
    CONSTRAINT "app_runtime_secrets_value_check" CHECK ((("char_length"("secret_value") >= 32) AND ("char_length"("secret_value") <= 1024)))
);


ALTER TABLE "internal"."app_runtime_secrets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."client_operations" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "client_operation_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "client_sequence" bigint NOT NULL,
    "local_created_at" timestamp with time zone NOT NULL,
    "operation_kind" "text" NOT NULL,
    "idempotency_scope" "text" NOT NULL,
    "request_hash" "bytea" NOT NULL,
    "response_hash" "bytea",
    "stored_response" "jsonb",
    "status" "text" DEFAULT 'started'::"text" NOT NULL,
    "locked_until" timestamp with time zone,
    "attempt_count" integer DEFAULT 1 NOT NULL,
    "last_attempt_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "failed_at" timestamp with time zone,
    "failure_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "client_operations_attempt_count_check" CHECK (("attempt_count" > 0)),
    CONSTRAINT "client_operations_client_sequence_check" CHECK (("client_sequence" > 0)),
    CONSTRAINT "client_operations_completed_status_check" CHECK ((("completed_at" IS NULL) OR ("status" = 'succeeded'::"text"))),
    CONSTRAINT "client_operations_failed_status_check" CHECK ((("failed_at" IS NULL) OR ("status" = ANY (ARRAY['failed_retryable'::"text", 'failed_terminal'::"text"])))),
    CONSTRAINT "client_operations_failure_timestamp_check" CHECK ((("status" <> ALL (ARRAY['failed_retryable'::"text", 'failed_terminal'::"text"])) OR (("failed_at" IS NOT NULL) AND ("failure_code" IS NOT NULL)))),
    CONSTRAINT "client_operations_idempotency_scope_check" CHECK ((("length"("idempotency_scope") >= 1) AND ("length"("idempotency_scope") <= 160))),
    CONSTRAINT "client_operations_locked_status_check" CHECK ((("locked_until" IS NULL) OR ("status" = 'started'::"text"))),
    CONSTRAINT "client_operations_operation_kind_check" CHECK ((("length"("operation_kind") >= 1) AND ("length"("operation_kind") <= 120))),
    CONSTRAINT "client_operations_request_hash_check" CHECK (("octet_length"("request_hash") = 32)),
    CONSTRAINT "client_operations_response_hash_check" CHECK ((("response_hash" IS NULL) OR ("octet_length"("response_hash") = 32))),
    CONSTRAINT "client_operations_status_check" CHECK (("status" = ANY (ARRAY['started'::"text", 'succeeded'::"text", 'failed_retryable'::"text", 'failed_terminal'::"text"]))),
    CONSTRAINT "client_operations_success_response_check" CHECK ((("status" <> 'succeeded'::"text") OR (("completed_at" IS NOT NULL) AND ("stored_response" IS NOT NULL) AND ("response_hash" IS NOT NULL))))
)
WITH ("autovacuum_vacuum_scale_factor"='0.01', "autovacuum_vacuum_threshold"='50', "autovacuum_analyze_scale_factor"='0.02', "autovacuum_analyze_threshold"='50');


ALTER TABLE "internal"."client_operations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."entitlement_grants" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "product_id" "uuid",
    "grant_kind" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "scope" "text" DEFAULT 'user'::"text" NOT NULL,
    "environment" "text",
    "source_review_session_id" "uuid",
    "reason" "text",
    "granted_by" "text",
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "revoked_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "entitlement_grants_environment_check" CHECK ((("environment" IS NULL) OR ("environment" = ANY (ARRAY['xcode'::"text", 'sandbox'::"text", 'production'::"text"])))),
    CONSTRAINT "entitlement_grants_grant_kind_check" CHECK (("grant_kind" = ANY (ARRAY['lifetime'::"text", 'review'::"text", 'test'::"text", 'beta'::"text"]))),
    CONSTRAINT "entitlement_grants_granted_by_check" CHECK ((("granted_by" IS NULL) OR ("char_length"("granted_by") <= 255))),
    CONSTRAINT "entitlement_grants_reason_check" CHECK ((("reason" IS NULL) OR ("char_length"("reason") <= 1000))),
    CONSTRAINT "entitlement_grants_review_session_check" CHECK ((("grant_kind" <> 'review'::"text") OR ("source_review_session_id" IS NOT NULL))),
    CONSTRAINT "entitlement_grants_review_test_expiry_check" CHECK ((("grant_kind" <> ALL (ARRAY['review'::"text", 'test'::"text"])) OR ("expires_at" IS NOT NULL))),
    CONSTRAINT "entitlement_grants_revoked_reason_check" CHECK ((("revoked_reason" IS NULL) OR ("char_length"("revoked_reason") <= 1000))),
    CONSTRAINT "entitlement_grants_revoked_state_check" CHECK (((("status" = 'revoked'::"text") AND ("revoked_at" IS NOT NULL)) OR (("status" <> 'revoked'::"text") AND ("revoked_at" IS NULL)))),
    CONSTRAINT "entitlement_grants_scope_check" CHECK (("scope" = ANY (ARRAY['user'::"text", 'review'::"text"]))),
    CONSTRAINT "entitlement_grants_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'expired'::"text", 'revoked'::"text"])))
);


ALTER TABLE "internal"."entitlement_grants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."moderation_actions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "report_id" "uuid",
    "action_kind" "text" NOT NULL,
    "status" "text" DEFAULT 'started'::"text" NOT NULL,
    "target_kind" "text",
    "target_id" "uuid",
    "previous_moderation_status" "text",
    "new_moderation_status" "text",
    "storage_action" "text",
    "operator_kind" "text" NOT NULL,
    "operator_identifier" "text" NOT NULL,
    "reviewer_user_id" "uuid",
    "runbook_id" "text",
    "reason" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "moderation_actions_action_kind_check" CHECK (("action_kind" = ANY (ARRAY['hide'::"text", 'remove'::"text", 'restore'::"text", 'reject_upload'::"text", 'delete_storage'::"text", 'create_pair_warning'::"text", 'clear_pair_warning'::"text", 'block_pair'::"text", 'unblock_pair'::"text"]))),
    CONSTRAINT "moderation_actions_moderation_status_check" CHECK ((("previous_moderation_status" IS NULL) OR ("previous_moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"])))),
    CONSTRAINT "moderation_actions_new_moderation_status_check" CHECK ((("new_moderation_status" IS NULL) OR ("new_moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"])))),
    CONSTRAINT "moderation_actions_notes_check" CHECK ((("notes" IS NULL) OR ("char_length"("notes") <= 4000))),
    CONSTRAINT "moderation_actions_operator_identifier_check" CHECK ((("char_length"("btrim"("operator_identifier")) >= 1) AND ("char_length"("btrim"("operator_identifier")) <= 255))),
    CONSTRAINT "moderation_actions_operator_kind_check" CHECK (("operator_kind" = ANY (ARRAY['service_role'::"text", 'sql_runbook'::"text", 'edge_function'::"text", 'admin_user'::"text"]))),
    CONSTRAINT "moderation_actions_reason_check" CHECK ((("reason" IS NULL) OR ("char_length"("reason") <= 1000))),
    CONSTRAINT "moderation_actions_runbook_id_check" CHECK ((("runbook_id" IS NULL) OR (("char_length"("btrim"("runbook_id")) >= 1) AND ("char_length"("btrim"("runbook_id")) <= 255)))),
    CONSTRAINT "moderation_actions_status_check" CHECK (("status" = ANY (ARRAY['started'::"text", 'applied'::"text", 'partially_applied'::"text", 'failed'::"text"]))),
    CONSTRAINT "moderation_actions_storage_action_check" CHECK ((("storage_action" IS NULL) OR ("storage_action" = ANY (ARRAY['none'::"text", 'queued_delete'::"text", 'deleted'::"text", 'failed'::"text"]))))
);


ALTER TABLE "internal"."moderation_actions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."notification_outbox" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "recipient_user_id" "uuid" NOT NULL,
    "target_device_id" "uuid" NOT NULL,
    "push_token_hash" "bytea" NOT NULL,
    "apns_environment" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "payload_version" integer DEFAULT 1 NOT NULL,
    "redaction_level" "text" DEFAULT 'private'::"text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "dedupe_key" "text",
    "apns_push_type" "text" DEFAULT 'alert'::"text" NOT NULL,
    "apns_collapse_id" "text",
    "provider_message_id" "text",
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "last_attempt_at" timestamp with time zone,
    "last_error" "text",
    "scheduled_for" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone,
    "failed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "title" "text",
    "body" "text",
    CONSTRAINT "notification_outbox_apns_collapse_id_check" CHECK ((("apns_collapse_id" IS NULL) OR (("char_length"("btrim"("apns_collapse_id")) >= 1) AND ("char_length"("btrim"("apns_collapse_id")) <= 64)))),
    CONSTRAINT "notification_outbox_apns_environment_check" CHECK (("apns_environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "notification_outbox_apns_push_type_check" CHECK (("apns_push_type" = ANY (ARRAY['alert'::"text", 'background'::"text"]))),
    CONSTRAINT "notification_outbox_attempt_count_check" CHECK (("attempt_count" >= 0)),
    CONSTRAINT "notification_outbox_body_check" CHECK ((("body" IS NULL) OR (("char_length"("btrim"("body")) >= 1) AND ("char_length"("btrim"("body")) <= 1000)))),
    CONSTRAINT "notification_outbox_dedupe_key_check" CHECK ((("dedupe_key" IS NULL) OR (("char_length"("btrim"("dedupe_key")) >= 1) AND ("char_length"("btrim"("dedupe_key")) <= 320)))),
    CONSTRAINT "notification_outbox_kind_check" CHECK (("kind" = ANY (ARRAY['streak_reminder'::"text", 'daily_challenge_completed'::"text", 'partner_answered'::"text", 'widget_updated'::"text", 'location_updated'::"text", 'relationship_ended'::"text", 'entitlement_changed'::"text", 'subscription_trial_reminder'::"text", 'memory_created'::"text", 'thread_message_sent'::"text"]))),
    CONSTRAINT "notification_outbox_last_error_check" CHECK ((("last_error" IS NULL) OR ("char_length"("last_error") <= 2000))),
    CONSTRAINT "notification_outbox_payload_check" CHECK ((("jsonb_typeof"("payload") = 'object'::"text") AND ("octet_length"(("payload")::"text") <= 4096))),
    CONSTRAINT "notification_outbox_payload_version_check" CHECK (("payload_version" = 1)),
    CONSTRAINT "notification_outbox_provider_message_id_check" CHECK ((("provider_message_id" IS NULL) OR ("char_length"("btrim"("provider_message_id")) <= 255))),
    CONSTRAINT "notification_outbox_push_token_hash_check" CHECK (("octet_length"("push_token_hash") = 32)),
    CONSTRAINT "notification_outbox_redaction_level_check" CHECK (("redaction_level" = ANY (ARRAY['private'::"text", 'generic'::"text", 'content_allowed'::"text"]))),
    CONSTRAINT "notification_outbox_terminal_state_check" CHECK ((NOT (("sent_at" IS NOT NULL) AND ("failed_at" IS NOT NULL)))),
    CONSTRAINT "notification_outbox_title_check" CHECK ((("title" IS NULL) OR (("char_length"("btrim"("title")) >= 1) AND ("char_length"("btrim"("title")) <= 200))))
);


ALTER TABLE "internal"."notification_outbox" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."pair_safety_warning_flags" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "pair_id" "uuid" NOT NULL,
    "source_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "internal"."pair_safety_warning_flags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."pairing_invite_attempts" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "code_hash_prefix" "text" NOT NULL,
    "matched_invite_id" "uuid",
    "user_id" "uuid",
    "success" boolean DEFAULT false NOT NULL,
    "failure_reason" "text",
    "ip_hash" "bytea",
    "device_hash" "bytea",
    "app_version" "text",
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pairing_invite_attempts_app_version_check" CHECK ((("app_version" IS NULL) OR (("char_length"("btrim"("app_version")) >= 1) AND ("char_length"("btrim"("app_version")) <= 64)))),
    CONSTRAINT "pairing_invite_attempts_code_hash_prefix_check" CHECK ((("char_length"("code_hash_prefix") >= 1) AND ("char_length"("code_hash_prefix") <= 32))),
    CONSTRAINT "pairing_invite_attempts_device_hash_check" CHECK ((("device_hash" IS NULL) OR ("octet_length"("device_hash") = 32))),
    CONSTRAINT "pairing_invite_attempts_failure_reason_check" CHECK ((("failure_reason" IS NULL) OR (("char_length"("failure_reason") >= 1) AND ("char_length"("failure_reason") <= 120)))),
    CONSTRAINT "pairing_invite_attempts_ip_hash_check" CHECK ((("ip_hash" IS NULL) OR ("octet_length"("ip_hash") = 32))),
    CONSTRAINT "pairing_invite_attempts_success_failure_check" CHECK ((("success" AND ("failure_reason" IS NULL)) OR ((NOT "success") AND ("failure_reason" IS NOT NULL))))
);


ALTER TABLE "internal"."pairing_invite_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."pairing_invite_secrets" (
    "invite_id" "uuid" NOT NULL,
    "code_hash" "bytea" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pairing_invite_secrets_code_hash_check" CHECK (("octet_length"("code_hash") = 32))
);


ALTER TABLE "internal"."pairing_invite_secrets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."privacy_request_events" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "actor_user_id" "uuid",
    "event_kind" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "privacy_request_events_event_kind_check" CHECK ((("char_length"("event_kind") >= 1) AND ("char_length"("event_kind") <= 120))),
    CONSTRAINT "privacy_request_events_metadata_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text"))
);


ALTER TABLE "internal"."privacy_request_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."report_snapshot_assets" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "report_id" "uuid" NOT NULL,
    "source_media_asset_id" "uuid",
    "source_bucket" "text" NOT NULL,
    "source_storage_path" "text" NOT NULL,
    "bucket" "text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "media_type" "text" NOT NULL,
    "byte_size" bigint,
    "sha256" "bytea",
    "copy_status" "text" DEFAULT 'pending_copy'::"text" NOT NULL,
    "copy_claimed_at" timestamp with time zone,
    "copy_attempts" integer DEFAULT 0 NOT NULL,
    "copy_completed_at" timestamp with time zone,
    "last_copy_error" "text",
    "delete_after" timestamp with time zone,
    "storage_delete_status" "text" DEFAULT 'none'::"text" NOT NULL,
    "storage_deleted_at" timestamp with time zone,
    "storage_delete_attempts" integer DEFAULT 0 NOT NULL,
    "last_storage_delete_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "report_snapshot_assets_attempts_check" CHECK (("storage_delete_attempts" >= 0)),
    CONSTRAINT "report_snapshot_assets_bucket_check" CHECK (("bucket" = 'report-snapshots'::"text")),
    CONSTRAINT "report_snapshot_assets_byte_size_check" CHECK ((("byte_size" IS NULL) OR ("byte_size" > 0))),
    CONSTRAINT "report_snapshot_assets_copy_attempts_check" CHECK (("copy_attempts" >= 0)),
    CONSTRAINT "report_snapshot_assets_copy_state_check" CHECK (((("copy_status" = ANY (ARRAY['pending_copy'::"text", 'copying'::"text", 'copy_failed'::"text"])) AND ("copy_completed_at" IS NULL)) OR (("copy_status" = 'copied'::"text") AND ("copy_completed_at" IS NOT NULL) AND ("byte_size" IS NOT NULL) AND ("sha256" IS NOT NULL)))),
    CONSTRAINT "report_snapshot_assets_copy_status_check" CHECK (("copy_status" = ANY (ARRAY['pending_copy'::"text", 'copying'::"text", 'copied'::"text", 'copy_failed'::"text"]))),
    CONSTRAINT "report_snapshot_assets_last_copy_error_check" CHECK ((("last_copy_error" IS NULL) OR ("char_length"("last_copy_error") <= 4000))),
    CONSTRAINT "report_snapshot_assets_last_error_check" CHECK ((("last_storage_delete_error" IS NULL) OR ("char_length"("last_storage_delete_error") <= 4000))),
    CONSTRAINT "report_snapshot_assets_media_type_check" CHECK (("media_type" = ANY (ARRAY['image'::"text", 'voice'::"text", 'drawing_payload'::"text", 'report_snapshot'::"text"]))),
    CONSTRAINT "report_snapshot_assets_sha256_check" CHECK ((("sha256" IS NULL) OR ("octet_length"("sha256") = 32))),
    CONSTRAINT "report_snapshot_assets_source_bucket_check" CHECK (("source_bucket" = ANY (ARRAY['profile-photos'::"text", 'couple-media'::"text", 'widget-drawings'::"text"]))),
    CONSTRAINT "report_snapshot_assets_source_storage_path_check" CHECK ((("char_length"("source_storage_path") BETWEEN 1 AND 1024) AND ("source_storage_path" !~ '(^/|//|/\./|/\.\./|\.\./|/$)'::"text"))),
    CONSTRAINT "report_snapshot_assets_storage_delete_status_check" CHECK (("storage_delete_status" = ANY (ARRAY['none'::"text", 'pending'::"text", 'retrying'::"text", 'deleted'::"text", 'failed'::"text"]))),
    CONSTRAINT "report_snapshot_assets_storage_deleted_at_check" CHECK (((("storage_delete_status" = 'deleted'::"text") AND ("storage_deleted_at" IS NOT NULL)) OR ("storage_delete_status" <> 'deleted'::"text"))),
    CONSTRAINT "report_snapshot_assets_storage_path_check" CHECK ((("char_length"("storage_path") BETWEEN 1 AND 1024) AND ("storage_path" !~ '(^/|//|/\./|/\.\./|\.\./|/$)'::"text")))
);


ALTER TABLE "internal"."report_snapshot_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."report_snapshots" (
    "report_id" "uuid" NOT NULL,
    "snapshot" "jsonb" NOT NULL,
    "delete_after" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "report_snapshots_snapshot_check" CHECK ((("jsonb_typeof"("snapshot") = 'object'::"text") AND ("octet_length"(("snapshot")::"text") <= 65536)))
);


ALTER TABLE "internal"."report_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."review_access_attempts" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "code_hash_prefix" "text" NOT NULL,
    "matched_code_id" "uuid",
    "success" boolean DEFAULT false NOT NULL,
    "failure_reason" "text",
    "ip_hash" "bytea",
    "device_hash" "bytea",
    "app_version" "text",
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "review_access_attempts_app_version_check" CHECK ((("app_version" IS NULL) OR (("char_length"("btrim"("app_version")) >= 1) AND ("char_length"("btrim"("app_version")) <= 64)))),
    CONSTRAINT "review_access_attempts_code_hash_prefix_check" CHECK ((("char_length"("code_hash_prefix") >= 1) AND ("char_length"("code_hash_prefix") <= 32))),
    CONSTRAINT "review_access_attempts_device_hash_check" CHECK ((("device_hash" IS NULL) OR ("octet_length"("device_hash") = 32))),
    CONSTRAINT "review_access_attempts_failure_reason_check" CHECK ((("failure_reason" IS NULL) OR (("char_length"("failure_reason") >= 1) AND ("char_length"("failure_reason") <= 120)))),
    CONSTRAINT "review_access_attempts_ip_hash_check" CHECK ((("ip_hash" IS NULL) OR ("octet_length"("ip_hash") = 32))),
    CONSTRAINT "review_access_attempts_success_failure_check" CHECK ((("success" AND ("failure_reason" IS NULL)) OR ((NOT "success") AND ("failure_reason" IS NOT NULL))))
);


ALTER TABLE "internal"."review_access_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."review_access_sessions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "code_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "seeded_partner_user_id" "uuid",
    "couple_id" "uuid",
    "entitlement_grant_id" "uuid",
    "scenario" "text" NOT NULL,
    "auth_verified_at" timestamp with time zone NOT NULL,
    "completed_at" timestamp with time zone,
    "redeemed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_agent" "text",
    "app_version" "text",
    "device_info" "jsonb",
    CONSTRAINT "review_access_sessions_app_version_check" CHECK ((("app_version" IS NULL) OR (("char_length"("btrim"("app_version")) >= 1) AND ("char_length"("btrim"("app_version")) <= 64)))),
    CONSTRAINT "review_access_sessions_device_info_check" CHECK ((("device_info" IS NULL) OR ("jsonb_typeof"("device_info") = 'object'::"text"))),
    CONSTRAINT "review_access_sessions_prepaired_partner_check" CHECK ((("scenario" <> ALL (ARRAY['pre_paired_entitled'::"text", 'pre_paired_paywalled'::"text"])) OR ("seeded_partner_user_id" IS NOT NULL))),
    CONSTRAINT "review_access_sessions_scenario_check" CHECK (("scenario" = ANY (ARRAY['pre_paired_entitled'::"text", 'purchase_flow_unentitled'::"text", 'pre_paired_paywalled'::"text"]))),
    CONSTRAINT "review_access_sessions_user_agent_check" CHECK ((("user_agent" IS NULL) OR ("char_length"("user_agent") <= 512)))
);


ALTER TABLE "internal"."review_access_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."review_demo_partners" (
    "slot" smallint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "review_demo_partners_display_name_check" CHECK ((("char_length"("btrim"("display_name")) >= 1) AND ("char_length"("btrim"("display_name")) <= 80))),
    CONSTRAINT "review_demo_partners_slot_check" CHECK ((("slot" >= 1) AND ("slot" <= 9)))
);


ALTER TABLE "internal"."review_demo_partners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."storekit_notification_events" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "notification_uuid" "uuid" NOT NULL,
    "notification_type" "text" NOT NULL,
    "subtype" "text",
    "environment" "text" NOT NULL,
    "original_transaction_id" "text",
    "raw_payload_id" "uuid",
    "signed_payload" "text",
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    "processing_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "storekit_notification_events_environment_check" CHECK (("environment" = ANY (ARRAY['xcode'::"text", 'sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "storekit_notification_events_notification_type_check" CHECK ((("char_length"("btrim"("notification_type")) >= 1) AND ("char_length"("btrim"("notification_type")) <= 120))),
    CONSTRAINT "storekit_notification_events_original_transaction_id_check" CHECK ((("original_transaction_id" IS NULL) OR (("char_length"("btrim"("original_transaction_id")) >= 1) AND ("char_length"("btrim"("original_transaction_id")) <= 255)))),
    CONSTRAINT "storekit_notification_events_processing_error_check" CHECK ((("processing_error" IS NULL) OR ("char_length"("processing_error") <= 4000))),
    CONSTRAINT "storekit_notification_events_signed_payload_check" CHECK ((("signed_payload" IS NULL) OR ("char_length"("signed_payload") <= 262144))),
    CONSTRAINT "storekit_notification_events_subtype_check" CHECK ((("subtype" IS NULL) OR (("char_length"("btrim"("subtype")) >= 1) AND ("char_length"("btrim"("subtype")) <= 120))))
);


ALTER TABLE "internal"."storekit_notification_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."storekit_payloads" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "payload_kind" "text" NOT NULL,
    "environment" "text" NOT NULL,
    "original_transaction_id" "text",
    "transaction_id" "text",
    "notification_uuid" "uuid",
    "signed_payload" "text",
    "payload_json" "jsonb",
    "sha256" "bytea",
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "storekit_payloads_environment_check" CHECK (("environment" = ANY (ARRAY['xcode'::"text", 'sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "storekit_payloads_original_transaction_id_check" CHECK ((("original_transaction_id" IS NULL) OR (("char_length"("btrim"("original_transaction_id")) >= 1) AND ("char_length"("btrim"("original_transaction_id")) <= 255)))),
    CONSTRAINT "storekit_payloads_payload_json_check" CHECK ((("payload_json" IS NULL) OR ("jsonb_typeof"("payload_json") = 'object'::"text"))),
    CONSTRAINT "storekit_payloads_payload_kind_check" CHECK (("payload_kind" = ANY (ARRAY['transaction'::"text", 'renewal_info'::"text", 'server_notification'::"text", 'server_api_response'::"text"]))),
    CONSTRAINT "storekit_payloads_sha256_check" CHECK ((("sha256" IS NULL) OR ("octet_length"("sha256") = 32))),
    CONSTRAINT "storekit_payloads_signed_payload_check" CHECK ((("signed_payload" IS NULL) OR ("char_length"("signed_payload") <= 262144))),
    CONSTRAINT "storekit_payloads_transaction_id_check" CHECK ((("transaction_id" IS NULL) OR (("char_length"("btrim"("transaction_id")) >= 1) AND ("char_length"("btrim"("transaction_id")) <= 255))))
);


ALTER TABLE "internal"."storekit_payloads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."storekit_transactions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "environment" "text" NOT NULL,
    "app_account_token" "uuid",
    "original_transaction_id" "text" NOT NULL,
    "transaction_id" "text" NOT NULL,
    "web_order_line_item_id" "text",
    "status" "text" NOT NULL,
    "purchased_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "revocation_reason" "text",
    "raw_payload_id" "uuid",
    "last_reconciled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reconciliation_claimed_at" timestamp with time zone,
    "reconciliation_attempts" integer DEFAULT 0 NOT NULL,
    "last_reconciliation_error" "text",
    CONSTRAINT "storekit_transactions_access_expiry_check" CHECK ((("status" <> ALL (ARRAY['active'::"text", 'grace'::"text"])) OR ("expires_at" IS NOT NULL))),
    CONSTRAINT "storekit_transactions_environment_check" CHECK (("environment" = ANY (ARRAY['xcode'::"text", 'sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "storekit_transactions_last_reconciliation_error_check" CHECK ((("last_reconciliation_error" IS NULL) OR ("char_length"("last_reconciliation_error") <= 4000))),
    CONSTRAINT "storekit_transactions_original_transaction_id_check" CHECK ((("char_length"("btrim"("original_transaction_id")) >= 1) AND ("char_length"("btrim"("original_transaction_id")) <= 255))),
    CONSTRAINT "storekit_transactions_reconciliation_attempts_check" CHECK (("reconciliation_attempts" >= 0)),
    CONSTRAINT "storekit_transactions_revocation_reason_check" CHECK ((("revocation_reason" IS NULL) OR ("char_length"("revocation_reason") <= 512))),
    CONSTRAINT "storekit_transactions_revoked_state_check" CHECK (((("status" = ANY (ARRAY['revoked'::"text", 'refunded'::"text"])) AND ("revoked_at" IS NOT NULL)) OR (("status" <> ALL (ARRAY['revoked'::"text", 'refunded'::"text"])) AND ("revoked_at" IS NULL)))),
    CONSTRAINT "storekit_transactions_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'grace'::"text", 'billing_retry'::"text", 'expired'::"text", 'revoked'::"text", 'refunded'::"text"]))),
    CONSTRAINT "storekit_transactions_transaction_id_check" CHECK ((("char_length"("btrim"("transaction_id")) >= 1) AND ("char_length"("btrim"("transaction_id")) <= 255))),
    CONSTRAINT "storekit_transactions_web_order_line_item_id_check" CHECK ((("web_order_line_item_id" IS NULL) OR (("char_length"("btrim"("web_order_line_item_id")) >= 1) AND ("char_length"("btrim"("web_order_line_item_id")) <= 255))))
);


ALTER TABLE "internal"."storekit_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."streak_restorations" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "purchaser_user_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "environment" "text" NOT NULL,
    "transaction_id" "text" NOT NULL,
    "original_transaction_id" "text",
    "restored_count" integer NOT NULL,
    "restorable_through_date" "date",
    "purchased_at" timestamp with time zone,
    "restored_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "raw_payload_id" "uuid",
    "status" "text" DEFAULT 'applied'::"text" NOT NULL,
    "refunded_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "streak_restorations_environment_check" CHECK (("environment" = ANY (ARRAY['xcode'::"text", 'sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "streak_restorations_original_transaction_id_check" CHECK ((("original_transaction_id" IS NULL) OR (("char_length"("btrim"("original_transaction_id")) >= 1) AND ("char_length"("btrim"("original_transaction_id")) <= 255)))),
    CONSTRAINT "streak_restorations_refunded_state_check" CHECK (((("status" = 'refunded'::"text") AND ("refunded_at" IS NOT NULL)) OR (("status" <> 'refunded'::"text") AND ("refunded_at" IS NULL)))),
    CONSTRAINT "streak_restorations_restored_count_check" CHECK (("restored_count" > 0)),
    CONSTRAINT "streak_restorations_status_check" CHECK (("status" = ANY (ARRAY['applied'::"text", 'refunded'::"text"]))),
    CONSTRAINT "streak_restorations_transaction_id_check" CHECK ((("char_length"("btrim"("transaction_id")) >= 1) AND ("char_length"("btrim"("transaction_id")) <= 255)))
);


ALTER TABLE "internal"."streak_restorations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "internal"."widget_push_outbox" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "recipient_user_id" "uuid" NOT NULL,
    "target_widget_device_id" "uuid" NOT NULL,
    "widget_push_token_hash" "bytea" NOT NULL,
    "apns_environment" "text" NOT NULL,
    "kind" "text" DEFAULT 'widget_updated'::"text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "dedupe_key" "text",
    "apns_collapse_id" "text",
    "provider_message_id" "text",
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "last_attempt_at" timestamp with time zone,
    "last_error" "text",
    "scheduled_for" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone,
    "failed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "widget_push_outbox_apns_environment_check" CHECK (("apns_environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "widget_push_outbox_attempt_count_check" CHECK (("attempt_count" >= 0)),
    CONSTRAINT "widget_push_outbox_collapse_id_check" CHECK ((("apns_collapse_id" IS NULL) OR (("char_length"("btrim"("apns_collapse_id")) >= 1) AND ("char_length"("btrim"("apns_collapse_id")) <= 64)))),
    CONSTRAINT "widget_push_outbox_dedupe_key_check" CHECK ((("dedupe_key" IS NULL) OR (("char_length"("btrim"("dedupe_key")) >= 1) AND ("char_length"("btrim"("dedupe_key")) <= 256)))),
    CONSTRAINT "widget_push_outbox_kind_check" CHECK (("kind" = 'widget_updated'::"text")),
    CONSTRAINT "widget_push_outbox_payload_check" CHECK ((("jsonb_typeof"("payload") = 'object'::"text") AND ("octet_length"(("payload")::"text") <= 2048))),
    CONSTRAINT "widget_push_outbox_token_hash_check" CHECK (("octet_length"("widget_push_token_hash") = 32))
);


ALTER TABLE "internal"."widget_push_outbox" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_report_targets" (
    "report_id" "uuid" NOT NULL,
    "target_kind" "text" NOT NULL,
    "daily_answer_id" "uuid",
    "memory_id" "uuid",
    "memory_note_id" "uuid",
    "memory_media_id" "uuid",
    "message_id" "uuid",
    "message_media_message_id" "uuid",
    "message_media_asset_id" "uuid",
    "widget_drawing_revision_id" "uuid",
    "media_asset_id" "uuid",
    "profile_user_id" "uuid",
    "conduct_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "live_target_deleted_at" timestamp with time zone,
    CONSTRAINT "content_report_targets_live_target_check" CHECK (((("live_target_deleted_at" IS NULL) AND ("num_nonnulls"("daily_answer_id", "memory_id", "memory_note_id", "memory_media_id", "message_id",
CASE
    WHEN ("message_media_message_id" IS NOT NULL) THEN "message_media_message_id"
    ELSE NULL::"uuid"
END, "widget_drawing_revision_id", "media_asset_id", "profile_user_id", "conduct_user_id") = 1) AND ((("target_kind" = 'daily_answer'::"text") AND ("daily_answer_id" IS NOT NULL)) OR (("target_kind" = 'memory'::"text") AND ("memory_id" IS NOT NULL)) OR (("target_kind" = 'memory_note'::"text") AND ("memory_note_id" IS NOT NULL)) OR (("target_kind" = 'memory_media'::"text") AND ("memory_media_id" IS NOT NULL)) OR (("target_kind" = 'thread_message'::"text") AND ("message_id" IS NOT NULL)) OR (("target_kind" = 'thread_message_media'::"text") AND ("message_media_message_id" IS NOT NULL)) OR (("target_kind" = 'widget_drawing_revision'::"text") AND ("widget_drawing_revision_id" IS NOT NULL)) OR (("target_kind" = 'media_asset'::"text") AND ("media_asset_id" IS NOT NULL)) OR (("target_kind" = 'profile'::"text") AND ("profile_user_id" IS NOT NULL)) OR (("target_kind" = 'conduct'::"text") AND ("conduct_user_id" IS NOT NULL)))) OR (("live_target_deleted_at" IS NOT NULL) AND ("daily_answer_id" IS NULL) AND ("memory_id" IS NULL) AND ("memory_note_id" IS NULL) AND ("memory_media_id" IS NULL) AND ("message_id" IS NULL) AND ("message_media_message_id" IS NULL) AND ("message_media_asset_id" IS NULL) AND ("widget_drawing_revision_id" IS NULL) AND ("media_asset_id" IS NULL) AND ("profile_user_id" IS NULL) AND ("conduct_user_id" IS NULL)))),
    CONSTRAINT "content_report_targets_message_media_pair_check" CHECK ((("message_media_message_id" IS NULL) = ("message_media_asset_id" IS NULL))),
    CONSTRAINT "content_report_targets_target_kind_check" CHECK (("target_kind" = ANY (ARRAY['daily_answer'::"text", 'memory'::"text", 'memory_note'::"text", 'memory_media'::"text", 'thread_message'::"text", 'thread_message_media'::"text", 'widget_drawing_revision'::"text", 'media_asset'::"text", 'profile'::"text", 'conduct'::"text"])))
);


ALTER TABLE "public"."content_report_targets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_reports" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "reporter_user_id" "uuid" NOT NULL,
    "reported_user_id" "uuid" NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "pair_id" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "note" "text",
    "status" "text" DEFAULT 'submitted'::"text" NOT NULL,
    "block_requested" boolean DEFAULT false NOT NULL,
    "leave_requested" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    CONSTRAINT "content_reports_distinct_users_check" CHECK (("reporter_user_id" <> "reported_user_id")),
    CONSTRAINT "content_reports_note_check" CHECK ((("note" IS NULL) OR ("char_length"("btrim"("note")) <= 4000))),
    CONSTRAINT "content_reports_reason_check" CHECK (("reason" = ANY (ARRAY['harassment'::"text", 'abuse'::"text", 'threat'::"text", 'sexual_content'::"text", 'hate'::"text", 'privacy'::"text", 'impersonation'::"text", 'self_harm'::"text", 'spam'::"text", 'other'::"text"]))),
    CONSTRAINT "content_reports_resolved_state_check" CHECK (((("status" = ANY (ARRAY['submitted'::"text", 'under_review'::"text"])) AND ("resolved_at" IS NULL)) OR (("status" = ANY (ARRAY['action_taken'::"text", 'rejected'::"text", 'closed'::"text"])) AND ("resolved_at" IS NOT NULL)))),
    CONSTRAINT "content_reports_status_check" CHECK (("status" = ANY (ARRAY['submitted'::"text", 'under_review'::"text", 'action_taken'::"text", 'rejected'::"text", 'closed'::"text"])))
);


ALTER TABLE "public"."content_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conversation_threads" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "created_by_user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    CONSTRAINT "conversation_threads_kind_check" CHECK (("kind" = ANY (ARRAY['daily_question'::"text", 'memory'::"text"]))),
    CONSTRAINT "conversation_threads_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."conversation_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."couple_activity_events" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "couple_day_id" "uuid" NOT NULL,
    "activity_kind" "text" NOT NULL,
    "occurred_at" timestamp with time zone NOT NULL,
    "dedupe_key" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "couple_activity_events_activity_kind_check" CHECK (("activity_kind" = ANY (ARRAY['daily_challenge_completed'::"text", 'widget_drawing_saved'::"text", 'memory_created'::"text", 'memory_updated'::"text", 'thread_message_sent'::"text"]))),
    CONSTRAINT "couple_activity_events_dedupe_key_check" CHECK ((("char_length"("btrim"("dedupe_key")) >= 1) AND ("char_length"("btrim"("dedupe_key")) <= 240))),
    CONSTRAINT "couple_activity_events_metadata_check" CHECK ((("jsonb_typeof"("metadata") = 'object'::"text") AND ("octet_length"(("metadata")::"text") <= 2048)))
);


ALTER TABLE "public"."couple_activity_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."couple_days" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "local_date" "date" NOT NULL,
    "anchor_time_zone_id" "text" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "couple_days_anchor_time_zone_id_check" CHECK ((("char_length"("btrim"("anchor_time_zone_id")) >= 1) AND ("char_length"("btrim"("anchor_time_zone_id")) <= 128))),
    CONSTRAINT "couple_days_window_check" CHECK (("starts_at" < "ends_at"))
);


ALTER TABLE "public"."couple_days" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."couple_members" (
    "couple_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'partner'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "left_at" timestamp with time zone,
    "ended_notice_seen_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "couple_members_left_at_check" CHECK ((("left_at" IS NULL) OR ("status" = 'left'::"text"))),
    CONSTRAINT "couple_members_notice_seen_check" CHECK ((("ended_notice_seen_at" IS NULL) OR ("status" = 'ended_notice_seen'::"text"))),
    CONSTRAINT "couple_members_role_check" CHECK (("role" = ANY (ARRAY['creator'::"text", 'partner'::"text"]))),
    CONSTRAINT "couple_members_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'left'::"text", 'ended_notice_pending'::"text", 'ended_notice_seen'::"text"])))
);


ALTER TABLE "public"."couple_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."couples" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "pair_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "started_on" "date",
    "created_by_user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "delete_after" timestamp with time zone,
    CONSTRAINT "couples_ended_state_check" CHECK (((("status" = 'active'::"text") AND ("ended_at" IS NULL) AND ("delete_after" IS NULL)) OR (("status" = ANY (ARRAY['ended'::"text", 'deleted'::"text"])) AND ("ended_at" IS NOT NULL) AND ("delete_after" IS NOT NULL)))),
    CONSTRAINT "couples_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'ended'::"text", 'deleted'::"text"])))
);


ALTER TABLE "public"."couples" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_answer_media" (
    "answer_id" "uuid" NOT NULL,
    "media_asset_id" "uuid" NOT NULL,
    "sort_order" smallint NOT NULL,
    CONSTRAINT "daily_answer_media_sort_order_check" CHECK ((("sort_order" >= 1) AND ("sort_order" <= 10)))
);


ALTER TABLE "public"."daily_answer_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_answer_partner_choice" (
    "answer_id" "uuid" NOT NULL,
    "selected_user_id" "uuid" NOT NULL
);


ALTER TABLE "public"."daily_answer_partner_choice" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_answer_text" (
    "answer_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    CONSTRAINT "daily_answer_text_body_check" CHECK ((("char_length"("btrim"("body")) >= 1) AND ("char_length"("btrim"("body")) <= 2000)))
);


ALTER TABLE "public"."daily_answer_text" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_challenges" (
    "couple_day_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "completed_at" timestamp with time zone,
    "partner_notified_at" timestamp with time zone,
    CONSTRAINT "daily_challenges_partner_notified_check" CHECK ((("partner_notified_at" IS NULL) OR ("completed_at" IS NOT NULL)))
);


ALTER TABLE "public"."daily_challenges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_question_answers" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "instance_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    CONSTRAINT "daily_question_answers_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."daily_question_answers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_question_instances" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_day_id" "uuid" NOT NULL,
    "question_version_id" "uuid" NOT NULL,
    "seeded_for_user_id" "uuid" NOT NULL,
    "slot_number" smallint NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "replaced_by_instance_id" "uuid",
    "replaced_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "daily_question_instances_replaced_state_check" CHECK (((("status" = 'shuffled'::"text") AND ("replaced_at" IS NOT NULL)) OR (("status" <> 'shuffled'::"text") AND ("replaced_by_instance_id" IS NULL) AND ("replaced_at" IS NULL)))),
    CONSTRAINT "daily_question_instances_slot_number_check" CHECK ((("slot_number" >= 1) AND ("slot_number" <= 3))),
    CONSTRAINT "daily_question_instances_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'shuffled'::"text", 'answered'::"text"])))
);


ALTER TABLE "public"."daily_question_instances" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_question_shuffles" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "couple_day_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "question_id" "uuid" NOT NULL,
    "skipped_instance_id" "uuid" NOT NULL,
    "replacement_instance_id" "uuid" NOT NULL,
    "slot_number" smallint NOT NULL,
    "skipped_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "exclude_until" timestamp with time zone NOT NULL,
    CONSTRAINT "daily_question_shuffles_exclude_until_check" CHECK (("exclude_until" > "skipped_at")),
    CONSTRAINT "daily_question_shuffles_slot_number_check" CHECK ((("slot_number" >= 1) AND ("slot_number" <= 3)))
);


ALTER TABLE "public"."daily_question_shuffles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_question_threads" (
    "instance_id" "uuid" NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."daily_question_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."latest_partner_locations" (
    "couple_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "latitude" numeric(9,6) NOT NULL,
    "longitude" numeric(9,6) NOT NULL,
    "accuracy_m" numeric(10,2),
    "captured_at" timestamp with time zone NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" NOT NULL,
    "client_operation_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "client_sequence" bigint NOT NULL,
    CONSTRAINT "latest_partner_locations_accuracy_check" CHECK ((("accuracy_m" IS NULL) OR (("accuracy_m" >= (0)::numeric) AND ("accuracy_m" <= (100000)::numeric)))),
    CONSTRAINT "latest_partner_locations_captured_at_check" CHECK (("captured_at" <= ("now"() + '00:05:00'::interval))),
    CONSTRAINT "latest_partner_locations_client_sequence_check" CHECK (("client_sequence" > 0)),
    CONSTRAINT "latest_partner_locations_latitude_check" CHECK ((("latitude" >= ('-90'::integer)::numeric) AND ("latitude" <= (90)::numeric))),
    CONSTRAINT "latest_partner_locations_longitude_check" CHECK ((("longitude" >= ('-180'::integer)::numeric) AND ("longitude" <= (180)::numeric))),
    CONSTRAINT "latest_partner_locations_source_check" CHECK (("source" = ANY (ARRAY['foreground_open'::"text", 'manual_refresh'::"text", 'settings_toggle'::"text"])))
);


ALTER TABLE "public"."latest_partner_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."location_sharing_preferences" (
    "couple_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "is_enabled" boolean DEFAULT false NOT NULL,
    "enabled_at" timestamp with time zone,
    "disabled_at" timestamp with time zone DEFAULT "now"(),
    "consent_version" "text",
    "source" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "location_sharing_preferences_consent_version_check" CHECK ((("consent_version" IS NULL) OR (("char_length"("btrim"("consent_version")) >= 1) AND ("char_length"("btrim"("consent_version")) <= 80)))),
    CONSTRAINT "location_sharing_preferences_source_check" CHECK (("source" = ANY (ARRAY['foreground_open'::"text", 'manual_refresh'::"text", 'settings_toggle'::"text"]))),
    CONSTRAINT "location_sharing_preferences_state_check" CHECK ((("is_enabled" AND ("enabled_at" IS NOT NULL) AND ("disabled_at" IS NULL) AND ("consent_version" IS NOT NULL)) OR ((NOT "is_enabled") AND ("disabled_at" IS NOT NULL))))
);


ALTER TABLE "public"."location_sharing_preferences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."media_assets" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "owner_user_id" "uuid" NOT NULL,
    "couple_id" "uuid",
    "reserved_parent_kind" "text" NOT NULL,
    "reserved_parent_id" "uuid" NOT NULL,
    "reserved_by_client_operation_id" "uuid" NOT NULL,
    "bucket" "text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "media_type" "text" NOT NULL,
    "upload_purpose" "text" NOT NULL,
    "expected_media_type" "text" NOT NULL,
    "expected_bucket" "text" NOT NULL,
    "mime_type" "text",
    "byte_size" bigint,
    "sha256" "bytea",
    "width" integer,
    "height" integer,
    "duration_ms" integer,
    "upload_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "upload_expires_at" timestamp with time zone NOT NULL,
    "upload_finalized_at" timestamp with time zone,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    "storage_delete_status" "text" DEFAULT 'none'::"text" NOT NULL,
    "storage_deleted_at" timestamp with time zone,
    "storage_delete_attempts" integer DEFAULT 0 NOT NULL,
    "last_storage_delete_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "media_assets_bucket_check" CHECK (("bucket" = ANY (ARRAY['profile-photos'::"text", 'couple-media'::"text", 'widget-drawings'::"text", 'report-snapshots'::"text"]))),
    CONSTRAINT "media_assets_byte_size_check" CHECK ((("byte_size" IS NULL) OR ("byte_size" > 0))),
    CONSTRAINT "media_assets_deleted_storage_state_check" CHECK ((("deleted_at" IS NULL) OR ("storage_delete_status" = ANY (ARRAY['pending'::"text", 'retrying'::"text", 'deleted'::"text", 'failed'::"text"])))),
    CONSTRAINT "media_assets_dimensions_check" CHECK (((("width" IS NULL) OR ("width" > 0)) AND (("height" IS NULL) OR ("height" > 0)) AND (("duration_ms" IS NULL) OR ("duration_ms" > 0)))),
    CONSTRAINT "media_assets_expected_bucket_check" CHECK (("expected_bucket" = ANY (ARRAY['profile-photos'::"text", 'couple-media'::"text", 'widget-drawings'::"text", 'report-snapshots'::"text"]))),
    CONSTRAINT "media_assets_expected_contract_check" CHECK ((("bucket" = "expected_bucket") AND ("media_type" = "expected_media_type"))),
    CONSTRAINT "media_assets_expected_media_type_check" CHECK (("expected_media_type" = ANY (ARRAY['image'::"text", 'voice'::"text", 'drawing_payload'::"text", 'report_snapshot'::"text"]))),
    CONSTRAINT "media_assets_last_storage_delete_error_check" CHECK ((("last_storage_delete_error" IS NULL) OR ("char_length"("last_storage_delete_error") <= 4000))),
    CONSTRAINT "media_assets_media_type_check" CHECK (("media_type" = ANY (ARRAY['image'::"text", 'voice'::"text", 'drawing_payload'::"text", 'report_snapshot'::"text"]))),
    CONSTRAINT "media_assets_mime_type_check" CHECK ((("mime_type" IS NULL) OR (("char_length"("btrim"("mime_type")) >= 1) AND ("char_length"("btrim"("mime_type")) <= 255)))),
    CONSTRAINT "media_assets_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"]))),
    CONSTRAINT "media_assets_reserved_parent_kind_check" CHECK (("reserved_parent_kind" = ANY (ARRAY['profile_photo'::"text", 'memory_media'::"text", 'daily_answer_media'::"text", 'thread_message_media'::"text", 'widget_drawing_revision'::"text", 'report_snapshot'::"text"]))),
    CONSTRAINT "media_assets_sha256_check" CHECK ((("sha256" IS NULL) OR ("octet_length"("sha256") = 32))),
    CONSTRAINT "media_assets_storage_delete_attempts_check" CHECK (("storage_delete_attempts" >= 0)),
    CONSTRAINT "media_assets_storage_delete_status_check" CHECK (("storage_delete_status" = ANY (ARRAY['none'::"text", 'pending'::"text", 'retrying'::"text", 'deleted'::"text", 'failed'::"text"]))),
    CONSTRAINT "media_assets_storage_deleted_at_check" CHECK (((("storage_delete_status" = 'deleted'::"text") AND ("storage_deleted_at" IS NOT NULL)) OR ("storage_delete_status" <> 'deleted'::"text"))),
    CONSTRAINT "media_assets_storage_path_check" CHECK ((("char_length"("storage_path") BETWEEN 1 AND 1024) AND ("storage_path" !~ '(^/|//|/\./|/\.\./|\.\./|/$)'::"text"))),
    CONSTRAINT "media_assets_upload_contract_check" CHECK (((("upload_purpose" = 'profile_photo'::"text") AND ("reserved_parent_kind" = 'profile_photo'::"text") AND ("reserved_parent_id" = "owner_user_id") AND ("bucket" = 'profile-photos'::"text") AND ("media_type" = 'image'::"text") AND ("couple_id" IS NULL)) OR (("upload_purpose" = 'memory_photo'::"text") AND ("reserved_parent_kind" = 'memory_media'::"text") AND ("bucket" = 'couple-media'::"text") AND ("media_type" = 'image'::"text") AND ("couple_id" IS NOT NULL)) OR (("upload_purpose" = 'voice_note'::"text") AND ("reserved_parent_kind" = ANY (ARRAY['memory_media'::"text", 'daily_answer_media'::"text", 'thread_message_media'::"text"])) AND ("bucket" = 'couple-media'::"text") AND ("media_type" = 'voice'::"text") AND ("couple_id" IS NOT NULL)) OR (("upload_purpose" = 'daily_answer_media'::"text") AND ("reserved_parent_kind" = 'daily_answer_media'::"text") AND ("bucket" = 'couple-media'::"text") AND ("media_type" = 'image'::"text") AND ("couple_id" IS NOT NULL)) OR (("upload_purpose" = 'thread_media'::"text") AND ("reserved_parent_kind" = 'thread_message_media'::"text") AND ("bucket" = 'couple-media'::"text") AND ("media_type" = 'image'::"text") AND ("couple_id" IS NOT NULL)) OR (("upload_purpose" = 'widget_drawing_payload'::"text") AND ("reserved_parent_kind" = 'widget_drawing_revision'::"text") AND ("bucket" = 'widget-drawings'::"text") AND ("media_type" = 'drawing_payload'::"text") AND ("couple_id" IS NOT NULL)) OR (("upload_purpose" = 'report_snapshot'::"text") AND ("reserved_parent_kind" = 'report_snapshot'::"text") AND ("bucket" = 'report-snapshots'::"text") AND ("media_type" = 'report_snapshot'::"text")))),
    CONSTRAINT "media_assets_upload_lifecycle_check" CHECK (((("upload_status" = 'pending'::"text") AND ("upload_finalized_at" IS NULL)) OR (("upload_status" = 'finalized'::"text") AND ("upload_finalized_at" IS NOT NULL) AND ("byte_size" IS NOT NULL) AND ("mime_type" IS NOT NULL) AND ("sha256" IS NOT NULL)) OR (("upload_status" = ANY (ARRAY['failed'::"text", 'expired'::"text"])) AND ("upload_finalized_at" IS NULL)))),
    CONSTRAINT "media_assets_upload_purpose_check" CHECK (("upload_purpose" = ANY (ARRAY['profile_photo'::"text", 'memory_photo'::"text", 'voice_note'::"text", 'daily_answer_media'::"text", 'thread_media'::"text", 'widget_drawing_payload'::"text", 'report_snapshot'::"text"]))),
    CONSTRAINT "media_assets_upload_status_check" CHECK (("upload_status" = ANY (ARRAY['pending'::"text", 'finalized'::"text", 'failed'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."media_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."memories" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "memory_date" "date" NOT NULL,
    "created_by_user_id" "uuid" NOT NULL,
    "last_edited_by_user_id" "uuid" NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "memories_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"]))),
    CONSTRAINT "memories_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "memories_title_check" CHECK ((("char_length"("btrim"("title")) >= 1) AND ("char_length"("btrim"("title")) <= 160)))
);


ALTER TABLE "public"."memories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."memory_media" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "memory_id" "uuid" NOT NULL,
    "media_asset_id" "uuid" NOT NULL,
    "owner_user_id" "uuid" NOT NULL,
    "sort_order" smallint NOT NULL,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "memory_media_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"]))),
    CONSTRAINT "memory_media_sort_order_check" CHECK ((("sort_order" >= 1) AND ("sort_order" <= 20)))
);


ALTER TABLE "public"."memory_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."memory_notes" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "memory_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "memory_notes_body_check" CHECK ((("char_length"("btrim"("body")) >= 1) AND ("char_length"("btrim"("body")) <= 4000))),
    CONSTRAINT "memory_notes_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"]))),
    CONSTRAINT "memory_notes_revision_check" CHECK (("revision" > 0))
);


ALTER TABLE "public"."memory_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."memory_threads" (
    "memory_id" "uuid" NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."memory_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_preferences" (
    "user_id" "uuid" NOT NULL,
    "streak_reminders_enabled" boolean DEFAULT true NOT NULL,
    "daily_challenge_enabled" boolean DEFAULT true NOT NULL,
    "partner_answered_enabled" boolean DEFAULT true NOT NULL,
    "widget_updates_enabled" boolean DEFAULT true NOT NULL,
    "location_updates_enabled" boolean DEFAULT false NOT NULL,
    "lock_screen_detail_level" "text" DEFAULT 'private'::"text" NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "memories_enabled" boolean DEFAULT true NOT NULL,
    "messages_enabled" boolean DEFAULT true NOT NULL,
    CONSTRAINT "notification_preferences_lock_screen_detail_level_check" CHECK (("lock_screen_detail_level" = ANY (ARRAY['private'::"text", 'descriptive'::"text"]))),
    CONSTRAINT "notification_preferences_revision_check" CHECK (("revision" > 0))
);


ALTER TABLE "public"."notification_preferences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pairing_invites" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "created_by_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "accepted_by_user_id" "uuid",
    "accepted_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "couple_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pairing_invites_accepted_state_check" CHECK (((("status" = 'accepted'::"text") AND ("accepted_by_user_id" IS NOT NULL) AND ("accepted_at" IS NOT NULL) AND ("couple_id" IS NOT NULL)) OR (("status" <> 'accepted'::"text") AND ("accepted_by_user_id" IS NULL) AND ("accepted_at" IS NULL) AND ("couple_id" IS NULL)))),
    CONSTRAINT "pairing_invites_expiry_check" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "pairing_invites_not_self_accepted_check" CHECK ((("accepted_by_user_id" IS NULL) OR ("accepted_by_user_id" <> "created_by_user_id"))),
    CONSTRAINT "pairing_invites_revoked_state_check" CHECK (((("status" = 'revoked'::"text") AND ("revoked_at" IS NOT NULL)) OR (("status" <> 'revoked'::"text") AND ("revoked_at" IS NULL)))),
    CONSTRAINT "pairing_invites_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'revoked'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."pairing_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."privacy_requests" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "request_kind" "text" NOT NULL,
    "status" "text" DEFAULT 'submitted'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "verified_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "contact_email" "text",
    "requester_note" "text",
    "visible_status_message" "text",
    "revision" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "privacy_requests_cancelled_status_check" CHECK ((("cancelled_at" IS NULL) OR ("status" = 'cancelled'::"text"))),
    CONSTRAINT "privacy_requests_completed_status_check" CHECK ((("completed_at" IS NULL) OR ("status" = 'completed'::"text"))),
    CONSTRAINT "privacy_requests_contact_email_check" CHECK ((("contact_email" IS NULL) OR (("char_length"("btrim"("contact_email")) >= 3) AND ("char_length"("btrim"("contact_email")) <= 320)))),
    CONSTRAINT "privacy_requests_request_kind_check" CHECK (("request_kind" = ANY (ARRAY['access'::"text", 'export'::"text", 'deletion'::"text", 'correction'::"text"]))),
    CONSTRAINT "privacy_requests_requester_note_check" CHECK ((("requester_note" IS NULL) OR ("char_length"("requester_note") <= 4000))),
    CONSTRAINT "privacy_requests_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "privacy_requests_status_check" CHECK (("status" = ANY (ARRAY['submitted'::"text", 'verifying'::"text", 'processing'::"text", 'completed'::"text", 'rejected'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "privacy_requests_visible_status_message_check" CHECK ((("visible_status_message" IS NULL) OR ("char_length"("visible_status_message") <= 2000)))
);


ALTER TABLE "public"."privacy_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "user_id" "uuid" NOT NULL,
    "display_name" "text",
    "profile_photo_asset_id" "uuid",
    "time_zone_id" "text",
    "time_zone_updated_at" timestamp with time zone,
    "onboarding_completed_at" timestamp with time zone,
    "revision" integer DEFAULT 1 NOT NULL,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "provider_profile_photo_asset_id" "uuid",
    "provider_profile_photo_source" "text",
    CONSTRAINT "profiles_display_name_check" CHECK ((("display_name" IS NULL) OR (("char_length"("btrim"("display_name")) >= 1) AND ("char_length"("btrim"("display_name")) <= 80)))),
    CONSTRAINT "profiles_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"]))),
    CONSTRAINT "profiles_onboarding_completed_fields_check" CHECK ((("onboarding_completed_at" IS NULL) OR (("time_zone_id" IS NOT NULL) AND (("char_length"("btrim"("time_zone_id")) >= 1) AND ("char_length"("btrim"("time_zone_id")) <= 128)) AND ("time_zone_updated_at" IS NOT NULL)))),
    CONSTRAINT "profiles_provider_profile_photo_source_check" CHECK (((("provider_profile_photo_asset_id" IS NULL) AND ("provider_profile_photo_source" IS NULL)) OR (("provider_profile_photo_asset_id" IS NOT NULL) AND ("provider_profile_photo_source" = 'google'::"text")))),
    CONSTRAINT "profiles_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "profiles_time_zone_id_check" CHECK ((("time_zone_id" IS NULL) OR (("char_length"("btrim"("time_zone_id")) >= 1) AND ("char_length"("btrim"("time_zone_id")) <= 128)))),
    CONSTRAINT "profiles_time_zone_updated_at_check" CHECK ((("time_zone_updated_at" IS NULL) OR ("time_zone_id" IS NOT NULL)))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."profile_photo_asset_id" IS 'Optional Paeonia-uploaded profile-photo override. When null, clients use provider_profile_photo_asset_id.';



COMMENT ON COLUMN "public"."profiles"."provider_profile_photo_asset_id" IS 'Private imported OAuth profile-photo fallback; never stores or exposes the provider URL.';



COMMENT ON COLUMN "public"."profiles"."provider_profile_photo_source" IS 'OAuth source for the imported private fallback. MVP supports google.';



CREATE TABLE IF NOT EXISTS "public"."question_answer_kinds" (
    "question_version_id" "uuid" NOT NULL,
    "answer_kind" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "question_answer_kinds_answer_kind_check" CHECK (("answer_kind" = ANY (ARRAY['text'::"text", 'photo'::"text", 'voice'::"text", 'partner_choice'::"text"])))
);


ALTER TABLE "public"."question_answer_kinds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."question_collections" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "kind" "text" NOT NULL,
    "couple_id" "uuid",
    "created_by_user_id" "uuid",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "question_collections_kind_check" CHECK (("kind" = ANY (ARRAY['system'::"text", 'custom'::"text", 'mini_game'::"text"]))),
    CONSTRAINT "question_collections_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'retired'::"text", 'archived'::"text"]))),
    CONSTRAINT "question_collections_system_scope_check" CHECK ((("kind" <> 'system'::"text") OR (("couple_id" IS NULL) AND ("created_by_user_id" IS NULL))))
);


ALTER TABLE "public"."question_collections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."question_version_localizations" (
    "question_version_id" "uuid" NOT NULL,
    "locale" "text" NOT NULL,
    "prompt" "text" NOT NULL,
    "short_prompt" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "question_version_localizations_locale_check" CHECK (("locale" = ANY (ARRAY['en'::"text", 'nb'::"text"]))),
    CONSTRAINT "question_version_localizations_prompt_check" CHECK ((("char_length"("btrim"("prompt")) >= 3) AND ("char_length"("btrim"("prompt")) <= 500))),
    CONSTRAINT "question_version_localizations_short_prompt_check" CHECK ((("char_length"("btrim"("short_prompt")) >= 3) AND ("char_length"("btrim"("short_prompt")) <= 160)))
);


ALTER TABLE "public"."question_version_localizations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."question_versions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "question_id" "uuid" NOT NULL,
    "version_number" integer NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "active_from" timestamp with time zone DEFAULT "now"() NOT NULL,
    "retired_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "question_versions_retired_state_check" CHECK (((("status" = 'retired'::"text") AND ("retired_at" IS NOT NULL)) OR (("status" <> 'retired'::"text") AND ("retired_at" IS NULL)))),
    CONSTRAINT "question_versions_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'retired'::"text"]))),
    CONSTRAINT "question_versions_version_number_check" CHECK (("version_number" > 0))
);


ALTER TABLE "public"."question_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."questions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "collection_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "resurfaceable" boolean DEFAULT true NOT NULL,
    "resurface_after_months" smallint DEFAULT 6,
    "created_by_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "questions_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{2,120}$'::"text")),
    CONSTRAINT "questions_resurface_after_months_check" CHECK ((("resurfaceable" AND (("resurface_after_months" >= 1) AND ("resurface_after_months" <= 60))) OR ((NOT "resurfaceable") AND (("resurface_after_months" IS NULL) OR (("resurface_after_months" >= 1) AND ("resurface_after_months" <= 60)))))),
    CONSTRAINT "questions_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'active'::"text", 'retired'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."questions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."question_catalog_overview" WITH ("security_invoker"='true') AS
 WITH "localization_pivot" AS (
         SELECT "localization"."question_version_id",
            "max"("localization"."short_prompt") FILTER (WHERE ("localization"."locale" = 'en'::"text")) AS "question_short",
            "max"("localization"."prompt") FILTER (WHERE ("localization"."locale" = 'en'::"text")) AS "question_long",
            "max"("localization"."short_prompt") FILTER (WHERE ("localization"."locale" = 'nb'::"text")) AS "norwegian_short",
            "max"("localization"."prompt") FILTER (WHERE ("localization"."locale" = 'nb'::"text")) AS "norwegian_long",
            ("count"(*) FILTER (WHERE ("localization"."locale" = 'en'::"text")) > 0) AS "has_english_localization",
            ("count"(*) FILTER (WHERE ("localization"."locale" = 'nb'::"text")) > 0) AS "has_norwegian_localization"
           FROM "public"."question_version_localizations" "localization"
          GROUP BY "localization"."question_version_id"
        ), "answer_kind_groups" AS (
         SELECT "answer_kind"."question_version_id",
            "array_agg"("answer_kind"."answer_kind" ORDER BY "answer_kind"."answer_kind") AS "answer_kinds"
           FROM "public"."question_answer_kinds" "answer_kind"
          GROUP BY "answer_kind"."question_version_id"
        )
 SELECT "localization_pivot"."question_short",
    "localization_pivot"."question_long",
    "localization_pivot"."norwegian_short",
    "localization_pivot"."norwegian_long",
    "question"."resurfaceable",
    "question"."resurface_after_months",
    "question"."status",
    "question"."created_at",
    "question"."key" AS "question_key",
    "version"."version_number",
    "version"."status" AS "version_status",
    COALESCE("answer_kind_groups"."answer_kinds", ARRAY[]::"text"[]) AS "answer_kinds",
    "cardinality"(COALESCE("answer_kind_groups"."answer_kinds", ARRAY[]::"text"[])) AS "answer_kind_count",
    "collection"."kind" AS "collection_kind",
    "collection"."status" AS "collection_status",
    "version"."active_from",
    "version"."retired_at",
    "version"."created_at" AS "version_created_at",
    "question"."updated_at" AS "question_updated_at",
    "collection"."created_at" AS "collection_created_at",
    "collection"."updated_at" AS "collection_updated_at",
    "localization_pivot"."has_english_localization",
    "localization_pivot"."has_norwegian_localization",
    (("collection"."kind" = 'system'::"text") AND ("collection"."status" = 'active'::"text") AND ("question"."status" = 'active'::"text") AND ("version"."status" = 'active'::"text") AND COALESCE("localization_pivot"."has_english_localization", false) AND COALESCE("localization_pivot"."has_norwegian_localization", false) AND (("cardinality"(COALESCE("answer_kind_groups"."answer_kinds", ARRAY[]::"text"[])) >= 1) AND ("cardinality"(COALESCE("answer_kind_groups"."answer_kinds", ARRAY[]::"text"[])) <= 2))) AS "is_app_selectable",
    "collection"."id" AS "collection_id",
    "question"."id" AS "question_id",
    "version"."id" AS "question_version_id",
    "collection"."couple_id" AS "collection_couple_id",
    "collection"."created_by_user_id" AS "collection_created_by_user_id",
    "question"."created_by_user_id" AS "question_created_by_user_id"
   FROM (((("public"."question_collections" "collection"
     JOIN "public"."questions" "question" ON (("question"."collection_id" = "collection"."id")))
     JOIN "public"."question_versions" "version" ON (("version"."question_id" = "question"."id")))
     LEFT JOIN "localization_pivot" ON (("localization_pivot"."question_version_id" = "version"."id")))
     LEFT JOIN "answer_kind_groups" ON (("answer_kind_groups"."question_version_id" = "version"."id")));


ALTER VIEW "public"."question_catalog_overview" OWNER TO "postgres";


COMMENT ON VIEW "public"."question_catalog_overview" IS 'Admin-only catalog overview with prompt/localization columns first for question review.';



CREATE TABLE IF NOT EXISTS "public"."relationship_blocks" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "pair_id" "uuid" NOT NULL,
    "blocked_by_user_id" "uuid" NOT NULL,
    "blocked_user_id" "uuid" NOT NULL,
    "source_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    "revoked_by_user_id" "uuid",
    "revoke_reason" "text",
    CONSTRAINT "relationship_blocks_distinct_users_check" CHECK (("blocked_by_user_id" <> "blocked_user_id")),
    CONSTRAINT "relationship_blocks_revoke_reason_check" CHECK ((("revoke_reason" IS NULL) OR ("revoke_reason" = ANY (ARRAY['user_unblocked'::"text", 'moderation_unblocked'::"text", 'admin_correction'::"text"])))),
    CONSTRAINT "relationship_blocks_revoked_state_check" CHECK (((("revoked_at" IS NULL) AND ("revoked_by_user_id" IS NULL) AND ("revoke_reason" IS NULL)) OR (("revoked_at" IS NOT NULL) AND ("revoked_by_user_id" IS NOT NULL) AND ("revoke_reason" IS NOT NULL))))
);


ALTER TABLE "public"."relationship_blocks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."relationship_pairs" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_low_id" "uuid" NOT NULL,
    "user_high_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "relationship_pairs_distinct_users_check" CHECK (("user_low_id" <> "user_high_id")),
    CONSTRAINT "relationship_pairs_order_check" CHECK (("user_low_id" < "user_high_id"))
);


ALTER TABLE "public"."relationship_pairs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."relationship_sync_events" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "initiated_by_user_id" "uuid",
    "event_kind" "text" NOT NULL,
    "reason" "text",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "relationship_status" "text" NOT NULL,
    "member_status" "text" NOT NULL,
    "ended_at" timestamp with time zone,
    "delete_after" timestamp with time zone,
    "local_purge_scope" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "relationship_sync_events_event_kind_check" CHECK (("event_kind" = ANY (ARRAY['relationship_started'::"text", 'relationship_updated'::"text", 'relationship_ended'::"text", 'relationship_deleted'::"text", 'entitlement_lost'::"text", 'entitlement_restored'::"text", 'content_hidden'::"text", 'content_cleanup_scheduled'::"text", 'content_purged'::"text", 'account_deletion_started'::"text", 'account_deleted'::"text"]))),
    CONSTRAINT "relationship_sync_events_local_purge_scope_check" CHECK ((("jsonb_typeof"("local_purge_scope") = 'object'::"text") AND ("octet_length"(("local_purge_scope")::"text") <= 4096))),
    CONSTRAINT "relationship_sync_events_member_status_check" CHECK (("member_status" = ANY (ARRAY['active'::"text", 'left'::"text", 'ended_notice_pending'::"text", 'ended_notice_seen'::"text"]))),
    CONSTRAINT "relationship_sync_events_reason_check" CHECK ((("reason" IS NULL) OR (("char_length"("reason") >= 1) AND ("char_length"("reason") <= 160)))),
    CONSTRAINT "relationship_sync_events_relationship_status_check" CHECK (("relationship_status" = ANY (ARRAY['active'::"text", 'ended'::"text", 'deleted'::"text"])))
);


ALTER TABLE "public"."relationship_sync_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."streak_states" (
    "couple_id" "uuid" NOT NULL,
    "current_count" integer DEFAULT 0 NOT NULL,
    "longest_count" integer DEFAULT 0 NOT NULL,
    "last_qualified_date" "date",
    "last_qualified_couple_day_id" "uuid",
    "restore_available" boolean DEFAULT false NOT NULL,
    "next_activity_deadline_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "restorable_count" integer DEFAULT 0 NOT NULL,
    "restorable_through_date" "date",
    "restore_deadline" timestamp with time zone,
    "restored_at" timestamp with time zone,
    "last_restore_transaction_id" "text",
    CONSTRAINT "streak_states_counts_check" CHECK ((("current_count" >= 0) AND ("longest_count" >= "current_count"))),
    CONSTRAINT "streak_states_last_qualified_check" CHECK (((("current_count" = 0) AND ("last_qualified_date" IS NULL) AND ("last_qualified_couple_day_id" IS NULL) AND ("next_activity_deadline_at" IS NULL)) OR (("current_count" > 0) AND ("last_qualified_date" IS NOT NULL) AND ("last_qualified_couple_day_id" IS NOT NULL) AND ("next_activity_deadline_at" IS NOT NULL)))),
    CONSTRAINT "streak_states_restorable_check" CHECK (((("restorable_count" = 0) AND ("restorable_through_date" IS NULL) AND ("restore_deadline" IS NULL)) OR (("restorable_count" > 0) AND ("restorable_through_date" IS NOT NULL) AND ("restore_deadline" IS NOT NULL))))
);


ALTER TABLE "public"."streak_states" OWNER TO "postgres";


COMMENT ON COLUMN "public"."streak_states"."next_activity_deadline_at" IS 'Actual instant when the live streak breaks unless qualifying activity occurs first; recalculated from the latest activity and current partner time zones.';



CREATE TABLE IF NOT EXISTS "public"."subscription_products" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "apple_product_id" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "billing_period" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "subscription_products_apple_product_id_check" CHECK ((("char_length"("btrim"("apple_product_id")) >= 1) AND ("char_length"("btrim"("apple_product_id")) <= 255))),
    CONSTRAINT "subscription_products_billing_period_check" CHECK (("billing_period" = ANY (ARRAY['monthly'::"text", 'yearly'::"text", 'one_time'::"text"]))),
    CONSTRAINT "subscription_products_kind_check" CHECK (("kind" = ANY (ARRAY['couple_subscription'::"text", 'streak_restore'::"text"])))
);


ALTER TABLE "public"."subscription_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."thread_message_media" (
    "message_id" "uuid" NOT NULL,
    "media_asset_id" "uuid" NOT NULL,
    "sort_order" smallint NOT NULL,
    CONSTRAINT "thread_message_media_sort_order_check" CHECK ((("sort_order" >= 1) AND ("sort_order" <= 10)))
);


ALTER TABLE "public"."thread_message_media" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."thread_messages" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "sender_user_id" "uuid" NOT NULL,
    "body" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "edited_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    CONSTRAINT "thread_messages_body_check" CHECK ((("body" IS NULL) OR (("char_length"("btrim"("body")) >= 1) AND ("char_length"("btrim"("body")) <= 4000)))),
    CONSTRAINT "thread_messages_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."thread_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_devices" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "platform" "text" NOT NULL,
    "push_token" "text" NOT NULL,
    "push_token_hash" "bytea" NOT NULL,
    "apns_environment" "text" NOT NULL,
    "locale" "text",
    "time_zone_id" "text",
    "app_version" "text",
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "disabled_at" timestamp with time zone,
    CONSTRAINT "user_devices_apns_environment_check" CHECK (("apns_environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "user_devices_app_version_check" CHECK ((("app_version" IS NULL) OR (("char_length"("btrim"("app_version")) >= 1) AND ("char_length"("btrim"("app_version")) <= 64)))),
    CONSTRAINT "user_devices_locale_check" CHECK ((("locale" IS NULL) OR (("char_length"("btrim"("locale")) >= 2) AND ("char_length"("btrim"("locale")) <= 64)))),
    CONSTRAINT "user_devices_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'ipados'::"text"]))),
    CONSTRAINT "user_devices_push_token_check" CHECK ((("char_length"("push_token") >= 20) AND ("char_length"("push_token") <= 4096))),
    CONSTRAINT "user_devices_push_token_hash_check" CHECK (("octet_length"("push_token_hash") = 32)),
    CONSTRAINT "user_devices_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "user_devices_time_zone_id_check" CHECK ((("time_zone_id" IS NULL) OR (("char_length"("btrim"("time_zone_id")) >= 1) AND ("char_length"("btrim"("time_zone_id")) <= 128))))
);


ALTER TABLE "public"."user_devices" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."user_entitlements" WITH ("security_invoker"='true') AS
 SELECT "tx"."user_id",
    'storekit'::"text" AS "source",
    "tx"."status",
    "tx"."product_id",
    "tx"."expires_at" AS "current_period_end",
    COALESCE("tx"."last_reconciled_at", "tx"."updated_at", "tx"."created_at") AS "updated_at"
   FROM "internal"."storekit_transactions" "tx"
UNION ALL
 SELECT "grant_row"."user_id",
        CASE "grant_row"."grant_kind"
            WHEN 'lifetime'::"text" THEN 'lifetime_grant'::"text"
            WHEN 'review'::"text" THEN 'review_grant'::"text"
            ELSE 'test_grant'::"text"
        END AS "source",
        CASE
            WHEN ("grant_row"."status" = 'revoked'::"text") THEN 'revoked'::"text"
            WHEN ("grant_row"."status" = 'expired'::"text") THEN 'expired'::"text"
            WHEN (("grant_row"."expires_at" IS NOT NULL) AND ("grant_row"."expires_at" <= "now"())) THEN 'expired'::"text"
            WHEN ("grant_row"."grant_kind" = 'lifetime'::"text") THEN 'lifetime'::"text"
            ELSE 'active'::"text"
        END AS "status",
    "grant_row"."product_id",
    "grant_row"."expires_at" AS "current_period_end",
    "grant_row"."updated_at"
   FROM "internal"."entitlement_grants" "grant_row";


ALTER VIEW "public"."user_entitlements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."widget_canvases" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "couple_id" "uuid" NOT NULL,
    "active_revision_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."widget_canvases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."widget_drawing_revisions" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "canvas_id" "uuid" NOT NULL,
    "author_user_id" "uuid" NOT NULL,
    "parent_revision_id" "uuid",
    "format" "text" DEFAULT 'pkdrawing'::"text" NOT NULL,
    "format_version" integer DEFAULT 1 NOT NULL,
    "payload_media_asset_id" "uuid" NOT NULL,
    "payload_bytes" bigint NOT NULL,
    "uncompressed_bytes" bigint NOT NULL,
    "compression" "text" DEFAULT 'none'::"text" NOT NULL,
    "stroke_count" integer,
    "point_count" integer,
    "bounds" "jsonb",
    "renderer_version" integer DEFAULT 1 NOT NULL,
    "client_decode_validated_at" timestamp with time zone NOT NULL,
    "client_renderer_version" "text" NOT NULL,
    "client_validation_version" "text" NOT NULL,
    "moderation_status" "text" DEFAULT 'visible'::"text" NOT NULL,
    "moderated_at" timestamp with time zone,
    "moderated_by" "uuid",
    "moderation_report_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "widget_drawing_revisions_bounds_check" CHECK ((("bounds" IS NULL) OR (("jsonb_typeof"("bounds") = 'object'::"text") AND ("octet_length"(("bounds")::"text") <= 2048)))),
    CONSTRAINT "widget_drawing_revisions_client_decode_validated_at_check" CHECK (("client_decode_validated_at" <= ("now"() + '00:05:00'::interval))),
    CONSTRAINT "widget_drawing_revisions_client_renderer_version_check" CHECK ((("char_length"("btrim"("client_renderer_version")) >= 1) AND ("char_length"("btrim"("client_renderer_version")) <= 80))),
    CONSTRAINT "widget_drawing_revisions_client_validation_version_check" CHECK ((("char_length"("btrim"("client_validation_version")) >= 1) AND ("char_length"("btrim"("client_validation_version")) <= 80))),
    CONSTRAINT "widget_drawing_revisions_compression_check" CHECK (("compression" = ANY (ARRAY['none'::"text", 'gzip'::"text"]))),
    CONSTRAINT "widget_drawing_revisions_format_check" CHECK (("format" = 'pkdrawing'::"text")),
    CONSTRAINT "widget_drawing_revisions_format_version_check" CHECK (("format_version" = 1)),
    CONSTRAINT "widget_drawing_revisions_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['pending_review'::"text", 'visible'::"text", 'hidden'::"text", 'removed'::"text", 'rejected'::"text"]))),
    CONSTRAINT "widget_drawing_revisions_payload_bytes_check" CHECK ((("payload_bytes" >= 1) AND ("payload_bytes" <= 2097152))),
    CONSTRAINT "widget_drawing_revisions_point_count_check" CHECK ((("point_count" IS NULL) OR (("point_count" >= 0) AND ("point_count" <= 200000)))),
    CONSTRAINT "widget_drawing_revisions_renderer_version_check" CHECK (("renderer_version" > 0)),
    CONSTRAINT "widget_drawing_revisions_stroke_count_check" CHECK ((("stroke_count" IS NULL) OR (("stroke_count" >= 0) AND ("stroke_count" <= 5000)))),
    CONSTRAINT "widget_drawing_revisions_uncompressed_bytes_check" CHECK ((("uncompressed_bytes" >= 1) AND ("uncompressed_bytes" <= 2097152))),
    CONSTRAINT "widget_drawing_revisions_uncompressed_contract_check" CHECK (((("compression" = 'none'::"text") AND ("uncompressed_bytes" = "payload_bytes")) OR (("compression" = 'gzip'::"text") AND ("uncompressed_bytes" >= "payload_bytes"))))
);


ALTER TABLE "public"."widget_drawing_revisions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."widget_push_devices" (
    "id" "uuid" DEFAULT "extensions"."gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "widget_kind" "text" NOT NULL,
    "widget_push_token" "text" NOT NULL,
    "widget_push_token_hash" "bytea" NOT NULL,
    "apns_environment" "text" NOT NULL,
    "locale" "text",
    "time_zone_id" "text",
    "app_version" "text",
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "disabled_at" timestamp with time zone,
    CONSTRAINT "widget_push_devices_apns_environment_check" CHECK (("apns_environment" = ANY (ARRAY['sandbox'::"text", 'production'::"text"]))),
    CONSTRAINT "widget_push_devices_app_version_check" CHECK ((("app_version" IS NULL) OR (("char_length"("btrim"("app_version")) >= 1) AND ("char_length"("btrim"("app_version")) <= 64)))),
    CONSTRAINT "widget_push_devices_locale_check" CHECK ((("locale" IS NULL) OR (("char_length"("btrim"("locale")) >= 2) AND ("char_length"("btrim"("locale")) <= 64)))),
    CONSTRAINT "widget_push_devices_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "widget_push_devices_time_zone_id_check" CHECK ((("time_zone_id" IS NULL) OR (("char_length"("btrim"("time_zone_id")) >= 1) AND ("char_length"("btrim"("time_zone_id")) <= 128)))),
    CONSTRAINT "widget_push_devices_token_check" CHECK ((("char_length"("widget_push_token") >= 20) AND ("char_length"("widget_push_token") <= 4096))),
    CONSTRAINT "widget_push_devices_token_hash_check" CHECK (("octet_length"("widget_push_token_hash") = 32)),
    CONSTRAINT "widget_push_devices_widget_kind_check" CHECK ((("char_length"("btrim"("widget_kind")) >= 1) AND ("char_length"("btrim"("widget_kind")) <= 128)))
);


ALTER TABLE "public"."widget_push_devices" OWNER TO "postgres";


ALTER TABLE ONLY "internal"."account_deletion_jobs"
    ADD CONSTRAINT "account_deletion_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."account_deletion_jobs"
    ADD CONSTRAINT "account_deletion_jobs_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "internal"."account_deletion_jobs"
    ADD CONSTRAINT "account_deletion_jobs_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "internal"."app_account_tokens"
    ADD CONSTRAINT "app_account_tokens_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "internal"."app_account_tokens"
    ADD CONSTRAINT "app_account_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "internal"."app_runtime_secrets"
    ADD CONSTRAINT "app_runtime_secrets_pkey" PRIMARY KEY ("secret_name");



ALTER TABLE ONLY "internal"."client_operations"
    ADD CONSTRAINT "client_operations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."client_operations"
    ADD CONSTRAINT "client_operations_user_operation_unique" UNIQUE ("user_id", "client_operation_id");



ALTER TABLE ONLY "internal"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."notification_outbox"
    ADD CONSTRAINT "notification_outbox_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."pair_safety_warning_flags"
    ADD CONSTRAINT "pair_safety_warning_flags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."pairing_invite_attempts"
    ADD CONSTRAINT "pairing_invite_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."pairing_invite_secrets"
    ADD CONSTRAINT "pairing_invite_secrets_code_hash_unique" UNIQUE ("code_hash");



ALTER TABLE ONLY "internal"."pairing_invite_secrets"
    ADD CONSTRAINT "pairing_invite_secrets_pkey" PRIMARY KEY ("invite_id");



ALTER TABLE ONLY "internal"."privacy_request_events"
    ADD CONSTRAINT "privacy_request_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."report_snapshot_assets"
    ADD CONSTRAINT "report_snapshot_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."report_snapshots"
    ADD CONSTRAINT "report_snapshots_pkey" PRIMARY KEY ("report_id");



ALTER TABLE ONLY "internal"."review_access_attempts"
    ADD CONSTRAINT "review_access_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."review_access_codes"
    ADD CONSTRAINT "review_access_codes_code_hash_unique" UNIQUE ("code_hash");



ALTER TABLE ONLY "internal"."review_access_codes"
    ADD CONSTRAINT "review_access_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."review_access_sessions"
    ADD CONSTRAINT "review_access_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."review_demo_partners"
    ADD CONSTRAINT "review_demo_partners_pkey" PRIMARY KEY ("slot");



ALTER TABLE ONLY "internal"."review_demo_partners"
    ADD CONSTRAINT "review_demo_partners_user_unique" UNIQUE ("user_id");



ALTER TABLE ONLY "internal"."storekit_notification_events"
    ADD CONSTRAINT "storekit_notification_events_notification_uuid_unique" UNIQUE ("notification_uuid");



ALTER TABLE ONLY "internal"."storekit_notification_events"
    ADD CONSTRAINT "storekit_notification_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."storekit_payloads"
    ADD CONSTRAINT "storekit_payloads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."storekit_transactions"
    ADD CONSTRAINT "storekit_transactions_environment_transaction_unique" UNIQUE ("environment", "transaction_id");



ALTER TABLE ONLY "internal"."storekit_transactions"
    ADD CONSTRAINT "storekit_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."streak_restorations"
    ADD CONSTRAINT "streak_restorations_environment_transaction_unique" UNIQUE ("environment", "transaction_id");



ALTER TABLE ONLY "internal"."streak_restorations"
    ADD CONSTRAINT "streak_restorations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."widget_push_outbox"
    ADD CONSTRAINT "widget_push_outbox_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_pkey" PRIMARY KEY ("report_id");



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversation_threads"
    ADD CONSTRAINT "conversation_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."couple_activity_events"
    ADD CONSTRAINT "couple_activity_events_dedupe_key_unique" UNIQUE ("dedupe_key");



ALTER TABLE ONLY "public"."couple_activity_events"
    ADD CONSTRAINT "couple_activity_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."couple_days"
    ADD CONSTRAINT "couple_days_couple_local_date_unique" UNIQUE ("couple_id", "local_date");



ALTER TABLE ONLY "public"."couple_days"
    ADD CONSTRAINT "couple_days_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."couple_members"
    ADD CONSTRAINT "couple_members_primary_key" PRIMARY KEY ("couple_id", "user_id");



ALTER TABLE ONLY "public"."couples"
    ADD CONSTRAINT "couples_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_answer_media"
    ADD CONSTRAINT "daily_answer_media_answer_sort_order_unique" UNIQUE ("answer_id", "sort_order");



ALTER TABLE ONLY "public"."daily_answer_media"
    ADD CONSTRAINT "daily_answer_media_primary_key" PRIMARY KEY ("answer_id", "media_asset_id");



ALTER TABLE ONLY "public"."daily_answer_partner_choice"
    ADD CONSTRAINT "daily_answer_partner_choice_pkey" PRIMARY KEY ("answer_id");



ALTER TABLE ONLY "public"."daily_answer_text"
    ADD CONSTRAINT "daily_answer_text_pkey" PRIMARY KEY ("answer_id");



ALTER TABLE ONLY "public"."daily_challenges"
    ADD CONSTRAINT "daily_challenges_primary_key" PRIMARY KEY ("couple_day_id", "user_id");



ALTER TABLE ONLY "public"."daily_question_answers"
    ADD CONSTRAINT "daily_question_answers_instance_user_unique" UNIQUE ("instance_id", "user_id");



ALTER TABLE ONLY "public"."daily_question_answers"
    ADD CONSTRAINT "daily_question_answers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_question_instances"
    ADD CONSTRAINT "daily_question_instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_question_threads"
    ADD CONSTRAINT "daily_question_threads_pkey" PRIMARY KEY ("instance_id");



ALTER TABLE ONLY "public"."daily_question_threads"
    ADD CONSTRAINT "daily_question_threads_thread_id_unique" UNIQUE ("thread_id");



ALTER TABLE ONLY "public"."latest_partner_locations"
    ADD CONSTRAINT "latest_partner_locations_primary_key" PRIMARY KEY ("couple_id", "user_id");



ALTER TABLE ONLY "public"."location_sharing_preferences"
    ADD CONSTRAINT "location_sharing_preferences_primary_key" PRIMARY KEY ("couple_id", "user_id");



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."memories"
    ADD CONSTRAINT "memories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."memory_media"
    ADD CONSTRAINT "memory_media_memory_asset_unique" UNIQUE ("memory_id", "media_asset_id");



ALTER TABLE ONLY "public"."memory_media"
    ADD CONSTRAINT "memory_media_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."memory_notes"
    ADD CONSTRAINT "memory_notes_memory_user_unique" UNIQUE ("memory_id", "user_id");



ALTER TABLE ONLY "public"."memory_notes"
    ADD CONSTRAINT "memory_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."memory_threads"
    ADD CONSTRAINT "memory_threads_pkey" PRIMARY KEY ("memory_id");



ALTER TABLE ONLY "public"."memory_threads"
    ADD CONSTRAINT "memory_threads_thread_id_unique" UNIQUE ("thread_id");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."pairing_invites"
    ADD CONSTRAINT "pairing_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."privacy_requests"
    ADD CONSTRAINT "privacy_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."question_answer_kinds"
    ADD CONSTRAINT "question_answer_kinds_primary_key" PRIMARY KEY ("question_version_id", "answer_kind");



ALTER TABLE ONLY "public"."question_collections"
    ADD CONSTRAINT "question_collections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."question_version_localizations"
    ADD CONSTRAINT "question_version_localizations_primary_key" PRIMARY KEY ("question_version_id", "locale");



ALTER TABLE ONLY "public"."question_versions"
    ADD CONSTRAINT "question_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."question_versions"
    ADD CONSTRAINT "question_versions_question_version_unique" UNIQUE ("question_id", "version_number");



ALTER TABLE ONLY "public"."questions"
    ADD CONSTRAINT "questions_collection_key_unique" UNIQUE ("collection_id", "key");



ALTER TABLE ONLY "public"."questions"
    ADD CONSTRAINT "questions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."relationship_blocks"
    ADD CONSTRAINT "relationship_blocks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."relationship_pairs"
    ADD CONSTRAINT "relationship_pairs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."relationship_pairs"
    ADD CONSTRAINT "relationship_pairs_user_pair_unique" UNIQUE ("user_low_id", "user_high_id");



ALTER TABLE ONLY "public"."relationship_sync_events"
    ADD CONSTRAINT "relationship_sync_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."streak_states"
    ADD CONSTRAINT "streak_states_pkey" PRIMARY KEY ("couple_id");



ALTER TABLE ONLY "public"."subscription_products"
    ADD CONSTRAINT "subscription_products_apple_product_id_unique" UNIQUE ("apple_product_id");



ALTER TABLE ONLY "public"."subscription_products"
    ADD CONSTRAINT "subscription_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."thread_message_media"
    ADD CONSTRAINT "thread_message_media_message_sort_order_unique" UNIQUE ("message_id", "sort_order");



ALTER TABLE ONLY "public"."thread_message_media"
    ADD CONSTRAINT "thread_message_media_primary_key" PRIMARY KEY ("message_id", "media_asset_id");



ALTER TABLE ONLY "public"."thread_messages"
    ADD CONSTRAINT "thread_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."widget_canvases"
    ADD CONSTRAINT "widget_canvases_couple_id_unique" UNIQUE ("couple_id");



ALTER TABLE ONLY "public"."widget_canvases"
    ADD CONSTRAINT "widget_canvases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_payload_asset_unique" UNIQUE ("payload_media_asset_id");



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."widget_push_devices"
    ADD CONSTRAINT "widget_push_devices_pkey" PRIMARY KEY ("id");



CREATE INDEX "account_deletion_jobs_due_idx" ON "internal"."account_deletion_jobs" USING "btree" ("next_attempt_at", "id") WHERE ("status" = ANY (ARRAY['ready_for_auth_delete'::"text", 'processing_auth_delete'::"text"]));



CREATE INDEX "client_operations_stale_cleanup_idx" ON "internal"."client_operations" USING "btree" ("status", "created_at") WHERE ("status" = ANY (ARRAY['started'::"text", 'failed_retryable'::"text"]));



CREATE INDEX "client_operations_started_locked_until_idx" ON "internal"."client_operations" USING "btree" ("status", "locked_until") WHERE (("status" = 'started'::"text") AND ("locked_until" IS NOT NULL));



CREATE INDEX "client_operations_succeeded_completed_idx" ON "internal"."client_operations" USING "btree" ("completed_at") WHERE ("status" = 'succeeded'::"text");



CREATE INDEX "client_operations_user_created_at_idx" ON "internal"."client_operations" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "client_operations_user_scope_created_at_idx" ON "internal"."client_operations" USING "btree" ("user_id", "idempotency_scope", "created_at" DESC);



CREATE UNIQUE INDEX "entitlement_grants_active_user_kind_product_idx" ON "internal"."entitlement_grants" USING "btree" ("user_id", "grant_kind", COALESCE("product_id", '00000000-0000-0000-0000-000000000000'::"uuid")) WHERE (("status" = 'active'::"text") AND ("revoked_at" IS NULL));



CREATE INDEX "entitlement_grants_product_id_fk_idx" ON "internal"."entitlement_grants" USING "btree" ("product_id") WHERE ("product_id" IS NOT NULL);



CREATE INDEX "entitlement_grants_review_session_idx" ON "internal"."entitlement_grants" USING "btree" ("source_review_session_id") WHERE ("source_review_session_id" IS NOT NULL);



CREATE INDEX "entitlement_grants_status_expires_at_cleanup_idx" ON "internal"."entitlement_grants" USING "btree" ("status", "expires_at");



CREATE INDEX "entitlement_grants_user_status_expires_at_idx" ON "internal"."entitlement_grants" USING "btree" ("user_id", "status", "expires_at");



CREATE INDEX "moderation_actions_report_created_at_idx" ON "internal"."moderation_actions" USING "btree" ("report_id", "created_at" DESC);



CREATE INDEX "moderation_actions_reviewer_user_id_fk_idx" ON "internal"."moderation_actions" USING "btree" ("reviewer_user_id") WHERE ("reviewer_user_id" IS NOT NULL);



CREATE UNIQUE INDEX "notification_outbox_dedupe_key_unique_idx" ON "internal"."notification_outbox" USING "btree" ("dedupe_key") WHERE ("dedupe_key" IS NOT NULL);



CREATE INDEX "notification_outbox_pending_due_idx" ON "internal"."notification_outbox" USING "btree" ("scheduled_for", "created_at", "id") WHERE (("sent_at" IS NULL) AND ("failed_at" IS NULL));



CREATE INDEX "notification_outbox_recipient_created_at_idx" ON "internal"."notification_outbox" USING "btree" ("recipient_user_id", "created_at" DESC);



CREATE INDEX "notification_outbox_target_device_id_fk_idx" ON "internal"."notification_outbox" USING "btree" ("target_device_id") WHERE ("target_device_id" IS NOT NULL);



CREATE INDEX "pair_safety_warning_flags_pair_created_at_idx" ON "internal"."pair_safety_warning_flags" USING "btree" ("pair_id", "created_at" DESC);



CREATE UNIQUE INDEX "pair_safety_warning_flags_pair_report_unique_idx" ON "internal"."pair_safety_warning_flags" USING "btree" ("pair_id", "source_report_id") WHERE ("source_report_id" IS NOT NULL);



CREATE INDEX "pair_safety_warning_flags_source_report_id_fk_idx" ON "internal"."pair_safety_warning_flags" USING "btree" ("source_report_id") WHERE ("source_report_id" IS NOT NULL);



CREATE INDEX "pairing_invite_attempts_code_prefix_attempted_at_idx" ON "internal"."pairing_invite_attempts" USING "btree" ("code_hash_prefix", "attempted_at" DESC);



CREATE INDEX "pairing_invite_attempts_matched_invite_id_fk_idx" ON "internal"."pairing_invite_attempts" USING "btree" ("matched_invite_id") WHERE ("matched_invite_id" IS NOT NULL);



CREATE INDEX "pairing_invite_attempts_user_attempted_at_idx" ON "internal"."pairing_invite_attempts" USING "btree" ("user_id", "attempted_at" DESC);



CREATE INDEX "privacy_request_events_request_created_at_idx" ON "internal"."privacy_request_events" USING "btree" ("request_id", "created_at");



CREATE UNIQUE INDEX "report_snapshot_assets_bucket_storage_path_unique_idx" ON "internal"."report_snapshot_assets" USING "btree" ("bucket", "storage_path");



CREATE INDEX "report_snapshot_assets_copy_claim_idx" ON "internal"."report_snapshot_assets" USING "btree" ("copy_status", "copy_attempts", "copy_claimed_at", "created_at");



CREATE INDEX "report_snapshot_assets_delete_status_idx" ON "internal"."report_snapshot_assets" USING "btree" ("delete_after", "storage_delete_status");



CREATE UNIQUE INDEX "report_snapshot_assets_report_source_unique_idx" ON "internal"."report_snapshot_assets" USING "btree" ("report_id", "source_media_asset_id") WHERE ("source_media_asset_id" IS NOT NULL);



CREATE INDEX "report_snapshot_assets_source_media_asset_id_fk_idx" ON "internal"."report_snapshot_assets" USING "btree" ("source_media_asset_id") WHERE ("source_media_asset_id" IS NOT NULL);



CREATE INDEX "report_snapshot_assets_storage_retry_idx" ON "internal"."report_snapshot_assets" USING "btree" ("storage_delete_status", "storage_delete_attempts", "updated_at") WHERE (("delete_after" IS NOT NULL) AND ("copy_status" = 'copied'::"text"));



CREATE INDEX "review_access_attempts_code_prefix_attempted_at_idx" ON "internal"."review_access_attempts" USING "btree" ("code_hash_prefix", "attempted_at" DESC);



CREATE INDEX "review_access_attempts_matched_code_id_fk_idx" ON "internal"."review_access_attempts" USING "btree" ("matched_code_id") WHERE ("matched_code_id" IS NOT NULL);



CREATE INDEX "review_access_attempts_user_attempted_at_idx" ON "internal"."review_access_attempts" USING "btree" ("user_id", "attempted_at" DESC);



CREATE INDEX "review_access_codes_status_expires_at_cleanup_idx" ON "internal"."review_access_codes" USING "btree" ("status", "expires_at");



CREATE INDEX "review_access_sessions_code_redeemed_at_idx" ON "internal"."review_access_sessions" USING "btree" ("code_id", "redeemed_at" DESC);



CREATE INDEX "review_access_sessions_couple_id_fk_idx" ON "internal"."review_access_sessions" USING "btree" ("couple_id") WHERE ("couple_id" IS NOT NULL);



CREATE INDEX "review_access_sessions_entitlement_grant_id_fk_idx" ON "internal"."review_access_sessions" USING "btree" ("entitlement_grant_id") WHERE ("entitlement_grant_id" IS NOT NULL);



CREATE INDEX "review_access_sessions_user_redeemed_at_idx" ON "internal"."review_access_sessions" USING "btree" ("user_id", "redeemed_at" DESC);



CREATE INDEX "storekit_notification_events_raw_payload_id_fk_idx" ON "internal"."storekit_notification_events" USING "btree" ("raw_payload_id") WHERE ("raw_payload_id" IS NOT NULL);



CREATE UNIQUE INDEX "storekit_payloads_environment_sha256_unique_idx" ON "internal"."storekit_payloads" USING "btree" ("environment", "sha256") WHERE ("sha256" IS NOT NULL);



CREATE INDEX "storekit_transactions_environment_original_transaction_idx" ON "internal"."storekit_transactions" USING "btree" ("environment", "original_transaction_id");



CREATE INDEX "storekit_transactions_product_user_idx" ON "internal"."storekit_transactions" USING "btree" ("product_id", "user_id");



CREATE INDEX "storekit_transactions_raw_payload_id_fk_idx" ON "internal"."storekit_transactions" USING "btree" ("raw_payload_id") WHERE ("raw_payload_id" IS NOT NULL);



CREATE INDEX "storekit_transactions_reconciliation_claim_idx" ON "internal"."storekit_transactions" USING "btree" ("status", "expires_at", "last_reconciled_at", "reconciliation_claimed_at");



CREATE INDEX "storekit_transactions_user_status_expires_at_idx" ON "internal"."storekit_transactions" USING "btree" ("user_id", "status", "expires_at");



CREATE INDEX "streak_restorations_couple_restored_at_idx" ON "internal"."streak_restorations" USING "btree" ("couple_id", "restored_at" DESC);



CREATE INDEX "streak_restorations_product_id_fk_idx" ON "internal"."streak_restorations" USING "btree" ("product_id");



CREATE INDEX "streak_restorations_purchaser_idx" ON "internal"."streak_restorations" USING "btree" ("purchaser_user_id", "restored_at" DESC);



CREATE INDEX "streak_restorations_raw_payload_id_fk_idx" ON "internal"."streak_restorations" USING "btree" ("raw_payload_id");



CREATE INDEX "widget_push_outbox_due_idx" ON "internal"."widget_push_outbox" USING "btree" ("scheduled_for", "id") WHERE (("sent_at" IS NULL) AND ("failed_at" IS NULL));



CREATE UNIQUE INDEX "widget_push_outbox_pending_dedupe_idx" ON "internal"."widget_push_outbox" USING "btree" ("target_widget_device_id", "dedupe_key") WHERE (("sent_at" IS NULL) AND ("failed_at" IS NULL) AND ("dedupe_key" IS NOT NULL));



CREATE INDEX "widget_push_outbox_recipient_user_id_fk_idx" ON "internal"."widget_push_outbox" USING "btree" ("recipient_user_id");



CREATE INDEX "content_report_targets_conduct_user_id_idx" ON "public"."content_report_targets" USING "btree" ("conduct_user_id") WHERE ("conduct_user_id" IS NOT NULL);



CREATE INDEX "content_report_targets_daily_answer_id_idx" ON "public"."content_report_targets" USING "btree" ("daily_answer_id") WHERE ("daily_answer_id" IS NOT NULL);



CREATE INDEX "content_report_targets_media_asset_id_idx" ON "public"."content_report_targets" USING "btree" ("media_asset_id") WHERE ("media_asset_id" IS NOT NULL);



CREATE INDEX "content_report_targets_memory_id_idx" ON "public"."content_report_targets" USING "btree" ("memory_id") WHERE ("memory_id" IS NOT NULL);



CREATE INDEX "content_report_targets_memory_media_id_idx" ON "public"."content_report_targets" USING "btree" ("memory_media_id") WHERE ("memory_media_id" IS NOT NULL);



CREATE INDEX "content_report_targets_memory_note_id_idx" ON "public"."content_report_targets" USING "btree" ("memory_note_id") WHERE ("memory_note_id" IS NOT NULL);



CREATE INDEX "content_report_targets_message_id_idx" ON "public"."content_report_targets" USING "btree" ("message_id") WHERE ("message_id" IS NOT NULL);



CREATE INDEX "content_report_targets_message_media_idx" ON "public"."content_report_targets" USING "btree" ("message_media_message_id", "message_media_asset_id") WHERE ("message_media_message_id" IS NOT NULL);



CREATE INDEX "content_report_targets_profile_user_id_idx" ON "public"."content_report_targets" USING "btree" ("profile_user_id") WHERE ("profile_user_id" IS NOT NULL);



CREATE INDEX "content_report_targets_widget_revision_id_idx" ON "public"."content_report_targets" USING "btree" ("widget_drawing_revision_id") WHERE ("widget_drawing_revision_id" IS NOT NULL);



CREATE INDEX "content_reports_couple_created_at_idx" ON "public"."content_reports" USING "btree" ("couple_id", "created_at" DESC);



CREATE INDEX "content_reports_pair_id_fk_idx" ON "public"."content_reports" USING "btree" ("pair_id") WHERE ("pair_id" IS NOT NULL);



CREATE INDEX "content_reports_reported_created_at_idx" ON "public"."content_reports" USING "btree" ("reported_user_id", "created_at" DESC);



CREATE INDEX "content_reports_reporter_created_at_idx" ON "public"."content_reports" USING "btree" ("reporter_user_id", "created_at" DESC);



CREATE INDEX "content_reports_status_created_at_idx" ON "public"."content_reports" USING "btree" ("status", "created_at");



CREATE INDEX "conversation_threads_couple_created_at_idx" ON "public"."conversation_threads" USING "btree" ("couple_id", "created_at" DESC);



CREATE INDEX "conversation_threads_couple_visibility_idx" ON "public"."conversation_threads" USING "btree" ("couple_id", "moderation_status", "deleted_at");



CREATE INDEX "conversation_threads_created_by_user_id_fk_idx" ON "public"."conversation_threads" USING "btree" ("created_by_user_id") WHERE ("created_by_user_id" IS NOT NULL);



CREATE INDEX "conversation_threads_moderated_by_fk_idx" ON "public"."conversation_threads" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "conversation_threads_moderation_report_id_fk_idx" ON "public"."conversation_threads" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "couple_activity_events_couple_day_id_fk_idx" ON "public"."couple_activity_events" USING "btree" ("couple_day_id") WHERE ("couple_day_id" IS NOT NULL);



CREATE INDEX "couple_activity_events_couple_day_kind_idx" ON "public"."couple_activity_events" USING "btree" ("couple_id", "couple_day_id", "activity_kind");



CREATE INDEX "couple_activity_events_user_created_at_idx" ON "public"."couple_activity_events" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "couple_days_current_window_idx" ON "public"."couple_days" USING "btree" ("couple_id", "starts_at" DESC, "ends_at") INCLUDE ("id", "local_date");



CREATE INDEX "couple_members_couple_user_status_idx" ON "public"."couple_members" USING "btree" ("couple_id", "user_id", "status");



CREATE UNIQUE INDEX "couple_members_one_active_couple_per_user_idx" ON "public"."couple_members" USING "btree" ("user_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "couple_members_user_status_couple_idx" ON "public"."couple_members" USING "btree" ("user_id", "status", "couple_id");



CREATE INDEX "couples_id_status_idx" ON "public"."couples" USING "btree" ("id", "status");



CREATE INDEX "couples_pair_status_idx" ON "public"."couples" USING "btree" ("pair_id", "status");



CREATE INDEX "couples_status_delete_after_idx" ON "public"."couples" USING "btree" ("status", "delete_after");



CREATE INDEX "daily_answer_media_media_asset_id_idx" ON "public"."daily_answer_media" USING "btree" ("media_asset_id");



CREATE INDEX "daily_answer_partner_choice_selected_user_id_fk_idx" ON "public"."daily_answer_partner_choice" USING "btree" ("selected_user_id") WHERE ("selected_user_id" IS NOT NULL);



CREATE INDEX "daily_challenges_user_id_fk_idx" ON "public"."daily_challenges" USING "btree" ("user_id") WHERE ("user_id" IS NOT NULL);



CREATE INDEX "daily_question_answers_instance_user_idx" ON "public"."daily_question_answers" USING "btree" ("instance_id", "user_id");



CREATE INDEX "daily_question_answers_moderated_by_idx" ON "public"."daily_question_answers" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "daily_question_answers_moderation_report_id_fk_idx" ON "public"."daily_question_answers" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "daily_question_answers_user_created_at_idx" ON "public"."daily_question_answers" USING "btree" ("user_id", "created_at" DESC);



CREATE UNIQUE INDEX "daily_question_instances_active_slot_unique_idx" ON "public"."daily_question_instances" USING "btree" ("couple_day_id", "seeded_for_user_id", "slot_number") WHERE ("status" = 'active'::"text");



CREATE INDEX "daily_question_instances_couple_day_question_version_idx" ON "public"."daily_question_instances" USING "btree" ("couple_day_id", "question_version_id");



CREATE INDEX "daily_question_instances_question_version_id_fk_idx" ON "public"."daily_question_instances" USING "btree" ("question_version_id") WHERE ("question_version_id" IS NOT NULL);



CREATE INDEX "daily_question_instances_replaced_by_instance_id_idx" ON "public"."daily_question_instances" USING "btree" ("replaced_by_instance_id") WHERE ("replaced_by_instance_id" IS NOT NULL);



CREATE INDEX "daily_question_instances_seeded_status_idx" ON "public"."daily_question_instances" USING "btree" ("seeded_for_user_id", "status");



CREATE INDEX "daily_question_shuffles_couple_day_user_idx" ON "public"."daily_question_shuffles" USING "btree" ("couple_day_id", "user_id");



CREATE INDEX "daily_question_shuffles_couple_id_fk_idx" ON "public"."daily_question_shuffles" USING "btree" ("couple_id") WHERE ("couple_id" IS NOT NULL);



CREATE INDEX "daily_question_shuffles_question_id_fk_idx" ON "public"."daily_question_shuffles" USING "btree" ("question_id") WHERE ("question_id" IS NOT NULL);



CREATE INDEX "daily_question_shuffles_replacement_instance_idx" ON "public"."daily_question_shuffles" USING "btree" ("replacement_instance_id");



CREATE INDEX "daily_question_shuffles_skipped_instance_id_fk_idx" ON "public"."daily_question_shuffles" USING "btree" ("skipped_instance_id") WHERE ("skipped_instance_id" IS NOT NULL);



CREATE INDEX "daily_question_shuffles_user_question_exclude_until_idx" ON "public"."daily_question_shuffles" USING "btree" ("user_id", "question_id", "exclude_until");



CREATE INDEX "latest_partner_locations_user_updated_at_idx" ON "public"."latest_partner_locations" USING "btree" ("user_id", "updated_at" DESC);



CREATE INDEX "location_sharing_preferences_user_id_fk_idx" ON "public"."location_sharing_preferences" USING "btree" ("user_id") WHERE ("user_id" IS NOT NULL);



CREATE UNIQUE INDEX "media_assets_bucket_storage_path_unique_idx" ON "public"."media_assets" USING "btree" ("bucket", "storage_path");



CREATE INDEX "media_assets_couple_created_at_idx" ON "public"."media_assets" USING "btree" ("couple_id", "created_at" DESC);



CREATE INDEX "media_assets_moderated_by_idx" ON "public"."media_assets" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "media_assets_moderation_report_id_fk_idx" ON "public"."media_assets" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "media_assets_owner_created_at_idx" ON "public"."media_assets" USING "btree" ("owner_user_id", "created_at" DESC);



CREATE INDEX "media_assets_reserved_parent_idx" ON "public"."media_assets" USING "btree" ("reserved_parent_kind", "reserved_parent_id");



CREATE INDEX "media_assets_sha256_idx" ON "public"."media_assets" USING "btree" ("sha256") WHERE ("sha256" IS NOT NULL);



CREATE INDEX "media_assets_storage_delete_retry_idx" ON "public"."media_assets" USING "btree" ("storage_delete_status", "storage_delete_attempts", "updated_at");



CREATE INDEX "media_assets_upload_status_expires_at_idx" ON "public"."media_assets" USING "btree" ("upload_status", "upload_expires_at");



CREATE INDEX "memories_couple_memory_date_id_idx" ON "public"."memories" USING "btree" ("couple_id", "memory_date" DESC, "id");



CREATE INDEX "memories_couple_updated_at_id_idx" ON "public"."memories" USING "btree" ("couple_id", "updated_at", "id");



CREATE INDEX "memories_created_by_user_id_fk_idx" ON "public"."memories" USING "btree" ("created_by_user_id") WHERE ("created_by_user_id" IS NOT NULL);



CREATE INDEX "memories_last_edited_by_user_id_fk_idx" ON "public"."memories" USING "btree" ("last_edited_by_user_id") WHERE ("last_edited_by_user_id" IS NOT NULL);



CREATE INDEX "memories_moderated_by_fk_idx" ON "public"."memories" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "memories_moderation_report_id_fk_idx" ON "public"."memories" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "memories_visibility_idx" ON "public"."memories" USING "btree" ("couple_id", "moderation_status", "deleted_at");



CREATE UNIQUE INDEX "memory_media_active_owner_sort_order_idx" ON "public"."memory_media" USING "btree" ("memory_id", "owner_user_id", "sort_order") WHERE ("deleted_at" IS NULL);



CREATE INDEX "memory_media_media_asset_id_idx" ON "public"."memory_media" USING "btree" ("media_asset_id");



CREATE INDEX "memory_media_memory_sort_order_idx" ON "public"."memory_media" USING "btree" ("memory_id", "sort_order");



CREATE INDEX "memory_media_memory_updated_at_idx" ON "public"."memory_media" USING "btree" ("memory_id", "updated_at");



CREATE INDEX "memory_media_moderated_by_fk_idx" ON "public"."memory_media" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "memory_media_moderation_report_id_fk_idx" ON "public"."memory_media" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "memory_media_owner_memory_idx" ON "public"."memory_media" USING "btree" ("owner_user_id", "memory_id");



CREATE INDEX "memory_media_visibility_idx" ON "public"."memory_media" USING "btree" ("memory_id", "moderation_status", "deleted_at");



CREATE INDEX "memory_notes_memory_updated_at_idx" ON "public"."memory_notes" USING "btree" ("memory_id", "updated_at");



CREATE INDEX "memory_notes_memory_visibility_idx" ON "public"."memory_notes" USING "btree" ("memory_id", "moderation_status", "deleted_at");



CREATE INDEX "memory_notes_moderated_by_fk_idx" ON "public"."memory_notes" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "memory_notes_moderation_report_id_fk_idx" ON "public"."memory_notes" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "memory_notes_user_updated_at_idx" ON "public"."memory_notes" USING "btree" ("user_id", "updated_at" DESC);



CREATE INDEX "pairing_invites_couple_id_fk_idx" ON "public"."pairing_invites" USING "btree" ("couple_id") WHERE ("couple_id" IS NOT NULL);



CREATE INDEX "pairing_invites_created_by_status_expires_at_idx" ON "public"."pairing_invites" USING "btree" ("created_by_user_id", "status", "expires_at");



CREATE INDEX "pairing_invites_status_expires_at_cleanup_idx" ON "public"."pairing_invites" USING "btree" ("status", "expires_at");



CREATE UNIQUE INDEX "privacy_requests_active_deletion_user_idx" ON "public"."privacy_requests" USING "btree" ("user_id") WHERE (("request_kind" = 'deletion'::"text") AND ("status" = ANY (ARRAY['submitted'::"text", 'verifying'::"text", 'processing'::"text"])));



CREATE INDEX "privacy_requests_user_requested_at_idx" ON "public"."privacy_requests" USING "btree" ("user_id", "requested_at" DESC);



CREATE INDEX "privacy_requests_user_updated_at_id_idx" ON "public"."privacy_requests" USING "btree" ("user_id", "updated_at", "id");



CREATE INDEX "profiles_moderation_report_id_fk_idx" ON "public"."profiles" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "profiles_profile_photo_asset_id_idx" ON "public"."profiles" USING "btree" ("profile_photo_asset_id") WHERE ("profile_photo_asset_id" IS NOT NULL);



CREATE INDEX "profiles_provider_profile_photo_asset_id_idx" ON "public"."profiles" USING "btree" ("provider_profile_photo_asset_id") WHERE ("provider_profile_photo_asset_id" IS NOT NULL);



CREATE INDEX "profiles_updated_at_user_id_idx" ON "public"."profiles" USING "btree" ("updated_at", "user_id");



CREATE INDEX "question_collections_couple_id_idx" ON "public"."question_collections" USING "btree" ("couple_id") WHERE ("couple_id" IS NOT NULL);



CREATE INDEX "question_collections_created_by_user_id_fk_idx" ON "public"."question_collections" USING "btree" ("created_by_user_id") WHERE ("created_by_user_id" IS NOT NULL);



CREATE INDEX "question_collections_kind_status_idx" ON "public"."question_collections" USING "btree" ("kind", "status");



CREATE UNIQUE INDEX "question_collections_one_active_system_idx" ON "public"."question_collections" USING "btree" ("kind") WHERE (("kind" = 'system'::"text") AND ("status" = 'active'::"text"));



CREATE INDEX "question_version_localizations_locale_idx" ON "public"."question_version_localizations" USING "btree" ("locale");



CREATE UNIQUE INDEX "question_versions_one_active_per_question_idx" ON "public"."question_versions" USING "btree" ("question_id") WHERE ("status" = 'active'::"text");



CREATE INDEX "question_versions_question_status_idx" ON "public"."question_versions" USING "btree" ("question_id", "status");



CREATE INDEX "questions_collection_status_idx" ON "public"."questions" USING "btree" ("collection_id", "status");



CREATE INDEX "questions_created_by_user_id_fk_idx" ON "public"."questions" USING "btree" ("created_by_user_id") WHERE ("created_by_user_id" IS NOT NULL);



CREATE UNIQUE INDEX "relationship_blocks_active_pair_direction_idx" ON "public"."relationship_blocks" USING "btree" ("pair_id", "blocked_by_user_id", "blocked_user_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "relationship_blocks_pair_revoked_at_idx" ON "public"."relationship_blocks" USING "btree" ("pair_id", "revoked_at");



CREATE INDEX "relationship_blocks_source_report_id_fk_idx" ON "public"."relationship_blocks" USING "btree" ("source_report_id") WHERE ("source_report_id" IS NOT NULL);



CREATE INDEX "relationship_sync_events_couple_created_at_id_idx" ON "public"."relationship_sync_events" USING "btree" ("couple_id", "created_at", "id");



CREATE INDEX "relationship_sync_events_user_created_at_id_idx" ON "public"."relationship_sync_events" USING "btree" ("user_id", "created_at", "id");



CREATE INDEX "streak_states_last_qualified_couple_day_id_fk_idx" ON "public"."streak_states" USING "btree" ("last_qualified_couple_day_id") WHERE ("last_qualified_couple_day_id" IS NOT NULL);



CREATE INDEX "subscription_products_is_active_kind_idx" ON "public"."subscription_products" USING "btree" ("is_active", "kind");



CREATE INDEX "thread_message_media_media_asset_id_idx" ON "public"."thread_message_media" USING "btree" ("media_asset_id");



CREATE INDEX "thread_messages_moderated_by_fk_idx" ON "public"."thread_messages" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "thread_messages_moderation_report_id_fk_idx" ON "public"."thread_messages" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "thread_messages_sender_created_at_idx" ON "public"."thread_messages" USING "btree" ("sender_user_id", "created_at" DESC);



CREATE INDEX "thread_messages_thread_created_at_id_idx" ON "public"."thread_messages" USING "btree" ("thread_id", "created_at", "id");



CREATE INDEX "thread_messages_thread_visibility_idx" ON "public"."thread_messages" USING "btree" ("thread_id", "moderation_status", "deleted_at", "created_at");



CREATE UNIQUE INDEX "user_devices_active_token_hash_idx" ON "public"."user_devices" USING "btree" ("push_token_hash", "apns_environment") WHERE ("disabled_at" IS NULL);



CREATE INDEX "user_devices_user_disabled_at_idx" ON "public"."user_devices" USING "btree" ("user_id", "disabled_at");



CREATE INDEX "user_devices_user_updated_at_id_idx" ON "public"."user_devices" USING "btree" ("user_id", "updated_at", "id");



CREATE INDEX "widget_canvases_active_revision_id_fk_idx" ON "public"."widget_canvases" USING "btree" ("active_revision_id") WHERE ("active_revision_id" IS NOT NULL);



CREATE INDEX "widget_drawing_revisions_author_created_at_idx" ON "public"."widget_drawing_revisions" USING "btree" ("author_user_id", "created_at" DESC);



CREATE INDEX "widget_drawing_revisions_canvas_created_at_id_idx" ON "public"."widget_drawing_revisions" USING "btree" ("canvas_id", "created_at" DESC, "id" DESC);



CREATE INDEX "widget_drawing_revisions_canvas_updated_at_id_idx" ON "public"."widget_drawing_revisions" USING "btree" ("canvas_id", "updated_at", "id");



CREATE INDEX "widget_drawing_revisions_moderated_by_fk_idx" ON "public"."widget_drawing_revisions" USING "btree" ("moderated_by") WHERE ("moderated_by" IS NOT NULL);



CREATE INDEX "widget_drawing_revisions_moderation_report_id_fk_idx" ON "public"."widget_drawing_revisions" USING "btree" ("moderation_report_id") WHERE ("moderation_report_id" IS NOT NULL);



CREATE INDEX "widget_drawing_revisions_parent_revision_id_idx" ON "public"."widget_drawing_revisions" USING "btree" ("parent_revision_id") WHERE ("parent_revision_id" IS NOT NULL);



CREATE UNIQUE INDEX "widget_push_devices_active_token_environment_kind_idx" ON "public"."widget_push_devices" USING "btree" ("widget_push_token_hash", "apns_environment", "widget_kind") WHERE ("disabled_at" IS NULL);



CREATE INDEX "widget_push_devices_user_id_idx" ON "public"."widget_push_devices" USING "btree" ("user_id") WHERE ("disabled_at" IS NULL);



CREATE OR REPLACE TRIGGER "assert_notification_outbox_payload_safe" BEFORE INSERT OR UPDATE OF "payload" ON "internal"."notification_outbox" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_notification_payload_safe"();



CREATE OR REPLACE TRIGGER "invalidate_trial_reminder_after_storekit_delete" AFTER DELETE ON "internal"."storekit_transactions" FOR EACH ROW EXECUTE FUNCTION "internal"."invalidate_subscription_trial_reminder"();



CREATE OR REPLACE TRIGGER "invalidate_trial_reminder_after_storekit_update" AFTER UPDATE OF "status", "expires_at" ON "internal"."storekit_transactions" FOR EACH ROW EXECUTE FUNCTION "internal"."invalidate_subscription_trial_reminder"();



CREATE OR REPLACE TRIGGER "invoke_account_deletion_drain_on_jobs" AFTER INSERT OR UPDATE OF "status", "next_attempt_at" ON "internal"."account_deletion_jobs" FOR EACH STATEMENT EXECUTE FUNCTION "internal"."invoke_account_deletion_drain"();



CREATE OR REPLACE TRIGGER "invoke_push_notification_drain_on_notification_outbox" AFTER INSERT ON "internal"."notification_outbox" FOR EACH STATEMENT EXECUTE FUNCTION "internal"."invoke_push_notification_drain"();



CREATE OR REPLACE TRIGGER "invoke_push_notification_drain_on_widget_push_outbox" AFTER INSERT ON "internal"."widget_push_outbox" FOR EACH STATEMENT EXECUTE FUNCTION "internal"."invoke_push_notification_drain"();



CREATE OR REPLACE TRIGGER "reject_pending_account_client_operation" BEFORE INSERT OR UPDATE ON "internal"."client_operations" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "set_account_deletion_jobs_updated_at" BEFORE UPDATE ON "internal"."account_deletion_jobs" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_app_account_tokens_updated_at" BEFORE UPDATE ON "internal"."app_account_tokens" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_client_operations_updated_at" BEFORE UPDATE ON "internal"."client_operations" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_entitlement_grants_updated_at" BEFORE UPDATE ON "internal"."entitlement_grants" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_moderation_actions_updated_at" BEFORE UPDATE ON "internal"."moderation_actions" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_report_snapshot_assets_updated_at" BEFORE UPDATE ON "internal"."report_snapshot_assets" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_storekit_transactions_updated_at" BEFORE UPDATE ON "internal"."storekit_transactions" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "assert_conversation_thread_allowed" BEFORE INSERT OR UPDATE OF "couple_id", "created_by_user_id" ON "public"."conversation_threads" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_conversation_thread_allowed"();



CREATE OR REPLACE TRIGGER "assert_daily_answer_media_allowed" BEFORE INSERT OR UPDATE ON "public"."daily_answer_media" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_answer_media_allowed"();



CREATE OR REPLACE TRIGGER "assert_daily_answer_partner_choice_allowed" BEFORE INSERT OR UPDATE ON "public"."daily_answer_partner_choice" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_answer_partner_choice_allowed"();



CREATE OR REPLACE TRIGGER "assert_daily_answer_text_allowed" BEFORE INSERT OR UPDATE ON "public"."daily_answer_text" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_answer_text_allowed"();



CREATE OR REPLACE TRIGGER "assert_daily_challenge_member" BEFORE INSERT OR UPDATE ON "public"."daily_challenges" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_challenge_member"();



CREATE OR REPLACE TRIGGER "assert_daily_question_answer_member" BEFORE INSERT OR UPDATE ON "public"."daily_question_answers" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_question_answer_member"();



CREATE OR REPLACE TRIGGER "assert_daily_question_instance_member" BEFORE INSERT OR UPDATE ON "public"."daily_question_instances" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_question_instance_member"();



CREATE OR REPLACE TRIGGER "assert_daily_question_shuffle_valid" BEFORE INSERT OR UPDATE ON "public"."daily_question_shuffles" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_question_shuffle_valid"();



CREATE OR REPLACE TRIGGER "assert_daily_question_thread_allowed" BEFORE INSERT OR UPDATE ON "public"."daily_question_threads" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_daily_question_thread_allowed"();



CREATE OR REPLACE TRIGGER "assert_memory_media_allowed" BEFORE INSERT OR UPDATE OF "id", "memory_id", "media_asset_id", "owner_user_id" ON "public"."memory_media" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_memory_media_allowed"();



CREATE OR REPLACE TRIGGER "assert_memory_member_allowed" BEFORE INSERT OR UPDATE OF "couple_id", "created_by_user_id", "last_edited_by_user_id" ON "public"."memories" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_memory_member_allowed"();



CREATE OR REPLACE TRIGGER "assert_memory_note_allowed" BEFORE INSERT OR UPDATE OF "memory_id", "user_id" ON "public"."memory_notes" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_memory_note_allowed"();



CREATE OR REPLACE TRIGGER "assert_memory_thread_allowed" BEFORE INSERT OR UPDATE ON "public"."memory_threads" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_memory_thread_allowed"();



CREATE OR REPLACE TRIGGER "assert_profiles_profile_photo_asset_owner" BEFORE INSERT OR UPDATE OF "profile_photo_asset_id", "provider_profile_photo_asset_id", "provider_profile_photo_source", "deleted_at" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_profile_photo_asset_owner"();



CREATE CONSTRAINT TRIGGER "assert_question_answer_kinds_ready" AFTER INSERT OR DELETE OR UPDATE ON "public"."question_answer_kinds" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."assert_question_version_child_ready_trigger"();



CREATE CONSTRAINT TRIGGER "assert_question_collections_ready" AFTER INSERT OR DELETE OR UPDATE ON "public"."question_collections" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."assert_question_collection_ready_trigger"();



CREATE CONSTRAINT TRIGGER "assert_question_version_localizations_ready" AFTER INSERT OR DELETE OR UPDATE ON "public"."question_version_localizations" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."assert_question_version_child_ready_trigger"();



CREATE CONSTRAINT TRIGGER "assert_question_versions_ready" AFTER INSERT OR DELETE OR UPDATE ON "public"."question_versions" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."assert_question_version_ready_trigger"();



CREATE CONSTRAINT TRIGGER "assert_questions_ready" AFTER INSERT OR DELETE OR UPDATE ON "public"."questions" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."assert_question_ready_trigger"();



CREATE OR REPLACE TRIGGER "assert_relationship_block_pair_members" BEFORE INSERT OR UPDATE ON "public"."relationship_blocks" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_relationship_block_pair_members"();



CREATE OR REPLACE TRIGGER "assert_thread_message_allowed" BEFORE INSERT OR UPDATE OF "thread_id", "sender_user_id" ON "public"."thread_messages" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_thread_message_allowed"();



CREATE OR REPLACE TRIGGER "assert_thread_message_media_allowed" BEFORE INSERT OR UPDATE ON "public"."thread_message_media" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_thread_message_media_allowed"();



CREATE OR REPLACE TRIGGER "assert_widget_canvas_active_revision_allowed" BEFORE INSERT OR UPDATE OF "active_revision_id" ON "public"."widget_canvases" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_widget_canvas_active_revision_allowed"();



CREATE OR REPLACE TRIGGER "assert_widget_canvas_couple_allowed" BEFORE INSERT OR UPDATE OF "couple_id", "deleted_at" ON "public"."widget_canvases" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_widget_canvas_couple_allowed"();



CREATE OR REPLACE TRIGGER "assert_widget_drawing_revision_allowed" BEFORE INSERT OR UPDATE OF "canvas_id", "author_user_id", "parent_revision_id", "payload_media_asset_id", "payload_bytes" ON "public"."widget_drawing_revisions" FOR EACH ROW EXECUTE FUNCTION "internal"."assert_widget_drawing_revision_allowed"();



CREATE OR REPLACE TRIGGER "delete_latest_locations_on_preference_disable" AFTER INSERT OR UPDATE OF "is_enabled" ON "public"."location_sharing_preferences" FOR EACH ROW EXECUTE FUNCTION "internal"."delete_latest_locations_on_preference_disable"();



CREATE OR REPLACE TRIGGER "delete_latest_locations_on_relationship_end" AFTER UPDATE OF "status" ON "public"."couples" FOR EACH ROW EXECUTE FUNCTION "internal"."delete_latest_locations_on_relationship_end"();



CREATE OR REPLACE TRIGGER "enqueue_memory_created_notification" AFTER INSERT ON "public"."memories" FOR EACH ROW EXECUTE FUNCTION "internal"."enqueue_memory_created_notification"();


CREATE OR REPLACE TRIGGER "enqueue_partner_answered_notification" AFTER INSERT ON "public"."daily_question_answers" FOR EACH ROW EXECUTE FUNCTION "internal"."enqueue_partner_answered_notification"();



CREATE OR REPLACE TRIGGER "handle_daily_challenge_completed" BEFORE UPDATE OF "completed_at" ON "public"."daily_challenges" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_daily_challenge_completed"();



CREATE OR REPLACE TRIGGER "handle_thread_message_created" AFTER INSERT ON "public"."thread_messages" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_thread_message_created"();



CREATE OR REPLACE TRIGGER "handle_widget_drawing_revision_created" AFTER INSERT ON "public"."widget_drawing_revisions" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_widget_drawing_revision_created"();



CREATE OR REPLACE TRIGGER "invoke_media_storage_cleanup_on_media_assets" AFTER UPDATE OF "storage_delete_status" ON "public"."media_assets" FOR EACH STATEMENT EXECUTE FUNCTION "internal"."invoke_media_storage_cleanup"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_daily_answer_media_after_answer_delete" AFTER UPDATE OF "deleted_at" ON "public"."daily_question_answers" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL))) EXECUTE FUNCTION "internal"."queue_daily_answer_media_assets_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_daily_answer_media_after_delete" AFTER DELETE ON "public"."daily_answer_media" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_daily_answer_media_after_update" AFTER UPDATE OF "media_asset_id" ON "public"."daily_answer_media" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (("old"."media_asset_id" IS DISTINCT FROM "new"."media_asset_id")) EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_memory_media_after_delete" AFTER DELETE ON "public"."memory_media" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_memory_media_after_memory_delete" AFTER UPDATE OF "deleted_at" ON "public"."memories" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL))) EXECUTE FUNCTION "internal"."queue_memory_media_assets_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_memory_media_after_update" AFTER UPDATE OF "media_asset_id", "deleted_at" ON "public"."memory_media" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."media_asset_id" IS DISTINCT FROM "new"."media_asset_id") OR (("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL)))) EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_profile_photo_after_delete" AFTER DELETE ON "public"."profiles" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (("old"."profile_photo_asset_id" IS NOT NULL)) EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_profile_photo_after_update" AFTER UPDATE OF "profile_photo_asset_id", "provider_profile_photo_asset_id", "provider_profile_photo_source", "deleted_at" ON "public"."profiles" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((("old"."profile_photo_asset_id" IS NOT NULL) AND (("old"."profile_photo_asset_id" IS DISTINCT FROM "new"."profile_photo_asset_id") OR (("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL)))) OR (("old"."provider_profile_photo_asset_id" IS NOT NULL) AND (("old"."provider_profile_photo_asset_id" IS DISTINCT FROM "new"."provider_profile_photo_asset_id") OR (("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL)))))) EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_thread_media_after_thread_delete" AFTER UPDATE OF "deleted_at" ON "public"."conversation_threads" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL))) EXECUTE FUNCTION "internal"."queue_thread_media_assets_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_thread_message_media_after_delete" AFTER DELETE ON "public"."thread_message_media" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_thread_message_media_after_message_delete" AFTER UPDATE OF "deleted_at" ON "public"."thread_messages" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL))) EXECUTE FUNCTION "internal"."queue_thread_message_media_assets_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_thread_message_media_after_update" AFTER UPDATE OF "media_asset_id" ON "public"."thread_message_media" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (("old"."media_asset_id" IS DISTINCT FROM "new"."media_asset_id")) EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_widget_payload_after_canvas_delete" AFTER UPDATE OF "deleted_at" ON "public"."widget_canvases" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL))) EXECUTE FUNCTION "internal"."queue_widget_payloads_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_widget_payload_after_delete" AFTER DELETE ON "public"."widget_drawing_revisions" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE CONSTRAINT TRIGGER "queue_orphaned_widget_payload_after_update" AFTER UPDATE OF "payload_media_asset_id", "deleted_at" ON "public"."widget_drawing_revisions" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((("old"."payload_media_asset_id" IS DISTINCT FROM "new"."payload_media_asset_id") OR (("old"."deleted_at" IS NULL) AND ("new"."deleted_at" IS NOT NULL)))) EXECUTE FUNCTION "internal"."queue_old_media_asset_if_orphaned"();



CREATE OR REPLACE TRIGGER "refresh_streak_after_device_time_zone_change" AFTER INSERT OR UPDATE OF "time_zone_id", "last_seen_at", "disabled_at" ON "public"."user_devices" FOR EACH ROW EXECUTE FUNCTION "internal"."refresh_streak_after_device_time_zone_change"();



CREATE OR REPLACE TRIGGER "refresh_streak_after_profile_time_zone_change" AFTER UPDATE OF "time_zone_id" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "internal"."refresh_streak_after_profile_time_zone_change"();



CREATE OR REPLACE TRIGGER "reject_pending_account_latest_location" BEFORE INSERT OR UPDATE ON "public"."latest_partner_locations" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "reject_pending_account_location_preference" BEFORE INSERT OR UPDATE ON "public"."location_sharing_preferences" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "reject_pending_account_notification_preference" BEFORE INSERT OR UPDATE ON "public"."notification_preferences" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "reject_pending_account_privacy_request" BEFORE INSERT ON "public"."privacy_requests" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "reject_pending_account_user_device" BEFORE INSERT OR UPDATE ON "public"."user_devices" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "reject_pending_account_widget_device" BEFORE INSERT OR UPDATE ON "public"."widget_push_devices" FOR EACH ROW EXECUTE FUNCTION "internal"."reject_pending_account_client_operation"();



CREATE OR REPLACE TRIGGER "set_content_reports_updated_at" BEFORE UPDATE ON "public"."content_reports" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_conversation_threads_updated_at" BEFORE UPDATE ON "public"."conversation_threads" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_couple_members_updated_at" BEFORE UPDATE ON "public"."couple_members" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_couples_updated_at" BEFORE UPDATE ON "public"."couples" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_daily_question_answers_updated_at" BEFORE UPDATE ON "public"."daily_question_answers" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_latest_partner_locations_updated_at" BEFORE UPDATE ON "public"."latest_partner_locations" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_location_sharing_preferences_updated_at" BEFORE UPDATE ON "public"."location_sharing_preferences" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_media_assets_updated_at" BEFORE UPDATE ON "public"."media_assets" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_memory_media_updated_at" BEFORE UPDATE ON "public"."memory_media" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_pairing_invites_updated_at" BEFORE UPDATE ON "public"."pairing_invites" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_question_collections_updated_at" BEFORE UPDATE ON "public"."question_collections" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_question_version_localizations_updated_at" BEFORE UPDATE ON "public"."question_version_localizations" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_questions_updated_at" BEFORE UPDATE ON "public"."questions" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_relationship_sync_events_updated_at" BEFORE UPDATE ON "public"."relationship_sync_events" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_streak_states_updated_at" BEFORE UPDATE ON "public"."streak_states" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_subscription_products_updated_at" BEFORE UPDATE ON "public"."subscription_products" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_thread_messages_updated_at" BEFORE UPDATE ON "public"."thread_messages" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_widget_canvases_updated_at" BEFORE UPDATE ON "public"."widget_canvases" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_widget_drawing_revisions_updated_at" BEFORE UPDATE ON "public"."widget_drawing_revisions" FOR EACH ROW EXECUTE FUNCTION "internal"."set_updated_at"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_daily_answer" BEFORE DELETE ON "public"."daily_question_answers" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_media_asset" BEFORE DELETE ON "public"."media_assets" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_memory" BEFORE DELETE ON "public"."memories" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_memory_media" BEFORE DELETE ON "public"."memory_media" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_memory_note" BEFORE DELETE ON "public"."memory_notes" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_profile" BEFORE DELETE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_thread_message" BEFORE DELETE ON "public"."thread_messages" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_thread_message_media" BEFORE DELETE ON "public"."thread_message_media" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "tombstone_content_report_target_widget_revision" BEFORE DELETE ON "public"."widget_drawing_revisions" FOR EACH ROW EXECUTE FUNCTION "internal"."tombstone_content_report_target"();



CREATE OR REPLACE TRIGGER "touch_memories_updated_at_and_revision" BEFORE UPDATE ON "public"."memories" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



CREATE OR REPLACE TRIGGER "touch_memory_notes_updated_at_and_revision" BEFORE UPDATE ON "public"."memory_notes" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



CREATE OR REPLACE TRIGGER "touch_notification_preferences_updated_at_and_revision" BEFORE UPDATE ON "public"."notification_preferences" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



CREATE OR REPLACE TRIGGER "touch_privacy_requests_updated_at_and_revision" BEFORE UPDATE ON "public"."privacy_requests" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



CREATE OR REPLACE TRIGGER "touch_profiles_updated_at_and_revision" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



CREATE OR REPLACE TRIGGER "touch_user_devices_updated_at_and_revision" BEFORE UPDATE ON "public"."user_devices" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



CREATE OR REPLACE TRIGGER "touch_widget_push_devices_updated_at_and_revision" BEFORE UPDATE ON "public"."widget_push_devices" FOR EACH ROW EXECUTE FUNCTION "internal"."touch_updated_at_and_revision"();



ALTER TABLE ONLY "internal"."account_deletion_jobs"
    ADD CONSTRAINT "account_deletion_jobs_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."privacy_requests"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."app_account_tokens"
    ADD CONSTRAINT "app_account_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."client_operations"
    ADD CONSTRAINT "client_operations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."subscription_products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."entitlement_grants"
    ADD CONSTRAINT "entitlement_grants_source_review_session_id_fkey" FOREIGN KEY ("source_review_session_id") REFERENCES "internal"."review_access_sessions"("id") ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "internal"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."content_reports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."moderation_actions"
    ADD CONSTRAINT "moderation_actions_reviewer_user_id_fkey" FOREIGN KEY ("reviewer_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."notification_outbox"
    ADD CONSTRAINT "notification_outbox_recipient_user_id_fkey" FOREIGN KEY ("recipient_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."notification_outbox"
    ADD CONSTRAINT "notification_outbox_target_device_id_fkey" FOREIGN KEY ("target_device_id") REFERENCES "public"."user_devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."pair_safety_warning_flags"
    ADD CONSTRAINT "pair_safety_warning_flags_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "public"."relationship_pairs"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."pair_safety_warning_flags"
    ADD CONSTRAINT "pair_safety_warning_flags_source_report_id_fkey" FOREIGN KEY ("source_report_id") REFERENCES "public"."content_reports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."pairing_invite_attempts"
    ADD CONSTRAINT "pairing_invite_attempts_matched_invite_id_fkey" FOREIGN KEY ("matched_invite_id") REFERENCES "public"."pairing_invites"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."pairing_invite_secrets"
    ADD CONSTRAINT "pairing_invite_secrets_invite_id_fkey" FOREIGN KEY ("invite_id") REFERENCES "public"."pairing_invites"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."privacy_request_events"
    ADD CONSTRAINT "privacy_request_events_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."privacy_requests"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."report_snapshot_assets"
    ADD CONSTRAINT "report_snapshot_assets_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."content_reports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."report_snapshot_assets"
    ADD CONSTRAINT "report_snapshot_assets_source_media_asset_id_fkey" FOREIGN KEY ("source_media_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."report_snapshots"
    ADD CONSTRAINT "report_snapshots_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."content_reports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."review_access_attempts"
    ADD CONSTRAINT "review_access_attempts_matched_code_id_fkey" FOREIGN KEY ("matched_code_id") REFERENCES "internal"."review_access_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."review_access_sessions"
    ADD CONSTRAINT "review_access_sessions_code_id_fkey" FOREIGN KEY ("code_id") REFERENCES "internal"."review_access_codes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."review_access_sessions"
    ADD CONSTRAINT "review_access_sessions_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."review_access_sessions"
    ADD CONSTRAINT "review_access_sessions_entitlement_grant_id_fkey" FOREIGN KEY ("entitlement_grant_id") REFERENCES "internal"."entitlement_grants"("id") ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "internal"."review_demo_partners"
    ADD CONSTRAINT "review_demo_partners_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."storekit_notification_events"
    ADD CONSTRAINT "storekit_notification_events_raw_payload_id_fkey" FOREIGN KEY ("raw_payload_id") REFERENCES "internal"."storekit_payloads"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."storekit_transactions"
    ADD CONSTRAINT "storekit_transactions_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."subscription_products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."storekit_transactions"
    ADD CONSTRAINT "storekit_transactions_raw_payload_id_fkey" FOREIGN KEY ("raw_payload_id") REFERENCES "internal"."storekit_payloads"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."streak_restorations"
    ADD CONSTRAINT "streak_restorations_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."streak_restorations"
    ADD CONSTRAINT "streak_restorations_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."subscription_products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."streak_restorations"
    ADD CONSTRAINT "streak_restorations_raw_payload_id_fkey" FOREIGN KEY ("raw_payload_id") REFERENCES "internal"."storekit_payloads"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "internal"."widget_push_outbox"
    ADD CONSTRAINT "widget_push_outbox_recipient_user_id_fkey" FOREIGN KEY ("recipient_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."widget_push_outbox"
    ADD CONSTRAINT "widget_push_outbox_target_widget_device_id_fkey" FOREIGN KEY ("target_widget_device_id") REFERENCES "public"."widget_push_devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_daily_answer_id_fkey" FOREIGN KEY ("daily_answer_id") REFERENCES "public"."daily_question_answers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_memory_id_fkey" FOREIGN KEY ("memory_id") REFERENCES "public"."memories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_memory_media_id_fkey" FOREIGN KEY ("memory_media_id") REFERENCES "public"."memory_media"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_memory_note_id_fkey" FOREIGN KEY ("memory_note_id") REFERENCES "public"."memory_notes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."thread_messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_message_media_fkey" FOREIGN KEY ("message_media_message_id", "message_media_asset_id") REFERENCES "public"."thread_message_media"("message_id", "media_asset_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_profile_user_id_fkey" FOREIGN KEY ("profile_user_id") REFERENCES "public"."profiles"("user_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."content_reports"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_report_targets"
    ADD CONSTRAINT "content_report_targets_widget_drawing_revision_id_fkey" FOREIGN KEY ("widget_drawing_revision_id") REFERENCES "public"."widget_drawing_revisions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_reports"
    ADD CONSTRAINT "content_reports_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "public"."relationship_pairs"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."conversation_threads"
    ADD CONSTRAINT "conversation_threads_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_threads"
    ADD CONSTRAINT "conversation_threads_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."conversation_threads"
    ADD CONSTRAINT "conversation_threads_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."couple_activity_events"
    ADD CONSTRAINT "couple_activity_events_couple_day_id_fkey" FOREIGN KEY ("couple_day_id") REFERENCES "public"."couple_days"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."couple_activity_events"
    ADD CONSTRAINT "couple_activity_events_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."couple_days"
    ADD CONSTRAINT "couple_days_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."couple_members"
    ADD CONSTRAINT "couple_members_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."couples"
    ADD CONSTRAINT "couples_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "public"."relationship_pairs"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."daily_answer_media"
    ADD CONSTRAINT "daily_answer_media_answer_id_fkey" FOREIGN KEY ("answer_id") REFERENCES "public"."daily_question_answers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_answer_media"
    ADD CONSTRAINT "daily_answer_media_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_answer_partner_choice"
    ADD CONSTRAINT "daily_answer_partner_choice_answer_id_fkey" FOREIGN KEY ("answer_id") REFERENCES "public"."daily_question_answers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_answer_text"
    ADD CONSTRAINT "daily_answer_text_answer_id_fkey" FOREIGN KEY ("answer_id") REFERENCES "public"."daily_question_answers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_challenges"
    ADD CONSTRAINT "daily_challenges_couple_day_id_fkey" FOREIGN KEY ("couple_day_id") REFERENCES "public"."couple_days"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_answers"
    ADD CONSTRAINT "daily_question_answers_instance_id_fkey" FOREIGN KEY ("instance_id") REFERENCES "public"."daily_question_instances"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_answers"
    ADD CONSTRAINT "daily_question_answers_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_question_answers"
    ADD CONSTRAINT "daily_question_answers_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_question_instances"
    ADD CONSTRAINT "daily_question_instances_couple_day_id_fkey" FOREIGN KEY ("couple_day_id") REFERENCES "public"."couple_days"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_instances"
    ADD CONSTRAINT "daily_question_instances_question_version_id_fkey" FOREIGN KEY ("question_version_id") REFERENCES "public"."question_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_instances"
    ADD CONSTRAINT "daily_question_instances_replaced_by_instance_id_fkey" FOREIGN KEY ("replaced_by_instance_id") REFERENCES "public"."daily_question_instances"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_couple_day_id_fkey" FOREIGN KEY ("couple_day_id") REFERENCES "public"."couple_days"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."questions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_replacement_instance_id_fkey" FOREIGN KEY ("replacement_instance_id") REFERENCES "public"."daily_question_instances"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_skipped_instance_id_fkey" FOREIGN KEY ("skipped_instance_id") REFERENCES "public"."daily_question_instances"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_shuffles"
    ADD CONSTRAINT "daily_question_shuffles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_threads"
    ADD CONSTRAINT "daily_question_threads_instance_id_fkey" FOREIGN KEY ("instance_id") REFERENCES "public"."daily_question_instances"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_question_threads"
    ADD CONSTRAINT "daily_question_threads_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."conversation_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."latest_partner_locations"
    ADD CONSTRAINT "latest_partner_locations_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."latest_partner_locations"
    ADD CONSTRAINT "latest_partner_locations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."location_sharing_preferences"
    ADD CONSTRAINT "location_sharing_preferences_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."location_sharing_preferences"
    ADD CONSTRAINT "location_sharing_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memories"
    ADD CONSTRAINT "memories_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."memories"
    ADD CONSTRAINT "memories_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memories"
    ADD CONSTRAINT "memories_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_media"
    ADD CONSTRAINT "memory_media_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."memory_media"
    ADD CONSTRAINT "memory_media_memory_id_fkey" FOREIGN KEY ("memory_id") REFERENCES "public"."memories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."memory_media"
    ADD CONSTRAINT "memory_media_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_media"
    ADD CONSTRAINT "memory_media_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_notes"
    ADD CONSTRAINT "memory_notes_memory_id_fkey" FOREIGN KEY ("memory_id") REFERENCES "public"."memories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."memory_notes"
    ADD CONSTRAINT "memory_notes_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_notes"
    ADD CONSTRAINT "memory_notes_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_threads"
    ADD CONSTRAINT "memory_threads_memory_id_fkey" FOREIGN KEY ("memory_id") REFERENCES "public"."memories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."memory_threads"
    ADD CONSTRAINT "memory_threads_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."conversation_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pairing_invites"
    ADD CONSTRAINT "pairing_invites_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_profile_photo_asset_id_fkey" FOREIGN KEY ("profile_photo_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_provider_profile_photo_asset_id_fkey" FOREIGN KEY ("provider_profile_photo_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_answer_kinds"
    ADD CONSTRAINT "question_answer_kinds_question_version_id_fkey" FOREIGN KEY ("question_version_id") REFERENCES "public"."question_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_collections"
    ADD CONSTRAINT "question_collections_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_version_localizations"
    ADD CONSTRAINT "question_version_localizations_question_version_id_fkey" FOREIGN KEY ("question_version_id") REFERENCES "public"."question_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."question_versions"
    ADD CONSTRAINT "question_versions_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."questions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."questions"
    ADD CONSTRAINT "questions_collection_id_fkey" FOREIGN KEY ("collection_id") REFERENCES "public"."question_collections"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."relationship_blocks"
    ADD CONSTRAINT "relationship_blocks_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "public"."relationship_pairs"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."relationship_blocks"
    ADD CONSTRAINT "relationship_blocks_source_report_id_fkey" FOREIGN KEY ("source_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."relationship_sync_events"
    ADD CONSTRAINT "relationship_sync_events_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."streak_states"
    ADD CONSTRAINT "streak_states_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."streak_states"
    ADD CONSTRAINT "streak_states_last_qualified_couple_day_id_fkey" FOREIGN KEY ("last_qualified_couple_day_id") REFERENCES "public"."couple_days"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."thread_message_media"
    ADD CONSTRAINT "thread_message_media_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."thread_message_media"
    ADD CONSTRAINT "thread_message_media_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."thread_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."thread_messages"
    ADD CONSTRAINT "thread_messages_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."thread_messages"
    ADD CONSTRAINT "thread_messages_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."thread_messages"
    ADD CONSTRAINT "thread_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."conversation_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."widget_canvases"
    ADD CONSTRAINT "widget_canvases_active_revision_id_fkey" FOREIGN KEY ("active_revision_id") REFERENCES "public"."widget_drawing_revisions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."widget_canvases"
    ADD CONSTRAINT "widget_canvases_couple_id_fkey" FOREIGN KEY ("couple_id") REFERENCES "public"."couples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_canvas_id_fkey" FOREIGN KEY ("canvas_id") REFERENCES "public"."widget_canvases"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_moderated_by_fkey" FOREIGN KEY ("moderated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_moderation_report_id_fkey" FOREIGN KEY ("moderation_report_id") REFERENCES "public"."content_reports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_parent_revision_id_fkey" FOREIGN KEY ("parent_revision_id") REFERENCES "public"."widget_drawing_revisions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."widget_drawing_revisions"
    ADD CONSTRAINT "widget_drawing_revisions_payload_media_asset_id_fkey" FOREIGN KEY ("payload_media_asset_id") REFERENCES "public"."media_assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."widget_push_devices"
    ADD CONSTRAINT "widget_push_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "internal"."account_deletion_jobs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_deletion_jobs_service_role_all" ON "internal"."account_deletion_jobs" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."app_account_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_account_tokens_service_role_all" ON "internal"."app_account_tokens" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."app_runtime_secrets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_runtime_secrets_service_role_all" ON "internal"."app_runtime_secrets" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."client_operations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "client_operations_service_role_all" ON "internal"."client_operations" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."entitlement_grants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "entitlement_grants_service_role_all" ON "internal"."entitlement_grants" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."moderation_actions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "moderation_actions_service_role_all" ON "internal"."moderation_actions" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."notification_outbox" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_outbox_service_role_all" ON "internal"."notification_outbox" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."pair_safety_warning_flags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pair_safety_warning_flags_service_role_all" ON "internal"."pair_safety_warning_flags" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."pairing_invite_attempts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pairing_invite_attempts_service_role_all" ON "internal"."pairing_invite_attempts" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."pairing_invite_secrets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pairing_invite_secrets_service_role_all" ON "internal"."pairing_invite_secrets" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."privacy_request_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "privacy_request_events_service_role_all" ON "internal"."privacy_request_events" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."report_snapshot_assets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_snapshot_assets_service_role_all" ON "internal"."report_snapshot_assets" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."report_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_snapshots_service_role_all" ON "internal"."report_snapshots" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."review_access_attempts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "review_access_attempts_service_role_all" ON "internal"."review_access_attempts" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."review_access_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "review_access_codes_service_role_all" ON "internal"."review_access_codes" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."review_access_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "review_access_sessions_service_role_all" ON "internal"."review_access_sessions" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."review_demo_partners" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "review_demo_partners_service_role_all" ON "internal"."review_demo_partners" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."storekit_notification_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storekit_notification_events_service_role_all" ON "internal"."storekit_notification_events" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."storekit_payloads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storekit_payloads_service_role_all" ON "internal"."storekit_payloads" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."storekit_transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storekit_transactions_service_role_all" ON "internal"."storekit_transactions" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."streak_restorations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "streak_restorations_service_role_all" ON "internal"."streak_restorations" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "internal"."widget_push_outbox" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "widget_push_outbox_service_role_all" ON "internal"."widget_push_outbox" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "Users can read their own widget push devices" ON "public"."widget_push_devices" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."content_report_targets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "content_report_targets_select_own_report" ON "public"."content_report_targets" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."content_reports" "report"
  WHERE (("report"."id" = "content_report_targets"."report_id") AND ("report"."reporter_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



ALTER TABLE "public"."content_reports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "content_reports_select_own" ON "public"."content_reports" FOR SELECT TO "authenticated" USING (("reporter_user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."conversation_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "conversation_threads_service_role_all" ON "public"."conversation_threads" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."couple_activity_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "couple_activity_events_service_role_all" ON "public"."couple_activity_events" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."couple_days" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "couple_days_service_role_all" ON "public"."couple_days" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."couple_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "couple_members_service_role_all" ON "public"."couple_members" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."couples" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "couples_service_role_all" ON "public"."couples" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_answer_media" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_answer_media_service_role_all" ON "public"."daily_answer_media" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_answer_partner_choice" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_answer_partner_choice_service_role_all" ON "public"."daily_answer_partner_choice" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_answer_text" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_answer_text_service_role_all" ON "public"."daily_answer_text" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_challenges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_challenges_service_role_all" ON "public"."daily_challenges" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_question_answers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_question_answers_service_role_all" ON "public"."daily_question_answers" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_question_instances" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_question_instances_service_role_all" ON "public"."daily_question_instances" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_question_shuffles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_question_shuffles_service_role_all" ON "public"."daily_question_shuffles" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."daily_question_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_question_threads_service_role_all" ON "public"."daily_question_threads" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."latest_partner_locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "latest_partner_locations_service_role_all" ON "public"."latest_partner_locations" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."location_sharing_preferences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "location_sharing_preferences_service_role_all" ON "public"."location_sharing_preferences" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."media_assets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "media_assets_service_role_all" ON "public"."media_assets" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."memories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memories_service_role_all" ON "public"."memories" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."memory_media" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memory_media_service_role_all" ON "public"."memory_media" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."memory_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memory_notes_service_role_all" ON "public"."memory_notes" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."memory_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memory_threads_service_role_all" ON "public"."memory_threads" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."notification_preferences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_preferences_select_own" ON "public"."notification_preferences" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "notification_preferences_update_own" ON "public"."notification_preferences" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."pairing_invites" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pairing_invites_select_created" ON "public"."pairing_invites" FOR SELECT TO "authenticated" USING (("created_by_user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."privacy_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "privacy_requests_insert_own" ON "public"."privacy_requests" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "privacy_requests_select_own" ON "public"."privacy_requests" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("deleted_at" IS NULL))) WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("deleted_at" IS NULL)));



ALTER TABLE "public"."question_answer_kinds" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_answer_kinds_service_role_all" ON "public"."question_answer_kinds" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."question_collections" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_collections_service_role_all" ON "public"."question_collections" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."question_version_localizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_version_localizations_service_role_all" ON "public"."question_version_localizations" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."question_versions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "question_versions_service_role_all" ON "public"."question_versions" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."questions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "questions_service_role_all" ON "public"."questions" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."relationship_blocks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "relationship_blocks_service_role_all" ON "public"."relationship_blocks" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."relationship_pairs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "relationship_pairs_service_role_all" ON "public"."relationship_pairs" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."relationship_sync_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "relationship_sync_events_select_own" ON "public"."relationship_sync_events" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."streak_states" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "streak_states_service_role_all" ON "public"."streak_states" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."subscription_products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscription_products_select_active" ON "public"."subscription_products" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."thread_message_media" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "thread_message_media_service_role_all" ON "public"."thread_message_media" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."thread_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "thread_messages_service_role_all" ON "public"."thread_messages" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_devices_insert_own" ON "public"."user_devices" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "user_devices_select_own" ON "public"."user_devices" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "user_devices_update_own" ON "public"."user_devices" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."widget_canvases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "widget_canvases_service_role_all" ON "public"."widget_canvases" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."widget_drawing_revisions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "widget_drawing_revisions_service_role_all" ON "public"."widget_drawing_revisions" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."widget_push_devices" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "internal" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage_private" TO "authenticated";
GRANT USAGE ON SCHEMA "storage_private" TO "service_role";



REVOKE ALL ON FUNCTION "internal"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."apply_couple_activity"("p_couple_id" "uuid", "p_user_id" "uuid", "p_couple_day_id" "uuid", "p_activity_kind" "text", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."apply_couple_activity"("p_couple_id" "uuid", "p_user_id" "uuid", "p_couple_day_id" "uuid", "p_activity_kind" "text", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."apply_report_moderation_action"("p_report_id" "uuid", "p_action_kind" "text", "p_operator_kind" "text", "p_operator_identifier" "text", "p_reason" "text", "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."apply_report_moderation_action"("p_report_id" "uuid", "p_action_kind" "text", "p_operator_kind" "text", "p_operator_identifier" "text", "p_reason" "text", "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."apply_streak_restore"("p_couple_id" "uuid", "p_purchaser_user_id" "uuid", "p_product_id" "uuid", "p_environment" "text", "p_transaction_id" "text", "p_original_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_raw_payload_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."apply_streak_restore"("p_couple_id" "uuid", "p_purchaser_user_id" "uuid", "p_product_id" "uuid", "p_environment" "text", "p_transaction_id" "text", "p_original_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_raw_payload_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_active_question_collection_ready"("p_collection_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_active_question_collection_ready"("p_collection_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_active_question_ready"("p_question_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_active_question_ready"("p_question_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_active_question_version_ready"("p_question_version_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_active_question_version_ready"("p_question_version_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_conversation_thread_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_conversation_thread_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_answer_media_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_answer_media_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_answer_partner_choice_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_answer_partner_choice_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_answer_text_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_answer_text_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_challenge_member"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_challenge_member"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_question_answer_member"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_question_answer_member"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_question_instance_member"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_question_instance_member"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_question_shuffle_valid"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_question_shuffle_valid"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_daily_question_thread_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_daily_question_thread_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_memory_media_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_memory_media_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_memory_member_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_memory_member_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_memory_note_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_memory_note_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_memory_thread_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_memory_thread_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_notification_payload_safe"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_notification_payload_safe"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_pairing_invite_attempt_allowed"("p_user_id" "uuid", "p_code_hash_prefix" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_pairing_invite_attempt_allowed"("p_user_id" "uuid", "p_code_hash_prefix" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_profile_photo_asset_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_profile_photo_asset_owner"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_question_collection_ready_trigger"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_question_collection_ready_trigger"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_question_ready_trigger"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_question_ready_trigger"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_question_version_child_ready_trigger"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_question_version_child_ready_trigger"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_question_version_ready_trigger"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_question_version_ready_trigger"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_relationship_block_pair_members"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_relationship_block_pair_members"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_thread_message_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_thread_message_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_thread_message_media_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_thread_message_media_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_widget_canvas_active_revision_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_widget_canvas_active_revision_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_widget_canvas_couple_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_widget_canvas_couple_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."assert_widget_drawing_revision_allowed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."assert_widget_drawing_revision_allowed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."attach_memory_media_assets"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."attach_memory_media_assets"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."auth_metadata_display_name"("raw_user_meta_data" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."auth_metadata_display_name"("raw_user_meta_data" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."begin_client_operation"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_operation_kind" "text", "p_idempotency_scope" "text", "p_request_hash" "bytea") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."begin_client_operation"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_operation_kind" "text", "p_idempotency_scope" "text", "p_request_hash" "bytea") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."block_relationship"("p_blocked_user_id" "uuid", "p_source_report_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."block_relationship"("p_blocked_user_id" "uuid", "p_source_report_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."bump_revision"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."bump_revision"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."can_access_couple_content"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."can_access_couple_content"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."can_access_visible_memory"("p_memory_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."can_access_visible_memory"("p_memory_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."can_read_media_object"("p_bucket" "text", "p_storage_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."can_read_media_object"("p_bucket" "text", "p_storage_path" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."can_report_relationship_content"("p_couple_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."can_report_relationship_content"("p_couple_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."can_upload_reserved_media_object"("p_bucket" "text", "p_storage_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."can_upload_reserved_media_object"("p_bucket" "text", "p_storage_path" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."can_view_daily_answer"("p_answer_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."can_view_daily_answer"("p_answer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_account_deletion_jobs"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer, "p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_account_deletion_jobs"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer, "p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_due_notifications"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_due_notifications"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_expired_pending_uploads"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_expired_pending_uploads"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_media_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_media_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_notification_batch"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_notification_batch"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_report_snapshot_asset_copies"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_report_snapshot_asset_copies"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_storekit_transactions_for_reconciliation"("p_now" timestamp with time zone, "p_limit" integer, "p_reconcile_after" interval, "p_retry_after" interval, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_storekit_transactions_for_reconciliation"("p_now" timestamp with time zone, "p_limit" integer, "p_reconcile_after" interval, "p_retry_after" interval, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."claim_widget_push_batch"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."claim_widget_push_batch"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."cleanup_attempt_logs"("p_now" timestamp with time zone, "p_pairing_retention" interval, "p_review_retention" interval, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."cleanup_attempt_logs"("p_now" timestamp with time zone, "p_pairing_retention" interval, "p_review_retention" interval, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."cleanup_expired_relationship_content"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."cleanup_expired_relationship_content"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."complete_client_operation"("p_client_operation_id" "uuid", "p_stored_response" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."complete_client_operation"("p_client_operation_id" "uuid", "p_stored_response" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."complete_review_access_session"("p_review_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."complete_review_access_session"("p_review_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_profile_for_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_profile_for_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."create_relationship_sync_event"("p_user_id" "uuid", "p_couple_id" "uuid", "p_initiated_by_user_id" "uuid", "p_event_kind" "text", "p_reason" "text", "p_relationship_status" "text", "p_member_status" "text", "p_ended_at" timestamp with time zone, "p_delete_after" timestamp with time zone, "p_local_purge_scope" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."create_relationship_sync_event"("p_user_id" "uuid", "p_couple_id" "uuid", "p_initiated_by_user_id" "uuid", "p_event_kind" "text", "p_reason" "text", "p_relationship_status" "text", "p_member_status" "text", "p_ended_at" timestamp with time zone, "p_delete_after" timestamp with time zone, "p_local_purge_scope" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."current_user_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."current_user_id"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."delete_latest_locations_on_preference_disable"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."delete_latest_locations_on_preference_disable"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."delete_latest_locations_on_relationship_end"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."delete_latest_locations_on_relationship_end"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."detect_streak_break"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."detect_streak_break"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."disable_user_device"("p_device_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."disable_user_device"("p_device_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."end_relationship_for_pair"("p_pair_id" "uuid", "p_initiated_by_user_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."end_relationship_for_pair"("p_pair_id" "uuid", "p_initiated_by_user_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_due_streak_reminders"("p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_due_streak_reminders"("p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_memory_created_notification"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_memory_created_notification"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_notification_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_redaction_level" "text", "p_apns_push_type" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_notification_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_redaction_level" "text", "p_apns_push_type" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_partner_answered_notification"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_partner_answered_notification"() TO "service_role";


REVOKE ALL ON FUNCTION "internal"."enqueue_partner_notification"("p_couple_id" "uuid", "p_actor_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_redaction_level" "text", "p_apns_push_type" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_partner_notification"("p_couple_id" "uuid", "p_actor_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_redaction_level" "text", "p_apns_push_type" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_report_snapshot_assets"("p_report_id" "uuid", "p_target_snapshot" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_report_snapshot_assets"("p_report_id" "uuid", "p_target_snapshot" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_widget_push_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_widget_push_for_user"("p_recipient_user_id" "uuid", "p_kind" "text", "p_payload" "jsonb", "p_dedupe_key" "text", "p_apns_collapse_id" "text", "p_scheduled_for" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."enqueue_widget_update_alert"("p_couple_id" "uuid", "p_author_user_id" "uuid", "p_canvas_id" "uuid", "p_revision_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."enqueue_widget_update_alert"("p_couple_id" "uuid", "p_author_user_id" "uuid", "p_canvas_id" "uuid", "p_revision_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."ensure_daily_challenge_slots"("p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."ensure_daily_challenge_slots"("p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."expire_stale_entitlements"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."expire_stale_entitlements"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."expire_stale_invites_and_review_codes"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."expire_stale_invites_and_review_codes"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."fail_exhausted_notification_claims"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."fail_exhausted_notification_claims"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."fail_exhausted_widget_push_claims"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."fail_exhausted_widget_push_claims"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) TO "service_role";



GRANT ALL ON TABLE "internal"."review_access_codes" TO "service_role";



REVOKE ALL ON FUNCTION "internal"."find_active_review_access_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."find_active_review_access_code"("p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."find_relationship_pair_id"("p_first_user_id" "uuid", "p_second_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."find_relationship_pair_id"("p_first_user_id" "uuid", "p_second_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."find_reportable_relationship_between"("p_reporter_user_id" "uuid", "p_reported_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."find_reportable_relationship_between"("p_reporter_user_id" "uuid", "p_reported_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_access_snapshot"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_access_snapshot"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_active_question_catalog"("p_locale" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_active_question_catalog"("p_locale" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_conversation_threads"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_conversation_threads"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_couple_day_streak_qualified_at"("p_couple_id" "uuid", "p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_couple_day_streak_qualified_at"("p_couple_id" "uuid", "p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_couple_streak"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_couple_streak"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_couple_streak_for_couple"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_couple_streak_for_couple"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_couple_streak_participation_for_user"("p_couple_id" "uuid", "p_current_user_id" "uuid", "p_observed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_couple_streak_participation_for_user"("p_couple_id" "uuid", "p_current_user_id" "uuid", "p_observed_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_current_entitled_couple_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_current_entitled_couple_id"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_current_relationship_state"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_current_relationship_state"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_answer_details"("p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_answer_details"("p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_answer_details_for_context"("p_couple_day_ids" "uuid"[], "p_current_user_id" "uuid", "p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_answer_details_for_context"("p_couple_day_ids" "uuid"[], "p_current_user_id" "uuid", "p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_answer_history_details"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_answer_history_details"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_questions_for_couple_day"("p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_questions_for_couple_day"("p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_daily_questions_history"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_daily_questions_history"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_entitled_couple_id_for_user"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_entitled_couple_id_for_user"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_or_create_app_account_token"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_or_create_app_account_token"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_or_create_couple_day_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_or_create_couple_day_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_or_create_relationship_pair"("p_first_user_id" "uuid", "p_second_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_or_create_relationship_pair"("p_first_user_id" "uuid", "p_second_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_or_create_today_couple_day"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_or_create_today_couple_day"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_or_create_widget_canvas"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_or_create_widget_canvas"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_partner_location_visibility"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_partner_location_visibility"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_question_answer_history"("p_question_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_question_answer_history"("p_question_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_thread_messages"("p_thread_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_thread_messages"("p_thread_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_today_daily_challenge_snapshot"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_today_daily_challenge_snapshot"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_today_daily_questions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_today_daily_questions"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_today_daily_questions_for_context"("p_current_user_id" "uuid", "p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_today_daily_questions_for_context"("p_current_user_id" "uuid", "p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_user_id_by_app_account_token"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_user_id_by_app_account_token"("p_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_widget_canvas"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_widget_canvas"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."handle_daily_challenge_completed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."handle_daily_challenge_completed"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."handle_thread_message_created"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."handle_thread_message_created"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."handle_widget_drawing_revision_created"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."handle_widget_drawing_revision_created"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."has_active_relationship_block"("p_pair_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."has_active_relationship_block"("p_pair_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."has_due_account_deletion_work"("p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."has_due_account_deletion_work"("p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."has_due_push_notification_work"("p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."has_due_push_notification_work"("p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."hash_pairing_invite_code"("p_invite_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."hash_pairing_invite_code"("p_invite_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."hash_review_access_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."hash_review_access_code"("p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."infer_report_target_for_moderation"("p_report_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."infer_report_target_for_moderation"("p_report_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."insert_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."insert_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."invalidate_subscription_trial_reminder"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."invalidate_subscription_trial_reminder"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."invoke_account_deletion_drain"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."invoke_account_deletion_drain"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."invoke_media_storage_cleanup"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."invoke_media_storage_cleanup"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."invoke_push_notification_drain"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."invoke_push_notification_drain"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."is_active_couple_member"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."is_active_couple_member"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."is_active_entitled_couple_member"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."is_active_entitled_couple_member"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."is_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."is_couple_pair_member"("p_pair_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."is_couple_pair_member"("p_pair_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text", "p_expires_at" timestamp with time zone, "p_max_redemptions" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text", "p_expires_at" timestamp with time zone, "p_max_redemptions" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."list_review_demo_partners"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."list_review_demo_partners"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_account_deletion_completed"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_account_deletion_completed"("p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_media_for_deletion"("p_media_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_media_for_deletion"("p_media_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_media_storage_deleted"("p_media_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_media_storage_deleted"("p_media_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_notification_failed"("p_outbox_id" "uuid", "p_error" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_notification_failed"("p_outbox_id" "uuid", "p_error" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_notification_sent"("p_outbox_id" "uuid", "p_provider_message_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_notification_sent"("p_outbox_id" "uuid", "p_provider_message_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_report_snapshot_asset_copied"("p_snapshot_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_report_snapshot_asset_copied"("p_snapshot_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_report_snapshot_asset_copy_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_report_snapshot_asset_copy_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_storekit_transaction_reconciled"("p_transaction_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_storekit_transaction_reconciled"("p_transaction_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_storekit_transaction_reconciliation_failed"("p_transaction_id" "uuid", "p_error" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_storekit_transaction_reconciliation_failed"("p_transaction_id" "uuid", "p_error" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."media_asset_has_live_reference"("p_media_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."media_asset_has_live_reference"("p_media_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."media_byte_limit"("p_media_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."media_byte_limit"("p_media_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."media_extension_matches_type"("p_media_type" "text", "p_file_extension" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."media_extension_matches_type"("p_media_type" "text", "p_file_extension" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."media_mime_matches_type"("p_media_type" "text", "p_mime_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."media_mime_matches_type"("p_media_type" "text", "p_mime_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."normalize_media_file_extension"("p_file_extension" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."normalize_media_file_extension"("p_file_extension" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."normalize_memory_note_body"("p_body" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."normalize_memory_note_body"("p_body" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."normalize_memory_title"("p_title" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."normalize_memory_title"("p_title" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."notification_actor_display_name"("p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."notification_actor_display_name"("p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."notification_alert_body"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."notification_alert_body"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."notification_alert_title"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."notification_alert_title"("p_kind" "text", "p_payload" "jsonb", "p_locale" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."notification_locale_language"("p_locale" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."notification_locale_language"("p_locale" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."notification_payload_is_safe"("p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."notification_payload_is_safe"("p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."pick_daily_question_version"("p_couple_day_id" "uuid", "p_user_id" "uuid", "p_excluded_question_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."pick_daily_question_version"("p_couple_day_id" "uuid", "p_user_id" "uuid", "p_excluded_question_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."preview_pairing_invite"("p_invite_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."preview_pairing_invite"("p_invite_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."purge_deleted_relationship_content"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."purge_deleted_relationship_content"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."purge_deleted_report_snapshots"("p_now" timestamp with time zone, "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."purge_deleted_report_snapshots"("p_now" timestamp with time zone, "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_daily_answer_media_assets_if_orphaned"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_daily_answer_media_assets_if_orphaned"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_memory_media_assets_if_orphaned"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_memory_media_assets_if_orphaned"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_old_media_asset_if_orphaned"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_old_media_asset_if_orphaned"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_orphaned_media_asset_for_delete"("p_media_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_orphaned_media_asset_for_delete"("p_media_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_orphaned_media_assets_for_delete"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_orphaned_media_assets_for_delete"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_subscription_trial_reminders"("p_batch_size" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_subscription_trial_reminders"("p_batch_size" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_thread_media_assets_if_orphaned"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_thread_media_assets_if_orphaned"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_thread_message_media_assets_if_orphaned"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_thread_message_media_assets_if_orphaned"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."queue_widget_payloads_if_orphaned"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."queue_widget_payloads_if_orphaned"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."record_couple_activity"("p_activity_kind" "text", "p_couple_day_id" "uuid", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."record_couple_activity"("p_activity_kind" "text", "p_couple_day_id" "uuid", "p_occurred_at" timestamp with time zone, "p_dedupe_key" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."redeem_review_access"("p_code_id" "uuid", "p_reviewer_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."redeem_review_access"("p_code_id" "uuid", "p_reviewer_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."refresh_streak_after_device_time_zone_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."refresh_streak_after_device_time_zone_change"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."refresh_streak_after_profile_time_zone_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."refresh_streak_after_profile_time_zone_change"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."refresh_streak_deadline"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."refresh_streak_deadline"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."reject_pending_account_client_operation"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."reject_pending_account_client_operation"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."request_account_deletion"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."request_account_deletion"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."request_account_deletion_drain"("p_source" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."request_account_deletion_drain"("p_source" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."request_push_notification_drain"("p_source" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."request_push_notification_drain"("p_source" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."reset_review_demo"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."reset_review_demo"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_content_report_target"("p_reporter_user_id" "uuid", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_content_report_target"("p_reporter_user_id" "uuid", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_couple_day_anchor"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_couple_day_anchor"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_couple_day_anchor_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_couple_day_anchor_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_current_couple_entitlement"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_current_couple_entitlement"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_next_activity_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_next_activity_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_streak_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone, "p_local_days_after" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_streak_deadline_at"("p_couple_id" "uuid", "p_observed_at" timestamp with time zone, "p_local_days_after" integer) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."resolve_user_entitlement"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."resolve_user_entitlement"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."retry_account_deletion_job"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."retry_account_deletion_job"("p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."revoke_pairing_invite"("p_invite_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."revoke_pairing_invite"("p_invite_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."revoke_review_access_codes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."revoke_review_access_codes"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."run_scheduled_push_notification_jobs"("p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."run_scheduled_push_notification_jobs"("p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."set_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_leave_relationship" boolean, "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_leave_relationship" boolean, "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."sync_profile_display_name_from_auth_metadata"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."sync_profile_display_name_from_auth_metadata"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."tombstone_content_report_target"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."tombstone_content_report_target"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."touch_updated_at_and_revision"() FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."touch_updated_at_and_revision"() TO "service_role";



REVOKE ALL ON FUNCTION "internal"."unblock_pair"("p_pair_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."unblock_pair"("p_pair_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."user_has_direct_entitlement"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."user_has_direct_entitlement"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."user_local_date"("p_user_id" "uuid", "p_observed_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."user_local_date"("p_user_id" "uuid", "p_observed_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "internal"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "internal"."widget_updated_notification_body"("p_locale" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "internal"."widget_updated_notification_body"("p_locale" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_started_on" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."attach_memory_media"("p_memory_id" "uuid", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."block_relationship"("p_blocked_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."block_relationship"("p_blocked_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."block_relationship"("p_blocked_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_account_deletion_jobs"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer, "p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_account_deletion_jobs"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer, "p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_media_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_media_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_notification_batch"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_notification_batch"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_report_snapshot_storage_deletes"("p_now" timestamp with time zone, "p_limit" integer, "p_retry_after" interval, "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_widget_push_batch"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_widget_push_batch"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_review_access_session"("p_review_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_review_access_session"("p_review_session_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_review_access_session"("p_review_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_daily_question_thread_with_message"("p_instance_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_memory"("p_memory_id" "uuid", "p_title" "text", "p_memory_date" "date", "p_note_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_memory_thread_with_message"("p_memory_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_pairing_invite"("p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_pending_media_upload"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_file_extension" "text", "p_couple_id" "uuid", "p_upload_expires_at" timestamp with time zone, "p_path_context" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."disable_user_device"("p_device_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."disable_user_device"("p_device_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."disable_user_device"("p_device_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_review_partner"("p_user_id" "uuid", "p_display_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."finalize_media_upload"("p_media_asset_id" "uuid", "p_reserved_by_client_operation_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_bucket" "text", "p_storage_path" "text", "p_reserved_parent_kind" "text", "p_reserved_parent_id" "uuid", "p_upload_purpose" "text", "p_media_type" "text", "p_mime_type" "text", "p_byte_size" bigint, "p_sha256_hex" "text", "p_width" integer, "p_height" integer, "p_duration_ms" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_access_snapshot"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_access_snapshot"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_access_snapshot"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_active_question_catalog"("p_locale" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_active_question_catalog"("p_locale" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_active_question_catalog"("p_locale" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_conversation_threads"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_conversation_threads"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_conversation_threads"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_couple_streak"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_couple_streak"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_couple_streak"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_current_relationship_state"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_current_relationship_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_relationship_state"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_daily_answer_details"("p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_daily_answer_details"("p_couple_day_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_answer_details"("p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_answer_details_for_couple_days"("p_couple_day_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_daily_answer_history_details"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_daily_answer_history_details"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_answer_history_details"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_answer_reveal_state"("p_couple_day_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_daily_questions_history"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_daily_questions_history"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_questions_history"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_media_signed_url"("p_media_asset_id" "uuid", "p_expires_in_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_memories"("p_updated_after" timestamp with time zone, "p_cursor_memory_id" "uuid", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_couple_entitlement"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_couple_entitlement"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_couple_entitlement"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_entitlement"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_entitlement"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_entitlement"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_or_create_app_account_token"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_or_create_app_account_token"("p_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_or_create_widget_canvas"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_or_create_widget_canvas"("p_couple_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_widget_canvas"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_partner_location_visibility"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_partner_location_visibility"("p_couple_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_partner_location_visibility"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_question_answer_history"("p_question_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_question_answer_history"("p_question_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_question_answer_history"("p_question_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_thread_messages"("p_thread_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_thread_messages"("p_thread_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_thread_messages"("p_thread_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_today_daily_challenge_snapshot"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_today_daily_challenge_snapshot"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_today_daily_challenge_snapshot"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_today_daily_questions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_today_daily_questions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_today_daily_questions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_widget_canvas"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_widget_canvas"("p_couple_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_widget_canvas"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_widget_drawing_revisions"("p_canvas_id" "uuid", "p_updated_after" timestamp with time zone, "p_limit" integer, "p_updated_after_revision_id" "uuid", "p_created_before" timestamp with time zone, "p_created_before_revision_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hide_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text", "p_expires_at" timestamp with time zone, "p_max_redemptions" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."issue_review_access_code"("p_code" "text", "p_seeded_partner_user_id" "uuid", "p_scenario" "text", "p_expires_at" timestamp with time zone, "p_max_redemptions" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."leave_relationship"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_review_demo_partners"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_review_demo_partners"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_account_deletion_auth_failed"("p_job_id" "uuid", "p_error_code" "text", "p_max_attempts" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_account_deletion_completed"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_account_deletion_completed"("p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_account_deletion_provider_result"("p_job_id" "uuid", "p_status" "text", "p_error_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_media_for_deletion"("p_media_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_media_for_deletion"("p_media_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_media_for_deletion"("p_media_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_media_storage_delete_failed"("p_media_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_media_storage_deleted"("p_media_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_media_storage_deleted"("p_media_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_notification_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_relationship_ended_notice_seen"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_report_snapshot_storage_delete_failed"("p_snapshot_asset_id" "uuid", "p_error" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_report_snapshot_storage_deleted"("p_snapshot_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_streak_restore_refunded"("p_environment" "text", "p_transaction_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_widget_push_result"("p_outbox_id" "uuid", "p_success" boolean, "p_provider_message_id" "text", "p_error" "text", "p_invalid_token" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."preview_pairing_invite"("p_invite_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."preview_pairing_invite"("p_invite_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."preview_pairing_invite"("p_invite_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_storekit_server_notification"("p_notification_uuid" "uuid", "p_notification_type" "text", "p_subtype" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_notification_payload" "text", "p_signed_transaction_info" "text", "p_payload_json" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_verified_storekit_transaction"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_web_order_line_item_id" "text", "p_status" "text", "p_purchased_at" timestamp with time zone, "p_expires_at" timestamp with time zone, "p_revoked_at" timestamp with time zone, "p_revocation_reason" "text", "p_signed_payload" "text", "p_payload_json" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_verified_streak_restore"("p_user_id" "uuid", "p_app_account_token" "uuid", "p_apple_product_id" "text", "p_environment" "text", "p_original_transaction_id" "text", "p_transaction_id" "text", "p_purchased_at" timestamp with time zone, "p_signed_payload" "text", "p_payload_json" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_review_demo_partner"("p_slot" smallint, "p_user_id" "uuid", "p_display_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_user_device"("p_platform" "text", "p_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_widget_push_device"("p_widget_kind" "text", "p_widget_push_token" "text", "p_apns_environment" "text", "p_locale" "text", "p_time_zone_id" "text", "p_app_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_memory_media"("p_memory_media_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_account_deletion"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_account_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_account_deletion"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."reset_daily_challenge_for_testing"("p_couple_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_daily_challenge_for_testing"("p_couple_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reset_review_demo"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_review_demo"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."retry_account_deletion_job"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."retry_account_deletion_job"("p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_pairing_invite"("p_invite_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_pairing_invite"("p_invite_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_pairing_invite"("p_invite_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_review_access_codes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_review_access_codes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."rotate_pairing_invite"("p_current_invite_id" "uuid", "p_invite_code" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone, "p_expires_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_thread_message"("p_thread_id" "uuid", "p_body" "text", "p_media_asset_ids" "uuid"[], "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_couple_started_on"("p_started_on" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_own_provider_profile_photo"("p_profile_photo_asset_id" "uuid", "p_source" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_own_provider_profile_photo"("p_profile_photo_asset_id" "uuid", "p_source" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_own_provider_profile_photo"("p_profile_photo_asset_id" "uuid", "p_source" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."shuffle_daily_question"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."shuffle_daily_question_snapshot"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."shuffle_daily_question_snapshot"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."shuffle_daily_question_snapshot"("p_slot_number" smallint, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_daily_challenge"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_daily_challenge_snapshot"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_daily_challenge_snapshot"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_daily_challenge_snapshot"("p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_content_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_daily_answer"("p_instance_id" "uuid", "p_payload" "jsonb", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_leave_and_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_leave_and_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_leave_and_report"("p_reason" "text", "p_note" "text", "p_target_kind" "text", "p_target_id" "uuid", "p_target_aux_id" "uuid", "p_block_reported_user" boolean, "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_widget_drawing_revision"("p_canvas_id" "uuid", "p_payload_media_asset_id" "uuid", "p_parent_revision_id" "uuid", "p_payload_bytes" bigint, "p_uncompressed_bytes" bigint, "p_compression" "text", "p_stroke_count" integer, "p_point_count" integer, "p_bounds" "jsonb", "p_sha256_hex" "text", "p_client_decode_validated_at" timestamp with time zone, "p_client_renderer_version" "text", "p_client_validation_version" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."unblock_pair"("p_pair_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."unblock_pair"("p_pair_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unblock_pair"("p_pair_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_daily_answer_partner_choice"("p_instance_id" "uuid", "p_selected_user_id" "uuid", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_daily_answer_text"("p_instance_id" "uuid", "p_text" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_latest_partner_location"("p_couple_id" "uuid", "p_latitude" numeric, "p_longitude" numeric, "p_accuracy_m" numeric, "p_captured_at" timestamp with time zone, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_location_sharing_preference"("p_couple_id" "uuid", "p_is_enabled" boolean, "p_consent_version" "text", "p_source" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_memory"("p_memory_id" "uuid", "p_expected_revision" integer, "p_title" "text", "p_memory_date" "date", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_own_profile"("p_display_name" "text", "p_profile_photo_asset_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_own_profile"("p_display_name" "text", "p_profile_photo_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_own_profile"("p_display_name" "text", "p_profile_photo_asset_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_memory_note"("p_memory_id" "uuid", "p_expected_revision" integer, "p_body" "text", "p_client_operation_id" "uuid", "p_client_id" "uuid", "p_client_sequence" bigint, "p_local_created_at" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_my_pairing_invite"("p_invite_id" "uuid", "p_invite_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "storage_private"."paeonia_can_read_media_object"("p_bucket_id" "text", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "storage_private"."paeonia_can_read_media_object"("p_bucket_id" "text", "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "storage_private"."paeonia_can_read_media_object"("p_bucket_id" "text", "p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "storage_private"."paeonia_can_upload_reserved_media_object"("p_bucket_id" "text", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "storage_private"."paeonia_can_upload_reserved_media_object"("p_bucket_id" "text", "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "storage_private"."paeonia_can_upload_reserved_media_object"("p_bucket_id" "text", "p_name" "text") TO "service_role";



GRANT ALL ON TABLE "internal"."account_deletion_jobs" TO "service_role";



GRANT ALL ON TABLE "internal"."app_account_tokens" TO "service_role";



GRANT ALL ON TABLE "internal"."app_runtime_secrets" TO "service_role";



GRANT ALL ON TABLE "internal"."client_operations" TO "service_role";



GRANT ALL ON TABLE "internal"."entitlement_grants" TO "service_role";



GRANT ALL ON TABLE "internal"."moderation_actions" TO "service_role";



GRANT ALL ON TABLE "internal"."notification_outbox" TO "service_role";



GRANT ALL ON TABLE "internal"."pair_safety_warning_flags" TO "service_role";



GRANT ALL ON TABLE "internal"."pairing_invite_attempts" TO "service_role";



GRANT ALL ON TABLE "internal"."pairing_invite_secrets" TO "service_role";



GRANT ALL ON TABLE "internal"."privacy_request_events" TO "service_role";



GRANT ALL ON TABLE "internal"."report_snapshot_assets" TO "service_role";



GRANT ALL ON TABLE "internal"."report_snapshots" TO "service_role";



GRANT ALL ON TABLE "internal"."review_access_attempts" TO "service_role";



GRANT ALL ON TABLE "internal"."review_access_sessions" TO "service_role";



GRANT ALL ON TABLE "internal"."review_demo_partners" TO "service_role";



GRANT ALL ON TABLE "internal"."storekit_notification_events" TO "service_role";



GRANT ALL ON TABLE "internal"."storekit_payloads" TO "service_role";



GRANT ALL ON TABLE "internal"."storekit_transactions" TO "service_role";



GRANT ALL ON TABLE "internal"."streak_restorations" TO "service_role";



GRANT ALL ON TABLE "internal"."widget_push_outbox" TO "service_role";



GRANT ALL ON TABLE "public"."content_report_targets" TO "service_role";
GRANT SELECT ON TABLE "public"."content_report_targets" TO "authenticated";



GRANT ALL ON TABLE "public"."content_reports" TO "service_role";
GRANT SELECT ON TABLE "public"."content_reports" TO "authenticated";



GRANT ALL ON TABLE "public"."conversation_threads" TO "service_role";



GRANT ALL ON TABLE "public"."couple_activity_events" TO "service_role";



GRANT ALL ON TABLE "public"."couple_days" TO "service_role";



GRANT ALL ON TABLE "public"."couple_members" TO "service_role";



GRANT ALL ON TABLE "public"."couples" TO "service_role";



GRANT ALL ON TABLE "public"."daily_answer_media" TO "service_role";



GRANT ALL ON TABLE "public"."daily_answer_partner_choice" TO "service_role";



GRANT ALL ON TABLE "public"."daily_answer_text" TO "service_role";



GRANT ALL ON TABLE "public"."daily_challenges" TO "service_role";



GRANT ALL ON TABLE "public"."daily_question_answers" TO "service_role";



GRANT ALL ON TABLE "public"."daily_question_instances" TO "service_role";



GRANT ALL ON TABLE "public"."daily_question_shuffles" TO "service_role";



GRANT ALL ON TABLE "public"."daily_question_threads" TO "service_role";



GRANT ALL ON TABLE "public"."latest_partner_locations" TO "service_role";



GRANT ALL ON TABLE "public"."location_sharing_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."media_assets" TO "service_role";



GRANT ALL ON TABLE "public"."memories" TO "service_role";



GRANT ALL ON TABLE "public"."memory_media" TO "service_role";



GRANT ALL ON TABLE "public"."memory_notes" TO "service_role";



GRANT ALL ON TABLE "public"."memory_threads" TO "service_role";



GRANT ALL ON TABLE "public"."notification_preferences" TO "service_role";



GRANT SELECT("user_id") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("streak_reminders_enabled"),UPDATE("streak_reminders_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("daily_challenge_enabled"),UPDATE("daily_challenge_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("partner_answered_enabled"),UPDATE("partner_answered_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("widget_updates_enabled"),UPDATE("widget_updates_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("location_updates_enabled"),UPDATE("location_updates_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("lock_screen_detail_level"),UPDATE("lock_screen_detail_level") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("revision") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."notification_preferences" TO "authenticated";


GRANT SELECT("memories_enabled"),UPDATE("memories_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";


GRANT SELECT("messages_enabled"),UPDATE("messages_enabled") ON TABLE "public"."notification_preferences" TO "authenticated";



GRANT ALL ON TABLE "public"."pairing_invites" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("created_by_user_id") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("status") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("expires_at") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("accepted_by_user_id") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("accepted_at") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("revoked_at") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("couple_id") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."pairing_invites" TO "authenticated";



GRANT ALL ON TABLE "public"."privacy_requests" TO "service_role";



GRANT SELECT("id"),INSERT("id") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("user_id"),INSERT("user_id") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("request_kind"),INSERT("request_kind") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("status") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("requested_at") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("verified_at") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("completed_at") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("cancelled_at") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("contact_email"),INSERT("contact_email") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("requester_note"),INSERT("requester_note") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("visible_status_message") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("revision") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."privacy_requests" TO "authenticated";



GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT("user_id") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("display_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("profile_photo_asset_id"),UPDATE("profile_photo_asset_id") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("time_zone_id"),UPDATE("time_zone_id") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("time_zone_updated_at"),UPDATE("time_zone_updated_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("onboarding_completed_at"),UPDATE("onboarding_completed_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("revision") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("moderation_status") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("deleted_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("provider_profile_photo_asset_id") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("provider_profile_photo_source") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."question_answer_kinds" TO "service_role";



GRANT ALL ON TABLE "public"."question_collections" TO "service_role";



GRANT ALL ON TABLE "public"."question_version_localizations" TO "service_role";



GRANT ALL ON TABLE "public"."question_versions" TO "service_role";



GRANT ALL ON TABLE "public"."questions" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."question_catalog_overview" TO "service_role";



GRANT ALL ON TABLE "public"."relationship_blocks" TO "service_role";



GRANT ALL ON TABLE "public"."relationship_pairs" TO "service_role";



GRANT ALL ON TABLE "public"."relationship_sync_events" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("user_id") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("couple_id") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("initiated_by_user_id") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("event_kind") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("reason") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("occurred_at") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("relationship_status") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("member_status") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("ended_at") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("delete_after") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("local_purge_scope") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."relationship_sync_events" TO "authenticated";



GRANT ALL ON TABLE "public"."streak_states" TO "service_role";



GRANT ALL ON TABLE "public"."subscription_products" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT SELECT("apple_product_id") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT SELECT("kind") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT SELECT("billing_period") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT SELECT("is_active") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."subscription_products" TO "authenticated";



GRANT ALL ON TABLE "public"."thread_message_media" TO "service_role";



GRANT ALL ON TABLE "public"."thread_messages" TO "service_role";



GRANT ALL ON TABLE "public"."user_devices" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("user_id") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("platform") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("apns_environment") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("locale") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("time_zone_id") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("app_version") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("last_seen_at") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("revision") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT("disabled_at") ON TABLE "public"."user_devices" TO "authenticated";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_entitlements" TO "service_role";



GRANT ALL ON TABLE "public"."widget_canvases" TO "service_role";



GRANT ALL ON TABLE "public"."widget_drawing_revisions" TO "service_role";



GRANT ALL ON TABLE "public"."widget_push_devices" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("user_id") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("widget_kind") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("apns_environment") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("locale") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("time_zone_id") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("app_version") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("last_seen_at") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("revision") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."widget_push_devices" TO "authenticated";



GRANT SELECT("disabled_at") ON TABLE "public"."widget_push_devices" TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON TABLES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";
