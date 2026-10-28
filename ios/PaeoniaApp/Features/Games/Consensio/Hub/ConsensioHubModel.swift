import Observation
import SwiftUI

/// Consensio on the Games tab: its hub card and badge, read from the Consensio
/// cache, and the screens it opens. `game` is built once, so a notification that
/// opens the game finds it ready.
@MainActor
@Observable
final class ConsensioHubModel: GameHubModel {
    let kind = GameKind.consensio
    let game: ConsensioViewModel
    /// "What we know".
    let history: ConsensioHistoryViewModel
    private(set) var summary: ConsensioHubSummary?

    private let dependencies: GamesDependencies
    private var userID: UUID?

    init(dependencies: GamesDependencies, game: ConsensioViewModel? = nil) {
        self.dependencies = dependencies
        self.game = game ?? ConsensioViewModel(dependencies: dependencies)
        history = ConsensioHistoryViewModel(dependencies: dependencies)
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
        let document = await dependencies.consensioCache.document(ownerUserID: userID)
        let pending = await ConsensioPendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        ) ?? .none
        guard self.userID == userID else { return }
        // No state means the first read has not finished, so there is no card yet.
        let newSummary = document.state.map { state in
            let resolution = ConsensioResolver(userID: userID).resolve(
                state: state,
                hasLoaded: true,
                isStarting: false,
                pending: pending
            )
            return ConsensioHubSummary(state: state, resolution: resolution)
        }
        if summary != newSummary {
            summary = newSummary
        }
    }

    func refresh() async {
        guard let userID else { return }
        _ = try? await dependencies.consensioCache.fetchState(from: dependencies.consensioGateway, ownerUserID: userID)
    }

    var historyLink: GameHistoryLink? {
        .consensio
    }

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        guard let summary else { return nil }
        return AnyView(ConsensioHubCard(
            summary: summary,
            context: context,
            open: { open(.game(.consensio)) },
            openHistory: context.isOnHub ? { open(.consensioHistory) } : nil
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(.consensio):
            AnyView(ConsensioScreen(viewModel: game))
        case .consensioHistory:
            AnyView(ConsensioHistoryScreen(viewModel: history))
        case let .consensioHistoryDetail(roundID):
            AnyView(ConsensioHistoryDetailHost(history: history, roundID: roundID))
        default:
            nil
        }
    }
}
