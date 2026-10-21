import Observation
import SwiftUI

/// Exquisite corpse on the Games tab: its hub card and badge, read from the
/// Exquisite corpse cache, and the screens it opens. `game` is built once, so a
/// notification that opens the game finds it ready.
@MainActor
@Observable
final class ExquisiteCorpseHubModel: GameHubModel {
    let kind = GameKind.exquisiteCorpse
    let game: ExquisiteCorpseViewModel
    /// "Our creatures".
    let history: ExquisiteCorpseHistoryViewModel
    private(set) var summary: ExquisiteCorpseHubSummary?

    @ObservationIgnored private let dependencies: GamesDependencies
    @ObservationIgnored private var userID: UUID?
    /// The last queue that was read. A failed read keeps it, because treating
    /// the failure as an empty queue would make a saved part look lost.
    @ObservationIgnored private var pending = ExquisiteCorpsePendingWork.none

    init(dependencies: GamesDependencies, game: ExquisiteCorpseViewModel? = nil) {
        self.dependencies = dependencies
        let game = game ?? ExquisiteCorpseViewModel(dependencies: dependencies)
        self.game = game
        history = ExquisiteCorpseHistoryViewModel(dependencies: dependencies)
    }

    /// The game waits for this person: their part to draw, or a creature to look at.
    var isYourTurn: Bool {
        summary?.status.isYourTurn == true
    }

    func configure(participants: GameParticipants) {
        if userID != participants.currentUserID {
            summary = nil
            pending = .none
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
        let document = await dependencies.exquisiteCorpseCache.document(ownerUserID: userID)
        let hasSettings = await dependencies.cache.document(ownerUserID: userID).overview?.settings != nil
        let work = await ExquisiteCorpsePendingWork.load(
            from: dependencies.pendingOperationStore,
            ownerUserID: userID
        )
        guard self.userID == userID else { return }
        if let work {
            pending = work
        }
        let newSummary = document.state.map { state in
            let resolution = ExquisiteCorpseResolver(userID: userID).resolve(
                state: state,
                hasSettings: hasSettings,
                pending: pending,
                isPartnerDrawingLive: false
            )
            return ExquisiteCorpseHubSummary(state: state, resolution: resolution)
        }
        if summary != newSummary {
            summary = newSummary
        }
    }

    func refresh() async {
        guard let userID else { return }
        _ = try? await dependencies.exquisiteCorpseCache.fetchState(
            from: dependencies.exquisiteCorpseGateway,
            ownerUserID: userID
        )
    }

    func takeNotice() async -> GamesNotice? {
        guard let userID else { return nil }
        return await dependencies.exquisiteCorpseCache.takeNotices(ownerUserID: userID).last.map(GamesNotice.init)
    }

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        guard let summary else { return nil }
        return AnyView(ExquisiteCorpseHubCard(
            summary: summary,
            context: context,
            open: { open(.game(.exquisiteCorpse)) },
            openHistory: context.isOnHub ? { open(.exquisiteCorpseHistory) } : nil
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(.exquisiteCorpse):
            return AnyView(ExquisiteCorpseScreenHost(game: game, history: history))
        case .exquisiteCorpseHistory:
            return AnyView(ExquisiteCorpseHistoryScreen(viewModel: history))
        case let .exquisiteCorpseHistoryDetail(figureID):
            return AnyView(ExquisiteCorpseHistoryDetailHost(history: history, figureID: figureID))
        default:
            return nil
        }
    }
}
