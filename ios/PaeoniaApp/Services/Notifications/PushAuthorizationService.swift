import UserNotifications

/// Requests and reports the system notification permission used for the
/// partner's widget drawing alerts. Silent refresh pushes never need this; only
/// the visible banner does.
nonisolated protocol PushAuthorizationProviding: Sendable {
    /// True only while iOS has not asked the user for a notification choice.
    /// The app uses this to avoid showing its primer after a choice has already
    /// been made in the system dialog or Settings.
    func isNotDetermined() async -> Bool

    /// Prompts for permission only the first time (status `.notDetermined`), so
    /// it is safe to call on every transition into the paired state.
    /// Returns true only after iOS has a settled authorization status.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool

    /// True once the user has actively turned notifications off in iOS Settings,
    /// so the settings screen can point them back there.
    func isDenied() async -> Bool
}

extension PushAuthorizationProviding {
    // swiftlint:disable async_without_await
    /// Conservative default for lightweight test doubles and feature clients
    /// that only need denial reporting. Production overrides this below.
    func isNotDetermined() async -> Bool {
        false
    }
    // swiftlint:enable async_without_await
}

struct PushAuthorizationService: PushAuthorizationProviding {
    func isNotDetermined() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return true
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await center.notificationSettings().authorizationStatus != .notDetermined
    }

    func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
