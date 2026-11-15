# Calling plan

Plan and decisions for voice and video calls between partners.

Keep this file current. When a calling decision changes, or calling code lands, update the matching section in the same change. Move items from "Open questions" to "Decisions" once the developer settles them, and replace proposals with what was actually built.

## Decisions

Decided on 2026-11-14.

- The first version has voice and video calls.
- Calling has three entry points, each a phone button. The most important one is in every game toolbar, left of the chat button, so a game toolbar reads score, call, chat, then the "•••" menu (`GameToolbarActions`). The second is on the Us tab next to the partner. The third is in the top bar of the "Just us" couple chat.
- Calls show in the Phone app's Recents as the partner's name with the Paeonia icon (`includesConversationInRecents`), or as "Paeonia" when lock screen details are private. Calling back from Recents or Siri goes through the same start path as the in-app buttons. The system hands back the name the call showed, not an id, because the handle's value is that name (see "System call UI"). A couple has one partner, so a call back to the partner's current name or to "Paeonia" calls the partner. A call back with no partner, or to any other name, such as a name from before a nickname change, is refused with plain copy. Recents keeps the partner's name after sign-out, leaving or account deletion, because the app cannot remove entries from it. The developer accepted that when choosing Recents.
- Drawing together during a call needs no new feature. The live canvas already works whenever both partners have it open, so it works during a call because the call keeps running while people move around the app.
- Calls ring with the system ringtone.
- The phone button starts a voice call. Either partner turns on their own camera during the call, so one button fits the game toolbars and nobody's camera turns on without their own tap.
- The call keeps running across the app. Starting or answering a call opens a full call screen. Swiping it down shrinks it to a floating bubble that stays over every screen, games included, until the call ends. A voice call's bubble shows the partner's face, the call time, mute and end. A video call's bubble shows the partner's video. Tapping the bubble opens the full call screen again. The bubble stays clear of the toolbar, the bottom controls and the game chat panel, which report their edges already (`paeoniaBannerBottomEdge()`, `GameChatScreen`).
- Outside the app, the system shows the call on the Lock Screen and in the Dynamic Island. During a video call the partner's video continues in system Picture in Picture (`AVPictureInPictureVideoCallViewController`), drawn by an `AVSampleBufferDisplayLayer`, because a Metal view stops drawing in the background. Your own camera keeps sending through `AVCaptureSession.isMultitaskingCameraAccessEnabled`, which needs no entitlement since iOS 18. Inside the app the bubble is used, not system Picture in Picture.
- The call screen shows the partner's local time when it is known. At night their time, from 22:00 to 07:00, the app asks "It's 02:14 for Robin. Call anyway?" before it rings. The hours are the same night that quiet pushes use (`QUIET_NIGHT_START_HOUR` in `backend/convex/lib/apns.ts`). The partner's time zone is hidden while the partner does not share their location (sharing off or paused), because it tells roughly where they are. Without a time zone the app shows no time and does not ask.
- A missed call adds a "Missed call" row with the time and a Call back button to "Just us", and sends a normal push under the Messages switch. It counts toward the app icon badge until the person opens the chat.
- A finished call adds a quiet "Call" row with its length to "Just us". It never marks the chat unread.
- With lock screen details set to private, the incoming call shows "Paeonia" instead of the partner's name.
- A person's call media goes only through TURN unless they share their location (sharing on and not paused). A partner who cannot see where someone is never sees their IP address either.
- A phone call from the cellular network during a Paeonia call ends the Paeonia call. Paeonia calls do not support hold.
- Voice notes cannot record during a call, and game sounds and other app audio do not touch the audio session while a call runs.

## Call screens

Built on 2026-11-14 in `ios/PaeoniaApp/Features/Calls/` (`docs/implementation-map.md` lists the files).

- The full call screen and the bubble live in a window of their own above the app's window and below the app lock's cover, so they stay over sheets, covers and games. Starting or answering a call opens the full screen. The chevron or a swipe down shrinks it to the bubble, which the person can drag to any corner.
- The phone buttons and Call back go through `CallStarter`, which opens the call screen while a call is live and asks the night question first.
- The Us tab's phone button sits in its header row beside the streak, because the partner's avatar moves around the map.
- An ended call shows why on the call screen until the engine clears the session. A microphone refusal adds an Open Settings button, and any other failure adds the support link.
- "Just us" decodes a message's `call` (`outcome`, `duration_seconds`) and the thread summary's `last_message_call`, which the Just us card and the message banner read. A finished call never marks the chat unread and gets no banner.

## How it works

Every part except the WebRTC library reuses something Paeonia already runs.

- **Media.** WebRTC sends audio and video directly between the two phones, encrypted with DTLS-SRTP, when the person shares their location. Otherwise `get_call_ice_servers` returns `relay_only: true` and their phone sends media only through TURN. A couple only ever has two people on a call, so there is no media server. The library is [stasel/WebRTC](https://github.com/stasel/WebRTC), an unmodified build of Google's WebRTC, pinned to an exact release. The relay forwards the session descriptions that carry the encryption fingerprints, so the relay is trusted not to swap them.
- **Call state.** Convex owns each live call in a `calls` table that holds at most one row per couple, and only while the call rings or runs. Each way a call can end deletes the row and writes the call's row in "Just us". Every state change is a Convex mutation, and both phones follow the row through a subscription.
- **Call setup messages.** The relay (`relay/`) carries only the WebRTC offer, answer and network candidates, after the partner's socket has joined. It gets a `call` channel in `ALLOWED_CHANNELS` (`relay/src/ticket.ts`) and its own ticket mutation, which checks that the person is in the live call. The relay stores nothing, so it never decides whether a call rang, was answered or ended.
- **TURN.** Some networks block a direct connection. For those calls the media goes through Cloudflare's TURN service. A Convex action mints TURN credentials for a member of the live call, with the call id as the identifier, and revokes them when the call ends. Each member gets at most four sets per call. A local backend has no TURN key and returns no TURN servers.
- **Ringing.** `start_call` schedules a one-shot action that sends a VoIP push (`apns-push-type: voip`, topic `no.paeonia.app.voip`, priority 10, expiring at the ring deadline) to every active device of the partner. It has no outbox row and no retries, because a late ring is worse than none. The PushKit token is a `voip_push_token` on the device's `user_devices` row, sent with `register_user_device`, so sign-out and device cleanup already cover it. A ring that APNs calls dead clears only that token, so the phone keeps its other pushes. The payload holds ids, the ring deadline and nothing the person wrote. The phone reports the call at once with the partner's id and name from a small cache that it writes on every unlocked read of the partner, because the local store may be unreadable while the phone is locked. Sign-out clears the cache.
- **Ringing while the app is open.** The app also rings from the Convex subscription, and drops a second report of the same call UUID. That is how two simulators on a local backend, which has no APNs keys, can call each other.
- **System call UI.** LiveCommunicationKit's `ConversationManager` shows incoming and ongoing calls on the Lock Screen, in the Dynamic Island and in Recents. The app creates it and the `PKPushRegistry` at launch, even when signed out, in a call engine that lives outside SwiftUI views. The handle's value is the name the call shows, the partner's name or "Paeonia" when lock screen details are private, and its display name is the same. The system call UI shows the value and ignores the display name, which reaches the system only as the Siri name (Apple feedback FB24933340, seen on iPadOS 27.0.1), so a user ID as the value showed a long UUID on the incoming call. Outgoing calls go through `StartConversationAction`.
- **Audio.** WebRTC's audio starts only in `conversationManager(_:didActivate:)`, with WebRTC's manual audio mode on. Nothing in the app calls `setActive` during a call. `PaeoniaAudioSession` has a call-active gate that game sounds, the pairing celebration and voice notes check. If `didActivate` has not arrived a few seconds after a join, the call fails instead of running without sound.
- **Access.** Starting a call needs a couple with access (`getCurrentEntitledCoupleId`). A call in progress finishes even if the subscription lapses, so its tickets and TURN credentials check membership in the live call only. `start_call` has a rate limit. Every new public function has a `convex-test` test that someone outside the couple, or without access, is refused.
- **Leaving.** Sign-out, leaving the relationship and account deletion end the live call first, in the existing purge paths.
- **App setup.** The app adds the `audio` and `voip` background modes next to `remote-notification`. `NSMicrophoneUsageDescription` and `NSCameraUsageDescription` in `ios/PaeoniaApp/Supporting/Info.plist` mention calls as well as voice messages and photos.

## Backend

Built on 2026-11-14 in `backend/convex/calls.ts`, `lib/calls.ts`, `push:send_call_ring` and the relay's `call` channel. `backend/AGENTS.md` lists the functions and their errors.

- `start_call` takes the call id the app proposes and the phone's device id. A retry with the same id returns the same call, and an id whose call already ended is refused, because the call's row in "Just us" uses the call id as its message id.
- The call's row in "Just us" is a `thread_messages` row with `call: { outcome, duration_seconds }`, the caller as sender and no body. Every message read returns `call` (null for a message), and `get_conversation_threads` returns `last_message_call`. The server refuses to edit, reply to, delete, react to or report it.
- `get_conversation_threads` returns `has_unread` for each chat, decided by the same rule as the app icon's badge (`lib/threadUnread.ts`). It passes over completed calls, so a finished call after an unread message leaves the chat unread.
- The missed-call push is the `missed_call` kind under the Messages switch. It opens `paeonia://chat` and uses the chat's `message` category, so the lock screen says "New message" when previews are hidden. It goes out for a caller cancel or a ring timeout, not for a decline, and not when the person already read the chat.
- A `sweep-calls` cron every 15 seconds ends a running call that lost one side's heartbeat for 60 seconds, and a ringing call whose scheduled timeout was lost.
- Sign-out (`disable_user_device`) ends the person's live call whichever phone signs out. Ending the relationship, which account deletion and bans also do, ends it before the couple ends, so its row still lands in "Just us".
- TURN credentials come from Cloudflare's `generate-ice-servers` endpoint with a 24-hour TTL and the call id as `customIdentifier`. The call row keeps their usernames, and the call's end revokes them. A member who asks a fifth time in one call is refused with `P0003 turn_limit_reached`.

- **Extra rules from the review.** The phone button answers the partner's call when it is ringing. The partner's time zone is cached and refreshed in the background, and the night check waits at most 1.5 seconds for a fresh one. Offers and answers carry an offer number, and an answer to an older offer is dropped. A voice call on the earpiece turns on the proximity sensor. A `start_call` whose answer never arrives sends `end_call`, so the partner stops ringing.

## Call states

| Event | Rule |
| --- | --- |
| Start while the partner's call to you rings | `start_call` answers that call instead. Mutations run one at a time, so no tie-break is needed. |
| Start while a call is live for the couple | Refused with "You're already in a call". |
| Answer | The first device to answer wins and is recorded on the row. The person's other devices end their ring as answered elsewhere. |
| Decline | Ends the ring on every device of the person who declined. Writes a missed-call row. |
| Ring timeout | A scheduled mutation ends a call still ringing after 45 seconds and writes a missed-call row. |
| Caller cancels | Ends the ring and writes a missed-call row. No second VoIP push goes out. A late push is reported and ended at once, from the ring deadline and the row. |
| End | Either person ends an active call. Writes a "Call" row with its length. |
| Lost phone | Each phone sends a heartbeat every 15 seconds while the call is active, each one given up after 5 seconds so a slow request never delays the next. A sweep ends a call with no heartbeat from one side for 60 seconds. The other phone ends the call itself after 30 seconds without a connection. |
| Network change | The call shows "Reconnecting", reconnects the relay at once, restarts WebRTC's connection, and ends after 30 seconds without one. |
| Answer before allowing the microphone | The answer goes through at once, because iOS cannot ask for the microphone on a locked screen or in the background. The app asks without waiting, and iOS shows the question when the person opens the app. Until then the call screen says the partner cannot hear them yet. Allowing it starts WebRTC's audio again so it records. Refusing it ends the call as a microphone failure. A microphone the person already refused stops the answer. Starting a call runs in the foreground, so it asks first. |
| Answer from a closed app before first unlock | The join fails and the call ends as failed, because the sign-in token is not readable yet. |

Only a call that is still in the expected state can move. Answer, decline, cancel and timeout each check that the call still rings, so exactly one of them writes the missed-call row.

## Mistakes other teams made

- **A VoIP push that reports no call.** iOS kills the app, and after repeated misses stops delivering its VoIP pushes. Report the call with `reportNewIncomingConversation` before the PushKit handler returns, with the UUID from the push. Fetch anything slow after reporting. A push for a call that already ended still reports it, then ends it at once. ([WWDC26 session 226](https://developer.apple.com/videos/play/wwdc2026/226/), [Apple forums](https://developer.apple.com/forums/thread/817976))
- **No sound after answering.** Audio that starts before the system activates the session gets torn down. Sometimes `didActivate` never fires, which an iOS 18.4.1 thread reports and which still happens on iOS 26. Apple's advice is to never call `setActive` yourself. ([Apple forums](https://developer.apple.com/forums/thread/783870))
- **Answering a call while the app is closed.** The join action can arrive before any screen exists, so screens cannot own the call. ([Apple forums](https://developer.apple.com/forums/thread/808667))
- **Actions left hanging.** Every `ConversationAction` must end in `fulfill` or `fail`, or the system call UI gets stuck. A failed answer must not go on to join the call. ([Stream's LiveCommunicationKit pull request](https://github.com/GetStream/stream-video-swift/pull/1200))
- **Handles that change.** A handle that is a temporary token breaks calling back from Recents. The usual advice is a stable user ID ([CallKit to LiveCommunicationKit migration](https://www.theswift.dev/posts/migrate-a-calling-app-from-callkit-to-livecommunicationkit/)), but the system call UI shows the handle's value instead of its display name (FB24933340), so Paeonia's handle is the shown name. A couple has one partner, so a call back to that name still finds them. A nickname change leaves old Recents entries that are refused.
- **The side button.** A side button that only locks the screen during a call came from the app's audio handling and route, not the system. Test the side button with the call on the receiver. ([Apple forums](https://developer.apple.com/forums/thread/852594))

## Testing

Two simulators on a local backend cover starting, answering, declining and ending a call, the call screen and the bubble. The simulator has no system call UI, so iOS ends every LiveCommunicationKit call there at once. Simulator builds use `SimulatorCallSystem` instead, which hands each request straight back to the engine and activates the audio session itself, and the call screen shows Answer and Decline for an incoming call. The required UI test, `CallJourneyUITests` on the `local-flow-call` scenario, starts a call from a game, shrinks it to the bubble, opens "Just us" and ends it there from the bubble. The simulators get no VoIP pushes, so the developer tests the rest on two real phones: ringing a locked phone, answering from the Lock Screen, a closed app, AirPods and car audio, a network change mid-call, and the side button. The backend tests cover every call state above.

## Open questions

- Whether score, call, chat and "•••" fit in every game toolbar on the smallest supported iPhone. Check each game with `scripts/scenario-screenshot` once the button exists.
