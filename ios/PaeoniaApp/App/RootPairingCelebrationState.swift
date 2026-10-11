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

    /// Applies a committed access resolution. `shouldCelebrate` is true for a
    /// fresh link, which plays the intro; an ordinary launch into an unseen pair
    /// shows the settled celebration without it.
    mutating func update(for resolution: AccessRouteResolution, shouldCelebrate: Bool) {
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
        playsIntro = shouldCelebrate && !hasSeen
        isPresented = !hasSeen
    }

    private func markSeen(_ resolution: AccessRouteResolution) -> Bool {
        guard let pairID = resolution.pairingCelebrationPairID else {
            return false
        }

        store.markCelebrationSeen(forPairID: pairID)
        return true
    }

    /// A fresh link is a move into `.paired` from a state where the couple was
    /// not linked yet. An ordinary app open that is already paired starts from
    /// no previous route and must not replay the intro.
    static func isFreshLink(from previous: AccessRoute?, to current: AccessRoute) -> Bool {
        guard current == .paired, let previous else {
            return false
        }

        switch previous {
        case .invitePending, .unpaired, .limitedAuthenticated, .pairedPaywalled:
            return true
        case .paired, .relationshipEndedNotice:
            return false
        }
    }
}
