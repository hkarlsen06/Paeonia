#if DEBUG
  import SwiftUI

  nonisolated extension DeveloperScenario {
    static let liveActivityViews = DeveloperScenario(
      "live-activity-views", "Games · Robin's game Live Activity, every view",
      "The production Lock Screen view and the compact, minimal and expanded Dynamic Island views, "
        + "playing with no turn, your turn, their turn, stale and ended, laid out on an ordinary screen",
      .games
    ) { _ in DeveloperLiveActivityViewsScenarioView() }
  }

  /// `live-activity-views`: the production views of the game Live Activity, laid out in shapes like
  /// the Lock Screen and the Dynamic Island. Simulator screenshots do not draw the real island, so
  /// this is where a check sees the island views. It is not the real island.
  struct DeveloperLiveActivityViewsScenarioView: View {
    private static let attributes = GameLiveActivityAttributes(activityID: "scenario", partnerName: "Robin")

    private struct Sample: Identifiable {
      let label: String
      let content: GameLiveActivityContent
      var id: String { label }
    }

    private static let samples = [
      Sample(label: "Playing", content: content(.mindMeld, .playing, .none, isStale: false)),
      Sample(label: "YourTurn", content: content(.connectFour, .playing, .yours, isStale: false)),
      Sample(label: "TheirTurn", content: content(.storyChain, .playing, .theirs, isStale: false)),
      Sample(label: "Stale", content: content(.drawAndGuess, .playing, .yours, isStale: true)),
      Sample(label: "Ended", content: content(.piccante, .ended, .none, isStale: false)),
    ]

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
          ForEach(Self.samples) { state in
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
              Text(state.label)
                .font(.headline)
                .accessibilityIdentifier("developer.liveActivityViews.\(state.label)")
              lockScreen(state.content)
              HStack(spacing: PaeoniaSpacing.space12) {
                compact(state.content)
                minimal(state.content)
              }
              expanded(state.content)
            }
          }
        }
        .padding(PaeoniaSpacing.space16)
      }
      .background(Color.paeoniaSurfacePrimary)
    }

    private static func content(
      _ game: GameLiveActivityAttributes.Game,
      _ phase: GameLiveActivityAttributes.Phase,
      _ turn: GameLiveActivityAttributes.Turn,
      isStale: Bool
    ) -> GameLiveActivityContent {
      GameLiveActivityContent(
        attributes: attributes,
        state: .init(gameKind: game, phase: phase, turn: turn),
        isStale: isStale
      )
    }

    private func lockScreen(_ content: GameLiveActivityContent) -> some View {
      GameLiveActivityLockScreenView(content: content)
        .background(PaeoniaBrandColors.background, in: RoundedRectangle(cornerRadius: 24))
    }

    /// The compact island: leading and trailing views beside the camera.
    private func compact(_ content: GameLiveActivityContent) -> some View {
      HStack(spacing: 0) {
        GameLiveActivityIcon(content: content, size: 24, speaksTitle: true)
        Spacer(minLength: 96)
        GameLiveActivityCompactName(content: content)
      }
      .padding(.horizontal, 8)
      .frame(width: 236, height: 37)
      .background(.black, in: Capsule())
      .environment(\.colorScheme, .dark)
    }

    private func minimal(_ content: GameLiveActivityContent) -> some View {
      GameLiveActivityIcon(content: content, size: 24, speaksTitle: true)
        .frame(width: 37, height: 37)
        .background(.black, in: Circle())
        .environment(\.colorScheme, .dark)
    }

    /// The expanded island: leading, trailing and bottom regions.
    private func expanded(_ content: GameLiveActivityContent) -> some View {
      VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
        HStack {
          GameLiveActivityIcon(content: content, size: 44)
          Spacer()
          GameLiveActivityBadge(content: content)
        }
        GameLiveActivityText(content: content)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(PaeoniaSpacing.space16)
      .background(.black, in: RoundedRectangle(cornerRadius: 44))
      .environment(\.colorScheme, .dark)
    }
  }
#endif
