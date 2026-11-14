# Calling plan

Plan and decisions for voice and video calls between partners. Nothing is built yet.

Keep this file current. When a calling decision changes, or calling code lands, update the matching section in the same change. Move items from "Proposed defaults" and "Open questions" to "Decisions" once the developer settles them, and replace proposals with what was actually built.

## Decisions

Decided on 2026-11-14.

- The first version has voice and video calls.
- Calling has three entry points, each a phone button. The most important one is in every game toolbar, left of the chat button, so a game toolbar reads score, call, chat, then the "•••" menu (`GameToolbarActions`). The second is on the Us tab next to the partner. The third is in the top bar of the "Just us" couple chat.
- Calls show in the Phone app's Recents as the partner's name with the Paeonia icon (`includesConversationInRecents`). Calling back from Recents or Siri goes through the same start path as the in-app buttons.
- Drawing together during a call needs no new feature. The live canvas already works whenever both partners have it open, so it works during a call because the call keeps running while people move around the app.

## Proposed defaults

These follow from the decisions above. The developer has not confirmed them yet.

- The phone button starts a voice call. Either partner turns on their own camera during the call, so one button fits the game toolbars and nobody's camera turns on without their own tap. LiveCommunicationKit allows a conversation's capabilities to change mid-call, so the system UI follows.
- The call keeps running across the app. Starting or answering a call opens a full call screen. Swiping it down shrinks it to a floating bubble that stays over every screen, games included, until the call ends. A voice call's bubble shows the partner's face, the call time, mute and end. A video call's bubble shows the partner's video. Tapping the bubble opens the full call screen again. The bubble stays clear of the toolbar, the bottom controls and the game chat panel, which report their edges already (`paeoniaBannerBottomEdge()`, `GameChatScreen`).
- Outside the app, the system shows the call on the Lock Screen and in the Dynamic Island. During a video call the partner's video continues in Picture in Picture (`AVPictureInPictureVideoCallViewController`). Sending your own camera while the app is in the background needs Apple's multitasking camera access entitlement (`com.apple.developer.avfoundation.multitasking-camera-access`). Ask Apple for it early, because some developers waited months. Until Apple grants it, your camera pauses when you leave the app and your partner sees your photo.
- The call screen shows the partner's local time. Between 23:00 and 07:00 their time, the app asks "It's 02:14 for Robin. Call anyway?" before it rings.
- A missed call adds a "Missed call" row with the time and a Call back button to "Just us", and sends a normal push. It counts toward the app icon badge until the person sees it, because it waits for them (`badgeCountsForUser`).
- A finished call adds a quiet "Call" row with its length to "Just us".

## How it works

Every part except the media library reuses something Paeonia already runs.

- **Media.** WebRTC sends audio and video directly between the two phones, encrypted with DTLS-SRTP. No server receives the call's media. A couple only ever has two people on a call, so there is no media server (SFU).
- **Call setup messages.** The relay (`relay/`) carries the WebRTC offer, answer, network candidates and hang-up. It gets a `call` channel in `ALLOWED_CHANNELS` (`relay/src/ticket.ts`), and Convex mints its ticket with `lib/liveTicket.ts`, as it does for games. Every message carries the call's UUID. The relay forwards them without reading them. A relay socket ends after 10 minutes (`SESSION_MS`). The call's media does not use the socket, so the app reopens it with a fresh ticket and only needs it again to restart the connection after a network change.
- **TURN.** Some networks block a direct connection. For those calls the media goes through Cloudflare's TURN service. A Convex action mints short-lived TURN credentials for each call, and the TURN key stays on the server. Cloudflare charges $0.05 per GB sent from its servers, and only for calls that use TURN.
- **Call records.** Convex owns each call. Starting one creates the call and its UUID, checks that the caller is in the couple and that the couple has access (`coupleHasEntitledMember`), and rings the partner. Answering, declining, ending and timing out update it, and the missed-call and finished-call rows in "Just us" come from it. Each new public function gets a `convex-test` test that someone outside the couple, or without access, is refused.
- **Ringing.** Convex sends a VoIP push (`apns-push-type: voip`, topic `no.paeonia.app.voip`) through `backend/convex/lib/apns.ts`, which already sends the widget and Live Activity push types. Each device registers its PushKit token with the backend as well as its normal push token.
- **System call UI.** LiveCommunicationKit's `ConversationManager` shows incoming and ongoing calls on the Lock Screen, in the Dynamic Island and in Recents. The app creates it at launch, in a call engine that lives outside SwiftUI views. The handle is the partner's user ID, with their name as the display name.
- **Audio.** WebRTC's audio starts only in `conversationManager(_:didActivate:)`, with WebRTC's manual audio mode on. `PaeoniaAudioSession`, voice notes and game sounds must not change the audio session during a call.
- **App setup.** The app adds the `audio` and `voip` background modes next to `remote-notification`. `NSMicrophoneUsageDescription` and `NSCameraUsageDescription` in `ios/PaeoniaApp/Supporting/Info.plist` mention calls as well as voice messages and photos.

## Mistakes other teams made

- **A VoIP push that reports no call.** iOS kills the app, and after repeated misses stops delivering its VoIP pushes. Report the call with `reportNewIncomingConversation` before the PushKit handler returns, with the UUID from the push. Fetch the partner's photo after reporting, never before. A push for a call that already ended still reports it, then ends it at once. ([WWDC26 session 226](https://developer.apple.com/videos/play/wwdc2026/226/), [Apple forums](https://developer.apple.com/forums/thread/817976))
- **No sound after answering.** This is the most common call bug. Audio that starts before the system activates the session gets torn down. An audio session that is already active can keep the system from activating it at all, which an iOS 18.4.1 thread reports. ([Apple forums](https://developer.apple.com/forums/thread/783870))
- **Answering a call while the app is closed.** The join action can arrive before any screen exists, so screens cannot own the call. ([Apple forums](https://developer.apple.com/forums/thread/808667))
- **Actions left hanging.** Every `ConversationAction` must end in `fulfill` or `fail`, or the system call UI gets stuck. A failed answer must not go on to join the call. ([Stream's LiveCommunicationKit pull request](https://github.com/GetStream/stream-video-swift/pull/1200))
- **Handles that change.** A handle that is a temporary token breaks calling back from Recents. Use the partner's user ID. ([CallKit to LiveCommunicationKit migration](https://www.theswift.dev/posts/migrate-a-calling-app-from-callkit-to-livecommunicationkit/))
- **The side button on the Lock Screen call.** A thread from this year reports that the side button fails to end a call on the Lock Screen call UI, with no fix yet. Test it on a real phone. ([Apple forums](https://developer.apple.com/forums/thread/852594))

## Testing

The Simulator cannot receive VoIP pushes, so ringing, answering from the Lock Screen, a closed app, AirPods and car audio, and a network change mid-call are tested on two real phones. The developer runs those checks. Agents cover the backend with `convex-test` and the in-app call screen and bubble with developer scenarios.

## Open questions

- Paeonia's own ringtone, or the system ringtone.
- Whether score, call, chat and "•••" fit in every game toolbar on the smallest supported iPhone. Check each game with `scripts/scenario-screenshot` once the button exists.
