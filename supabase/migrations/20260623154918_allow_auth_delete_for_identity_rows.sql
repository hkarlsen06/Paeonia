alter table public.profiles
drop constraint profiles_user_id_fkey,
add constraint profiles_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;

alter table public.notification_preferences
drop constraint notification_preferences_user_id_fkey,
add constraint notification_preferences_user_id_fkey
foreign key (user_id)
references auth.users (id)
on delete cascade;
