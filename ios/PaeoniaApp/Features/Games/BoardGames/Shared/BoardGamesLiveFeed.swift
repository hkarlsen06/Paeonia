import Foundation

/// Keeps the board games cache current while the app is open. One subscription
/// to `boardGames:get_board_games` carries all three games with their moves,
/// turns, tallies and previous endings. Each result goes into the cache, then
/// the hub and the boards re-read.
nonisolated struct BoardGamesLiveFeed: LiveFeed {
    let name = "board_games"

    /// Read by the Games tab, and while the partner plays one of the board games
    /// by the Home card and the tab badge.
    var activation: LiveFeedActivation {
        .gameState(.ludo, .connectFour, .dotsAndBoxes, .ultimateTicTacToe)
    }

    private let cache: any BoardGamesCaching

    init(cache: any BoardGamesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        await follow("boardGames:get_board_games", as: RemoteBoardGames.self, session: session, live: live) {
            await cache.saveState($0, ownerUserID: session.userID)
        }
    }
}

/// The same for both partners' marks. It is its own subscription, so a move
/// never resends the drawings.
nonisolated struct BoardGameMarksLiveFeed: LiveFeed {
    let name = "board_game_marks"

    /// Only the board game screens paint the marks.
    var activation: LiveFeedActivation {
        .whileNeeded([.gamesTab])
    }

    private let cache: any BoardGamesCaching

    init(cache: any BoardGamesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        await follow("boardGames:get_board_game_marks", as: RemoteBoardGameMarks.self, session: session, live: live) {
            await cache.saveMarks($0, ownerUserID: session.userID)
        }
    }
}

/// Subscribes to `path`, saves each result and tells the screens to re-read.
nonisolated private func follow<Value: Decodable & Sendable>(
    _ path: String,
    as type: Value.Type,
    session: SyncSession,
    live: LiveQueryService,
    save: (Value) async -> Void
) async {
    guard session.activeCoupleID != nil else {
        return
    }

    for await result in live.subscribe(path, as: type) {
        guard !Task.isCancelled else {
            return
        }
        guard case let .value(value) = result else {
            continue
        }
        await save(value)
        // The write may have finished after a cancel. The coordinator waits for
        // this task before a privacy purge, so nothing is written after it.
        guard !Task.isCancelled else {
            return
        }
        LocalStoreChanges.post(.games, ownerUserID: session.userID)
    }
}
