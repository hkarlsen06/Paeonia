# Couple Question Guidelines

Paeonia questions are product-authored daily ritual prompts. They come from Paeonia, not from either partner. Every question must preserve that framing.

## Core Voice Rule

Ask about the partner in third person or neutral relationship language.

Use:

- "What is one memory you have of them that you keep thinking of?"
- "What is one small thing your partner did recently that stayed with you?"
- "What is one thing the two of you could make easier this week?"

Do not use:

- "What is one memory you have of me that you keep thinking of?"
- "What did you miss most about me today?"
- "What should we do tomorrow?"

"You" is fine because Paeonia is asking the signed-in user. Avoid "I", "me", "my", "we", and "our" when those words could sound like they came from the partner. Prefer "them", "your partner", "the two of you", or "your relationship".

## Product Fit

Questions should support Paeonia's promise: small, reliable daily rituals that make distance feel less passive. The tone should feel private, calm, warm, premium, and emotionally grounded. Romantic is fine. Cheesy, needy, or manipulative is not.

Good questions:

- Take 1-3 minutes to answer.
- Ask one clear thing.
- Give the user a specific handle, such as a moment, object, message, choice, place, sound, plan, or timeframe.
- Work asynchronously across time zones.
- Make the relationship feel present without requiring a full conversation.
- Leave room for the couple's own content to carry the feeling.
- Are understandable to an ordinary 16-year-old.
- Feel safe to answer on an ordinary busy day.

Avoid questions that:

- Sound like a partner wrote them.
- Duplicate an existing question's intent, even if the wording is different.
- Create guilt, pressure, jealousy, tests, or scorekeeping.
- Assume gender, marriage, cohabitation, sex, religion, holidays, or a specific relationship stage.
- Ask for sensitive disclosures that do not fit a lightweight daily ritual.
- Try to diagnose the relationship or force conflict processing.
- Depend on both partners being awake or available at the same time.
- Expose private content in a short prompt, push, or compact card.
- Ask the user to invent too much context before they can answer.

## Originality And Specificity

Before drafting a new question, inspect the existing catalog in
`supabase/questions/system/` and, when needed, the live database catalog. Compare
the stable key, full prompt, short prompt, answer kinds, and underlying user
intent. Do not add near-duplicates. If the intent already exists, either skip the
new question or version the existing question when the wording or answer contract
really needs to change.

Questions should feel easy to start answering. Give the user one concrete angle
instead of asking them to imagine the whole situation from scratch. Specific does
not mean long or narrow; it means the prompt has a clear object, scene, or
constraint.

Prefer:

- "What TV series reminds you the most of the future you imagine with your partner?"

Avoid:

- "Record a voice note of something your partner would want to hear."

The first prompt gives the user a concrete reference point and emotional angle.
The second makes the user invent the context, the content, and the reason it
should be a voice note before they can answer.

## Copy Shape

Write full prompts as complete, direct questions or instructions.

- Full prompt: shown in the answering flow.
- Short prompt: shown in compact surfaces such as cards and lists.

The short prompt must summarize the task without sounding like a notification from the partner. Keep it clear and calm.

Examples:

| Intent | Full prompt | Short prompt |
| --- | --- | --- |
| Memory | What is one memory you have of them that you keep thinking of? | A memory that stayed |
| Gratitude | What is one small thing about your partner you appreciated today? | A small appreciation |
| Plans | What is one small thing the two of you could look forward to this week? | Something to look forward to |
| Comfort | What could help your partner feel close to you this week? | A way to feel close |

## Answer Kinds

The database supports these answer kinds:

- `text`
- `photo`
- `voice`
- `partner_choice`

A question version must have at least one answer kind and at most two answer kinds. The app receives `answer_kinds` from the daily question RPCs and shows the matching composer.

Use answer kinds this way:

- `text`: default for reflective prompts.
- `photo`: for prompts where the answer should be something the user can show, not just describe.
- `voice`: for prompts where tone, presence, or hearing the person matters.
- `partner_choice`: for prompts where the answer is one member of the couple.

Use a single answer kind when the prompt clearly calls for one mode. Use two answer kinds when both modes naturally fit the same question.

### Combine `text` with `photo` or `partner_choice` (prefer this)

`text` + `photo` and `text` + `partner_choice` are **combined** answers: the app shows **both composers at once** and the partner can add one, the other, or both in a single answer (a photo with a caption, or a pick with a few words of why). This is usually richer than forcing a choice, so reach for it whenever a prompt can be both shown/picked **and** described — e.g. "Show or describe one small thing that caught the mood of your day," or "Who's more likely to plan the next trip — and why?". The reveal shows every part the partner filled in.

Other two-kind pairings (anything involving `voice`) are **either/or**: the app shows a single-kind picker and the partner chooses one mode. So `text` + `voice` means "write it or say it," not both.

The wording must match the answer kinds, and for combined questions it should invite both parts without demanding either (each is optional). Do not write "Record a voice note" unless `voice` is allowed. Do not write "Send a photo" unless `photo` is allowed. For `partner_choice`, make the prompt about choosing a person (optionally with a reason when paired with `text`).

## Localization

Question content lives in the database, not in Xcode String Catalog generated symbols. Add both localizations directly to `public.question_version_localizations`.

Required locales:

- `en`
- `nb`

Each version needs:

- `prompt`: 3-500 characters.
- `short_prompt`: 3-160 characters.

Localize meaning, not word order. Norwegian Bokmal should sound natural to a normal user, not like translated database text. Be extra careful with the core voice rule in Norwegian: avoid "meg", "min", "vi", and "vår" when those words could sound like the partner is speaking. Prefer "partneren din" when "dem" would feel vague.

Good:

- EN: "What is one memory you have of them that you keep thinking of?"
- NB: "Hva er ett minne om partneren din som du stadig tenker på?"

Bad:

- EN: "What is one memory you have of me that you keep thinking of?"
- NB: "Hva er ett minne om meg som du stadig tenker på?"

For app chrome around the question UI, keep using String Catalog symbols and the `./scripts/xcstrings-set` helper. For server-authored question content, use database localizations.

## Database Model

System questions use these tables:

- `question_collections`: owns a system, custom, or mini-game collection.
- `questions`: stable question identity and resurfacing rules.
- `question_versions`: versioned copy and answer contract for a question.
- `question_version_localizations`: localized full and short prompts.
- `question_answer_kinds`: allowed answer kinds for a version.

Daily runtime rows then reference question versions:

- `daily_question_instances`
- `daily_question_answers`
- `daily_answer_text`
- `daily_answer_media`
- `daily_answer_partner_choice`
- `daily_question_shuffles`

Do not insert daily instances directly for content authoring. The backend RPCs choose active system questions and create instances.

## Adding Questions

Question catalog rows are content, not schema. For inserting, updating, retiring, or versioning questions, run SQL directly through the Supabase MCP `execute_sql` tool. Do not create migrations solely for question-content rows; that adds noise.

Before writing SQL, check `supabase/questions/system/` and the target database
for existing questions. Confirm the new prompt is original in intent, not only in
wording, and record the new or changed content in `supabase/questions/`.

Use migrations only when the change modifies schema, constraints, indexes, RPCs, triggers, policies, grants, or other database behavior that must be replayed through deployment history.

Use a transaction-safe `do $$ ... $$;` block. Insert into draft states first, then activate after localizations and answer kinds exist. The readiness triggers require active versions to have both `en` and `nb` localizations and at least one answer kind.

Use this shape for a batch:

```sql
do $$
declare
  system_collection_id uuid;
  inserted_question_id uuid;
  inserted_version_id uuid;
  seed_row record;
  seed_answer_kind text;
begin
  select id
  into system_collection_id
  from public.question_collections
  where kind = 'system'
    and status = 'active'
  order by created_at
  limit 1;

  if system_collection_id is null then
    insert into public.question_collections (kind, status)
    values ('system', 'draft')
    returning id into system_collection_id;
  end if;

  for seed_row in
    select *
    from (
      values
        (
          'memory_that_stayed',
          'What is one memory you have of them that you keep thinking of?',
          'A memory that stayed',
          'Hva er ett minne om partneren din som du stadig tenker på?',
          'Et minne som ble værende',
          true,
          6::smallint,
          array['text']::text[]
        )
    ) as seed(
      question_key,
      en_prompt,
      en_short_prompt,
      nb_prompt,
      nb_short_prompt,
      resurfaceable,
      resurface_after_months,
      answer_kinds
    )
  loop
    insert into public.questions (
      collection_id,
      key,
      status,
      resurfaceable,
      resurface_after_months
    ) values (
      system_collection_id,
      seed_row.question_key,
      'draft',
      seed_row.resurfaceable,
      seed_row.resurface_after_months
    )
    returning id into inserted_question_id;

    insert into public.question_versions (
      question_id,
      version_number,
      status,
      active_from
    ) values (
      inserted_question_id,
      1,
      'draft',
      now()
    )
    returning id into inserted_version_id;

    insert into public.question_version_localizations (
      question_version_id,
      locale,
      prompt,
      short_prompt
    ) values
      (inserted_version_id, 'en', seed_row.en_prompt, seed_row.en_short_prompt),
      (inserted_version_id, 'nb', seed_row.nb_prompt, seed_row.nb_short_prompt);

    foreach seed_answer_kind in array seed_row.answer_kinds loop
      insert into public.question_answer_kinds (
        question_version_id,
        answer_kind
      ) values (
        inserted_version_id,
        seed_answer_kind
      );
    end loop;

    update public.question_versions
    set status = 'active'
    where id = inserted_version_id;

    update public.questions
    set status = 'active'
    where id = inserted_question_id;
  end loop;

  update public.question_collections
  set status = 'active'
  where id = system_collection_id
    and status = 'draft';
end;
$$;
```

After applying locally or remotely, verify:

```sql
select
  question.key,
  version.version_number,
  version.status,
  array_agg(answer_kind.answer_kind order by answer_kind.answer_kind) as answer_kinds,
  count(localization.locale) filter (where localization.locale = 'en') as en_count,
  count(localization.locale) filter (where localization.locale = 'nb') as nb_count
from public.question_collections collection
join public.questions question
  on question.collection_id = collection.id
join public.question_versions version
  on version.question_id = question.id
join public.question_answer_kinds answer_kind
  on answer_kind.question_version_id = version.id
join public.question_version_localizations localization
  on localization.question_version_id = version.id
where collection.kind = 'system'
group by question.key, version.version_number, version.status
order by question.key;
```

Also check the app-facing catalog shape:

```sql
select *
from public.get_active_question_catalog(null)
order by question_key, locale;
```

## Versioning

Treat `questions.key` as stable identity. It is used for answer history, resurfacing, suppression, and future analytics.

Use a new `question_versions` row when:

- Prompt or short prompt meaning changes.
- Answer kinds change.
- A localization changes enough to alter what the user is answering.

Keep the same `questions.key` when the intent is the same. Create a new question key when the meaning changes enough that old answers should not count as history for the new prompt.

To replace an active version:

1. Insert the new version as `draft` with `version_number = previous max + 1`.
2. Insert both `en` and `nb` localizations.
3. Insert one or two `question_answer_kinds`.
4. Retire the old active version by setting `status = 'retired'` and `retired_at = now()`.
5. Activate the new version by setting `status = 'active'` and `active_from = now()`.

Do not edit historical versions in place after they have been used by daily instances. Old answers should continue to point at the version the user actually answered.

Retire or archive a question when it should no longer be selected. Do not delete a question that has answers, threads, or other relationship content.

## Resurfacing

`questions.resurfaceable` controls whether a user can see the same stable question identity again.

- Use `resurfaceable = true` for evergreen questions that can feel different later.
- Use `resurface_after_months = 6` unless there is a strong product reason to change it.
- Use `resurfaceable = false` for one-time prompts where a repeated answer would feel stale or confusing.

The backend excludes non-resurfaceable questions a user has already answered. For resurfaceable questions, it can select them again after the configured window.

## Review Checklist

Before adding or changing questions, confirm:

- Existing questions were checked and this is not a duplicate or near-duplicate.

- No prompt sounds like it came from the partner.
- Each prompt has one clear ask.
- Each prompt gives a specific enough handle that the user can start answering quickly.
- The answer kinds match the user action the app can actually support.
- Both `en` and `nb` are present and natural.
- The short prompt is calm, compact, and not misleading.
- The question can be answered without guilt, pressure, or sensitive disclosure.
- The key is stable, lowercase snake case, and describes the durable intent.
- Versioning preserves old answers and daily instances.
- The SQL is scoped to the intended target database and verified with follow-up reads.
