---
name: paeonia-questions
description: Add, edit, version, localize or sync Paeonia questions (daily questions, topic questions, Flirt) in backend/questions/. Use for any question prompt, answer kind, topic, or catalog sync to a backend.
---

# Paeonia questions

Questions are content, not schema. The markdown tree in `backend/questions/` is the source of truth, and `scripts/sync-question-catalog` uploads it to Convex (`catalog:sync_catalog` in `backend/convex/catalog.ts`). Paeonia writes every question. No question may sound like the partner wrote it.

Before you write or change any prompt text, read [writing.md](writing.md). It holds the voice rule, what makes a good question, and the Topics, Flirt and Norwegian rules.

## 1. Check for duplicates

Search `backend/questions/system/` and `backend/questions/topic/` for the same intent, not only the same words: compare keys, prompts, short prompts and answer kinds. If the intent exists, skip the new question or version the existing one (step 4). A topic question must not repeat a daily question's intent, or the other way round.

## 2. Write the files

```text
backend/questions/
|-- system/<question_key>/              daily questions
|   |-- question.md
|   `-- versions/v001/
|       |-- version.md
|       `-- locales/{en,nb}.md
`-- topic/<topic_key>/
    |-- topic.md
    |-- locales/{en,nb}.md
    `-- <question_key>/                 same layout as a system question
```

Each file is YAML front matter only. Copy a neighbouring question for the exact shape (prompts use the `>-` block style).

- `question.md`: `collection`, `key`, `status`, `resurfaceable`, `resurface_after_months`. Topic questions add `topic` and `sort_order`.
- `version.md`: `version_number`, `status`, `active_from`, `retired_at`, `answer_kinds`.
- `locales/<locale>.md`: `locale`, `prompt` (3-500 characters), `short_prompt` (3-160). An `either_or` version adds `option_a` and `option_b`.
- `topic.md`: `key`, `status`, `sort_order` (shelf order), `private` (true for Flirt, so its chat pushes name only the sender). Topic `locales/<locale>.md`: `locale`, `title` (1-60 characters), `subtitle` (at most 160).

Rules:

- `<question_key>` is stable lowercase snake case naming the lasting intent. It ties together answer history, resurfacing and suppression.
- Both `en` and `nb` locales are required.
- New questions start with `status: draft` on the question and the version. Switch both to `active` after a clean dry run.
- Daily questions: `resurfaceable: true` with `resurface_after_months: 6` for evergreen prompts, `resurfaceable: false` for one-time prompts that would feel stale if repeated.
- Topic questions: `resurfaceable: false`, `resurface_after_months: null`, and `sort_order` with the easiest questions first. A topic with `status: draft` stays hidden even when its questions are active.

## 3. Pick answer kinds

A version has one or two answer kinds. The app shows the composer for exactly those kinds, so the kinds must match what the prompt asks the person to do.

- `text`: the default for reflective prompts.
- `photo`: the answer is something the person can show. A prompt about a photo, a screenshot, or an object near them takes `photo`, usually with `text`.
- `voice`: tone, presence or hearing the person matters.
- `partner_choice`: the answer is one member of the couple.
- `either_or`: the prompt offers exactly two options ("Would you rather spend a week by the sea or in the mountains?").

`text` + `photo`, `text` + `voice` and `text` + `partner_choice` show both inputs at once. The person can send either part or both, and the prompt invites both without demanding either: "Show or describe...", "Write it or say it", "Pick or describe...". Other two-kind pairings show a picker and send one mode.

`either_or` stands alone or pairs with `text`, which adds an optional "why" line under the two options. Each locale then carries `option_a` and `option_b` in the order the prompt names them, at most 40 characters, written as plain options ("By the sea", never "I'd pick the sea"). They must read well in "You picked X. Robin picked Y." and "You both picked X".

Name a mode in the prompt only when its kind is allowed: "Send a photo" needs `photo`, "Record a voice note" needs `voice`.

## 4. Version an existing question

A version's prompts, short prompts, option labels and answer kinds are immutable once synced. Make a new version when any of them changes meaning, including a localization change that alters what the person answers. Keep the key when the intent stays the same. Use a new key when old answers should no longer count as history for the new prompt.

1. Add `versions/vNNN/` (the next number) with `version.md` and both locales, `status: active`.
2. In the old `version.md`, set `status: retired` and `retired_at` to the current UTC time (`"2026-10-28 01:19:06+00"`). Leave its prompts and answer kinds as they were.
3. Sync (step 5).

Until launch, the sync also moves every daily question already handed out onto the new version, so a fix reaches today's questions. That loop in `catalog.ts` must go before launch, so answers keep the version they were written for.

To stop a question from being picked, retire it. Keep the files of any question that has answers.

## 5. Sync

From the repository root:

```bash
scripts/sync-question-catalog            # dry run: validates files, lists pending changes
scripts/sync-question-catalog --apply    # uploads, after a dry run of every chunk passes
scripts/sync-question-catalog --emit-json  # prints the payload, contacts no deployment
```

It targets the dev deployment in `backend/.env.local`. For `api.paeonia.no`, sync from local `main` with:

```bash
CONVEX_DEPLOYMENT= CONVEX_SELF_HOSTED_URL=https://api.paeonia.no \
CONVEX_SELF_HOSTED_ADMIN_KEY="$(ssh one-s cat /srv/paeonia/convex/admin-key)" \
scripts/sync-question-catalog
```

`CONVEX_DEPLOYMENT=` must be set to empty, or the CLI also reads the dev deployment from `.env.local` and refuses to run. Never write the admin key to a file.

The sync rebuilds `topic_catalog`, the copy the topic screens read. Change catalog rows only through the sync, and never insert daily question instances by hand: the backend picks active questions and creates them.

## Done when

- The dry run lists only the changes you meant, and after `--apply` a second dry run prints "No catalog changes found."
- Every new or changed prompt passes each rule in [writing.md](writing.md), in both `en` and `nb`.
- Every prompt's answer kinds match what it asks the person to do.
