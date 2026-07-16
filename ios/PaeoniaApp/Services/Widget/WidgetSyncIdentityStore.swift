import Foundation

/// Persists the last-known sync identity so a silent-push-triggered sync (when
/// the app is in the background and no view is alive) can still label a synced
/// drawing with the right nickname.
nonisolated final class WidgetSyncIdentityStore: @unchecked Sendable {
    nonisolated static let shared = WidgetSyncIdentityStore()
    private static let appGroupIdentifier = "group.no.paeonia.app"

    private enum Key {
        static let userID = "paeonia.widgetSync.currentUserID"
        static let currentName = "paeonia.widgetSync.currentDisplayName"
        static let partnerName = "paeonia.widgetSync.partnerDisplayName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupIdentifier)
            ?? .standard
    }

    func save(_ identity: WidgetSyncIdentity) {
        defaults.set(identity.currentUserID?.uuidString, forKey: Key.userID)
        defaults.set(identity.currentDisplayName, forKey: Key.currentName)
        defaults.set(identity.partnerDisplayName, forKey: Key.partnerName)
    }

    func load() -> WidgetSyncIdentity {
        WidgetSyncIdentity(
            currentUserID: defaults.string(forKey: Key.userID).flatMap(UUID.init(uuidString:)),
            currentDisplayName: defaults.string(forKey: Key.currentName),
            partnerDisplayName: defaults.string(forKey: Key.partnerName)
        )
    }

    func clear() {
        defaults.removeObject(forKey: Key.userID)
        defaults.removeObject(forKey: Key.currentName)
        defaults.removeObject(forKey: Key.partnerName)
    }
}
