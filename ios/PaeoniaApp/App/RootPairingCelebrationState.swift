import Foundation

/// Decides when the one-time pairing celebration, and the first day sequence
/// that follows it, cover the paired screen. `RootViewModel` owns one and feeds
/// it every committed access resolution.
@MainActor
struct RootPairingCelebrationState {
    private let store: any PairingCelebrationStoring

    /// The celebration covers the paired screen until the user dismisses it.
    private(set) var isPresented = false
    /// The presented celebration should still play its intro. Cleared once the
    /// celebration claims it, so a recreated view cannot replay it.
    private(set) var playsIntro = false
    /// The first day sequence covers the paired screen. It starts when the
    /// celebration is dismissed and ends when the sequence finishes. An app kill
    /// in between brings it back on the next launch.
    private(set) var isFirstDayPresented = false
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
        isFirstDayPresented = false
        marksSeenWhenPairIDArrives = false
    }

    mutating func consumeIntro() {
        playsIntro = false
    }

    /// Ends the celebration and starts the first day sequence.
    mutating func dismiss(currentResolution: AccessRouteResolution?) {
        playsIntro = false
        isPresented = false
        isFirstDayPresented = true
        if let currentResolution, markSeen(currentResolution) {
            marksSeenWhenPairIDArrives = false
        } else {
            marksSeenWhenPairIDArrives = true
        }
    }

    /// Ends the first day sequence for good.
    mutating func finishFirstDay(currentResolution: AccessRouteResolution?) {
        isFirstDayPresented = false
        guard let pairID = currentResolution?.pairingCelebrationPairID,
              var progress = store.postPairingProgress(forPairID: pairID)
        else {
            return
        }
        progress.isFinished = true
        store.savePostPairingProgress(progress, forPairID: pairID)
    }

    mutating func clear() {
        playsIntro = false
        isPresented = false
        isFirstDayPresented = false
        marksSeenWhenPairIDArrives = false
    }

    /// Applies a committed access resolution. An unseen pair always shows the
    /// celebration with its intro, whether the couple just linked or the app
    /// opened into a pair this phone has not celebrated yet. A pair whose first
    /// day sequence was cut short shows the sequence again.
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

        if isPresented || isFirstDayPresented {
            return
        }

        let pairID = resolution.pairingCelebrationPairID
        let hasSeen = pairID.map(store.hasSeenCelebration(forPairID:)) ?? false
        playsIntro = !hasSeen
        isPresented = !hasSeen
        if let pairID, hasSeen, let progress = store.postPairingProgress(forPairID: pairID) {
            isFirstDayPresented = !progress.isFinished
        }
    }

    /// Records the celebration as seen and starts the pair's first day progress.
    private func markSeen(_ resolution: AccessRouteResolution) -> Bool {
        guard let pairID = resolution.pairingCelebrationPairID else {
            return false
        }

        store.markCelebrationSeen(forPairID: pairID)
        startProgressIfNeeded(forPairID: pairID)
        return true
    }

    private func startProgressIfNeeded(forPairID pairID: UUID) {
        guard store.postPairingProgress(forPairID: pairID) == nil else {
            return
        }
        store.savePostPairingProgress(PostPairingProgress(), forPairID: pairID)
    }
}
