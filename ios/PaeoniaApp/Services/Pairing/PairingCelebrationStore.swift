import Foundation

@MainActor
protocol PairingCelebrationStoring: AnyObject {
    func hasSeenCelebration(forPairID pairID: UUID) -> Bool
    func markCelebrationSeen(forPairID pairID: UUID)
}

@MainActor
final class UserDefaultsPairingCelebrationStore: PairingCelebrationStoring {
    static let shared = UserDefaultsPairingCelebrationStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasSeenCelebration(forPairID pairID: UUID) -> Bool {
        defaults.bool(forKey: key(for: pairID))
    }

    func markCelebrationSeen(forPairID pairID: UUID) {
        defaults.set(true, forKey: key(for: pairID))
    }

    private func key(for pairID: UUID) -> String {
        "paeonia.pairing.celebration.seen.\(pairID.uuidString)"
    }
}
