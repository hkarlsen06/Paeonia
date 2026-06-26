import Foundation

protocol PairingJoinInviteStoring: AnyObject {
    func loadInviteCode() -> String?
    func saveInviteCode(_ code: String)
    func clearInviteCode()
}

final class UserDefaultsPairingJoinInviteStore: PairingJoinInviteStoring {
    static let shared = UserDefaultsPairingJoinInviteStore()

    private let defaults: UserDefaults
    private let key = "paeonia.pairing.pendingJoinInviteCode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadInviteCode() -> String? {
        guard let code = defaults.string(forKey: key) else {
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
    }

    func clearInviteCode() {
        defaults.removeObject(forKey: key)
    }
}
