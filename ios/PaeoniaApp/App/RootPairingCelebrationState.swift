import Foundation

/// Decides when the one-time pairing celebration covers the paired screen.
/// `RootViewModel` owns one and feeds it every committed access resolution.
@MainActor
struct RootPairingCelebrationState {
    private let store: any PairingCelebrationStoring

    /// The celebration covers the paired screen until the user dismisses it.
    private(set) var isPresented = false
    /// The presented celebration should still play its intro. Cleared once the
    /// celebration claims it, so a recreated view cannot replay it.
    private(set) var playsIntro = false
    /// The user dismissed the celebration before the pair id was known. The
    /// next paired resolution records it as seen instead of showing it again.
    private var marksSeenWhenPairIDArrives = false

    init(store: any PairingCelebrationStoring) {
        self.store = store
    }

    /// The user just accepted an invite. Show the celebration with its intro
    /// right away, before the paired access snapshot arrives.
    mutating func presentAcceptedInvite() {
        playsIntro = true
        isPresented = true
        marksSeenWhenPairIDArrives = false
    }

    mutating func consumeIntro() {
        playsIntro = false
    }

    mutating func dismiss(currentResolution: AccessRouteResolution?) {
        playsIntro = false
        isPresented = false
        if let currentResolution, markSeen(currentResolution) {
            marksSeenWhenPairIDArrives = false
        } else {
            marksSeenWhenPairIDArrives = true
        }
    }

    mutating func clear() {
        playsIntro = false
        isPresented = false
        marksSeenWhenPairIDArrives = false
    }

    /// Applies a committed access resolution. An unseen pair always shows the
    /// celebration with its intro, whether the couple just linked or the app
    /// opened into a pair this phone has not celebrated yet.
    mutating func update(for resolution: AccessRouteResolution) {
        guard resolution.route == .paired else {
            clear()
            return
        }

        if marksSeenWhenPairIDArrives {
            if markSeen(resolution) {
                marksSeenWhenPairIDArrives = false
            }
            playsIntro = false
            isPresented = false
            return
        }

        if isPresented {
            return
        }

        let hasSeen = resolution.pairingCelebrationPairID
            .map(store.hasSeenCelebration(forPairID:)) ?? false
        playsIntro = !hasSeen
        isPresented = !hasSeen
    }

    private func markSeen(_ resolution: AccessRouteResolution) -> Bool {
        guard let pairID = resolution.pairingCelebrationPairID else {
            return false
        }

        store.markCelebrationSeen(forPairID: pairID)
        return true
    }
}
