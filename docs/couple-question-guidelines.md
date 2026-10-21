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
`backend/questions/system/` and, when needed, the live database catalog. Compare
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

## Topics

Topics are extra questions grouped by theme, such as Travel and places or Someday, which a couple answers as many of as they like, apart from the daily questions. They live in `backend/questions/topic/<topic_key>/` (see `backend/questions/README.md`).

- Topic questions are evergreen. They ask who someone is, what they have lived and what they hope for, not what happened today. Avoid "today" and "this week".
- Check for duplicates across both `system/` and `topic/`. A topic question must not repeat the intent of a daily question, and the other way round.
- Order each topic so the easiest questions come first. `sort_order` in `question.md` sets the order.
- Everything else in this document applies to topic questions too.

## Flirt topic

Flirt is the one place where questions may be flirty and suggestive. Every couple can see it, so Flirt content must stay within the 16+ rating, suggestive and never explicit. The rest of this document still applies.

Flirt questions may ask about attraction, what someone likes about how their partner looks or dresses, kissing and being held, flirting, romantic evenings, and messages they would like to get.

Flirt questions never:

- Mention sex acts, nudity, or anything explicit.
- Ask for a detailed fantasy or say "describe in detail".
- Assume the couple has sex, or ask how often, how good, or with whom.
- Ask about past partners.
- Use the `photo` answer kind, so no prompt ever invites a photo of a body.
- Make "no" or skipping feel like a failure.

Every Flirt question must work for a couple who isn't having sex. It must be answerable in a few playful words, or skipped without a second thought. Flirt questions must also work for couples who are apart, so a question about being together is a what-if, such as "If your partner were next to you right now". The short prompt names the theme, never the detail. Flirt content never appears in pushes, widgets, Look Back or Home. If a draft would push the App Store rating above "frequent mature or suggestive themes" (16+), it doesn't belong in Paeonia. In Norwegian, keep the tone light and natural, and don't translate English slang.

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
- `either_or`

A question version must have at least one answer kind and at most two answer kinds. The app receives `answer_kinds` from the daily question RPCs and shows the matching composer.

Use answer kinds this way:

- `text`: default for reflective prompts.
- `photo`: for prompts where the answer should be something the user can show, not just describe.
- `voice`: for prompts where tone, presence, or hearing the person matters.
- `partner_choice`: for prompts where the answer is one member of the couple.
- `either_or`: "pick one of two", for prompts that offer exactly two options, such as "Would you rather spend a week by the sea or in the mountains?". The answer is one of the two.

Use a single answer kind when the prompt clearly calls for one mode. Use two answer kinds when both modes naturally fit the same question.

### Combine `text` with `photo` or `partner_choice` (prefer this)

`text` + `photo` and `text` + `partner_choice` are **combined** answers: the app shows **both composers at once** and the partner can add one, the other, or both in a single answer (a photo with a caption, or a pick with a few words of why). This is usually richer than forcing a choice, so reach for it whenever a prompt can be both shown/picked **and** described — e.g. "Show or describe one small thing that caught the mood of your day," or "Who's more likely to plan the next trip — and why?". The reveal shows every part the partner filled in.

Other two-kind pairings (anything involving `voice`) are **either/or**: the app shows a single-kind picker and the partner chooses one mode. So `text` + `voice` means "write it or say it," not both.

The wording must match the answer kinds, and for combined questions it should invite both parts without demanding either (each is optional). Do not write "Record a voice note" unless `voice` is allowed. Do not write "Send a photo" unless `photo` is allowed. For `partner_choice`, make the prompt about choosing a person (optionally with a reason when paired with `text`).

### `either_or` (pick one of two)

An `either_or` version is `either_or` alone or `either_or` + `text`. It combines with nothing else. With `text`, the app shows the two options and a short optional "why" line under them. The pick is always required, and the why line never answers on its own.

Each locale file of an `either_or` version also carries `option_a` and `option_b`, the two labels, in the same order as the prompt names them. Labels are short, at most 40 characters, and must read well in "You picked X. Robin picked Y." and "You both picked X". Write them as plain options, never in the first person: "By the sea", not "I'd pick the sea", and not "My favorite film". The labels are part of the version, like the prompts, so changing one needs a new version.

Other versions carry no labels. The sync rejects missing labels, labels on a version without `either_or`, and `either_or` with any kind other than `text`.

## Localization

Question content lives in the database, not in Xcode String Catalog generated symbols. Add both localizations in the question's `locales/` folder.

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

For app chrome around the question UI, keep using String Catalog symbols and the `./scripts/xcstrings-set` helper. For server-authored question content, use the localization files in `backend/questions/`.

## Database Model

System questions use these tables:

- `question_collections`: owns a system, custom, mini-game or topic collection. Each topic is its own collection, with its key, shelf order, `private` flag (Flirt: its chat pushes name only the sender) and names (`question_collection_localizations`).
- `questions`: stable question identity and resurfacing rules.
- `question_versions`: versioned copy and answer contract for a question.
- `question_version_localizations`: localized full and short prompts.
- `question_answer_kinds`: allowed answer kinds for a version.
- `topic_catalog`: a copy of each active topic's names and ready questions, rebuilt by `catalog:sync_catalog` for the topic reads. Never write it by hand. Run the sync after any change to a topic's catalog rows.

Daily runtime rows then reference question versions:

- `daily_question_instances`
- `daily_question_answers`
- `daily_answer_text`
- `daily_answer_media`
- `daily_answer_partner_choice`
- `daily_question_shuffles`

Do not insert daily instances directly for content authoring. The backend RPCs choose active system questions and create instances.

## Adding Questions

Question catalog rows are content, not schema. The source of truth is the markdown tree in `backend/questions/` (see `backend/questions/README.md` for the file format). Add or change a question there, then run the sync script.

Before writing a question, check `backend/questions/system/` for existing questions. Confirm the new prompt is original in intent, not only in wording.

1. Create `backend/questions/system/<question_key>/question.md` and a `versions/v001/` folder with `version.md`, `locales/en.md`, and `locales/nb.md`. Start with `status: draft` on the question and the version.
2. Run `scripts/sync-question-catalog` for a dry run. It validates the files and lists what would change.
3. Set `status: active` on the question and its version, and run the script again.
4. Run `scripts/sync-question-catalog --apply`.

The sync rejects an active version that lacks an `en` or `nb` localization, or that has no answer kinds or more than two. After applying, `npx convex data questions` lists the stored questions.

To point the script at the hosted deployment (`api.paeonia.no`), export `CONVEX_SELF_HOSTED_URL` and `CONVEX_SELF_HOSTED_ADMIN_KEY` in the shell first.

## Versioning

Treat `questions.key` as stable identity. It is used for answer history, resurfacing, suppression, and future analytics.

Use a new `question_versions` row when:

- Prompt or short prompt meaning changes.
- Answer kinds change.
- A localization changes enough to alter what the user is answering.

Keep the same `questions.key` when the intent is the same. Create a new question key when the meaning changes enough that old answers should not count as history for the new prompt.

To replace an active version:

1. Add the next `versions/vNNN/` folder with `version.md` and both locale files. Set `status: active`.
2. In the old version's `version.md`, set `status: retired` and add a `retired_at` timestamp. Leave its prompts and answer kinds unchanged.
3. Run `scripts/sync-question-catalog`, then `--apply`. The sync retires the old active version and activates the new one.

Do not edit historical versions in place after they have been used by daily instances. After launch, old answers should continue to point at the version the user actually answered. Until launch, the sync moves every daily instance of the question to the newly active version, so a wording fix also shows on questions already handed out. Remove that step in `backend/convex/catalog.ts` before launch.

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
- The dry run of `scripts/sync-question-catalog` lists only the intended changes.
