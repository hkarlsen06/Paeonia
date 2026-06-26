import UserNotifications

/// Requests and reports the system notification permission used for the
/// partner's widget drawing alerts. Silent refresh pushes never need this; only
/// the visible banner does.
nonisolated protocol PushAuthorizationProviding: Sendable {
    /// Prompts for permission only the first time (status `.notDetermined`), so
    /// it is safe to call on every transition into the paired state.
    func requestAuthorizationIfNeeded() async

    /// True once the user has actively turned notifications off in iOS Settings,
    /// so the settings screen can point them back there.
    func isDenied() async -> Bool
}

struct PushAuthorizationService: PushAuthorizationProviding {
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
