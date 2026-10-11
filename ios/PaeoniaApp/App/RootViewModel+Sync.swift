import Foundation

/// Sync startup and the sync passes the root runs for launch, foreground,
/// local changes, and pull-to-refresh.
extension RootViewModel {
    /// Waits for the paired read models needed immediately after launch or a
    /// sign-in transition. Location is local-first, but its server-backed
    /// preference may be the only surviving copy after a privacy purge or app
    /// reinstall, so the root reloads the cache only after this pass settles.
    func synchronizePairedPresentationData() async {
        await startSyncIfNeeded()

        guard state == .paired, hasStartedSync, currentSession != nil else {
            return
        }

        _ = await syncService.runOnce(reason: .startup)
    }

    func refreshAfterForegroundActivation() async {
        if await privacyLifecycle.retryPendingOnForeground(),
           let session = currentSession {
            privacyLifecycle.cancelRecovery()
            await resolveAccessRoute(for: session)
        }
        await runSync(reason: .foreground)
    }

    func syncAfterLocalLocationChange() async {
        await syncAfterLocalChange()
    }

    /// Flushes pending local changes (e.g. a queued media answer) to the backend now,
    /// starting sync first if it hasn't begun.
    func syncAfterLocalChange() async {
        await runSync(reason: .localChange)
    }

    /// Pull-to-refresh on Home. The widget sync is triggered alongside this from
    /// the view (see `RootView`).
    func refreshFromHomePull() async {
        await runSync(reason: .manualRefresh)
    }

    private func runSync(reason: SyncRequestReason) async {
        await startSyncIfNeeded()

        guard hasStartedSync, currentSession != nil else {
            return
        }

        _ = await syncService.runOnce(reason: reason)
    }

    func startSyncIfNeeded() async {
        // The purge pauses live feeds and resumes them before it returns here.
        // Starting them now would subscribe the old couple again before the
        // new route commits. The resolution that ran the purge starts sync
        // afterwards.
        guard !privacyLifecycle.hasPendingRetry, inFlightAccessPrivacyPurge == nil else {
            return
        }

        switch authRoute {
        case .signedOut, .onboarding:
            stopObservingAccessChanges()
            return
        case let .limitedAuthenticated(session):
            guard let userID = UUID(uuidString: session.id) else {
                return
            }
            observeAccessChanges(for: userID)
            await startSync(for: userID)
        }
    }

    /// Sign-out can finish while this suspends. It checks after every await so
    /// feeds never start, or restart, for a session that has ended.
    private func startSync(for userID: UUID) async {
        let epoch = sessionEpoch
        let syncSession = SyncSession(
            userID: userID,
            activeCoupleID: syncActiveCoupleID,
            relationshipCoupleID: currentActiveCoupleID
        )
        if configuredSyncSession != syncSession {
            await syncService.configure(session: syncSession)
            guard epoch == sessionEpoch else { return }
            configuredSyncSession = syncSession
        }
        // Idempotent. Also restarts feeds that a privacy purge stopped.
        await liveSync?.start(session: syncSession)
        guard epoch == sessionEpoch else {
            // The session ended while the feeds were starting. Stop them,
            // unless someone new is already signed in and owns them.
            if currentSession == nil {
                await liveSync?.stop()
            }
            return
        }

        if !hasStartedSync {
            await syncService.start()
            hasStartedSync = true
        }
    }

    private var syncActiveCoupleID: UUID? {
        guard route.accessResolution?.route == .paired else {
            return nil
        }

        return currentActiveCoupleID
    }
}
