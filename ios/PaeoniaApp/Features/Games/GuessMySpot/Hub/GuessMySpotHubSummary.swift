import Foundation

/// What the Games hub shows for Guess my spot.
nonisolated struct GuessMySpotHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has no game yet, or it is being made.
        case new
        /// This person picks a photo to send.
        case send
        /// The partner sent a photo and this person guesses.
        case guess
        /// This person's photo waits for the partner's guess.
        case waiting
        /// The partner is picking a photo.
        case choosing
        /// A guessed round waits for this person to see it.
        case reveal
    }

    let status: Status
    /// The game waits for this person, so the card stands out and the tab shows a badge.
    let isYourTurn: Bool
    let score: GuessMySpotScore
    /// The couple has a guessed round, so "Our guesses" has something to show.
    let hasHistory: Bool

    init(status: Status, isYourTurn: Bool, score: GuessMySpotScore, hasHistory: Bool) {
        self.status = status
        self.isYourTurn = isYourTurn
        self.score = score
        self.hasHistory = hasHistory
    }

    init(state: RemoteGuessMySpotState, resolution: GuessMySpotResolution, playStyle: GamePlayStyle) {
        let guessed = [state.currentRound, state.previousRound].contains { $0?.isGuessed == true }
        self.init(
            status: Self.status(for: resolution.phase),
            isYourTurn: resolution.isYourTurn,
            score: GuessMySpotScore(game: state.game, playStyle: playStyle),
            hasHistory: guessed
        )
    }

    private static func status(for phase: GuessMySpotPhase) -> Status {
        switch phase {
        case .loading, .starting: .new
        case .send: .send
        case .guess: .guess
        case .waitingForGuess: .waiting
        case .waitingForPhoto: .choosing
        case .reveal: .reveal
        }
    }
}
