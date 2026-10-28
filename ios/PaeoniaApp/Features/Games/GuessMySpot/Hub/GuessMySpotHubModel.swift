import Observation
import SwiftUI

/// Guess my spot on the Games tab: its hub card and badge, read from the game's
/// cache, and the screens it opens. `game` is built once, so a notification that
/// opens the game finds it ready.
@MainActor
@Observable
final class GuessMySpotHubModel: GameHubModel {
    let kind = GameKind.guessMySpot
    let game: GuessMySpotViewModel
    /// "Our guesses".
    let history: GuessMySpotHistoryViewModel
    private(set) var summary: GuessMySpotHubSummary?

    private let dependencies: GamesDependencies
    private var userID: UUID?

    init(dependencies: GamesDependencies, game: GuessMySpotViewModel? = nil) {
        self.dependencies = dependencies
        self.game = game ?? GuessMySpotViewModel(dependencies: dependencies)
        history = GuessMySpotHistoryViewModel(dependencies: dependencies)
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
        history.setLocalChangeSyncHandler(handler)
    }

    func reload() async {
        guard let userID else { return }
        let document = await dependencies.guessMySpotCache.document(ownerUserID: userID)
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let playStyle = overview?.settings?.playStyle ?? .together
        let pending = await GuessMySpotPendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        ) ?? .none
        guard self.userID == userID else { return }
        // No state means the first read has not finished, so there is no card yet.
        let newSummary = document.state.map { state in
            let resolution = GuessMySpotResolver(userID: userID).resolve(
                state: state,
                hasLoaded: true,
                isStarting: false,
                pending: pending
            )
            return GuessMySpotHubSummary(state: state, resolution: resolution, playStyle: playStyle)
        }
        if summary != newSummary {
            summary = newSummary
        }
    }

    func refresh() async {
        guard let userID else { return }
        _ = try? await dependencies.guessMySpotCache.fetchState(
            from: dependencies.guessMySpotGateway,
            ownerUserID: userID
        )
    }

    var historyLink: GameHistoryLink? {
        .guessMySpot
    }

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        guard let summary else { return nil }
        return AnyView(GuessMySpotHubCard(
            summary: summary,
            context: context,
            me: game.me,
            partner: game.partner,
            open: { open(.game(.guessMySpot)) },
            openHistory: context.isOnHub ? { open(.guessMySpotHistory) } : nil
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(.guessMySpot):
            AnyView(GuessMySpotScreen(viewModel: game))
        case .guessMySpotHistory:
            AnyView(GuessMySpotHistoryScreen(viewModel: history))
        default:
            nil
        }
    }
}
