import Foundation

/// What the Games hub shows for Consensio.
nonisolated struct ConsensioHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has no game yet, or it is being made.
        case new
        /// This person picks a topic and places their marker.
        case place
        /// The partner placed a marker and this person guesses.
        case guess
        /// This person's marker waits for the partner's guess.
        case waiting
        /// The partner is picking a topic.
        case choosing
        /// A guessed round waits for this person to see it.
        case reveal
    }

    let status: Status
    /// The game waits for this person, so the card stands out and the tab shows a badge.
    let isYourTurn: Bool
    let sharedPoints: Int
    /// The couple has a guessed round, so "What we know" has something to show.
    let hasHistory: Bool

    init(status: Status, isYourTurn: Bool, sharedPoints: Int, hasHistory: Bool) {
        self.status = status
        self.isYourTurn = isYourTurn
        self.sharedPoints = sharedPoints
        self.hasHistory = hasHistory
    }

    init(state: RemoteConsensioState, resolution: ConsensioResolution) {
        let guessed = [state.currentRound, state.previousRound].contains { $0?.guess != nil }
        self.init(
            status: Self.status(for: resolution.phase),
            isYourTurn: resolution.isYourTurn,
            sharedPoints: state.game?.sharedPoints ?? 0,
            hasHistory: guessed
        )
    }

    private static func status(for phase: ConsensioPhase) -> Status {
        switch phase {
        case .loading, .starting: .new
        case .choose: .place
        case .guess: .guess
        case .waitingForGuess: .waiting
        case .waitingForTopic: .choosing
        case .reveal: .reveal
        }
    }
}
