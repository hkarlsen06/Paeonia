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
    /// The partner has the game screen open right now.
    let partnerIsHere: Bool
    /// Nil until the game exists.
    let score: DrawAndGuessScore?
    /// The couple has a finished drawing, so "Our drawings" has something to show.
    let hasDrawings: Bool

    init(status: Status, partnerIsHere: Bool, score: DrawAndGuessScore?, hasDrawings: Bool = false) {
        self.status = status
        self.partnerIsHere = partnerIsHere
        self.score = score
        self.hasDrawings = hasDrawings
    }

    init(state: RemoteDrawAndGuessState, resolution: DrawAndGuessResolution, now: Date) {
        let playStyle = state.settings?.playStyle ?? .against
        self.init(
            status: Self.status(for: resolution.turnPhase),
            partnerIsHere: GamePresence.isFresh(state.partnerLastSeenAt, now: now),
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
