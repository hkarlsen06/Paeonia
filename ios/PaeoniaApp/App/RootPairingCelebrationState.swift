import Foundation

/// Decides when the one-time pairing celebration, and the first day sequence
/// that follows it, cover the paired screen. `RootViewModel` owns one and feeds
/// it every committed access resolution. After a restore brings a couple back,
/// the same celebration plays once more as a reunion, without the first day.
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
    /// The presented celebration is for a couple that came back through a restore.
    /// Dismissing it leads to Home, not to the first day sequence.
    private(set) var isReunion = false
    /// The user dismissed the celebration before the couple id was known. The
    /// next paired resolution records it as seen instead of showing it again.
    private var marksSeenWhenCoupleIDArrives = false

    init(store: any PairingCelebrationStoring) {
        self.store = store
    }

    /// The user just accepted an invite. Show the celebration with its intro
    /// right away, before the paired access snapshot arrives.
    mutating func presentAcceptedInvite() {
        playsIntro = true
        isPresented = true
        isFirstDayPresented = false
        isReunion = false
        marksSeenWhenCoupleIDArrives = false
    }

    mutating func consumeIntro() {
        playsIntro = false
    }

    /// Ends the celebration and starts the first day sequence. A reunion ends on Home.
    mutating func dismiss(currentResolution: AccessRouteResolution?) {
        if isReunion {
            if let reunion = currentResolution?.dueReunionCelebration {
                store.markReunionCelebrationSeen(reunion)
            }
            clear()
            return
        }
        playsIntro = false
        isPresented = false
        isFirstDayPresented = true
        if let currentResolution, markSeen(currentResolution) {
            marksSeenWhenCoupleIDArrives = false
        } else {
            marksSeenWhenCoupleIDArrives = true
        }
    }

    /// Ends the first day sequence for good.
    mutating func finishFirstDay(currentResolution: AccessRouteResolution?) {
        isFirstDayPresented = false
        guard let coupleID = currentResolution?.activeCoupleID,
              var progress = store.postPairingProgress(forCoupleID: coupleID)
        else {
            return
        }
        progress.isFinished = true
        store.savePostPairingProgress(progress, forCoupleID: coupleID)
    }

    mutating func clear() {
        playsIntro = false
        isPresented = false
        isFirstDayPresented = false
        isReunion = false
        marksSeenWhenCoupleIDArrives = false
    }

    /// Applies a committed access resolution. A person the server says finished
    /// the first day sequence in this couple sees neither, so signing back in or a
    /// new phone lands on Home. Otherwise a couple this phone has not celebrated shows
    /// the celebration with its intro, whether it just linked or the app opened into
    /// it, and a couple whose first day sequence was cut short shows the sequence
    /// again. The phone keys all of it by couple, so two people who end a relationship
    /// and start fresh together get a new celebration and a new first day.
    ///
    /// A couple that came back through a restore shows the celebration with its
    /// intro until this person dismisses it on any phone. The server keeps it due
    /// until then, so signing out or a new phone never shows it twice.
    mutating func update(for resolution: AccessRouteResolution) {
        guard resolution.route == .paired else {
            clear()
            return
        }

        if updateReunion(for: resolution) {
            return
        }

        guard !resolution.hasFinishedFirstDay else {
            clear()
            return
        }

        if marksSeenWhenCoupleIDArrives {
            if markSeen(resolution) {
                marksSeenWhenCoupleIDArrives = false
            }
            playsIntro = false
            isPresented = false
            return
        }

        if isPresented || isFirstDayPresented {
            return
        }

        let coupleID = resolution.activeCoupleID
        let hasSeen = coupleID.map(store.hasSeenCelebration(forCoupleID:)) ?? false
        playsIntro = !hasSeen
        isPresented = !hasSeen
        if let coupleID, hasSeen, let progress = store.postPairingProgress(forCoupleID: coupleID) {
            isFirstDayPresented = !progress.isFinished
        }
    }

    /// Shows the reunion celebration while it is due and this phone has not
    /// dismissed it, and ends it once it is no longer due. True while it shows.
    private mutating func updateReunion(for resolution: AccessRouteResolution) -> Bool {
        guard let reunion = resolution.dueReunionCelebration,
              !store.hasSeenReunionCelebration(reunion)
        else {
            if isReunion {
                clear()
            }
            return false
        }
        if !(isPresented && isReunion) {
            clear()
            playsIntro = true
            isPresented = true
            isReunion = true
        }
        return true
    }

    /// This phone finished the couple's first day sequence and the server has not
    /// recorded it yet, for example because the phone was offline when it ended.
    func needsFirstDayRecorded(for resolution: AccessRouteResolution) -> Bool {
        guard resolution.route == .paired,
              !resolution.hasFinishedFirstDay,
              let coupleID = resolution.activeCoupleID
        else {
            return false
        }
        return store.postPairingProgress(forCoupleID: coupleID)?.isFinished == true
    }

    /// This phone dismissed the reunion celebration and the server has not recorded
    /// it yet. The reunion to record, or nil.
    func reunionToRecord(for resolution: AccessRouteResolution) -> ReunionCelebration? {
        guard let reunion = resolution.dueReunionCelebration,
              store.hasSeenReunionCelebration(reunion)
        else {
            return nil
        }
        return reunion
    }

    /// Records the celebration as seen and starts the couple's first day progress.
    private func markSeen(_ resolution: AccessRouteResolution) -> Bool {
        guard let coupleID = resolution.activeCoupleID else {
            return false
        }

        store.markCelebrationSeen(forCoupleID: coupleID)
        startProgressIfNeeded(forCoupleID: coupleID)
        return true
    }

    private func startProgressIfNeeded(forCoupleID coupleID: UUID) {
        guard store.postPairingProgress(forCoupleID: coupleID) == nil else {
            return
        }
        store.savePostPairingProgress(PostPairingProgress(), forCoupleID: coupleID)
    }
}
