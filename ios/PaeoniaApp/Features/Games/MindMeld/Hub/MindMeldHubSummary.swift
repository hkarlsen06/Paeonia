import Foundation

/// What the Games hub shows for Mind Meld.
nonisolated struct MindMeldHubSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The couple has no game yet, or one is being started.
        case new
        /// A round is open and nobody has locked in.
        case open(round: Int)
        case partnerLocked
        /// This person locked in and the partner has not.
        case waiting
        /// A round or an ending is revealed and this person has not seen it.
        case reveal
        case melded(rounds: Int)
        case gotAway
    }

    let status: Status
    /// The game waits for this person, so the card stands out and the tab shows a badge.
    let isYourTurn: Bool
    /// How many times the couple has melded.
    let melds: Int
    /// The couple has a finished game, so "Our melds" has something to show.
    let hasFinishedGames: Bool

    init(status: Status, isYourTurn: Bool, melds: Int, hasFinishedGames: Bool) {
        self.status = status
        self.isYourTurn = isYourTurn
        self.melds = melds
        self.hasFinishedGames = hasFinishedGames
    }

    init(state: RemoteMindMeldState, resolution: MindMeldResolution) {
        self.init(
            status: Self.status(for: resolution),
            isYourTurn: resolution.isYourTurn,
            melds: state.stats.melds,
            hasFinishedGames: state.stats.games > 0
        )
    }

    private static func status(for resolution: MindMeldResolution) -> Status {
        switch resolution.phase {
        case .loading, .starting:
            .new
        case .write:
            resolution.round?.partnerLocked == true ? .partnerLocked : .open(round: resolution.roundNumber)
        case .waiting:
            .waiting
        case .reveal:
            .reveal
        case .over:
            resolution.game?.state == .melded ? .melded(rounds: resolution.roundNumber) : .gotAway
        }
    }
}
