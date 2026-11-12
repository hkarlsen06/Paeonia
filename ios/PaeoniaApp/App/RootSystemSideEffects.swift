import Foundation

protocol RootSystemSideEffecting {
    func resetPushRegistrationState()
    /// Stops the partner's game Live Activities on this phone (`LiveActivityTokenService.endSession`).
    func endLiveActivitySession()
    /// The relationship the partner's game Live Activities show is gone from this phone.
    func endGameLiveActivities() async
    func reconcileDeliveredNotifications() async
    /// Removes the app icon number. Nothing waits for someone who is signed
    /// out or has no relationship, and the live feed that sets the number only
    /// runs inside one.
    func clearAppBadge()
}

struct LiveRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {
        PushRegistrationFingerprintStore.resetAll()
    }

    func endLiveActivitySession() {
        LiveActivityTokenService.shared.endSession()
    }

    func endGameLiveActivities() async {
        await GameLiveActivityController.endAll()
    }

    func reconcileDeliveredNotifications() async {
        await DeliveredNotifications.reconcile()
    }

    func clearAppBadge() {
        Task { await AppBadgeLiveFeed.clear() }
    }
}

struct NoOpRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {}
    func endLiveActivitySession() {}
    func endGameLiveActivities() {}
    func reconcileDeliveredNotifications() {}
    func clearAppBadge() {}
}
