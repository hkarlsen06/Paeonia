alter table public.profiles
drop constraint profiles_onboarding_completed_fields_check,
add constraint profiles_onboarding_completed_fields_check
check (
  onboarding_completed_at is null
  or (
    time_zone_id is not null
    and char_length(btrim(time_zone_id)) between 1 and 128
    and time_zone_updated_at is not null
  )
);

create or replace function internal.auth_metadata_display_name(raw_user_meta_data jsonb)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
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

create or replace function internal.sync_profile_display_name_from_auth_metadata()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
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

create trigger sync_profile_display_name_from_auth_metadata
after update of raw_user_meta_data on auth.users
for each row
execute function internal.sync_profile_display_name_from_auth_metadata();

create or replace function internal.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
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

update public.profiles profile
set display_name = internal.auth_metadata_display_name(auth_user.raw_user_meta_data)
from auth.users auth_user
where profile.user_id = auth_user.id
  and profile.display_name is distinct from internal.auth_metadata_display_name(auth_user.raw_user_meta_data);

revoke update (display_name) on public.profiles from authenticated;
