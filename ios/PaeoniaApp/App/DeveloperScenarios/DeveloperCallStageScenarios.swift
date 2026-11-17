#if DEBUG
  import SwiftUI
  import UIKit

  /// The call screen and the small call with screen sharing as it starts, runs, fails and loads, a paused
  /// or late partner video, a weak connection, the offer to turn the camera off, and the phone held on
  /// its side.
  nonisolated extension DeveloperScenario {
    static let callVideoScreenShare = screen(
      "call-video-screen-share", "Call · Robin shares their screen",
      "Robin's screen sits beside Robin's camera and yours in the top right, and a tap makes it fill the call",
      phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      DeveloperCallFixture.partnerShares(&$0)
    }
    static let callVideoScreenShareWide = screen(
      "call-video-screen-share-wide", "Call · Robin shares their screen held on its side",
      "Robin's wide screen sits under Robin's camera and yours in the top right, and a tap makes it fill the call",
      phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      DeveloperCallFixture.partnerShares(&$0, wide: true)
    }
    static let callVoiceScreenShare = screen(
      "call-voice-screen-share", "Call · Robin shares their screen in a voice call",
      "Robin's screen sits between the top bar and the buttons of the voice call, and a tap makes it fill the call",
      phase: DeveloperCallFixture.active
    ) { DeveloperCallFixture.partnerShares(&$0) }
    static let callSharingScreen = screen(
      "call-sharing-screen", "Call · you share your screen",
      "You're sharing your screen, with Stop above the buttons and the share button white",
      phase: DeveloperCallFixture.active
    ) { $0.screenShare = .on }
    static let callShareStarting = screen(
      "call-share-starting", "Call · your share is starting",
      "You picked in the system's picker, so the share button shows a spinner and takes no tap",
      phase: DeveloperCallFixture.active
    ) { $0.screenShare = .starting }
    static let callShareFailed = screen(
      "call-share-failed", "Call · your share did not start",
      "Above the buttons the call says sharing didn't start and to try again", phase: DeveloperCallFixture.active
    ) { $0.screenShare = .failed }
    static let callPartnerScreenLoading = screen(
      "call-partner-screen-loading", "Call · Robin's screen on its way",
      "Robin started sharing, and a spinner waits on a dim tile for the first picture",
      phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      $0.isPartnerSharingScreen = true
    }
    static let callPartnerScreenStalled = screen(
      "call-partner-screen-stalled", "Call · Robin's screen catching up",
      "No new picture of Robin's screen for a moment, so it shows blurred with a spinner",
      phase: DeveloperCallFixture.active
    ) {
      DeveloperCallFixture.bothCameras(&$0)
      DeveloperCallFixture.partnerShares(&$0)
      $0.isPartnerScreenStalled = true
    }
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
      "Robin's screen turns and sits beside the previews in the person's top right",
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
        presentation: .small, game: true)
    }

    static let callBubbleVoiceScreenShare = DeveloperScenario(
      "call-bubble-voice-screen-share", "Call · Robin's screen beside the voice bubble",
      "Us with the voice bubble and Robin's screen in a window above it", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) {
          DeveloperCallFixture.partnerShares(&$0)
        },
        presentation: .small)
    }

    static let callBubbleSharingScreen = DeveloperScenario(
      "call-bubble-sharing-screen", "Call · you share your screen from the bubble",
      "Us with the voice bubble saying you're sharing your screen, with Stop", .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) { $0.screenShare = .on },
        presentation: .small)
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
        presentation: .small, game: true)
    }
  }

  /// Robin's shared screen in the scenarios, a day's plans in Notes, drawn once for each shape.
  @MainActor
  enum DeveloperSharedScreen {
    private static var cached: [Bool: UIImage] = [:]

    static func image(wide: Bool) -> UIImage? {
      if let image = cached[wide] { return image }
      let renderer = ImageRenderer(content: content(size: DeveloperCallFixture.sharedScreenSize(wide: wide)))
      renderer.scale = 2
      cached[wide] = renderer.uiImage
      return cached[wide]
    }

    private static func content(size: CGSize) -> some View {
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
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .background(Color(red: 1, green: 0.98, blue: 0.92))
    }
  }
#endif
