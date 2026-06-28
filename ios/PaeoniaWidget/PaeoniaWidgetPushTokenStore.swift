import Foundation

nonisolated struct PaeoniaWidgetPushTokenSnapshot: Equatable, Sendable {
    let token: String
    let widgetKinds: [String]
    let savedAt: Date?
}

/// Stores WidgetKit's separate APNs token in the App Group so the signed-in app
/// can register it with Supabase on launch/foreground.
nonisolated final class PaeoniaWidgetPushTokenStore: @unchecked Sendable {
    nonisolated static let shared = PaeoniaWidgetPushTokenStore()

    private enum Key {
        static let token = "paeonia.widgetPush.token"
        static let widgetKinds = "paeonia.widgetPush.widgetKinds"
        static let savedAt = "paeonia.widgetPush.savedAt"
    }

    private static let appGroupIdentifier = "group.no.paeonia.app"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = Self.makeAppGroupDefaults()) {
        self.defaults = defaults ?? .standard
    }

    private static func makeAppGroupDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            return nil
        }

        return UserDefaults(suiteName: appGroupIdentifier)
    }

    func save(tokenData: Data, widgetKinds: [String], savedAt: Date = Date()) {
        save(token: tokenData.paeoniaHexString, widgetKinds: widgetKinds, savedAt: savedAt)
    }

    func save(token: String, widgetKinds: [String], savedAt: Date = Date()) {
        let uniqueKinds = Array(Set(widgetKinds)).sorted()
        defaults.set(token, forKey: Key.token)
        defaults.set(uniqueKinds, forKey: Key.widgetKinds)
        defaults.set(savedAt, forKey: Key.savedAt)
    }

    func load() -> PaeoniaWidgetPushTokenSnapshot? {
        guard let token = defaults.string(forKey: Key.token), !token.isEmpty else {
            return nil
        }

        return PaeoniaWidgetPushTokenSnapshot(
            token: token,
            widgetKinds: defaults.stringArray(forKey: Key.widgetKinds) ?? [],
            savedAt: defaults.object(forKey: Key.savedAt) as? Date
        )
    }

    func loadToken(forWidgetKind widgetKind: String) -> String? {
        guard let snapshot = load(), snapshot.widgetKinds.contains(widgetKind) else {
            return nil
        }

        return snapshot.token
    }

    func clear() {
        defaults.removeObject(forKey: Key.token)
        defaults.removeObject(forKey: Key.widgetKinds)
        defaults.removeObject(forKey: Key.savedAt)
    }
}

private extension Data {
    nonisolated var paeoniaHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
