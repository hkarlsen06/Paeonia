import Observation
import SwiftUI

/// Mind Meld on the Games tab: its hub card and badge, read from the Mind Meld
/// cache, and the screens it opens. `game` is built once, so a notification that
/// opens the game finds it ready.
@MainActor
@Observable
final class MindMeldHubModel: GameHubModel {
    let kind = GameKind.mindMeld
    let game: MindMeldViewModel
    /// "Our melds".
    let history: MindMeldHistoryViewModel
    private(set) var summary: MindMeldHubSummary?

    private let dependencies: GamesDependencies
    private var userID: UUID?

    init(dependencies: GamesDependencies, game: MindMeldViewModel? = nil) {
        self.dependencies = dependencies
        self.game = game ?? MindMeldViewModel(dependencies: dependencies)
        history = MindMeldHistoryViewModel(dependencies: dependencies)
    }

    var isYourTurn: Bool {
        summary?.isYourTurn == true
    }

    func configure(participants: GameParticipants) {
        if userID != participants.currentUserID {
            summary = nil
        }
        userID = participants.currentUserID
        game.configure(participants: participants)
        history.configure(participants: participants)
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        game.setLocalChangeSyncHandler(handler)
    }

    func reload() async {
        guard let userID else { return }
        let document = await dependencies.mindMeldCache.document(ownerUserID: userID)
        let pending = await MindMeldPendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        ) ?? .none
        guard self.userID == userID else { return }
        // No state means the first read has not finished, so there is no card yet.
        // A couple with no game gets the "Play" card.
        let newSummary = document.state.map { state in
            let resolution = MindMeldResolver(userID: userID).resolve(state: state, hasLoaded: true, pending: pending)
            return MindMeldHubSummary(state: state, resolution: resolution)
        }
        if summary != newSummary {
            summary = newSummary
        }
    }

    func refresh() async {
        guard let userID else { return }
        _ = try? await dependencies.mindMeldCache.fetchState(from: dependencies.mindMeldGateway, ownerUserID: userID)
    }

    var historyLink: GameHistoryLink? {
        .mindMeld
    }

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        guard let summary else { return nil }
        return AnyView(MindMeldHubCard(
            summary: summary,
            context: context,
            open: { open(.game(.mindMeld)) },
            openHistory: context.isOnHub ? { open(.mindMeldHistory) } : nil
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(.mindMeld):
            return AnyView(MindMeldScreen(viewModel: game))
        case .mindMeldHistory:
            return AnyView(MindMeldHistoryScreen(viewModel: history))
        case let .mindMeldHistoryDetail(gameID):
            return AnyView(MindMeldHistoryDetailHost(history: history, gameID: gameID))
        default:
            return nil
        }
    }
}
