# Data protection impact assessment

GDPR Art. 35. Version 1, written on 18 November 2026, before launch.

The controller is Hjalmar Karlsen, Storgata 61, 0182 Oslo, Norway, contact@paeonia.no. He runs Paeonia as a private person. Paeonia has no data protection officer. Art. 37 asks for one only where sensitive data is processed on a large scale, and Paeonia has no users yet.

[The record of processing](processing-record.md) lists every purpose with its data, legal basis, processors and retention, so this assessment does not repeat it. Paths are relative to the repository root.

## Why an assessment is needed

Datatilsynet's list of processing that always needs an assessment includes location data together with at least one other criterion. Paeonia shares a partner's precise location and meets two more of the EDPB's criteria (WP 248 rev.01):

- Highly personal data. Couples share private messages, photos, voice messages and calls. Flirt answers can say something about a person's sex life, which is a special category under Art. 9.
- Vulnerable people. Paeonia allows 16 and 17 year olds, and one partner in a couple can be under the other's control.

Paeonia does no profiling, makes no automated decisions, shows no advertising, and buys or sells no data. It is not large scale.

## The processing

Paeonia is an iOS app for two people in a relationship. One invites the other with a code, and the two get a private space. There are no public profiles, no search for other people and no content that anyone outside the pair can see.

It processes the account, what the couple shares (answers, messages, photos, videos, voice messages, memories, letters, drawings, game moves), the latest location of each partner who turned sharing on, call history with a short technical report, whether a partner has the app open, purchases, usage statistics after the person says yes, and reports and blocks. The purpose is to let the two people keep in touch, and the data is used for nothing else.

The database and the application run on a rented server in Leipzig. Files are in Cloudflare R2 buckets in the EU jurisdiction (`backend/AGENTS.md`, "Hosted deployment"). Clerk handles sign-in and keeps identity data in the USA. PostHog stores usage statistics in Frankfurt. Live drawing and call setup pass through a Cloudflare Worker that stores nothing. Apple delivers pushes. The controller is the only operator.

## Necessity and proportionality

### Shared content

The content is the service, so storing it rests on the agreement with the person. Paeonia is not end-to-end encrypted, because the server reads content to sync it, fill the widgets, build "Download my data" and keep a copy of what someone reports. The cost is that the operator, and anyone who breaks into the server, can read it. The measures under "A breach of intimate content" are what Paeonia does instead.

Retention limits how much there is to read. Content is hidden from both partners when the relationship ends and deleted about 30 days later (`backend/convex/lib/relationshipEnd.ts`, `backend/convex/lib/relationshipCleanup.ts`), notes are deleted after 24 hours (`backend/convex/stories.ts`), and push and retry records after 30 days (`backend/convex/retention.ts`).

### Partner location sharing

Location is the most intrusive part, so it is optional, off until each person turns it on, and rests on consent. `location:update_location_sharing_preference` stores the consent text version with the choice (`backend/convex/location.ts`).

- The server holds one position per person and no history. Each new position overwrites the last (`update_latest_partner_location`). Retry records hold no position either (`backend/AGENTS.md`, "Client operations").
- Sharing is mutual. A person who has not turned it on, or who paused it, does not see the partner (`get_partner_location_visibility`).
- Sharing while the app is closed is a separate switch that is off by default (`updates_while_closed`).
- Turning sharing off deletes the stored position at once (`deleteLatestLocationForUser`). It works without a subscription, from the paywall's privacy sheet, because it takes a consent back (`update_location_sharing_preference`).
- The server notes the dates the two were within 1 km of each other, never the place, and deletes each date after 45 days (`backend/convex/lib/together.ts`, `backend/convex/retention.ts`).

A precise position is more than a distance needs. It is precise because the map is what the person asks for when they turn sharing on. A coarser option would lower the risk and is not built.

### Flirt and other intimate content

Flirt is one topic of questions about attraction. Explicit consent under Art. 9(2)(a) is the only ground that fits, so the app asks the first time a person opens a private topic and stores the yes with the version of the text they saw (`set_private_topics_consent` in `backend/convex/topics.ts`). The server refuses an answer in a private topic without it (`submit_topic_answer`). The switch under Privacy and safety takes the yes back and deletes what the person wrote there, with or without a subscription (`deleteOwnPrivateTopicAnswers` in `backend/convex/lib/privateTopics.ts`). The rest of the paid app works without Flirt, so the consent is freely given.

Elsewhere a person can write about their health, beliefs or love life in a message. Paeonia does not ask for that, does not analyse it, and stores it only to show it to the partner, as the privacy policy says. A consent step before every message would protect nobody.

### 16 and 17 year olds

Paeonia is for people aged 16 and older. Sixteen is the highest age any EEA country sets for consenting to an online service under Art. 8, so a 16 year old can give Paeonia's consents themselves in every country where it is sold. Flirt's questions would not be appropriate for anyone younger.

The sign-in step states that the person is 16 or older and accepts the terms (`ios/PaeoniaApp/Features/Auth/Welcome/WelcomeSignInStep.swift`), the account stores which terms those were (`accepted_terms_version` on `users`), and the App Store rating is 16+. Paeonia checks no ID. A real age check would take an identity document from every user to keep a few people out, which is more data than the risk justifies. An account that belongs to someone younger is deleted when Paeonia learns of it.

A person meets nobody in Paeonia except the one they invited. There are no ads, and usage statistics stay off until the person says yes, as ekomloven § 3-15 requires (`backend/convex/analytics.ts`).

### Calls and safety records

Calls are never recorded. The connection report holds no content and no location, and is deleted after 30 days (`backend/convex/calls.ts`, `backend/convex/retention.ts`). Reports and blocks rest on Paeonia's legitimate interest in a safe service, and are kept three years after a case closes so that a repeated pattern can be seen (`prune_kept_records` in `backend/convex/retention.ts`).

## Risks to people and the measures built

| Risk | Harm to the person | Likelihood after the measures | Remaining risk |
| --- | --- | --- | --- |
| Coercive control between partners | Serious | Possible | Medium |
| A breach of intimate content | Severe | Unlikely | Medium |
| A reported partner finds out | Serious | Unlikely | Low |
| IP address exposed in a call | Limited | Unlikely | Low |

### Coercive control between partners

A controlling partner can use a couples app to watch where the other is, when they are online and what they do. Paeonia's own features create this risk, and a 16 or 17 year old with an older partner is the person most exposed to it.

- Nobody can turn location sharing on for their partner. The server takes the person from the session, never from an argument (`backend/convex/location.ts`).
- A person can pause sharing for 1 hour, 4 hours or until morning. The partner is not told. They keep seeing the last position and its age, the same as when a phone has no signal (`paused_until` in `backend/convex/schema.ts`, `get_partner_location_visibility`).
- The partner's local time is hidden while the person does not share their location, because a time zone says roughly where someone is (`get_call_context` in `backend/convex/calls.ts`).
- "Show when I'm here" turns presence off for both partners (`set_shows_presence` in `backend/convex/appPresence.ts`).
- Either partner can leave, block, or report and leave at any time. The shared space closes for both at once, and a block stops the two from pairing again (`backend/convex/lib/relationshipBlock.ts`, `backend/convex/pairing.ts`).
- An ended relationship comes back only if both say yes, and never after a block or a report (`backend/convex/lib/relationshipRestore.ts`).
- "Download my data" never contains what the partner wrote, uploaded or where they were, so it cannot be used to pull the partner's data out (`backend/convex/lib/dataExportRegistry.ts`).

**What remains.** Paeonia cannot stop a partner from demanding that sharing stays on, or from taking the phone. The pause is built so that using it does not show. The risk stays medium because the harm is serious where it happens and the app cannot see it.

### A breach of intimate content

Messages, photos and Flirt answers could reach other people through a break-in on the server, a leaked link, a processor, a lost phone or a lock screen. Photos that 16 and 17 year olds send each other would be the worst case.

- Access. Every public function takes the person from the session and checks membership, subscription access and blocks before it reads or writes (`backend/convex/lib/auth.ts`, `backend/convex/lib/access.ts`).
- Files. No file has a public address. The app gets a link signed with HMAC-SHA256 that works for 1 to 60 minutes, and the link stops working when the file is removed or the relationship ends (`get_media_signed_url` and `get_media_serve_target` in `backend/convex/media.ts`, `backend/convex/lib/mediaAssetState.ts`).
- Pushes. A push may carry only the fields listed for its kind, and never something a person wrote (`NOTIFICATION_PAYLOAD_FIELDS` in `backend/convex/lib/notifications.ts`). Lock screen detail starts as private (`backend/convex/lib/auth.ts`).
- The operator's tools. The in-app admin area searches accounts, bans and lists open reports with the reporter's note. It never shows relationship content, and it logs each ban (`backend/convex/admin.ts`). The database dashboard is reachable only on the private network (`backend/AGENTS.md`, "Hosted deployment").
- The relay stores nothing, accepts only a 60-second signed ticket from the server, and runs in the EU jurisdiction (`relay/src/index.ts`, `relay/src/room.ts`, `backend/convex/lib/liveTicket.ts`).
- Guessing. Invite code tries are rate limited per person (`backend/convex/lib/rateLimits.ts`), and the server stores a code only as a hash made with a server secret (`hashPairingInviteCode` in `backend/convex/pairing.ts`).
- The phone. Signing out, leaving and account deletion clear the local store, caches, widgets and the Spotlight index (`ios/PaeoniaApp/Storage/Privacy/LocalPrivacyPurgeService.swift`). The chats given to Spotlight and Siri leave private topics out (`ios/PaeoniaApp/Features/Siri/Messages/SiriChats.swift`). An optional app lock asks for Face ID (`ios/PaeoniaApp/Features/AppLock/`).
- Retention. Content goes about 30 days after a relationship ends, and location, hearts, nicknames and call reports go at once (`endRelationshipForPair` in `backend/convex/lib/relationshipEnd.ts`). Account deletion removes the profile, devices and location in one step and the identity at Clerk after it (`backend/convex/accountDeletion.ts`).

**What remains.** The content is readable on the server, one person has full access, and the database is on one rented server. Nothing on the server detects an intrusion. The watchdog reports outages only ([breach routine](breach-routine.md)). Three points are open:

1. The nightly backup is copied to a Cloudflare R2 bucket in the EU as it is. R2 encrypts it with Cloudflare's keys, not with a key of Paeonia's, and the archive with the server's own keys is stored beside it (`/srv/backup/paeonia-backup.sh` on the server). Encrypt both before upload, with a key kept off the server.
2. `scripts/local-backend` copies the hosted data to the developer's Mac. Remove that import at launch.
3. Confirm with the host whether the server's disk is encrypted.

### A reported partner finds out

A person who reports a partner may be at risk if the partner learns of it.

- A report ends the relationship, and the partner's records read as an ordinary leave. Only the server and the reporter's own records hold the real reason (`REASON_FOR_PARTNER` in `backend/convex/lib/relationshipEnd.ts`).
- The safety warning on a later invite shows only to the person who reported (`hasSafetyWarningFor` in `backend/convex/pairing.ts`).
- The reported person's data download leaves out the report, the snapshot, the operator's notes, the safety flag and the reason the relationship ended (`backend/convex/lib/dataExportRegistry.ts`).
- The push about a new report goes to the operator only and says nothing but that a case is open (`alertAdminsOfNewCase` in `backend/convex/lib/adminAlerts.ts`).
- The snapshot of reported content is deleted 180 days after the first action on it (`backend/convex/moderation.ts`).

**What remains.** The partner can guess from the timing, and they see it when the operator removes their content or closes their account. A manual answer to an access request from the reported person must leave the report out, as Art. 15(4) allows.

### IP address exposed in a call

Calls connect directly between the two phones where the network allows it, so each phone gets the other's IP address. An address shows roughly which town a phone is in.

- While a person has paused location sharing, their calls go only through Cloudflare's relay, and the partner's phone never gets their address. If the relay is unavailable the call is refused, not sent directly (`ice_server_access` and `get_call_ice_servers` in `backend/convex/calls.ts`).
- A ringing phone sends its own address only after its person answers (`docs/calling-plan.md`).
- Relay credentials are made per call and revoked when it ends (`revoke_turn_credentials`).
- Only the two members of an active couple can call each other, so a former or blocked partner cannot (`start_call` in `backend/convex/calls.ts`).
- The privacy policy says all of this under "Calls".

**What remains.** A person who never turned location sharing on, or turned it off, gives their partner's phone their address in every call. The controller accepted this on 15 November 2026, because sending every call through the relay would cost more than the risk warrants. Reading the address takes technical skill, and it shows a town, not a street.

## Conclusion

With the measures above, no risk stays high. Two stay medium. Control between partners is one, which no app can rule out. A breach is the other, where the harm would be severe and the likelihood is low. Prior consultation with Datatilsynet under Art. 36 is not needed, provided the three open points under "A breach of intimate content" are closed before launch.

Review this assessment once a year, and before any change that stores location history, lets people outside the couple see content, lowers the age limit, or adds a processor.

Signed by the controller:

Name: Hjalmar Karlsen

Date: ____________________

Signature: ____________________

## To confirm or sign outside the repository

- **Data processing agreements.** Accept or sign one with each of Clerk, Cloudflare, PostHog, the server host and the mail provider, and keep a copy. The mail for contact@paeonia.no and support@paeonia.no goes to iCloud Mail. iCloud+ is a consumer service, so check that Apple offers an agreement for it, and move the two addresses to a provider that does if not.
- **Transfers to the USA.** Clerk and PostHog both say they are certified under the EU-US Data Privacy Framework. Confirm each entry, and Cloudflare's, at dataprivacyframework.gov/list, and that each agreement includes the EU standard contractual clauses.
- **App Store Connect privacy answers.** They must match the privacy manifests (`ios/PaeoniaApp/Resources/PrivacyInfo.xcprivacy`) and the record of processing.
- **Age rating.** Answer the questionnaire so that the rating is 16+.
- **EU trader status.** A private person who sells a paid app is most likely a trader under the Digital Services Act. Apple then publishes the trader's address and phone number on the App Store page, and asks for both to be verified.
- **Accounting law.** Purchase records are kept five years because bokføringsloven § 13 requires it. Confirm with Skatteetaten or an accountant that it applies to Paeonia's income.
