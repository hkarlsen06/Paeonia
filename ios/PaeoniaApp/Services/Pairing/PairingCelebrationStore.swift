import Foundation

/// What this phone remembers about each couple's first moments: whether the
/// celebration played, how far the first day sequence after it got, and the
/// "Things to try together" card Home shows after that. It also remembers the
/// celebration it played after a restore, until the server has recorded it.
protocol PairingCelebrationStoring: AnyObject {
    func hasSeenCelebration(forCoupleID coupleID: UUID) -> Bool
    func markCelebrationSeen(forCoupleID coupleID: UUID)
    func hasSeenReunionCelebration(_ reunion: ReunionCelebration) -> Bool
    func markReunionCelebrationSeen(_ reunion: ReunionCelebration)
    /// Nil until the celebration was dismissed for this couple on this phone.
    func postPairingProgress(forCoupleID coupleID: UUID) -> PostPairingProgress?
    func savePostPairingProgress(_ progress: PostPairingProgress, forCoupleID coupleID: UUID)
    func homeFirstSteps(forCoupleID coupleID: UUID) -> HomeFirstStepsProgress
    func saveHomeFirstSteps(_ progress: HomeFirstStepsProgress, forCoupleID coupleID: UUID)
}

final class UserDefaultsPairingCelebrationStore: PairingCelebrationStoring {
    static let shared = UserDefaultsPairingCelebrationStore()

    private let defaults: UserDefaults
    private let keyPrefix = "paeonia.pairing.celebration.seen."
    private let progressKeyPrefix = "paeonia.pairing.firstDay."
    private let firstStepsKeyPrefix = "paeonia.pairing.firstSteps."
    private let reunionKeyPrefix = "paeonia.pairing.reunion.seen."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasSeenCelebration(forCoupleID coupleID: UUID) -> Bool {
        defaults.bool(forKey: key(for: coupleID))
    }

    func markCelebrationSeen(forCoupleID coupleID: UUID) {
        defaults.set(true, forKey: key(for: coupleID))
    }

    func hasSeenReunionCelebration(_ reunion: ReunionCelebration) -> Bool {
        defaults.object(forKey: reunionKey(for: reunion.coupleID)) as? Double == reunion.dueAt.timeIntervalSince1970
    }

    func markReunionCelebrationSeen(_ reunion: ReunionCelebration) {
        defaults.set(reunion.dueAt.timeIntervalSince1970, forKey: reunionKey(for: reunion.coupleID))
    }

    func postPairingProgress(forCoupleID coupleID: UUID) -> PostPairingProgress? {
        defaults.data(forKey: progressKey(for: coupleID))
            .flatMap { try? JSONDecoder().decode(PostPairingProgress.self, from: $0) }
    }

    func savePostPairingProgress(_ progress: PostPairingProgress, forCoupleID coupleID: UUID) {
        defaults.set(try? JSONEncoder().encode(progress), forKey: progressKey(for: coupleID))
    }

    func homeFirstSteps(forCoupleID coupleID: UUID) -> HomeFirstStepsProgress {
        defaults.data(forKey: firstStepsKey(for: coupleID))
            .flatMap { try? JSONDecoder().decode(HomeFirstStepsProgress.self, from: $0) }
            ?? HomeFirstStepsProgress()
    }

    func saveHomeFirstSteps(_ progress: HomeFirstStepsProgress, forCoupleID coupleID: UUID) {
        defaults.set(try? JSONEncoder().encode(progress), forKey: firstStepsKey(for: coupleID))
    }

    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(keyPrefix) || key.hasPrefix(progressKeyPrefix) || key.hasPrefix(firstStepsKeyPrefix)
            || key.hasPrefix(reunionKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for coupleID: UUID) -> String {
        "\(keyPrefix)\(coupleID.uuidString)"
    }

    private func reunionKey(for coupleID: UUID) -> String {
        "\(reunionKeyPrefix)\(coupleID.uuidString)"
    }

    private func progressKey(for coupleID: UUID) -> String {
        "\(progressKeyPrefix)\(coupleID.uuidString)"
    }

    private func firstStepsKey(for coupleID: UUID) -> String {
        "\(firstStepsKeyPrefix)\(coupleID.uuidString)"
    }
}
