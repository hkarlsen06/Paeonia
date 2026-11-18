# Privacy and data export

"Download my data" (More tab, Privacy and safety) answers the right of access (GDPR Art. 15) and the right to data portability (Art. 20) in the app. It is free, needs no email, and works without a subscription. The person gets their data as JSON files plus their original photos, videos, voice messages and drawings, in zip files, with a README that holds the supplementary information Art. 15 asks for.

The old manual `access` and `export` privacy requests are gone. Correction and deletion remain as requests.

## What the export contains

The scope rule: **your own content plus the shared context, never your partner's content.**

- **Yours.** Everything the person wrote, uploaded, chose or set: account, profile, devices (push tokens left out), notification and location settings, location, subscription and grant records, privacy requests and reports they filed, pairing history, analytics consent, answers, chat messages, memory notes, stories, notes, the letters they wrote, drawings, game moves and creations, reactions, favorites and the nickname they gave their partner (only in their own download). Always included, in every relationship they were part of that still has stored data.
- **Shared.** Things the couple holds as one object: the relationship, memories (title, date, place), countdowns, visits (dates and place, and `you_hid_the_photo_card`, whether the person hid the card that asks for photos after it, never whether the partner did) and the list of things to do together, the days the partners were together, streaks, chat threads, game boards, scores and results. Included only while the person is in the relationship, because after it ends the app hides them from that person too.
- **Your partner's.** What the partner wrote or uploaded, their files, location, devices, settings and private marks. Never included. Where a shared row mixes both, the export keeps the person's part. A Story Chain story keeps their lines and shows only the number and time of the partner's lines. A hidden game secret (a word, a spot, a photo location) stays out until the app itself would show it. Why a relationship ended is left off the couple row, and the report behind a moderated row is left off that row, because either can show the person that their partner blocked or reported them. The person's own reason is in their `relationship_sync_events`, where a partner's block or report reads as a leave.
- **Reports about the person** are left out. Art. 15(4) protects the person who reported.

Why this rule. Art. 15(4) and Art. 20(4) say the copy must not harm the rights and freedoms of others, and Art. 20 covers data the person provided. A partner's message, photo or location is the partner's personal data. Publishing it to the other partner through a download would also bypass the app's own rules, such as hiding an answer until both have answered. Keeping to "yours plus shared" needs no per-row visibility checks, so the export cannot leak what the app would not show. The privacy policy says the same in its "Your choices and rights" section.

The days the partners were together (`together_days`, `backend/convex/lib/together.ts`) hold dates only, never a place, as runs of days from a first to a last date. They let the streak and some reminders rest on those days.

- **From location.** When both share and two recent, precise fixes put the phones less than 1000 m apart, the server stores that one date. A partner who paused still shares, and their last fix counts, as the map still shows it to the other partner, so a pause changes nothing the other partner sees. The next day counts only if it gets its own match. A later fix, a pause or turning sharing off changes no stored date. The server keeps no other location history.
- **From visits.** A visit counts on its own dates, from the day they were saved. When a visit's dates change or it is deleted, the server first stores the days it covered that already ended, so a past day stays what it was.
- **How long.** The retention job (`retention.ts`) deletes each date 45 days after it. The streak reads back at most 32 days. Turning sharing off leaves the stored dates, because a day that ended must not change what the streak already counted. They are deleted when the relationship ends or account deletion begins (`endRelationshipForPair`), with the latest locations.
- **Trust.** The server cannot check that a fix is real. A partner who sends made-up coordinates near the other's last position can make a together day. It rests the couple's streak and some reminders that day and reveals nothing about the other partner. It does not open a letter written for the next meeting either. Only a fix from the author's own phone, near the recipient's latest fix, delivers that letter, so the recipient's fix alone cannot bring it on. A visit is the other way such a letter arrives, at 20:00 on the recipient's clock on the visit's first day, but only when that first day was set at least 20 hours before then. The server compares the two instants, with the recipient's zone as their phone last reported it, so the zones the partners were in when the visit was planned do not matter. Either partner can plan a visit. So the recipient can bring the letter on by planning a visit before their own first day starts, and the author sees that visit on the Us tab for at least 20 hours before the letter arrives, whatever zone the recipient's phone reports. A new zone moves the evening. Further east it comes earlier, as early as the evening before the first day on the clock the recipient had, and a visit planned the evening before can stop counting. Further west it comes later, and a visit planned early on its own first day can count. A visit brings on only letters written before its first day had begun in every zone, at noon UTC that day, so a letter written after a visit is never brought on by it. A visit planned, or moved to a new first day, less than 20 hours before that evening brings nothing on by time. A new last day or place changes nothing. A visit planned ahead still delivers the letter when the two do not meet after all, and the recipient can delete the visit once the letter has arrived.

What the export cannot hold, and the README says so: usage statistics at PostHog (the person writes to contact@paeonia.no), and sign-in details at Apple, Google and Clerk.

## Design

A "Download my data" request is a job, not a request-response call, because years of photos do not fit in one transaction or one action. `dataExport.ts` and `dataExportBuild.ts` hold the flow.

- A zip file never holds more than 96 MiB (`PAEONIA_EXPORT_PART_LIMIT_BYTES`).
- Download links are signed with `PAEONIA_MEDIA_URL_SECRET` and a `data-export.` prefix, like `GET /media`. The signature is the only credential, so a link works for its hour without an auth header, and an expired or deleted download answers 404.
- An export is never made at request time, never stored longer than three days, and a failure leaves no files behind (the person can ask again).

## One registry keeps it complete

`backend/convex/lib/dataExportRegistry.ts` lists every table in `schema.ts`. `TABLE_EXPORTS` is typed `{ [T in TableNames]: TableExport }`, so a new table without an entry fails `npm run typecheck`, and `lib/dataExportRegistry.test.ts` checks the entries.

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
