import SwiftUI

/// One built game as the Games tab and the Us tab see it. A game's
/// hub model conforms, and `GamesViewModel.games` lists it. A kind that is not
/// listed shows nowhere: no hub card, no Home card, and a deep link to it opens
/// the hub.
protocol GameHubModel: AnyObject {
    var kind: GameKind { get }
    /// The game waits for this person to move. The hub card shows it.
    var isYourTurn: Bool { get }
    /// What the game needs from this person, which the full call screen tells them about.
    var need: GameNeed? { get }
    /// The game's list of finished games. The game's menu and its card's
    /// long-press menu open it. Nil for a game without one.
    var historyLink: GameHistoryLink? { get }
    /// The game's pieces carry this person's mark, so its menus offer "Your mark".
    var hasBoardMark: Bool { get }
    func configure(participants: GameParticipants)
    /// Called after a move is saved on this phone, so it is sent soon.
    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?)
    /// Re-reads the game's cache. The tab calls it after every Games store change.
    func reload() async
    /// Reads the server once and caches the answer. A failure keeps the cache.
    func refresh() async
    /// A problem a background send left for the tab to show once.
    func takeNotice() async -> GamesNotice?
    /// The game's card, built on `GameHubCardFrame`. Nil hides the card, such as
    /// before the game's first read.
    func card(_ context: GameHubCardContext, open: @escaping (GamesDestination) -> Void) -> AnyView?
    /// The screen for one of this game's destinations, or nil for another game's.
    func screen(for destination: GamesDestination) -> AnyView?
}

extension GameHubModel {
    var need: GameNeed? {
        isYourTurn ? .yourTurn : nil
    }

    var hasBoardMark: Bool {
        false
    }

    func setLocalChangeSyncHandler(_: (@MainActor @Sendable () async -> Void)?) {}

    // swiftlint:disable:next async_without_await
    func takeNotice() async -> GamesNotice? {
        nil
    }
}

/// What a game has for this person that the call screen tells them about.
nonisolated enum GameNeed: Equatable, Sendable {
    /// A move, a guess, a reveal or an ending waits for this person.
    case yourTurn
    /// A board game ended. Its ending waits for nobody on the server, so it is told separately.
    case ended(BoardGameWinner)

    /// The game that newly needs this person between two readings of `GamesViewModel.needs`: the
    /// game on screen when it is one of them, or else the first in the hub's catalog order. Nil when
    /// nothing new waits, or when either reading came before the games were first read.
    static func newlyNeeded(
        previous: [GameKind: GameNeed]?, current: [GameKind: GameNeed]?, openGame: GameKind?
    ) -> (kind: GameKind, need: GameNeed)? {
        guard let previous, let current else { return nil }
        let changed = GameKind.allCases.filter { current[$0] != nil && current[$0] != previous[$0] }
        let kind = changed.contains { $0 == openGame } ? openGame : changed.first
        guard let kind, let need = current[kind] else { return nil }
        return (kind, need)
    }
}

/// What the tab knows that a game's card shows.
struct GameHubCardContext {
    let partnerName: String
    /// The partner has this game open right now.
    let partnerIsHere: Bool
    /// False on the Us tab, which has no room for extra links such as "Our drawings".
    let isOnHub: Bool
    /// "Not now", which moves the card to the hub's grid. Nil when the card is not under
    /// "Right now" for this person's turn, such as on the Us tab or while the partner is here.
    let hide: (() -> Void)?
}
