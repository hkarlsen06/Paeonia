import Foundation

/// Persists whether this installation has already answered Paeonia's calm
/// notification primer. Notification authorization is device-wide, so this is
/// intentionally installation-scoped rather than tied to one account.
nonisolated protocol PushPermissionPrimerPersisting {
    func hasResponded() -> Bool
    func markResponded()
}

nonisolated struct UserDefaultsPushPermissionPrimerStore: PushPermissionPrimerPersisting {
    private static let responseKey = "paeonia.notifications.permissionPrimerResponded.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasResponded() -> Bool {
        defaults.bool(forKey: Self.responseKey)
    }

    func markResponded() {
        defaults.set(true, forKey: Self.responseKey)
    }
}
