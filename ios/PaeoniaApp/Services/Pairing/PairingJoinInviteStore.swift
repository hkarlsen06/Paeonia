import Foundation

protocol PairingJoinInviteStoring: AnyObject {
    func loadInviteCode() -> String?
    func saveInviteCode(_ code: String)
    func clearInviteCode()
}

final class UserDefaultsPairingJoinInviteStore: PairingJoinInviteStoring {
    static let shared = UserDefaultsPairingJoinInviteStore()

    /// Invites last 7 days, so a saved code older than that cannot work anymore.
    nonisolated static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private let key = "paeonia.pairing.pendingJoinInviteCode"
    private let savedAtKey = "paeonia.pairing.pendingJoinInviteCodeSavedAt"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func loadInviteCode() -> String? {
        guard let code = defaults.string(forKey: key) else {
            return nil
        }

        // A code saved before the date was recorded starts its 7 days now.
        guard let savedAt = defaults.object(forKey: savedAtKey) as? Date else {
            defaults.set(now(), forKey: savedAtKey)
            return try? PairingInviteCode.normalized(code)
        }

        guard now().timeIntervalSince(savedAt) <= Self.maximumAge else {
            clearInviteCode()
            return nil
        }

        return try? PairingInviteCode.normalized(code)
    }

    func saveInviteCode(_ code: String) {
        guard let normalizedCode = try? PairingInviteCode.normalized(code) else {
            clearInviteCode()
            return
        }

        defaults.set(normalizedCode, forKey: key)
        defaults.set(now(), forKey: savedAtKey)
    }

    func clearInviteCode() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: savedAtKey)
    }
}
