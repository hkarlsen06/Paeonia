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
    private let keyPrefix = "paeonia.pairing.celebration.seen."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasSeenCelebration(forPairID pairID: UUID) -> Bool {
        defaults.bool(forKey: key(for: pairID))
    }

    func markCelebrationSeen(forPairID pairID: UUID) {
        defaults.set(true, forKey: key(for: pairID))
    }

    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for pairID: UUID) -> String {
        "\(keyPrefix)\(pairID.uuidString)"
    }
}
