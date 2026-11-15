#if DEBUG
  import SwiftUI
  import UIKit

  /// Every state of the call screen, the bubble, the call buttons and the call rows, for
  /// screenshots. Each scenario brings its own `CallCenter` with a fixed session and an engine
  /// that does nothing, so nothing rings and no microphone or camera turns on.
  nonisolated extension DeveloperScenario {
    static let calls: [DeveloperScenario] = [
      callOutgoing, callConnecting, callActiveVoice, callActiveVoiceMutedSpeaker, callActiveVoiceAirPods,
      callActiveVideo, callVideoOwnCamera, callMicrophoneWaiting, callReconnecting, callEnded, callEndedNoAnswer,
      callFailedOffline, callBusy, callBubbleVoiceGame, callBubbleVideoGame, callBubbleJustUs, callNightCheck,
      callGameToolbar, callUsTab, callJustUsRows,
    ]

    // MARK: The call screen

    static let callOutgoing = screen("call-outgoing", "Call · calling", "Robin's phone rings", phase: .ringing)
    static let callConnecting = screen(
      "call-connecting", "Call · connecting", "Robin answered and the phones connect", phase: .connecting)
    static let callActiveVoice = screen(
      "call-active-voice", "Call · voice", "A voice call four minutes in", phase: DeveloperCallFixture.active)
    static let callActiveVoiceMutedSpeaker = screen(
      "call-active-voice-muted-speaker", "Call · muted on speaker", "Muted, with the sound on the speaker",
      phase: DeveloperCallFixture.active
    ) {
      $0.isMuted = true
      $0.audioRoute = .speaker
    }
    static let callActiveVoiceAirPods = screen(
      "call-active-voice-airpods", "Call · AirPods", "The system's sound picker in place of Speaker",
      phase: DeveloperCallFixture.active
    ) { $0.audioRoute = .external(name: "AirPods Pro") }
    static let callMicrophoneWaiting = screen(
      "call-microphone-waiting", "Call · microphone not allowed yet",
      "Answered from the Lock Screen before allowing the microphone", phase: DeveloperCallFixture.active
    ) { $0.isWaitingForMicrophone = true }
    static let callActiveVideo = screen(
      "call-active-video", "Call · video", "Both cameras on", phase: DeveloperCallFixture.active
    ) {
      $0.isCameraOn = true
      $0.isPartnerCameraOn = true
    }
    static let callVideoOwnCamera = screen(
      "call-video-own-camera", "Call · your camera only", "Your camera on, Robin's off",
      phase: DeveloperCallFixture.active
    ) { $0.isCameraOn = true }
    static let callReconnecting = screen(
      "call-reconnecting", "Call · reconnecting", "The connection dropped and the phones try again",
      phase: .reconnecting(since: DeveloperCallFixture.startedAt))
    static let callEnded = screen("call-ended", "Call · ended", "Call ended", phase: .ended(.hungUp))
    static let callEndedNoAnswer = screen(
      "call-ended-no-answer", "Call · no answer", "Robin did not answer", phase: .ended(.noAnswer))
    static let callFailedOffline = screen(
      "call-failed-offline", "Call · offline", "The phone has no connection", phase: .ended(.failed(.offline)))
    static let callBusy = screen("call-busy", "Call · busy", "The couple already has a call", phase: .ended(.busy))

    // MARK: Over the app

    static let callBubbleVoiceGame = DeveloperScenario(
      "call-bubble-voice-game", "Call · voice bubble over a game", "Four in a Row with the call shrunk to its bubble",
      .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active), presentation: .bubble, game: true)
    }

    static let callBubbleVideoGame = DeveloperScenario(
      "call-bubble-video-game", "Call · video bubble over a game", "Four in a Row with Robin's video in the bubble",
      .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active) {
          $0.isCameraOn = true
          $0.isPartnerCameraOn = true
        },
        presentation: .bubble, game: true)
    }

    static let callBubbleJustUs = DeveloperScenario(
      "call-bubble-just-us", "Call · bubble over Just us", "The voice bubble over the chat, where nothing records",
      .calls
    ) { _ in
      DeveloperCallLocalFlow(
        session: DeveloperCallFixture.session(phase: DeveloperCallFixture.active), presentation: .bubble,
        coupleCalls: true)
    }

    static let callNightCheck = DeveloperScenario(
      "call-night-check", "Call · night check", "It's 02:14 for Robin. Call anyway?", .calls
    ) { _ in
      DeveloperCallLocalFlow(game: true, nightPrompt: DeveloperCallFixture.nightPrompt)
    }

    static let callGameToolbar = DeveloperScenario(
      "call-game-toolbar", "Call · game toolbar", "Score, call, chat and the menu in Four in a Row", .calls
    ) { _ in DeveloperCallLocalFlow(game: true) }

    static let callUsTab = DeveloperScenario(
      "call-us-tab", "Call · Us", "The call button under Robin's avatar on Us", .calls
    ) { _ in DeveloperCallLocalFlow() }

    static let callJustUsRows = DeveloperScenario(
      "call-just-us-rows", "Call · rows in Just us", "A finished call, your unanswered call and a missed one",
      .calls
    ) { _ in DeveloperCallLocalFlow(coupleCalls: true) }

    private static func screen(
      _ id: String, _ title: String, _ detail: String, phase: CallPhase,
      configure: @escaping @Sendable (inout CallSession) -> Void = { _ in }
    ) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .calls) { _ in
        DeveloperCallScreenHost(session: DeveloperCallFixture.session(phase: phase, configure: configure))
      }
    }
  }

  /// The couple and the call the scenarios show.
  nonisolated enum DeveloperCallFixture {
    static let startedAt = Date.now.addingTimeInterval(-252)
    static let active = CallPhase.active(since: startedAt)
    static let callID = UUID(uuidString: "ca11ca11-0000-4000-8000-000000000001") ?? UUID()

    static let participants = DailyChallengeParticipants(
      currentUserID: DeveloperScenarioFixture.currentUserID,
      currentDisplayName: "Alex",
      currentProfilePhotoAssetID: DeveloperAvatarFixture.ownPhoto,
      partnerUserID: DeveloperScenarioFixture.partnerUserID,
      partnerDisplayName: "Robin",
      partnerProfilePhotoAssetID: DeveloperAvatarFixture.partnerPhoto
    )

    /// The question as it reads at 02:14 on Robin's clock.
    static var nightPrompt: CallStarter.NightPrompt {
      let utc = TimeZone(identifier: "UTC") ?? .gmt
      var components = DateComponents(year: 2_026, month: 11, day: 14, hour: 2, minute: 14)
      components.timeZone = utc
      let date = Calendar(identifier: .gregorian).date(from: components) ?? .now
      return CallStarter.NightPrompt(partnerName: "Robin", localTime: CallNightCheck.localTime(at: date, in: utc))
    }

    static func session(
      phase: CallPhase, configure: (inout CallSession) -> Void = { _ in }
    ) -> CallSession {
      var session = CallSession(id: callID, direction: .outgoing, phase: phase)
      configure(&session)
      return session
    }

    /// "Just us" with a text, a finished call yesterday, your call Robin did not answer, and
    /// Robin's call you missed, which is the newest.
    static func coupleChat() -> (summary: ThreadChatSummary, messages: [ThreadChatMessage]) {
      let threadID = UUID(uuidString: "ca11ca11-0000-4000-8000-0000000000c0") ?? UUID()
      let now = Date.now
      func message(
        _ index: Int, from sender: UUID, minutesAgo: Double, body: String = "", call: ThreadChatCall? = nil
      ) -> ThreadChatMessage {
        ThreadChatMessage(
          id: UUID(uuidString: String(format: "ca11ca11-0000-4000-8000-%012d", index)) ?? UUID(),
          threadID: threadID, subjectID: ThreadChatSubject.couple.id, senderUserID: sender, body: body,
          createdAt: now.addingTimeInterval(-minutesAgo * 60), clientOperationID: nil, delivery: .sent, call: call)
      }
      let alex = DeveloperScenarioFixture.currentUserID
      let robin = DeveloperScenarioFixture.partnerUserID
      let messages = [
        message(1, from: robin, minutesAgo: 26 * 60, body: "Call me when you're home?"),
        message(2, from: alex, minutesAgo: 25 * 60, call: ThreadChatCall(outcome: .completed, durationSeconds: 745)),
        message(3, from: alex, minutesAgo: 25 * 60 - 2, body: "That was nice ❤️"),
        message(4, from: alex, minutesAgo: 95, call: ThreadChatCall(outcome: .missed, durationSeconds: nil)),
        message(5, from: robin, minutesAgo: 12, call: ThreadChatCall(outcome: .missed, durationSeconds: nil)),
      ]
      let newest = messages[messages.count - 1]
      let summary = ThreadChatSummary(
        threadID: threadID, coupleID: DeveloperScenarioFixture.coupleID, subject: .couple,
        createdAt: messages[0].createdAt, updatedAt: newest.createdAt, lastMessageID: newest.id,
        lastMessageAt: newest.createdAt, lastMessageSenderUserID: newest.senderUserID, lastMessageBody: "",
        lastMessageCall: newest.call)
      return (summary, messages)
    }
  }

  /// A call engine that does nothing. Its video is a still photo of each person, so the tiles look
  /// like a call, and Robin is in Oslo.
  @MainActor
  final class DeveloperCallEngine: CallEngineActions {
    func startCall() {}
    func answer() {}
    func decline() {}
    func end() {}
    func setMuted(_: Bool) {}
    func toggleSpeaker() {}
    func setCameraOn(_: Bool) {}
    func flipCamera() {}
    func refreshCallContext() {}

    // swiftlint:disable:next async_without_await
    func partnerTimeZone() async -> TimeZone? {
      TimeZone(identifier: "Europe/Oslo")
    }

    func makeVideoView(_ source: CallVideoSource) -> UIView {
      let photo = source == .partner ? DeveloperAvatarFixture.partnerPhoto : DeveloperAvatarFixture.ownPhoto
      let view = UIImageView(image: DeveloperAvatarFixture.photoData(for: photo).flatMap(UIImage.init(data:)))
      view.contentMode = .scaleAspectFill
      view.backgroundColor = .black
      return view
    }
  }

  /// The full call screen over a plain background. A ringing call plays the ringback, so it can be
  /// heard on the simulator.
  private struct DeveloperCallScreenHost: View {
    @State private var center: CallCenter
    @State private var sounds = CallSoundPlayer()

    init(session: CallSession) {
      _center = State(initialValue: CallCenter(engine: DeveloperCallEngine(), session: session))
    }

    var body: some View {
      Color.paeoniaBackgroundPrimary
        .ignoresSafeArea()
        .callOverlay(participants: DeveloperCallFixture.participants)
        .environment(center)
        .environment(\.profilePhotoImageProvider, DeveloperAvatarPhotoProvider())
        .onAppear {
          if center.session?.phase == .ringing {
            sounds.setRingback(true)
          }
        }
        .onDisappear { sounds.stopAll() }
    }
  }

  /// The real paired app from a local flow, with a call center of its own. `game` opens Four in a
  /// Row on Robin's turn, `coupleCalls` opens "Just us" with its call rows, and `nightPrompt` has
  /// the night question up.
  private struct DeveloperCallLocalFlow: View {
    @State private var center: CallCenter
    @State private var starter: CallStarter
    private let game: Bool
    private let coupleCalls: Bool

    init(
      session: CallSession? = nil, presentation: CallPresentation = .full, game: Bool = false,
      coupleCalls: Bool = false, nightPrompt: CallStarter.NightPrompt? = nil
    ) {
      let center = CallCenter(engine: DeveloperCallEngine(), session: session)
      center.presentation = presentation
      _center = State(initialValue: center)
      _starter = State(initialValue: CallStarter(center: center, nightPrompt: nightPrompt))
      self.game = game
      self.coupleCalls = coupleCalls
    }

    var body: some View {
      Group {
        if game {
          DeveloperLocalFlowHost(
            seed: .paired, gameConversation: .connectFourPartnerTurn, launchLink: "paeonia://games/connect-four",
            avatarStories: .noStory)
        } else if coupleCalls {
          DeveloperLocalFlowHost(
            seed: .paired, gameConversation: .mindMeldWrite, coupleCalls: true, launchLink: "paeonia://chat",
            avatarStories: .noStory)
        } else {
          DeveloperLocalFlowHost(seed: .paired, avatarStories: .noStory)
        }
      }
      .environment(center)
      .environment(starter)
    }
  }
#endif
