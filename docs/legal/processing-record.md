# Record of processing activities

GDPR Art. 30(1). Version 1, 18 November 2026.

- **Controller.** Hjalmar Karlsen, Storgata 61, 0182 Oslo, Norway, a private person. Email contact@paeonia.no.
- **Data protection officer and EU representative.** None. Neither is required.
- **The people.** Everyone below is an account holder aged 16 or older, unless the row says otherwise. A partner is another account holder.

The record follows the code. `backend/convex/lib/dataExportRegistry.ts` lists every table in `backend/convex/schema.ts`, and the last section of this record places each table in a row. A new table or processor needs a change here in the same commit. The small exemption in Art. 30(5) does not apply, because the processing is not occasional and includes Flirt answers.

## Processing by purpose

Legal bases refer to GDPR Art. 6(1). "Leipzig" means the rented server that runs the database and the application. "R2" means Cloudflare R2 file storage in the EU jurisdiction. Both store every row below unless the row says otherwise, and neither is a transfer out of the EEA.

| # | Purpose | Data | Legal basis | Recipients and processors | Transfers out of the EEA | Retention |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Account and sign-in | Sign-in id and method, email address, name, profile photo, language, time zone, which terms the person accepted | (b) contract | The partner sees the name and photo. Clerk, Inc. runs sign-in and sends the email code. Apple and Google run their own sign-in as separate controllers. | Clerk stores identity data in the USA, under the EU-US Data Privacy Framework and standard contractual clauses | Until account deletion, which clears the profile at once and the Clerk user within hours. The account row stays without the email address, so the same sign-in cannot make the account again. |
| 2 | Pairing and the relationship | Invites (the code only as a hash), who is paired with whom, start and end dates, birthdays if added, the private nickname for the partner, a log of relationship changes | (b) contract | The partner | None | An invite lasts 30 days. The nickname goes when the relationship ends, birthdays about 30 days later. The pair, membership and log rows hold ids and dates and have no end date in the code. |
| 3 | Shared content: questions, chat, memories, stories, notes, letters, drawings, games, dates, visits, streak | What the person wrote, chose, drew or uploaded, with the files, reactions, favorites and the days the couple was active | (b) contract. Free text can touch Art. 9 topics the person chose to write about. | The partner | None | Until the person deletes it. When a relationship ends it is hidden at once and deleted about 30 days later. A note lasts 24 hours. Hearts and anniversary recaps go when the relationship ends. |
| 4 | Flirt answers | Answers and chat messages in private topics, and when the person consented and to which text | (a) consent, with Art. 9(2)(a) explicit consent | The partner | None | Until the person turns Flirt off, which deletes what they wrote there. Otherwise as row 3. |
| 5 | Location sharing | Whether the person shares and since when, the consent text version, the latest position with its time and accuracy, the dates the two were within 1 km | (a) consent | The partner. OpenFreeMap and Apple Maps get the phone's IP address and the map area when the map is drawn. Apple Maps gets a place search, or a photo's position, to name a place. | Apple acts as its own controller. OpenFreeMap: see open points. | One position per person, overwritten by the next. Deleted when sharing is turned off, the relationship ends or account deletion starts. Each date is deleted after 45 days. |
| 6 | Calls | The live call (who, state, time), a chat row with the call's length or that it was missed, a connection report with no content | (b) contract. Connection reports: (f) legitimate interest in calls that work. | The partner's phone gets the person's IP address unless they paused location sharing. Cloudflare relays call setup, and call media when a direct path is not used. Apple delivers the ring. | Cloudflare, Inc. is a US company and relays encrypted media through its nearest site. Data Privacy Framework and standard contractual clauses. | The live row is deleted when the call ends. The chat row follows row 3. Connection reports: 30 days, or when the relationship ends. |
| 7 | Presence | That the person has the app, a chat, a game or the drawing open, and that they are typing | (b) contract, with a switch that turns it off | The partner | None | 30 to 60 seconds after the last signal |
| 8 | Notifications, widgets and Lock Screen activities | Push tokens, phone type, app version, language, time zone, notification choices, a row per push sent | (a) consent, given in iOS and in the app's switches | Apple delivers pushes as its own controller. A push carries ids and fixed text, never content. | Apple acts as its own controller | Tokens until the phone is signed out or the account is deleted. Push rows: 30 days. |
| 9 | Subscription and access | App Store transaction ids, product, period, status, free access grants, streak purchases, App Review access codes | (b) contract. Keeping purchase records: (c) legal obligation, bokføringsloven § 13. | Apple takes the payment as its own controller and sends purchase notices. Paeonia gets no card details. | Apple acts as its own controller | Purchase records and Apple's notices: five years after the end of the purchase year. Free access grants have no end date in the code. |
| 10 | Usage statistics and crash reports | Screens opened, actions taken without their content, crash reports, phone model, iOS version, linked to the account id. The person's yes or no and when. | (a) consent, also under ekomloven § 3-15 | PostHog, Inc., stored in Frankfurt. Session replay and IP-based location are off. | PostHog is a US company and staff there can reach the data. Data Privacy Framework and standard contractual clauses. | Deleted after 12 months without use, when the person turns sharing off, or with the account |
| 11 | Reports, blocks and moderation | Who reported whom, the reason and note, a copy of the reported content, what the operator did, a safety flag on the pair, blocks, bans and the ban log | (f) legitimate interest in a safe service | The operator only. The reported person is not told. | None | The copy of reported content: 180 days after the first action. Reports, actions and safety flags: three years after the case closes, or when the copy is gone if that is later. A block: until the person who made it removes it or deletes their account. The ban log has no end date in the code. |
| 12 | Requests about a person's data | Download, correction and deletion requests, their steps, and the download files | (c) legal obligation, GDPR Art. 12 to 22 | The person | None | Download files: three days. Request records: three years after the request closes. A finished account deletion keeps its request and job rows, which stop the account from being made again. |
| 13 | Security and operations | A stored answer per write to stop it running twice, rate limit counters, server logs with IP addresses, backups of the whole database and files | (f) legitimate interest in a service that is reliable and hard to misuse | The server host. Cloudflare holds the off-site backup in R2, EU. | None | Stored answers: 30 days. Backups: 14 nights on the server, 3 days off site, 48 hourly copies on the server. |
| 14 | Support and privacy email | People who write to contact@paeonia.no or support@paeonia.no: address, name, what they wrote | (b) contract, or (c) for a privacy request | The mail provider, iCloud Mail by Apple | See open points | Not set. See open points. |
| 15 | The website paeonia.no | Visitors: IP address and request data. No cookies, no analytics. | (f) legitimate interest in serving the site | Cloudflare Pages | Cloudflare serves from its nearest site. Data Privacy Framework and standard contractual clauses. | Cloudflare's own log period |

## Security measures in general terms

Art. 30(1)(g) asks for a general description. [The assessment](dpia.md) cites the code for each.

- Sign-in runs through Clerk with Apple, Google or an emailed code. There are no passwords.
- Every server function checks that the person belongs to the couple before it reads or writes, and takes the person from the session.
- Traffic uses TLS. Files have no public address and are reached through signed links that expire within an hour.
- The database dashboard and the server's shell are reachable only over a private network, and the server's keys are kept out of the repository.
- One operator has access. The in-app admin area shows no relationship content and logs bans.
- Pushes carry no content, and the phone clears its local data on sign-out, leaving and account deletion.
- Rate limits cover invite codes, uploads, messages, reports and data downloads.
- Retention jobs delete data on the periods in the table (`backend/convex/retention.ts`, `backend/convex/crons.ts`).
- Backups run nightly and hourly, and a watchdog emails the operator when the service or a backup fails. [The breach routine](breach-routine.md) covers what follows.

## Open points

- The off-site backup is not encrypted with a key of Paeonia's own. See the assessment.
- OpenFreeMap serves map tiles without an agreement with Paeonia. Confirm where it serves from, or use Apple Maps on every device.
- iCloud Mail is a consumer service. Confirm that Apple offers a data processing agreement for it, or move the two addresses. Decide how long support mail is kept.
- Data processing agreements and the Data Privacy Framework entries are on the list at the end of the assessment.

## Where each table belongs

Tables that hold no personal data are the question catalog (`questions`, `question_versions`, `question_version_localizations`, `question_answer_kinds`, `question_collections`, `question_collection_localizations`, `topic_catalog`), `subscription_products`, and the game bookkeeping tables `game_used_words`, `story_chain_used` and `consensio_used_topics`.

| Row | Tables |
| --- | --- |
| 1 | `users`, `profiles` |
| 2 | `pairing_invites`, `pairing_invite_secrets`, `relationship_pairs`, `couples`, `couple_members`, `relationship_sync_events` |
| 3 and 4 | `first_day_drafts`, `couple_days`, `couple_activity_events`, `daily_question_instances`, `daily_question_answers`, `daily_answer_text`, `daily_answer_option_choice`, `daily_answer_partner_choice`, `daily_answer_media`, `daily_question_shuffles`, `daily_question_threads`, `daily_answer_seen_states`, `topic_question_skips`, `conversation_threads`, `thread_messages`, `thread_message_media`, `thread_read_states`, `game_threads`, `memories`, `memory_notes`, `memory_media`, `memory_threads`, `stories`, `story_threads`, `couple_notes`, `letters`, `widget_canvases`, `widget_drawing_revisions`, `countdowns`, `visits`, `together_list_items`, `streak_states`, `anniversary_recaps`, `couple_hearts`, `reactions`, `favorites`, `media_assets`, and the game tables `game_settings`, `game_invites`, `game_plays`, `game_play_days`, `game_hidden_waits`, `game_seen_waits`, `games`, `game_moves`, `game_guesses`, `story_chain_games`, `story_chain_stories`, `mind_meld_games`, `mind_meld_rounds`, `mind_meld_words`, `piccante_games`, `piccante_results`, `consensio_games`, `consensio_rounds`, `guess_my_spot_games`, `guess_my_spot_rounds`, `exquisite_corpse_games`, `exquisite_corpse_figures`, `exquisite_corpse_parts`, `board_games`, `board_game_history`, `board_game_marks` |
| 5 | `location_sharing_preferences`, `latest_partner_locations`, `together_days` |
| 6 | `calls`, `call_reports` |
| 7 | No table. Presence lives in the presence component (`backend/convex/lib/presence.ts`), and the switch is on `profiles`. |
| 8 | `user_devices`, `widget_push_devices`, `live_activity_tokens`, `game_live_activities`, `notification_preferences`, `notification_outbox`, `widget_push_outbox`, `live_activity_push_outbox` |
| 9 | `storekit_transactions`, `storekit_payloads`, `storekit_notification_events`, `app_account_tokens`, `entitlement_grants`, `streak_restorations`, `review_access_codes`, `review_access_sessions`, `review_demo_partners` |
| 10 | The answer is on `profiles`. The statistics are at PostHog. |
| 11 | `content_reports`, `content_report_targets`, `report_snapshots`, `report_snapshot_assets`, `moderation_actions`, `pair_safety_warning_flags`, `relationship_blocks`, `admin_audit_log` |
| 12 | `privacy_requests`, `privacy_request_events`, `account_deletion_jobs`, `data_exports`, `data_export_parts`, `data_export_chunks` |
| 13 | `client_operations` |
