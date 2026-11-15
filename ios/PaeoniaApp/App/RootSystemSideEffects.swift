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
    /// Hangs up a call on this phone and tells the server, while requests still carry the sign-in.
    func endCall() async
    /// Tells the server this person left the app, while requests still carry the sign-in, so the
    /// partner stops seeing them at once instead of 30 seconds later.
    func leaveAppPresence() async
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

    func endCall() async {
        await CallCenter.shared.endCallForLeaving()
    }

    /// Waits at most as long as hanging up does, so a stalled connection can't hold sign-out.
    func leaveAppPresence() async {
        let leave = Task { try? await LivePartnerPresenceGateway.make().setInApp(false) }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(4))
            leave.cancel()
        }
        await leave.value
        timeout.cancel()
    }
}

struct NoOpRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {}
    func endLiveActivitySession() {}
    func endGameLiveActivities() {}
    func reconcileDeliveredNotifications() {}
    func clearAppBadge() {}
    func endCall() {}
    func leaveAppPresence() {}
}
