import Foundation

/// How far this installation has come with Paeonia's notification asks.
nonisolated enum PushPermissionPrimerProgress: Equatable {
    /// The first ask has not been answered.
    case notAsked
    /// The person tapped "Not now" on the first ask at this time. One second ask is left.
    case declinedFirstAsk(at: Date)
    /// Nothing more to ask. iOS has the person's choice, or the second ask has shown.
    case finished
}

/// Persists how far this installation has come with Paeonia's calm notification
/// asks. Notification authorization is device-wide, so this is intentionally
/// installation-scoped rather than tied to one account.
nonisolated protocol PushPermissionPrimerPersisting {
    func progress() -> PushPermissionPrimerProgress
    func markDeclinedFirstAsk(at date: Date)
    func markFinished()
}

nonisolated struct UserDefaultsPushPermissionPrimerStore: PushPermissionPrimerPersisting {
    private static let finishedKey = "paeonia.notifications.permissionPrimer.finished"
    private static let declinedAtKey = "paeonia.notifications.permissionPrimer.declinedAt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func progress() -> PushPermissionPrimerProgress {
        if defaults.bool(forKey: Self.finishedKey) {
            return .finished
        }
        if let declinedAt = defaults.object(forKey: Self.declinedAtKey) as? Date {
            return .declinedFirstAsk(at: declinedAt)
        }
        return .notAsked
    }

    func markDeclinedFirstAsk(at date: Date) {
        defaults.set(date, forKey: Self.declinedAtKey)
    }

    func markFinished() {
        defaults.set(true, forKey: Self.finishedKey)
    }
}
