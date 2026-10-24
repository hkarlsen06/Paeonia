import CryptoKit
import Foundation

/// Remembers which streak milestones, and which free save of a broken streak, this
/// phone has celebrated for one user, so each one shows once. The key holds a hash of the user ID, so UserDefaults does
/// not store the account ID in plain text. The rules live in `StreakMilestoneTracker`.
nonisolated struct StreakMilestoneStore {
    private static let keyPrefix = "paeonia.streak.shownMilestones.v1."
    private static let saveKeyPrefix = "paeonia.streak.celebratedSave.v1."

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

    /// True the first time this phone claims the free save made on `day` (`yyyy-MM-dd`),
    /// which then also counts the milestones up to `count` as shown, since the save has
    /// its own celebration. Callers claim it only when they are about to show it.
    func claimSave(on day: String, count: Int, userID: UUID) -> Bool {
        let saveKey = key(prefix: Self.saveKeyPrefix, userID: userID)
        guard defaults.string(forKey: saveKey) != day else { return false }
        defaults.set(day, forKey: saveKey)
        markRestored(upTo: count, userID: userID)
        return true
    }

    private func shown(userID: UUID) -> Set<Int> {
        Set(defaults.array(forKey: key(prefix: Self.keyPrefix, userID: userID)) as? [Int] ?? [])
    }

    private func save(_ shown: Set<Int>, userID: UUID) {
        defaults.set(shown.sorted(), forKey: key(prefix: Self.keyPrefix, userID: userID))
    }

    private func key(prefix: String, userID: UUID) -> String {
        let digest = SHA256.hash(data: Data(userID.uuidString.lowercased().utf8))
        return prefix + digest.paeoniaHexString
    }
}
