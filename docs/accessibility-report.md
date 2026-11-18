# Accessibility release gate

No label is verified, and this development audit is not legal certification. App Store answers and the public statement are prepared, not published.

## Criteria and scope

Apple requires every common task to work with a feature before claiming its label, separately for each supported device. This includes first launch, third-party sign-in, purchases, settings, widgets and notification actions. Use the current [overview and linked evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels) when reviewing the device-specific answers below.

The current implementation has five main tabs and ten games. `MainTab.questions` names the Chats tab internally. Existing native semantics, local-first storage, private nickname resolution, hidden-answer rules, adaptive layouts and Reduce Motion behavior were inspected before extending them.

More > Accessibility controls optional visible tools. Extra controls, descriptions/transcripts and High contrast are switches. Extra controls also turn on through SwiftUI's [assistive-technology environment](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityenabled), and descriptions/transcripts through [VoiceOver](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityvoiceoverenabled), both including before sign-in. XCTest and `agent-device` runners set the first but not VoiceOver. The preferences hide optional buttons and fields, preserve drafts and stored descriptions, and keep validation and failed-save recovery available. Labels, board semantics, text size, contrast and Reduce Motion remain active. The final settings journey passed at actual Large and AX5, including independent options, authored-description retention before relaunch, preference persistence and restored compact defaults. Both drawing games passed description-read recovery at both sizes. Debug scenarios simulate only Paeonia's presentation input because XCTest is itself an accessibility client. They retain the native accessibility tree and do not validate manual AT use.

Our quality goals exceed Apple's label requirements: comfortable AX5 layouts, 44-point custom targets, efficient navigation, stable focus, accessible creation, durable drafts and correction after sharing. Apple does not list the last two as separate label requirements. Neither automated audits nor the labels establish legal compliance.

## Task-by-feature matrix

`S` means source inspected; `J` means a direct simulator journey without assistive technology; `A` means a completed automated audit, with its pass or findings retained; `U` means a passing completed automated journey; `R` means passing assertions recovered from the incomplete AX5 run; `P` means remaining runtime verification. Both `U` and `R` describe only the named assertions, not whole workflows. A code never means complete feature support. Scope and size come from the record above or linked historical result. Every row remains pending for actual assistive technology and separately for iPad.

For each row cover ready, empty, loading, offline, failure, disabled, completed and interrupted states where applicable. Record any inapplicable state with a reason. Check English and Norwegian Bokmal, long names, AX5, Bold Text, Reduce Motion, Increase Contrast with Reduce Transparency and grayscale. Check focus after presentation, error, live update and dismissal. Locked answers, secret targets, unfinished creature parts and private nickname sources must never enter speech, braille, trees or announcements.

| Task | Current ownership and representative entry | iPhone | iPad | Particular state or privacy checks |
| --- | --- | --- | --- | --- |
| First launch and invitation paste | `Auth/Welcome`, `local-flow-fresh`, `welcome` | S/A/P | S/P | Saved progress, invalid invite, interruption, optional welcome doodle. |
| Apple and Google authentication | `Auth/Welcome/WelcomeSignInStep`, `sign-in`, `sign-in-invite` | S/A/P | S/P | Actual provider sheets, dictation, cancellation, failure, restored session. Local fixtures cannot verify providers. |
| Profile and mandatory photo | `Auth/Onboarding`, shared profile crop | S/U/P | S/P | Large and AX5 Photos/Zoom/Apply and profile editing/cancellation passed selected assertions. Actual authentication, denial/retry and AT focus remain pending. |
| First shared activities | `Onboarding`, first-steps and inviter scenarios | S/U/P | S/P | Date, first drawing and answer, joiner's unwrap, consent, notification refusal, restart. |
| Pair and invite | `Pairing/Invite`, `Pairing/Join`, `pairing-invite-ready`, `pairing-invite-expired` | S/P | S/P | Copy/share code, invalid or expired code, safety warning, joining, partner joins live. |
| Subscription and access changes | `Paywall`, `Settings/Purchases`, access-notice scenarios | S/A/P | S/P | Loading price, trial, choose plan, actual StoreKit sheet, pending/cancel/failure, restore, lost access. |
| Streak restore | `StreakRestore`, streak scenarios | S/P | S/P | Eligibility, expired offer, actual purchase, restored state. |
| Home and hearts | `Pairing/Home`, `Hearts`, `local-flow-paired`, location scenarios | S/A/P | S/P | Cached content, loading order, partner activity, heart feedback without motion or sound, no repeated announcements. |
| Daily question and waiting | `DailyChallenge`, `questions`, `questions-empty`, `questions-error` | S/A/U/P | S/P | Neither, one, both answered, waiting, day ended, skipped, queued/failed send. |
| Answer creation | `DailyChallenge/AnswerFlow`, `question-answer-flow` | S/A/U/P | S/P | Text, either/or, partner choice, photo, voice; draft survival, keyboard, mic/photos denial, disabled Send. |
| Mutual reveal and history | Daily chat and thread, `DailyQuestionJourneyUITests` | S/U/P | S/P | Hidden answer absent from semantic output until own answer; stable focus when partner answers. |
| Topics and Flirt | `Topics/Shelf`, `Topics/Topic` | S/P | S/P | Pick question, private topic exclusions, waiting/reveal, completion, history. No new question content in this work. |
| Chat text and thread navigation | `Chat`, question/memory/story/game threads | S/U/P | S/P | Text, pagination, unread, quote/reply, timestamp, edit/delete, reactions, favorites, removed targets. |
| Chat photos | Chat composer, photo row and viewer | S/P | S/P | Multiple photos, caption, author/edit/read descriptions, retry, gallery, save, privacy. |
| Chat and daily voice | Chat voice composer, daily recorder/player | S/P | S/P | Start/stop without hold, transcript author/edit/read, playback/seek/retry, unavailable audio, interruption. |
| Memories | `Memories/Timeline`, editor/detail, `memories-cards`, `memory-editor` | S/A/U/P | S/P | Title/date, notes, photos/descriptions, place, save/delete, comments, long content. |
| Memories map | `Memories/Map`, `memories-map`, selected/cluster/empty variants | S/P | S/P | Textual place/list alternatives, clusters, countries/cities, selection, detail destination. |
| Stories and archive | `Stories`, `avatar-stories-new` | S/U/R/P | S/P | Camera/library, caption/description, posting, pause, next/previous, expiry, archive, reply/reaction/delete/share. |
| Story notes | `Stories/Home/StoryNoteScreen` | S/P | S/P | Own/partner note, edit, expiry, interruption, reactions. |
| Shared drawing | `WidgetDrawing/Canvas`, `widget-drawing`, history scenarios | S/J/A/U/P | S/P | Large and AX5 native creation, description, undo and history correction passed assertions; frame warnings remain. Tools, color indicators, clear/undo, draft/send and live edits need full AT journeys. |
| Countdowns and milestones | `Countdown`, missing/upcoming/today scenarios | S/P | S/P | Calendar, birthdays, long title, past/future/today, edit/delete, spoken full date and duration. |
| Location and Home map | `Location`, `Pairing/Home`, location scenarios | S/P | S/P | Sharing off, primer/denial, finding/no fix, partner off, pause/resume, last-known/stale, textual places, pan/zoom/reset. |
| Search, favorites and look-back | `Search`, `Favorites`, `LookBack` | S/P | S/P | No results, local/offline result, deleted target, star/unstar, opening the right content. |
| Games setup and hub | `Games/Hub`, games hub scenarios | S/P | S/P | Invite, first instructions, partner here/away, turn/wait/reveal, records/history/favorite/share/chat. |
| Ludo | `Games/BoardGames/Ludo`, board scenarios | S/U/P | S/P | Inspect both players' pawns, home/track/finish, roll without drag, legal destination/capture, disabled move, win. |
| Four in a Row | `Games/BoardGames/ConnectFour` | S/U/P | S/P | Every row and column owner, full column, selection/drop, opponent turn, win/draw. |
| Dots and Boxes | `Games/BoardGames/DotsAndBoxes` | S/U/P | S/P | Large and AX5 native side/closure/disabled-side/extra-turn assertions passed. Inspect ownership, turn changes and outcome with AT. |
| Ultimate Tic-Tac-Toe | `Games/BoardGames/UltimateTicTacToe` | S/U/P | S/P | Nine boards and 81 cells, legal board, selected square, lock in, won/drawn subboard, result. |
| Consensio | `Games/Consensio` | S/U/R/P | S/P | Scale endpoints, set/adjust position without dragging, hidden target excluded, revealed owners and positions. |
| Guess my spot | `Games/GuessMySpot` | S/P | S/P | Photo clue, author place, guess arbitrary place, map controls, reveal/distance. Never initialize from secret coordinates or photo metadata. |
| Draw & Guess | `Games/DrawAndGuess` | S/U/P | S/P | Choose word privately, create clue accessibly, guess without sight, letters/hints, scoring/timing, replay without long press. |
| Odd Creatures | `Games/ExquisiteCorpse` | S/U/P | S/P | Native shape creation, only allowed previous strip, hidden parts, reveal, geometry readouts, share. Freehand meaning is not described. |
| Mind Meld | `Games/MindMeld` | S/P | S/P | Dictation/editing, face-down word privacy, waiting, reveal focus, restart, history, long words. |
| Story Chain | `Games/StoryChain` | S/P | S/P | Read author and line, write/dictate/edit, word dare, live typing focus, name and finish, history. |
| Settings and permissions | `Settings`, `settings`, denied variants | S/A/U/P | S/P | Profile, private nickname, decorations, board marks, dates, notifications and location; disabled and denied controls explain recovery. |
| App lock | `AppLock` | S/P | S/P | Unlock/cancel/failure, passcode fallback, background privacy shield, deferred link, changed OS security. |
| Privacy and reporting | `PrivacySafety`, `privacy-safety`, `report-and-leave` | S/A/P | S/P | Consent, correction, reporting, loading/status/failure; report remains private. |
| Export | `PrivacySafety/DataExport` | S/P | S/P | Request/preparing/ready, download/share, expiry, retry; alternatives preserved in exported content. |
| Leave, delete and sign out | Settings account and root lifecycle | S/P | S/P | Explicit confirmation, cancel, failed request, access change, local privacy purge; focus lands usefully. |
| Home Screen widgets | Drawing, days, countdown, question and streak | S/P | S/P | Placeholder, locked/redacted, cached/stale, tinted/contrast variants, semantic text and correct link. |
| Lock Screen widgets | Days, countdown, their time, distance, streak, question, your move | S/P | S/P | Small text constraints, symbols, privacy and dates, link destination. |
| Notification actions | `Notifications/NotificationQuickActions` | S/P | S/P | Reply/heart, locked phone, queued offline, failure, accessible system text field, no private lock-screen leak. |
| Deep links | `PaeoniaDeepLink`, router, destination scenarios | S/P | S/P | Drawing, daily/chat, game chat, topics, memories/comments, stories/replies, Us/dates/games/streak/subscription/export; signed out, locked, removed or unavailable. |

## Label recommendations, not submitted

| Apple label | iPhone | iPad | Evidence and remaining gate |
| --- | --- | --- | --- |
| [VoiceOver](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria) | blocked | blocked | Common blind drawing participation and competitive fairness remain unresolved. Native controls need proficient end-to-end physical-device testing for order, headings, focus, actions, announcements and privacy across the matrix. |
| [Voice Control](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voice-control-evaluation-criteria) | unverified | unverified | Verify name/number overlays, visible-name matching, dictation/editing, scrolling, secondary actions, all boards/maps, draft interruptions and actual provider/purchase sheets using voice alone. |
| [Larger Text](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria) | unverified | unverified | Apple requires at least 200% or the system maximum; comfortable AX5 is our stronger goal. Actual-size evidence exists, but Home/Questions Dynamic Type findings, the full matrix, small-screen and iPad resizing checks remain open. |
| [Dark Interface](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria) | unverified | unverified | Canonical dark plum presentation exists. Verify launch, transitions, keyboard, crop, provider and purchases for flashes. Apple excludes third-party/user-generated content from its core criterion; our experience review still includes them. |
| [Differentiate Without Color Alone](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/differentiate-without-color-alone-evaluation-criteria) | unverified | unverified | Fixed owner symbols and selected-color indicators exist. Verify grayscale, partners, turns, selected tools, errors and completion throughout both device experiences. |
| [Sufficient Contrast](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria) | unverified | unverified | Current Welcome, Home, Questions, AX5 paywall and local sign-in findings remain open. Large paywall passed its latest audit only. Measure every relevant rendered state: ordinary text 4.5:1, qualifying large text and essential non-text 3:1. Selected glyph samples waive nothing. |
| [Reduced Motion](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria) | unverified | unverified | Shared/feature effects observe the system preference. Verify launch and live changes, every game/effect, interruptions, flashing and sound/haptic alternatives. Frame-scheduled chat-to-game returns need Reduce Motion, hardware-keyboard and interruption checks. Partial combined-setting journeys are insufficient; the latest Reduce Motion group was unperformed because Settings could not open Motion. |
| [Captions](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/captions-evaluation-criteria) | unverified | unverified | High-quality audio-only transcripts can qualify without synchronization. Authoring/reading exists, but accuracy, representative availability, discoverability, preferences and complete voice journeys remain unverified. Apple does not require captions for every third-party item. No video claim is made. |
| [Audio Descriptions](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/audio-descriptions-evaluation-criteria) | inapplicable | inapplicable | No relevant time-based visual video narrative exists. Static image descriptions and VoiceOver do not establish this label. Re-evaluate if relevant media is added. |

Recommended App Store Connect answers today: indicate support for none of the nine labels on either device. Select only individually verified labels after their gates close. The EN/nb public statement is prepared with the existing `support@paeonia.no` contact route and known limitations. It is not published. Use `https://paeonia.no/accessibility/` only after that page is actually deployed. Do not publish these answers or the statement as part of this audit.

## Repeatable release gate

- [ ] Verify Automatic with actual VoiceOver, Voice Control and Switch Control before launch and during open editors. Verify the settings route with Full Keyboard Access and that hiding fields preserves authored content. Debug policy simulation does not satisfy this check.
- [ ] Verify any later source changes and affected actual-size UI groups. Keep failed assertions intact and fix causes. Record the tested commit, build, device, OS, language, size and preferences.
- [ ] Use `XCODE_TEST_AGENT_KEEP_ARTIFACTS=1 ./scripts/xcode-test-agent.sh -- -collect-test-diagnostics never`; add `--ui` before `--` for UI cohorts. Capture app console separately, retain bundles and every audit issue, and split selections to finish within 600 seconds. A stalled wrapper is not a pass.
- [ ] Resolve or individually substantiate every audit finding and runtime frame warning. Complete Accessibility Inspector audits on representative screens/states. An unavailable element is unresolved, not a false positive.
- [ ] Complete every matrix task on iPhone and iPad using proficient VoiceOver. Verify headings/order, values, focus restoration, stable live updates, custom actions and timely, nonrepeating announcements. Check private content in speech, braille, trees and notifications.
- [ ] Complete the matrix using Voice Control alone with Show names/Show numbers, dictation, text selection/deletion, scrolling, secondary actions and non-gesture media/game/map controls. Include actual Apple/Google authentication and sandbox purchase, cancellation, pending purchase, restoration and access changes.
- [ ] Test representative creation, navigation, media and board tasks using Switch Control and Full Keyboard Access. Verify visible focus, no traps, no overlap, keyboard dismissal and escape.
- [ ] Review at least 200% text and comfortable AX5 in both languages, Bold Text, long content, small iPhone and iPad portrait/landscape/narrow windows. Repeat actual AX5 crop Zoom/Apply using assistive technology. Repeat combined settings after the Home header/native creation changes.
- [ ] Measure text, symbols and controls across opacity, gradients, images, placeholders, selected/pressed/disabled/error states. Check grayscale and Increase Contrast with Reduce Transparency together.
- [ ] Test Reduce Motion before launch and during animation. Verify calm alternatives, no hazardous flashing, perceivable sound/haptic alternatives and results independent of animation callbacks.
- [ ] Verify authored media alternatives through creation, editing, interrupted upload, sharing, display, export and deletion. Review actual audio accuracy and discoverability. Do not send intimate media externally without appropriate explicit consent.
- [ ] Run focused SwiftLint and relevant backend tests/typecheck. Re-run `bun run --cwd marketing typecheck && bun run --cwd marketing build` if statement files change. Complete the regular-user protocol below.
- [ ] Reconcile the public statement and App Store answers with the final tested build. Keep unperformed checks pending. Publish only through the normal authorized release process.

For actual-size cohorts, acquire the repository simulator lease, use the bound device command to set Large or `accessibility-extra-extra-extra-large`, then close its panel before the wrapper. XCTest checks the public UIKit category. Leave `XCODE_TEST_AGENT_DESTINATION` unset. Run live reflow alone after resetting Large. Restore Large after failure too, close the panel and release the lease. Never use a personal device without explicit authorization; iPad and physical AT checks need an authorized device session.

## Usability protocol, pending

Recruit regular VoiceOver and Voice Control users and people who use large text, Switch Control or keyboard access. Include iPhone/iPad users and both languages. Agree compensation, recording consent and an accessible stop method. Use synthetic couple content.

Give tasks without naming controls or gestures: start/join a space, answer/reveal, exchange described photos/transcribed voice, create/edit drawings, play every game, inspect a shared place, change privacy, export and leave. Include offline interruption, failed sending, permission refusal, actual sign-in and sandbox purchase cancellation/restoration without a real charge.

Record independent completion, help, focus loss, missed state, wrong actions, hidden information, fatigue and recovery. Ask what participants expected. Do not use speed as the main measure. Fix barriers and repeat affected tasks. This validation remains pending until those sessions and repeats occur.

