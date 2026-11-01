import SwiftUI

extension MainTab {
    /// The live feeds this tab needs while it is on screen.
    var liveFeedTopic: LiveFeedTopic {
        switch self {
        case .us: .usTab
        case .questions: .questionsTab
        case .games: .gamesTab
        case .memories: .memoriesTab
        case .settings: .settingsTab
        }
    }
}

extension View {
    /// Tells `LiveFeedDemand` which tab is on screen and which games the partner
    /// plays, and touches the game turns whenever the app comes to the front. The
    /// live feeds that serve other tabs stop after a short linger.
    func liveFeedDemand(
        visibleTab: MainTab, partnerGames: [GameKind], retainedGames: Set<GameKind> = []
    ) -> some View {
        modifier(
            LiveFeedDemandModifier(visibleTab: visibleTab, partnerGames: partnerGames, retainedGames: retainedGames)
        )
    }
}

private struct LiveFeedDemandModifier: ViewModifier {
    let visibleTab: MainTab
    let partnerGames: [GameKind]
    let retainedGames: Set<GameKind>

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // `onAppear` and `onChange` both publish. The set is idempotent, and
            // `onAppear` repairs the demand if a cover made this view disappear.
            .onAppear(perform: publish)
            .onChange(of: visibleTab) { publish() }
            .onChange(of: partnerGames) { publish() }
            .onChange(of: retainedGames) { publish() }
            // The Home game card reads cached turns. A launch or a return to
            // the front refreshes them without keeping nine subscriptions open.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    LiveFeedDemand.shared.touch([.gameTurns])
                }
            }
    }

    private func publish() {
        LiveFeedDemand.shared.hold(
            Set([visibleTab.liveFeedTopic]).union(retainedGames.map(LiveFeedTopic.partnerInGame)), for: .visibleTab
        )
        LiveFeedDemand.shared.hold(Set(partnerGames.map(LiveFeedTopic.partnerInGame)), for: .partnerGames)
    }
}
