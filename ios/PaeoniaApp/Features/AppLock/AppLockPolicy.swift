import Foundation

/// How long Paeonia may be out of sight before it asks to be unlocked again.
nonisolated enum AppLockTimeout: String, CaseIterable, Sendable {
    case immediately
    case afterOneMinute
    case afterFifteenMinutes

    static let `default`: AppLockTimeout = .afterOneMinute

    /// The time away that still counts as "just stepped out".
    var grace: Duration {
        switch self {
        case .immediately: .zero
        case .afterOneMinute: .seconds(60)
        case .afterFifteenMinutes: .seconds(15 * 60)
        }
    }
}

/// The pure rules for when the lock closes.
nonisolated enum AppLockPolicy {
    /// Whether coming back after `elapsed` in the background locks the app. Only
    /// a real trip to the background counts. Control Center, a system sheet or
    /// the Face ID prompt only make the app inactive and never reach this.
    static func locksAfterBackground(timeout: AppLockTimeout, elapsed: Duration) -> Bool {
        elapsed >= timeout.grace
    }
}

/// What the phone unlocks with, for the labels. Passcode means the phone has no
/// Face ID or Touch ID, or none is set up.
nonisolated enum AppLockBiometry: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    case passcode
}

/// What this phone can do for the lock right now.
nonisolated struct AppLockCapability: Equatable, Sendable {
    var biometry: AppLockBiometry
    /// False when the phone has no passcode. Without one there is nothing to
    /// unlock with, so the lock cannot be offered.
    var canAuthenticate: Bool
}

nonisolated enum AppLockAuthResult: Equatable, Sendable {
    case success
    /// The person dismissed the prompt, or the system did because the app left
    /// the screen. Nothing to report.
    case cancelled
    /// The phone cannot ask any more, for example because the passcode was removed.
    case unavailable
    case failed
}
