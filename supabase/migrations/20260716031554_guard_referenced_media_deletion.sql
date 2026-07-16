-- Explicit cleanup requests must never override the canonical reference graph.
-- Orphan-triggered cleanup already uses media_asset_has_live_reference; apply
-- the same invariant to the app-callable profile-photo path and the worker claim.

-- A previous client bug could queue a just-linked asset and leave the profile
-- pointing at bytes the cleanup worker had already removed. Those references
-- cannot be recovered; clear them so clients render a valid fallback and can
-- replace the photo normally.
update public.profiles profile
set profile_photo_asset_id = null
from public.media_assets asset
where profile.profile_photo_asset_id = asset.id
  and asset.storage_delete_status = 'deleted';

update public.profiles profile
set
  provider_profile_photo_asset_id = null,
  provider_profile_photo_source = null
from public.media_assets asset
where profile.provider_profile_photo_asset_id = asset.id
  and asset.storage_delete_status = 'deleted';

update public.media_assets asset
set
  deleted_at = null,
  storage_delete_status = 'none',
  last_storage_delete_error = null
where asset.storage_delete_status in ('pending', 'retrying', 'failed')
  and internal.media_asset_has_live_reference(asset.id);

create or replace function internal.mark_media_for_deletion(p_media_asset_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
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

revoke all on function internal.mark_media_for_deletion(uuid) from public, anon, authenticated;
grant execute on function internal.mark_media_for_deletion(uuid) to service_role;

revoke all on function internal.claim_media_storage_deletes(timestamptz, integer, interval, integer)
from public, anon, authenticated;
grant execute on function internal.claim_media_storage_deletes(timestamptz, integer, interval, integer)
to service_role;
