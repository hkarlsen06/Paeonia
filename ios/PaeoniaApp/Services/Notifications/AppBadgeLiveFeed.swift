import Foundation
import UserNotifications

/// Keeps the app icon number current while the app is open. One subscription to
/// `badges:get_badge_count` carries how many things wait for this person: unread
/// chats, answers to open, games that wait on them, and unseen stories. Each new
/// number goes on the icon. When it changes after the first one, the feed calls
/// `badges:sync_badge`, so this person's other phones get the number too.
/// Pushes carry the number while the app is closed (`backend/convex/lib/badges.ts`).
nonisolated struct AppBadgeLiveFeed: LiveFeed {
    let name = "app-badge"

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            // Nothing can wait without a couple.
            await Self.setBadge(0)
            return
        }

        var last: Int?
        let results = live.subscribe("badges:get_badge_count", as: Double.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(value) = result else {
                continue
            }
            let count = max(0, Int(value))
            guard count != last else {
                continue
            }
            await Self.setBadge(count)
            if last != nil {
                // Best effort: a missed sync only leaves another phone's number
                // stale until its next push or its next launch.
                try? await PaeoniaConvexClientProvider.shared.client().mutation("badges:sync_badge")
            }
            last = count
        }
    }

    static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
