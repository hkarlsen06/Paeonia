import Observation
import SwiftUI

/// What the Games hub shows for Story Chain.
nonisolated struct StoryChainHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has not played yet.
        case notStarted
        /// This person starts the next story.
        case yourTurnToStart
        case yourTurnToWrite
        /// The partner wrote the last line, and this person gives the story a title.
        case yourTurnToName
        /// The partner named a finished story that this person has not read yet.
        case readEnding
        case partnerTurn
        case waitingForPartner

        /// The game waits for this person. The hub card glows and the tab shows a badge.
        var isYourTurn: Bool {
            switch self {
            case .yourTurnToStart, .yourTurnToWrite, .yourTurnToName, .readEnding: true
            case .notStarted, .partnerTurn, .waitingForPartner: false
            }
        }
    }

    let status: Status
    /// The stories the two of them have finished.
    let finishedCount: Int
    /// The couple has a finished story, so "Our stories" has something to show.
    let hasHistory: Bool

    init(status: Status, finishedCount: Int = 0, hasHistory: Bool? = nil) {
        self.status = status
        self.finishedCount = finishedCount
        self.hasHistory = hasHistory ?? (finishedCount > 0)
    }

    /// Who is here comes from the shared overview (`GamesViewModel.partnerIsHere(in:)`).
    init(state: RemoteStoryChainState, resolution: StoryChainResolution) {
        // A title that is only on this phone has not reached the server's count yet.
        let unsentName = resolution.story?.hasUnsentName == true ? 1 : 0
        self.init(
            status: Self.status(for: resolution),
            finishedCount: (state.game?.finishedCount ?? 0) + unsentName
        )
    }

    /// A finished story comes first, then the turn that follows it.
    private static func status(for resolution: StoryChainResolution) -> Status {
        if case .finished = resolution.phase {
            return .readEnding
        }
        return switch resolution.turnPhase {
        case .loading, .needsSetup, .preparing: .notStarted
        case .chooseOpening: .yourTurnToStart
        case .writing: .yourTurnToWrite
        case .naming: .yourTurnToName
        case .waitingForLine: .partnerTurn
        case .waitingForOpening, .waitingForName, .waitingToSync, .finished: .waitingForPartner
        }
    }
}

/// Story Chain on the Games tab: its hub card and badge, read from the caches,
/// and the screens it opens. `game` is built once, so a notification that opens
/// the game finds it ready.
@MainActor
@Observable
final class StoryChainHubModel: GameHubModel {
    let kind = GameKind.storyChain
    let game: StoryChainViewModel
    /// "Our stories".
    let history: StoryChainHistoryViewModel
    private(set) var summary: StoryChainHubSummary?

    private let dependencies: GamesDependencies
    private var userID: UUID?

    init(dependencies: GamesDependencies, game: StoryChainViewModel? = nil) {
        self.dependencies = dependencies
        let game = game ?? StoryChainViewModel(dependencies: dependencies)
        self.game = game
        history = StoryChainHistoryViewModel(dependencies: dependencies)
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
        let overview = await dependencies.cache.document(ownerUserID: userID).overview
        let document = await dependencies.storyChainCache.document(ownerUserID: userID)
        let work = await StoryChainPendingWork.load(from: dependencies.pendingOperationStore, ownerUserID: userID)
        guard self.userID == userID else { return }
        // A queue that could not be read keeps the card as it is.
        guard let work else { return }
        let newSummary = document.state.map { state in
            let resolution = StoryChainResolver(userID: userID)
                .resolve(state: state, settings: overview?.settings, pending: work)
            return StoryChainHubSummary(state: state, resolution: resolution)
        }
        if summary != newSummary {
            summary = newSummary
        }
    }

    func refresh() async {
        guard let userID else { return }
        _ = try? await dependencies.storyChainCache.fetchState(
            from: dependencies.storyChainGateway,
            ownerUserID: userID
        )
    }

    func takeNotice() async -> GamesNotice? {
        guard let userID else { return nil }
        return await dependencies.storyChainCache.takeNotices(ownerUserID: userID).first.map(GamesNotice.init)
    }

    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView? {
        guard let summary else { return nil }
        return AnyView(StoryChainHubCard(
            summary: summary,
            context: context,
            partnerName: context.partnerName,
            open: { open(.game(.storyChain)) },
            openHistory: context.isOnHub ? { open(.storyChainHistory) } : nil
        ))
    }

    func screen(for destination: GamesDestination) -> AnyView? {
        switch destination {
        case .game(.storyChain):
            return AnyView(StoryChainScreen(viewModel: game))
        case .storyChainHistory:
            return AnyView(StoryChainHistoryScreen(viewModel: history))
        case let .storyChainHistoryDetail(storyID):
            return AnyView(StoryChainHistoryDetailHost(history: history, storyID: storyID))
        default:
            return nil
        }
    }
}
