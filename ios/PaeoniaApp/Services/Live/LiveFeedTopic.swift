import Foundation

/// A reason to keep a live feed running. The screens and events that need data
/// publish topics through `LiveFeedDemand`, and each feed lists the topics it
/// serves in its `activation`.
nonisolated enum LiveFeedTopic: Hashable, Sendable {
    /// The tab on screen. Exactly one is wanted at a time.
    case homeTab
    case questionsTab
    case gamesTab
    case memoriesTab
    case usTab
    /// The partner has this game open. The Home card follows the game while the
    /// partner plays it.
    case partnerInGame(GameKind)
    /// A moment when every game's turn state should be current: the app opens or
    /// returns to the front, or a game push arrives. It is touched, not held.
    case gameTurns
}

/// When a feed runs.
nonisolated enum LiveFeedActivation: Sendable {
    /// From the start of the session to its end. For data that matters whatever
    /// screen is showing: access, the app badge, anything that drives a tab badge
    /// or Home, and anything a background job reads.
    case always
    /// Only while one of these topics is wanted, plus a short linger after the
    /// last one goes away (see `LiveSyncCoordinator.lingerDelay`).
    case whileNeeded(Set<LiveFeedTopic>)

    /// A game's state feed. It runs while the Games tab is open, while the partner
    /// plays one of `kinds`, and when game turns are touched. `also` adds the
    /// screens outside the Games tab that read the same state.
    static func gameState(_ kinds: GameKind..., also extra: Set<LiveFeedTopic> = []) -> LiveFeedActivation {
        var topics: Set<LiveFeedTopic> = [.gamesTab, .gameTurns]
        topics.formUnion(kinds.map(LiveFeedTopic.partnerInGame))
        topics.formUnion(extra)
        return .whileNeeded(topics)
    }

    /// The topics of a `whileNeeded` feed, or nil for a feed that always runs.
    var topics: Set<LiveFeedTopic>? {
        switch self {
        case .always: nil
        case let .whileNeeded(topics): topics
        }
    }
}
