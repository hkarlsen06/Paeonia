create or replace function internal.record_storekit_server_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_app_account_token uuid,
  p_apple_product_id text,
  p_web_order_line_item_id text,
  p_status text,
  p_purchased_at timestamptz,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_revocation_reason text,
  p_signed_notification_payload text,
  p_signed_transaction_info text,
  p_payload_json jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
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

create or replace function public.record_storekit_server_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_app_account_token uuid,
  p_apple_product_id text,
  p_web_order_line_item_id text,
  p_status text,
  p_purchased_at timestamptz,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_revocation_reason text,
  p_signed_notification_payload text,
  p_signed_transaction_info text,
  p_payload_json jsonb
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog
as $$
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

revoke all on function internal.record_storekit_server_notification(
  uuid,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  jsonb
) from public, anon, authenticated;
grant execute on function internal.record_storekit_server_notification(
  uuid,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  jsonb
) to service_role;

revoke all on function public.record_storekit_server_notification(
  uuid,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  jsonb
) from public, anon, authenticated;
grant execute on function public.record_storekit_server_notification(
  uuid,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  jsonb
) to service_role;
