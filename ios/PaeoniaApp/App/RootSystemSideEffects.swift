import Foundation

@MainActor
protocol RootSystemSideEffecting {
    func resetPushRegistrationState()
    func reconcileDeliveredNotifications() async
    /// Removes the app icon number. Nothing waits for someone who is signed
    /// out or has no relationship, and the live feed that sets the number only
    /// runs inside one.
    func clearAppBadge()
}

@MainActor
struct LiveRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {
        PushRegistrationFingerprintStore.resetAll()
    }

    func reconcileDeliveredNotifications() async {
        await DeliveredNotifications.reconcile()
    }

    func clearAppBadge() {
        Task { await AppBadgeLiveFeed.clear() }
    }
}

@MainActor
struct NoOpRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {}
    func reconcileDeliveredNotifications() {}
    func clearAppBadge() {}
}
