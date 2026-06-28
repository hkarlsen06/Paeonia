drop view if exists public.question_catalog_overview;

create view public.question_catalog_overview
with (security_invoker = true)
as
with localization_pivot as (
  select
    localization.question_version_id,
    max(localization.short_prompt) filter (where localization.locale = 'en') as question_short,
    max(localization.prompt) filter (where localization.locale = 'en') as question_long,
    max(localization.short_prompt) filter (where localization.locale = 'nb') as norwegian_short,
    max(localization.prompt) filter (where localization.locale = 'nb') as norwegian_long,
    count(*) filter (where localization.locale = 'en') > 0 as has_english_localization,
    count(*) filter (where localization.locale = 'nb') > 0 as has_norwegian_localization
  from public.question_version_localizations localization
  group by localization.question_version_id
),
answer_kind_groups as (
  select
    answer_kind.question_version_id,
    array_agg(answer_kind.answer_kind order by answer_kind.answer_kind) as answer_kinds
  from public.question_answer_kinds answer_kind
  group by answer_kind.question_version_id
)
select
  localization_pivot.question_short,
  localization_pivot.question_long,
  localization_pivot.norwegian_short,
  localization_pivot.norwegian_long,
  question.resurfaceable,
  question.resurface_after_months,
  question.status as status,
  question.created_at as created_at,
  question.key as question_key,
  version.version_number,
  version.status as version_status,
  coalesce(answer_kind_groups.answer_kinds, array[]::text[]) as answer_kinds,
  cardinality(coalesce(answer_kind_groups.answer_kinds, array[]::text[])) as answer_kind_count,
  collection.kind as collection_kind,
  collection.status as collection_status,
  version.active_from,
  version.retired_at,
  version.created_at as version_created_at,
  question.updated_at as question_updated_at,
  collection.created_at as collection_created_at,
  collection.updated_at as collection_updated_at,
  localization_pivot.has_english_localization,
  localization_pivot.has_norwegian_localization,
  collection.kind = 'system'
    and collection.status = 'active'
    and question.status = 'active'
    and version.status = 'active'
    and coalesce(localization_pivot.has_english_localization, false)
    and coalesce(localization_pivot.has_norwegian_localization, false)
    and cardinality(coalesce(answer_kind_groups.answer_kinds, array[]::text[])) between 1 and 2
    as is_app_selectable,
  collection.id as collection_id,
  question.id as question_id,
  version.id as question_version_id,
  collection.couple_id as collection_couple_id,
  collection.created_by_user_id as collection_created_by_user_id,
  question.created_by_user_id as question_created_by_user_id
from public.question_collections collection
join public.questions question
  on question.collection_id = collection.id
join public.question_versions version
  on version.question_id = question.id
left join localization_pivot
  on localization_pivot.question_version_id = version.id
left join answer_kind_groups
  on answer_kind_groups.question_version_id = version.id;

comment on view public.question_catalog_overview is
  'Admin-only catalog overview with prompt/localization columns first for question review.';

revoke all on public.question_catalog_overview from public, anon, authenticated;
grant select on public.question_catalog_overview to service_role;
