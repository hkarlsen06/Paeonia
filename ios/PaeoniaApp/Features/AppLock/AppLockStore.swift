import Foundation

/// The lock setting. It belongs to this phone, not to an account.
nonisolated protocol AppLockPersisting {
    var isEnabled: Bool { get set }
    var timeout: AppLockTimeout { get set }
    func clear()
}

nonisolated struct UserDefaultsAppLockStore: AppLockPersisting {
    private static let enabledKey = "paeonia.appLock.enabled"
    private static let timeoutKey = "paeonia.appLock.timeout"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var timeout: AppLockTimeout {
        get {
            defaults.string(forKey: Self.timeoutKey).flatMap(AppLockTimeout.init(rawValue:)) ?? .default
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.timeoutKey) }
    }

    func clear() {
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.timeoutKey)
    }
}
