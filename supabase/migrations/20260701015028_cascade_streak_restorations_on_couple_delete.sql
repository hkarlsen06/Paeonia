-- Streak restoration rows are couple-owned cleanup metadata. The table was
-- added after the cascade-couple-deletion migration, so its couple FK kept the
-- original restrictive behavior and blocked deleting a couple.
alter table internal.streak_restorations
  drop constraint if exists streak_restorations_couple_id_fkey;

alter table internal.streak_restorations
  add constraint streak_restorations_couple_id_fkey
  foreign key (couple_id)
  references public.couples (id)
  on delete cascade;
