#if DEBUG
  import SwiftUI
  import UIKit

  /// What the partner does in a local flow's calls.
  nonisolated enum DeveloperCallPartner: Sendable {
    /// Answers your calls.
    case answers
    /// Answers your calls, and calls you two seconds after the flow starts.
    case callsIn
  }

  /// A call engine for the local flows that plays a partner who answers: the call rings for a
  /// second, connects for a second, then runs until you end it. The partner's own call rings inside
  /// the app as the pill, as `CallEngine` rings while the app is open, and connects when you answer.
  /// Ending a call adds its row to "Just us" through `recordCall`, the way the server does. It plays
  /// the ringback, the ring, the connected sound and haptic, and the ended sound as `CallEngine` does.
  @MainActor
  final class DeveloperAnsweringCallEngine: CallEngineActions {
    private weak var center: CallCenter?
    private let recordCall: @MainActor (ThreadChatCall) async -> Void
    private let stills = DeveloperCallEngine()
    private let sounds = CallSoundPlayer()
    private var script: Task<Void, Never>?
    private var ring: Task<Void, Never>?

    /// A call center whose calls this engine plays.
    static func center(
      partner: DeveloperCallPartner, recordCall: @escaping @MainActor (ThreadChatCall) async -> Void
    ) -> CallCenter {
      let engine = DeveloperAnsweringCallEngine(recordCall: recordCall)
      let center = CallCenter(engine: engine)
      engine.center = center
      if partner == .callsIn {
        engine.ringIn(after: .seconds(2))
      }
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
        self?.connect(haptic: true)
      }
    }

    func answer() {
      guard let center, let session = center.session, session.direction == .incoming, session.phase == .ringing
      else { return }
      ring?.cancel()
      center.presentation = .full
      center.session?.ringsInApp = false
      connect(haptic: false)
    }

    private func ringIn(after delay: Duration) {
      script = Task { [weak self] in
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, let self, let center, !center.isInCall else { return }
        center.presentation = .bubble
        center.session = CallSession(
          id: UUID(), direction: .incoming, phase: .ringing, audioRoute: .speaker, ringsInApp: true)
        ring = CallRinger.ring()
      }
    }

    /// Connects for a second, then runs until you end it. Only the caller's phone taps.
    private func connect(haptic: Bool) {
      center?.session?.phase = .connecting
      script?.cancel()
      script = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self else { return }
        center?.session?.phase = .active(since: .now)
        sounds.play(.connected)
        if haptic {
          CallHaptics.connected()
        }
      }
    }

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
      ring?.cancel()
      sounds.stopAll()
      if case .completed = call.outcome {
        sounds.play(.ended)
      }
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

  /// Robin is here in both call flows, so the call screen and the ring pill grow out of Robin's
  /// avatar, and it comes back when the call ends.
  nonisolated extension DeveloperScenario {
    static let localFlowCall = DeveloperScenario(
      "local-flow-call", "Local flow · a call Robin answers",
      "Call Robin from Four in a Row, shrink the call to its bubble, and end it over Just us", .localFlows
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, gameConversation: .connectFourPartnerTurn, callPartner: .answers,
        launchLink: "paeonia://games/connect-four", avatarStories: .noStory,
        presence: DeveloperPresenceFixture.model(partner: PartnerPresence()))
    }

    static let localFlowIncomingCall = DeveloperScenario(
      "local-flow-incoming-call", "Local flow · Robin calls you",
      "Robin's call rings in its pill over Us, opens to the call screen, and connects when you answer",
      .localFlows
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, callPartner: .callsIn, avatarStories: .noStory,
        presence: DeveloperPresenceFixture.model(partner: PartnerPresence()))
    }
  }
#endif
