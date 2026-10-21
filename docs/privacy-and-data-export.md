# Privacy and data export

"Download my data" (Us tab, Privacy and safety) answers the right of access (GDPR Art. 15) and the right to data portability (Art. 20) in the app. It is free, needs no email, and works without a subscription. The person gets their data as JSON files plus their original photos, voice messages and drawings, in zip files, with a README that holds the supplementary information Art. 15 asks for.

The old manual `access` and `export` privacy requests are gone. Correction and deletion remain as requests.

## What the export contains

The scope rule: **your own content plus the shared context, never your partner's content.**

- **Yours.** Everything the person wrote, uploaded, chose or set: account, profile, devices (push tokens left out), notification and location settings, location, subscription and grant records, privacy requests and reports they filed, pairing history, analytics consent, answers, chat messages, memory notes, stories, notes, drawings, game moves and creations, reactions, favorites and the nickname they gave their partner (only in their own download). Always included, in every relationship they were part of that still has stored data.
- **Shared.** Things the couple holds as one object: the relationship, memories (title, date, place), countdowns, streaks, chat threads, game boards, scores and results. Included only while the person is in the relationship, because after it ends the app hides them from that person too.
- **Your partner's.** What the partner wrote or uploaded, their files, location, devices, settings and private marks. Never included. Where a shared row mixes both, the export keeps the person's part. A Story Chain story keeps their lines and shows only the number and time of the partner's lines. A hidden game secret (a word, a spot, a photo location) stays out until the app itself would show it.
- **Reports about the person** are left out. Art. 15(4) protects the person who reported.

Why this rule. Art. 15(4) and Art. 20(4) say the copy must not harm the rights and freedoms of others, and Art. 20 covers data the person provided. A partner's message, photo or location is the partner's personal data. Publishing it to the other partner through a download would also bypass the app's own rules, such as hiding an answer until both have answered. Keeping to "yours plus shared" needs no per-row visibility checks, so the export cannot leak what the app would not show. The privacy policy says the same in its "Your choices and rights" section.

What the export cannot hold, and the README says so: usage statistics at PostHog (the person writes to contact@paeonia.no), and sign-in details at Apple, Google and Clerk.

## Design

A "Download my data" request is a job, not a request-response call, because years of photos do not fit in one transaction or one action.

1. `dataExport:request_data_export` (mutation) checks the session, refuses a pending account deletion, applies the `dataExportRequest` rate limit (3 a day), replaces any earlier finished download, inserts a `data_exports` row and schedules `dataExportBuild:collect_data`. A request while one is building returns the running job.
2. `collect_data` (a Node action) reads the registry tables one by one through paged internal queries. It cuts each table into JSON files of about 4 MiB (`PAEONIA_EXPORT_CHUNK_BYTES`), deflates them and stores each one as a `_storage` blob with a `data_export_chunks` row, so a table is never held whole. After five minutes (`PAEONIA_EXPORT_COLLECT_BUDGET_MS`) it stops between tables and schedules itself to go on. A table that fits in one file is `folder/table.json`. A bigger one is `folder/table-001.json`, `-002.json` and so on. Tables that others read keys from (`child` tables and `referencedBy`) are read again from the database when the action went on in a new run.
3. When the last table is collected, the same action plans the zip files: the data files first, then the media files, with part 1 keeping 1 MiB free for the README and `manifest.json`. `build_part` then builds one zip file per action, chained through the scheduler. It adds the data files and media files planned for that part, and for part 1 the README and `manifest.json`, which says which zip file holds each file. A zip file never holds more than 96 MiB (`PAEONIA_EXPORT_PART_LIMIT_BYTES`), and once a part is stored its data files are deleted. A data file or zip file that was stored but could not be recorded is deleted at once (`storeAndRecord` in `lib/dataExportFiles.ts`). No action holds more than one zip file or runs long, so neither the memory nor the ten-minute action limit grows with the size of the account.
4. The last part marks the export `ready`, sets `expires_at` three days out and queues the `data_export_ready` push.
5. The app subscribes to `dataExportStatus:get_data_export` (status, progress from 0 to 1, counts). When it is ready, `create_data_export_download_links` returns one signed `GET /data-export` link per zip, valid for an hour. The app downloads them and hands the files to the share sheet.
6. The hourly `expire-data-exports` job deletes the zip files after three days and gives up on builds older than two hours. A person can delete a finished download at once. Account deletion deletes all of them. `media:sweep_orphan_storage` knows the parts and data files, so it does not delete them.

Links are signed with `PAEONIA_MEDIA_URL_SECRET` and a `data-export.` prefix, like `GET /media`. The signature is the only credential, so a link works for its hour without an auth header, and a download that has expired or been deleted answers 404.

An export is never made at request time, never stored longer than three days, and a failure leaves no files behind (`failed` status, the person can ask again).

## One registry keeps it complete

`backend/convex/lib/dataExportRegistry.ts` lists every table in `schema.ts`: how its rows tie to a person (`own`, `couple`, or `child` of an exported table), the index to read them with, the fields to hide, an optional `select` that keeps or reshapes a row, and a plain-language description in English and Norwegian. A table that holds no personal data of the person is `excluded` with a reason.

`TABLE_EXPORTS` is typed `{ [T in TableNames]: TableExport }`, so a new table without an entry fails `npm run typecheck`. `lib/dataExportRegistry.test.ts` checks the same at run time and also checks that every field and index named in an entry exists, that fields that look like secrets are hidden, that parents come before children, and that every exclusion has a reason.

When you add a table:

1. Decide whose data a row is. A row with a `user_id`-like field is `own`. A row of the couple is `shared` (current relationship only) or `yours` (rows of the couple that one person authored). A table that hangs off a parent row is `child`.
2. Add the entry with its description in both languages. Hide any secret field. Use `select` where one row mixes the person's and the partner's data or holds a game secret.
3. If the table holds nothing personal (a catalog, bookkeeping, a raw log), use `excluded` and write the reason.

A new field on an existing table needs no change: rows are exported whole, minus the `hide` list.

## Limits and what to verify

- Parts are built in memory. If a deployment is short of memory, lower `PAEONIA_EXPORT_PART_LIMIT_BYTES` (it must stay above the largest single file, 50 MiB).
- The download streams a stored blob through an HTTP action. If the host caps HTTP action responses, lower the part size to stay under the cap.
- A very large account gives many zip files (about one for every 96 MiB of photos).
- A file that vanishes from storage between planning and building is skipped and counted (`skipped_file_count`), and the README says how many.
