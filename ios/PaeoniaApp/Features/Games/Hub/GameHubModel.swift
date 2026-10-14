import SwiftUI

/// One built game as the Games tab, its badge, and the Home tab see it. A game's
/// hub model conforms, and `GamesViewModel.games` lists it. A kind that is not
/// listed shows nowhere: no hub card, no Home card, and a deep link to it opens
/// the hub.
@MainActor
protocol GameHubModel: AnyObject {
    var kind: GameKind { get }
    /// The game waits for this person to move. The Games tab shows a badge.
    var isYourTurn: Bool { get }
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
    func setLocalChangeSyncHandler(_: (@MainActor @Sendable () async -> Void)?) {}

    // swiftlint:disable:next async_without_await
    func takeNotice() async -> GamesNotice? {
        nil
    }
}

/// What the tab knows that a game's card shows.
struct GameHubCardContext {
    let partnerName: String
    /// The partner has this game open right now.
    let partnerIsHere: Bool
    /// False on the Home tab, which has no room for extra links such as "Our drawings".
    let isOnHub: Bool
}
