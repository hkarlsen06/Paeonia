import Observation
import SwiftUI

/// Draw & Guess on the Games tab: its hub card and badge, read from the Games
/// cache, and the screens it opens. `game` is built once, so a notification
/// that opens the game finds it ready.
@MainActor
@Observable
final class DrawAndGuessHubModel: GameHubModel {
    let kind = GameKind.drawAndGuess
    let game: DrawAndGuessViewModel
    /// "Our drawings".
    let history: DrawAndGuessHistoryViewModel
    private(set) var summary: DrawAndGuessHubSummary?

    private let dependencies: GamesDependencies
    private var userID: UUID?

    init(dependencies: GamesDependencies, game: DrawAndGuessViewModel? = nil) {
        self.dependencies = dependencies
        let game = game ?? DrawAndGuessViewModel(dependencies: dependencies)
        self.game = game
        history = DrawAndGuessHistoryViewModel(dependencies: dependencies)
    }

    var isYourTurn: Bool {
        summary?.status.isYourTurn == true
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
        let document = await dependencies.cache.document(ownerUserID: userID)
        let pending = await DrawAndGuessPendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        ) ?? .none
        guard self.userID == userID else { return }
        let newSummary = document.state.map { state in
            let resolution = DrawAndGuessResolver(userID: userID).resolve(
                state: state,
                pending: pending,
                isPartnerDrawingLive: false
            )
            return DrawAndGuessHubSummary(state: state, resolution: resolution)
        }
        if summary != newSummary {
            summary = newSummary
        }
    }

    func refresh() async {
        guard let userID else { return }
        _ = try? await dependencies.cache.fetchState(from: dependencies.gateway, ownerUserID: userID)
    }

    func takeNotice() async -> GamesNotice? {
        guard let userID else { return nil }
        return await dependencies.cache.takeNotices(ownerUserID: userID).last.map(GamesNotice.init)
    }

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        guard let summary else { return nil }
        return AnyView(DrawAndGuessHubCard(
            summary: summary,
            context: context,
            me: game.me,
            partner: game.partner,
            open: { open(.game(.drawAndGuess)) },
            openHistory: context.isOnHub ? { open(.drawAndGuessHistory) } : nil
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(.drawAndGuess):
            return AnyView(DrawAndGuessScreen(viewModel: game))
        case .drawAndGuessHistory:
            return AnyView(DrawAndGuessHistoryScreen(viewModel: history))
        case let .drawAndGuessHistoryDetail(roundID):
            return AnyView(DrawAndGuessHistoryDetailHost(history: history, roundID: roundID))
        default:
            return nil
        }
    }
}
