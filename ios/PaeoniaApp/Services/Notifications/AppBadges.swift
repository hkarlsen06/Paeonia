import Foundation
import Observation

/// `badges:get_badges`: what waits for this person, by the tab that shows it, and
/// the number on the app icon (`backend/convex/lib/badges.ts`).
nonisolated struct AppBadgeCounts: Decodable, Equatable, Sendable {
    /// Unread question and story chats, today's answers to open, and Topics questions that wait.
    var questions: Int
    /// Games that wait on this person, and open invites.
    var games: Int
    /// The partner's stories still on Home that this person has not opened.
    var home: Int
    /// Memories whose comments the partner wrote in and this person has not read.
    var memories: Int
    /// The tabs' items of the kinds whose alerts are on in Notifications.
    var icon: Int

    static let zero = AppBadgeCounts(questions: 0, games: 0, home: 0, memories: 0, icon: 0)
}

/// The server's badge counts for the tab bar. The tabs and the app icon read the
/// same counts, so the icon never shows a number that no tab explains.
@MainActor
@Observable
final class AppBadges {
    static let shared = AppBadges()

    private(set) var counts = AppBadgeCounts.zero

    private init() {}

    func update(_ counts: AppBadgeCounts) {
        guard counts != self.counts else { return }
        self.counts = counts
    }
}
