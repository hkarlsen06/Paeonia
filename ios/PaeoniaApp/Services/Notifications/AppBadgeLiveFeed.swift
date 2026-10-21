import Foundation
import UserNotifications

/// Keeps the app icon number and the tab badges current while the app is open.
/// One subscription to `badges:get_badges` carries what waits for this person:
/// unread chats, answers to open, games that wait on them, and unseen stories.
/// Each new value goes to `AppBadges` and the icon. When the icon number changes
/// after the first one, the feed calls `badges:sync_badge`, so this person's
/// other phones get the number too. Pushes carry the number while the app is
/// closed (`backend/convex/lib/badges.ts`).
nonisolated struct AppBadgeLiveFeed: LiveFeed {
    let name = "app-badge"

    func run(session: SyncSession, live: LiveQueryService) async {
        guard session.activeCoupleID != nil else {
            // Nothing can wait without a couple.
            await Self.clear()
            return
        }

        var lastIcon: Int?
        let results = live.subscribe("badges:get_badges", as: AppBadgeCounts.self)
        for await result in results {
            guard !Task.isCancelled else {
                return
            }
            guard case let .value(counts) = result else {
                continue
            }
            await AppBadges.shared.update(counts)
            let icon = max(0, counts.icon)
            guard icon != lastIcon else {
                continue
            }
            await Self.setBadge(icon)
            if lastIcon != nil {
                // Best effort: a missed sync only leaves another phone's number
                // stale until its next push or its next launch.
                try? await PaeoniaConvexClientProvider.shared.client().mutation("badges:sync_badge")
            }
            lastIcon = icon
        }
    }

    /// Nothing waits: zero on the icon and on every tab.
    static func clear() async {
        await AppBadges.shared.update(.zero)
        await setBadge(0)
    }

    static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
