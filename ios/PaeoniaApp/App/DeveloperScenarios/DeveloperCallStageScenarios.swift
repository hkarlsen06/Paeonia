#if DEBUG
  import SwiftUI
  import UIKit

  /// The call screen and the small call with screen sharing, a paused or late partner video, a weak
  /// connection, the offer to turn the camera off, the phone held on its side, and "Just us" open
  /// under the call.
  nonisolated extension DeveloperScenario {
    static let callVideoScreenShare = screen(
      "call-video-screen-share", "Call · Robin shares their screen",
      "Robin's screen fills the call, with Robin's camera and yours as previews in the top right",
      phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      DeveloperCallFixture.partnerShares(&$0)
    }
    static let callVoiceScreenShare = screen(
      "call-voice-screen-share", "Call · Robin shares their screen in a voice call",
      "Robin's screen fills the voice call, with no previews", phase: DeveloperCallFixture.active
    ) { DeveloperCallFixture.partnerShares(&$0) }
    static let callSharingScreen = screen(
      "call-sharing-screen", "Call · you share your screen",
      "You're sharing your screen, with Stop above the buttons and the share button white",
      phase: DeveloperCallFixture.active
    ) { $0.isSharingScreen = true }
    static let callVideoPaused = screen(
      "call-video-paused", "Call · Robin's camera paused",
      "Robin left the app, so their last frame shows blurred with a pause sign", phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      $0.partnerCamera = .paused
    }
    static let callVideoStalled = screen(
      "call-video-stalled", "Call · Robin's video catching up",
      "No new frame from Robin for a moment, so it shows blurred with a spinner", phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      $0.isPartnerVideoStalled = true
    }
    static let callWeakConnection = screen(
      "call-weak-connection", "Call · Robin's connection is weak",
      "A small line above the buttons says Robin's connection is weak", phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      $0.weakConnection = .partners
    }
    static let callCameraOffBattery = screen(
      "call-camera-off-battery", "Call · low battery",
      "The call offers to turn your camera off to save the battery", phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      $0.cameraOffSuggestion = .lowBattery
    }
    static let callCameraOffHot = screen(
      "call-camera-off-hot", "Call · hot phone",
      "The call offers to turn your camera off while the phone is hot, and says your connection is weak",
      phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      $0.cameraOffSuggestion = .hot
      $0.weakConnection = .mine
    }
    static let callVideoSideways = screen(
      "call-video-sideways", "Call · phone on its side",
      "The phone is held with its top to the left, so Robin's video, your camera and the symbols turn",
      phase: DeveloperCallFixture.active, turn: .left
    ) { DeveloperCallFixture.bothCameras(&$0) }
    static let callScreenShareSideways = screen(
      "call-screen-share-sideways", "Call · Robin's screen with the phone on its side",
      "Robin's screen fills the call turned, and the previews sit in the person's top right",
      phase: DeveloperCallFixture.active, turn: .right
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      DeveloperCallFixture.partnerShares(&$0)
    }

    static let callBubbleScreenShare = DeveloperScenario(
      "call-bubble-screen-share", "Call · Robin's screen beside the video bubble",
      "Four in a Row with Robin's video in the bubble and Robin's screen in a window above it", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) {
          DeveloperCallFixture.bothCameras(&$0)
          DeveloperCallFixture.partnerShares(&$0)
        },
        presentation: .bubble, game: true)
    }

    static let callBubbleVoiceScreenShare = DeveloperScenario(
      "call-bubble-voice-screen-share", "Call · Robin's screen beside the voice bubble",
      "Us with the voice bubble and Robin's screen in a window above it", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) {
          DeveloperCallFixture.partnerShares(&$0)
        },
        presentation: .bubble)
    }

    static let callBubbleSharingScreen = DeveloperScenario(
      "call-bubble-sharing-screen", "Call · you share your screen from the bubble",
      "Us with the voice bubble saying you're sharing your screen, with Stop", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) { $0.isSharingScreen = true },
        presentation: .bubble)
    }

    static let callBubblePaused = DeveloperScenario(
      "call-bubble-paused", "Call · Robin's camera paused in the bubble",
      "Four in a Row with Robin's last frame blurred in the bubble, with a pause sign", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) {
          DeveloperCallFixture.bothCameras(&$0)
          $0.partnerCamera = .paused
        },
        presentation: .bubble, game: true)
    }

    static let callChatVideo = DeveloperScenario(
      "call-chat-video", "Call · Just us under a video call",
      "Robin's video shrinks to the top and Just us rises under it", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) {
          DeveloperCallFixture.bothCameras(&$0)
        },
        presentation: .chat, chatRows: true)
    }

    static let callChatVoice = DeveloperScenario(
      "call-chat-voice", "Call · Just us under a voice call",
      "Robin's face, name and call time at the top, and Just us under them", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active), presentation: .chat,
        chatRows: true)
    }
  }

  /// Robin's shared screen in the scenarios: a day's plans in Notes, drawn once.
  @MainActor
  enum DeveloperSharedScreen {
    private static var cached: UIImage?

    static func image() -> UIImage? {
      if let cached { return cached }
      let renderer = ImageRenderer(content: content)
      renderer.scale = 2
      cached = renderer.uiImage
      return cached
    }

    private static var content: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text(verbatim: "9:41").font(.system(size: 13, weight: .semibold))
        Text(verbatim: "Saturday in Oslo").font(.system(size: 26, weight: .bold))
        ForEach(["Coffee at 10", "Walk by the fjord", "Ice cream", "Cinema at 8"], id: \.self) { line in
          HStack {
            Circle().strokeBorder(.orange, lineWidth: 2).frame(width: 20, height: 20)
            Text(verbatim: line).font(.system(size: 17))
          }
        }
        Spacer()
      }
      .foregroundStyle(.black)
      .padding(20)
      .frame(width: DeveloperCallFixture.sharedScreenSize.width, height: DeveloperCallFixture.sharedScreenSize.height,
        alignment: .topLeading)
      .background(Color(red: 1, green: 0.98, blue: 0.92))
    }
  }
#endif
