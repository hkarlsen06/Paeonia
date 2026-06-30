-- Authenticated clients do not have USAGE on the private `internal` schema.
-- These public wrappers call `internal.*`, so they must execute as definers
-- while the internal implementations continue to enforce auth with auth.uid().

alter function public.create_memory(
  uuid,
  text,
  date,
  text,
  uuid[],
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.create_memory(
  uuid,
  text,
  date,
  text,
  uuid[],
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.update_memory(
  uuid,
  integer,
  text,
  date,
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.update_memory(
  uuid,
  integer,
  text,
  date,
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.hide_memory(
  uuid,
  integer,
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.hide_memory(
  uuid,
  integer,
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.upsert_memory_note(
  uuid,
  integer,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.upsert_memory_note(
  uuid,
  integer,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.attach_memory_media(
  uuid,
  uuid[],
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.attach_memory_media(
  uuid,
  uuid[],
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.remove_memory_media(
  uuid,
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.remove_memory_media(
  uuid,
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.create_memory_thread_with_message(
  uuid,
  text,
  uuid[],
  uuid,
  uuid,
  bigint,
  timestamptz
) security definer;
alter function public.create_memory_thread_with_message(
  uuid,
  text,
  uuid[],
  uuid,
  uuid,
  bigint,
  timestamptz
) set search_path = pg_catalog;

alter function public.get_memories(
  timestamptz,
  uuid,
  integer
) security definer;
alter function public.get_memories(
  timestamptz,
  uuid,
  integer
) set search_path = pg_catalog;
