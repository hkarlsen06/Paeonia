import Foundation

/// Remembers whose data is on this phone. A session can end without an
/// explicit sign-out (it expires, or is ended on another device). The data
/// stays so that person loses nothing, but if someone else signs in next,
/// the root clears it first, the same way a sign-out would.
@MainActor
protocol RootDeviceOwnerStoring: AnyObject {
    var ownerUserID: String? { get set }
}

@MainActor
final class UserDefaultsRootDeviceOwnerStore: RootDeviceOwnerStoring {
    private let defaults: UserDefaults
    private let widgetIdentityStore: WidgetSyncIdentityStore
    private let key = "paeonia.root.deviceOwnerUserID"

    init(defaults: UserDefaults = .standard, widgetIdentityStore: WidgetSyncIdentityStore = .shared) {
        self.defaults = defaults
        self.widgetIdentityStore = widgetIdentityStore
    }

    /// Installs from before this marker existed have none. The widget's saved
    /// identity names the last paired person whose drawing and partner details
    /// are on the phone, so a different person signing in first still clears
    /// them. A purge clears that identity, so a signed-out phone has no owner.
    var ownerUserID: String? {
        get { defaults.string(forKey: key) ?? widgetIdentityStore.load().currentUserID?.uuidString }
        set { defaults.set(newValue, forKey: key) }
    }
}

@MainActor
final class InMemoryRootDeviceOwnerStore: RootDeviceOwnerStoring {
    var ownerUserID: String?

    init(ownerUserID: String? = nil) {
        self.ownerUserID = ownerUserID
    }
}
