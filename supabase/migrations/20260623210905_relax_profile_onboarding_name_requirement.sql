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
