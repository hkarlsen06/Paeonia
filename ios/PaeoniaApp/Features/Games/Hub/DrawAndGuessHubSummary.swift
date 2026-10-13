import Foundation

/// What the Games hub shows for Draw & Guess.
nonisolated struct DrawAndGuessHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has not played yet.
        case notStarted
        case yourTurnToDraw
        case yourTurnToGuess
        case partnerIsDrawing
        case waitingForPartner
    }

    let status: Status
    /// Nil until the game exists.
    let score: DrawAndGuessScore?
    /// The couple has a finished drawing, so "Our drawings" has something to show.
    let hasDrawings: Bool

    init(status: Status, score: DrawAndGuessScore?, hasDrawings: Bool = false) {
        self.status = status
        self.score = score
        self.hasDrawings = hasDrawings
    }

    /// Who is here comes from the shared overview (`GamesViewModel.partnerIsHere(in:)`).
    init(state: RemoteDrawAndGuessState, resolution: DrawAndGuessResolution) {
        let playStyle = state.settings?.playStyle ?? .against
        self.init(
            status: Self.status(for: resolution.turnPhase),
            score: state.game.map { DrawAndGuessScore(game: $0, playStyle: playStyle) },
            hasDrawings: state.hasFinishedDrawing
        )
    }

    /// A reveal comes first, and the hub shows the turn that follows it.
    private static func status(for turnPhase: DrawAndGuessPhase) -> Status {
        switch turnPhase {
        case .loading, .needsSetup, .preparing:
            return .notStarted
        case .chooseWord, .drawing:
            return .yourTurnToDraw
        case .guessing:
            return .yourTurnToGuess
        case .waitingForDrawing, .watchingLive:
            return .partnerIsDrawing
        case .waitingForWord, .waitingForGuess, .waitingToSync, .reveal:
            return .waitingForPartner
        }
    }
}
