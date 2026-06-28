create or replace view public.question_catalog_overview
with (security_invoker = true)
as
with required_locales(locale) as (
  values
    ('en'::text),
    ('nb'::text)
),
answer_kind_groups as (
  select
    answer_kind.question_version_id,
    array_agg(answer_kind.answer_kind order by answer_kind.answer_kind) as answer_kinds
  from public.question_answer_kinds answer_kind
  group by answer_kind.question_version_id
)
select
  collection.id as collection_id,
  collection.kind as collection_kind,
  collection.status as collection_status,
  collection.couple_id as collection_couple_id,
  collection.created_by_user_id as collection_created_by_user_id,
  collection.created_at as collection_created_at,
  collection.updated_at as collection_updated_at,
  question.id as question_id,
  question.key as question_key,
  question.status as question_status,
  question.resurfaceable,
  question.resurface_after_months,
  question.created_by_user_id as question_created_by_user_id,
  question.created_at as question_created_at,
  question.updated_at as question_updated_at,
  version.id as question_version_id,
  version.version_number,
  version.status as version_status,
  version.active_from,
  version.retired_at,
  version.created_at as version_created_at,
  required_locales.locale,
  localization.prompt,
  localization.short_prompt,
  localization.created_at as localization_created_at,
  localization.updated_at as localization_updated_at,
  localization.question_version_id is not null as has_localization,
  coalesce(answer_kind_groups.answer_kinds, array[]::text[]) as answer_kinds,
  cardinality(coalesce(answer_kind_groups.answer_kinds, array[]::text[])) as answer_kind_count,
  collection.kind = 'system'
    and collection.status = 'active'
    and question.status = 'active'
    and version.status = 'active'
    and localization.question_version_id is not null
    and cardinality(coalesce(answer_kind_groups.answer_kinds, array[]::text[])) between 1 and 2
    as is_app_selectable_locale
from public.question_collections collection
join public.questions question
  on question.collection_id = collection.id
join public.question_versions version
  on version.question_id = question.id
cross join required_locales
left join public.question_version_localizations localization
  on localization.question_version_id = version.id
  and localization.locale = required_locales.locale
left join answer_kind_groups
  on answer_kind_groups.question_version_id = version.id;

comment on view public.question_catalog_overview is
  'Admin-only catalog overview showing each question version against required locales and answer kinds.';

revoke all on public.question_catalog_overview from public, anon, authenticated;
grant select on public.question_catalog_overview to service_role;
