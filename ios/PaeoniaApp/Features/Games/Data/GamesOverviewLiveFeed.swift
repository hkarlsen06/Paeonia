import Foundation

/// Keeps the shared part of the Games cache current while the app is open. One
/// subscription to `games:get_games_overview` carries the couple's settings and,
/// for each game, who has it open and this person's last invite. Each result goes
/// into the cache, then the Games tab re-reads. Each game has a feed of its own
/// for its game state (`DrawAndGuessLiveFeed`).
nonisolated struct GamesOverviewLiveFeed: LiveFeed {
    let name = "games_overview"

    private let cache: any GamesCaching

    init(cache: any GamesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("games:get_games_overview", as: RemoteGamesOverview.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(overview) = result else {
                continue
            }
            await cache.saveOverview(overview, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.games, ownerUserID: session.userID)
        }
    }
}
