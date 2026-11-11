import Foundation

/// Keeps this person's Mail current while the app is open, with the letters waiting to be
/// opened and the newest page of each mailbox list. Each result of `letters:get_letters` goes
/// into the cache, then the Mail card and the mailbox re-read.
nonisolated struct MailLiveFeed: LiveFeed {
    /// The Us tab badge counts letters that wait to be opened, on every tab.
    var activation: LiveFeedActivation {
        .always
    }

    private let cache: any MailCaching

    init(cache: any MailCaching) {
        self.cache = cache
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            return
        }

        let results = live.subscribe("letters:get_letters", as: MailSnapshot.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(remote) = result else {
                continue
            }
            await cache.save(remote, ownerUserID: session.userID)
            // The coordinator waits for this task before a privacy purge, so nothing is written after it.
            guard !Task.isCancelled else {
                return
            }
            LocalStoreChanges.post(.mail, ownerUserID: session.userID)
        }
    }
}
