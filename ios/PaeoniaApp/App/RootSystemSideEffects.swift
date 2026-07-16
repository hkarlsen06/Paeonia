import Foundation

@MainActor
protocol RootSystemSideEffecting {
    func resetPushRegistrationState()
}

@MainActor
struct LiveRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {
        PushRegistrationFingerprintStore.resetAll()
    }
}

@MainActor
struct NoOpRootSystemSideEffects: RootSystemSideEffecting {
    func resetPushRegistrationState() {}
}
