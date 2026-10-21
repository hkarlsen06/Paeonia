import Foundation

/// Keeps this person's favorites current while the app is open, so a star is filled the
/// same on both of their devices and a favorite whose item was deleted drops out. Each
/// result of `favorites:list_favorites` goes into the cache, then the stars re-read.
nonisolated struct FavoritesLiveFeed: LiveFeed {
    let name = "favorites"

    /// Favorites show on every tab and in Search, which opens from any of them.
    var activation: LiveFeedActivation {
        .always
    }

    private let cache: any FavoritesCaching

    init(cache: any FavoritesCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("favorites:list_favorites", as: [FavoriteRef].self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(favorites) = result else {
                continue
            }
            await cache.save(favorites, ownerUserID: session.userID)
            // The write may have finished after a cancel. The coordinator waits for
            // this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.favorites, ownerUserID: session.userID)
        }
    }
}
