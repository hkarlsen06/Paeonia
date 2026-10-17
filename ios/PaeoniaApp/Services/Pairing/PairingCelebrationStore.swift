import Foundation

/// What this phone remembers about each pair's first moments: whether the
/// celebration played, and how far the first day sequence after it got.
@MainActor
protocol PairingCelebrationStoring: AnyObject {
    func hasSeenCelebration(forPairID pairID: UUID) -> Bool
    func markCelebrationSeen(forPairID pairID: UUID)
    /// Nil until the celebration was dismissed for this pair on this phone.
    func postPairingProgress(forPairID pairID: UUID) -> PostPairingProgress?
    func savePostPairingProgress(_ progress: PostPairingProgress, forPairID pairID: UUID)
}

@MainActor
final class UserDefaultsPairingCelebrationStore: PairingCelebrationStoring {
    static let shared = UserDefaultsPairingCelebrationStore()

    private let defaults: UserDefaults
    private let keyPrefix = "paeonia.pairing.celebration.seen."
    private let progressKeyPrefix = "paeonia.pairing.firstDay."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasSeenCelebration(forPairID pairID: UUID) -> Bool {
        defaults.bool(forKey: key(for: pairID))
    }

    func markCelebrationSeen(forPairID pairID: UUID) {
        defaults.set(true, forKey: key(for: pairID))
    }

    func postPairingProgress(forPairID pairID: UUID) -> PostPairingProgress? {
        defaults.data(forKey: progressKey(for: pairID))
            .flatMap { try? JSONDecoder().decode(PostPairingProgress.self, from: $0) }
    }

    func savePostPairingProgress(_ progress: PostPairingProgress, forPairID pairID: UUID) {
        defaults.set(try? JSONEncoder().encode(progress), forKey: progressKey(for: pairID))
    }

    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(keyPrefix) || key.hasPrefix(progressKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for pairID: UUID) -> String {
        "\(keyPrefix)\(pairID.uuidString)"
    }

    private func progressKey(for pairID: UUID) -> String {
        "\(progressKeyPrefix)\(pairID.uuidString)"
    }
}
