import CryptoKit
import Foundation

/// Remembers which streak milestones this phone has celebrated for one user, so
/// each one shows once. The key holds a hash of the user ID, so UserDefaults does
/// not store the account ID in plain text. The rules live in `StreakMilestoneTracker`.
nonisolated struct StreakMilestoneStore {
    private static let keyPrefix = "paeonia.streak.shownMilestones.v1."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The milestone to celebrate now at `count`, if any. It counts as shown from
    /// this call on, so callers claim it only when they are about to show it.
    func claim(count: Int, userID: UUID) -> Int? {
        let result = StreakMilestoneTracker.claim(count: count, shown: shown(userID: userID))
        save(result.shown, userID: userID)
        return result.milestone
    }

    func markRestored(upTo count: Int, userID: UUID) {
        save(StreakMilestoneTracker.markRestored(upTo: count, shown: shown(userID: userID)), userID: userID)
    }

    private func shown(userID: UUID) -> Set<Int> {
        Set(defaults.array(forKey: key(userID: userID)) as? [Int] ?? [])
    }

    private func save(_ shown: Set<Int>, userID: UUID) {
        defaults.set(shown.sorted(), forKey: key(userID: userID))
    }

    private func key(userID: UUID) -> String {
        let digest = SHA256.hash(data: Data(userID.uuidString.lowercased().utf8))
        return Self.keyPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }
}
