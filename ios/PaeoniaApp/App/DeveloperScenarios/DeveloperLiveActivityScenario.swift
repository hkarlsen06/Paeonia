#if DEBUG
  import ActivityKit
  import SwiftUI

  nonisolated extension DeveloperScenario {
    static let liveActivityGame = DeveloperScenario(
      "live-activity-game", "Games · Robin's game on the Lock Screen",
      "The hub with Robin's Mind Meld Live Activity started on this phone without a push. "
        + "Buttons start it again, move it to Draw & Guess, and end it",
      .games
    ) { _ in DeveloperLiveActivityScenarioView() }
  }

  /// `live-activity-game`: the quiet Games hub with Robin's game Live Activity started on this
  /// phone, without a push. The buttons start it again, move it to Draw & Guess, and end it,
  /// as the server's pushes do.
  struct DeveloperLiveActivityScenarioView: View {
    var body: some View {
      DeveloperPairedScenarioHost(scenario: .gamesHubQuiet)
        .overlay(alignment: .topLeading) { controls }
        .task { await start(.mindMeld) }
    }

    private var controls: some View {
      HStack(spacing: PaeoniaSpacing.space8) {
        control("Start", identifier: "developer.liveActivity.start") { await start(.mindMeld) }
        control("Draw & Guess", identifier: "developer.liveActivity.switch") { await show(.drawAndGuess) }
        control("End", identifier: "developer.liveActivity.end") { await endAll() }
      }
      .padding(.leading, PaeoniaSpacing.space12)
    }

    private func control(_ title: String, identifier: String, action: @escaping () async -> Void) -> some View {
      Button(title) { Task { await action() } }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, 6)
        .background(.paeoniaSurfacePrimary.opacity(0.92), in: Capsule())
        .accessibilityIdentifier(identifier)
    }

    private func start(_ game: GameLiveActivityAttributes.Game) async {
      await endAll()
      _ = try? Activity.request(
        attributes: GameLiveActivityAttributes(activityID: UUID().uuidString, partnerName: "Robin"),
        content: ActivityContent(state: .init(gameKind: game, phase: .playing), staleDate: nil),
        pushType: nil
      )
    }

    private func show(_ game: GameLiveActivityAttributes.Game) async {
      for activity in Activity<GameLiveActivityAttributes>.activities {
        await activity.update(ActivityContent(state: .init(gameKind: game, phase: .playing), staleDate: nil))
      }
    }

    private func endAll() async {
      for activity in Activity<GameLiveActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
#endif
