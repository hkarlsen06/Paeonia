#if DEBUG
  import SwiftUI
  import UIKit

  /// A call engine for the local flows that plays a partner who answers: the call rings for a
  /// second, connects for a second, then runs until you end it. Ending it adds its row to "Just us"
  /// through `recordCall`, the way the server does. It plays the ringback and the connected sound
  /// as `CallEngine` does.
  @MainActor
  final class DeveloperAnsweringCallEngine: CallEngineActions {
    private weak var center: CallCenter?
    private let recordCall: @MainActor (ThreadChatCall) async -> Void
    private let stills = DeveloperCallEngine()
    private let sounds = CallSoundPlayer()
    private var script: Task<Void, Never>?

    /// A call center whose calls this engine plays.
    static func center(recordCall: @escaping @MainActor (ThreadChatCall) async -> Void) -> CallCenter {
      let engine = DeveloperAnsweringCallEngine(recordCall: recordCall)
      let center = CallCenter(engine: engine)
      engine.center = center
      return center
    }

    private init(recordCall: @escaping @MainActor (ThreadChatCall) async -> Void) {
      self.recordCall = recordCall
    }

    func startCall() {
      guard let center, !center.isInCall else { return }
      // Every call starts on the speaker, as `CallEngine` starts it without AirPods.
      center.session = CallSession(id: UUID(), direction: .outgoing, phase: .ringing, audioRoute: .speaker)
      sounds.setRingback(true)
      script?.cancel()
      script = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        self?.sounds.setRingback(false)
        self?.center?.session?.phase = .connecting
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        self?.center?.session?.phase = .active(since: .now)
        self?.sounds.play(.connected)
      }
    }

    func answer() {}

    func decline() {
      end()
    }

    func end() {
      guard let center, let phase = center.session?.phase else { return }
      let call: ThreadChatCall
      switch phase {
      case .active(let since), .reconnecting(let since):
        call = ThreadChatCall(outcome: .completed, durationSeconds: Int(Date.now.timeIntervalSince(since)))
      case .ringing, .connecting:
        call = ThreadChatCall(outcome: .missed, durationSeconds: nil)
      case .ended:
        return
      }
      center.session?.phase = .ended(.hungUp)
      sounds.stopAll()
      script?.cancel()
      script = Task { [weak self] in
        await self?.recordCall(call)
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        self?.center?.session = nil
      }
    }

    func setMuted(_ isMuted: Bool) {
      center?.session?.isMuted = isMuted
    }

    func toggleSpeaker() {
      guard let route = center?.session?.audioRoute else { return }
      center?.session?.audioRoute = route == .speaker ? .receiver : .speaker
    }

    func setCameraOn(_ isOn: Bool) {
      center?.session?.isCameraOn = isOn
    }

    func flipCamera() {
      center?.session?.isUsingFrontCamera.toggle()
    }

    // Unknown, so the call never waits on the night question and the call screen shows no time.
    // swiftlint:disable:next async_without_await
    func partnerTimeZone() async -> TimeZone? {
      nil
    }

    func refreshCallContext() {}

    func makeVideoView(_ source: CallVideoSource) -> UIView {
      stills.makeVideoView(source)
    }
  }

  /// Puts a local flow's call center in the environment. Without one, a call center from outside
  /// the flow, such as a call scenario's, stays in place.
  struct DeveloperLocalFlowCalls: ViewModifier {
    let center: CallCenter?

    func body(content: Content) -> some View {
      if let center {
        content.environment(center)
      } else {
        content
      }
    }
  }

  nonisolated extension DeveloperScenario {
    static let localFlowCall = DeveloperScenario(
      "local-flow-call", "Local flow · a call Robin answers",
      "Call Robin from Four in a Row, shrink the call to its bubble, and end it over Just us", .localFlows
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, gameConversation: .connectFourPartnerTurn, answersCalls: true,
        launchLink: "paeonia://games/connect-four", avatarStories: .noStory)
    }
  }
#endif
