import Foundation

/// Pausing location sharing for a while. A pause is a sharing choice with an end
/// time: sharing stays on, the phone sends nothing, the partner's map shows that
/// sharing is paused, and the server ends the pause when its time comes. It uses the
/// same queued operation as turning sharing on or off, so a pause made offline
/// still reaches the server, and the phone stops sending at once either way.
extension LocationMapViewModel {
    /// Pauses sharing until `end`. Does nothing when sharing is off.
    func pauseSharing(until end: Date) async {
        // The server keeps milliseconds. Whole seconds compare equal on both sides.
        let end = Date(timeIntervalSince1970: end.timeIntervalSince1970.rounded(.down))
        guard end > Date() else { return }
        await changePause(to: end)
    }

    /// Ends a pause now and shares the current location.
    func resumeSharing() async {
        guard await changePause(to: nil) else { return }
        await refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
    }

    /// Follows the pause on screen and sends a position when its time passes while
    /// the app is open. A closed app is woken by the server's silent push instead.
    func trackPause(until end: Date?) {
        guard end != pausedUntil else { return }
        pausedUntil = end
        pauseExpiryTask?.cancel()
        pauseExpiryTask = nil
        guard let end else { return }
        pauseExpiryTask = Task { [weak self] in
            let wait = end.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else { return }
            await self?.pauseDidEnd(at: end)
        }
    }

    private func pauseDidEnd(at end: Date) async {
        guard pausedUntil == end else { return }
        pausedUntil = nil
        pauseExpiryTask = nil
        await reload()
        // Quiet like an automatic refresh on app open: no banner if the phone is indoors.
        await refreshOwnLocationIfSharingEnabled(source: .foregroundOpen, mayPromptForAuthorization: false)
    }

    /// Returns whether the change was saved.
    @discardableResult
    private func changePause(to end: Date?) async -> Bool {
        guard sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginOperation(.sharingChange)
        else {
            return false
        }

        let operationIdentity = identity
        defer { finishOperation(operationID) }
        let previousPause = pausedUntil

        do {
            try await savePause(
                end,
                ownerUserID: currentUserID,
                coupleID: coupleID,
                ensureCurrent: { [self] in try requireCurrent(operationID, identity: operationIdentity) }
            )
            await syncAfterLocalChange()
            try requireCurrent(operationID, identity: operationIdentity)
            await reload()
            return true
        } catch LocationOperationAbort.superseded {
            return false
        } catch {
            guard identity == operationIdentity else { return false }
            // Nothing was queued for this value, so it is not waiting on the server.
            try? await visibilityStore.setViewerSharing(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                choice: ViewerSharingChoice(isEnabled: true, pausedUntil: previousPause),
                updatedAt: Date(),
                isPendingConfirmation: false
            )
            trackPause(until: previousPause)
            show(notice(for: error))
            await reload()
            return false
        }
    }

    private func savePause(
        _ end: Date?,
        ownerUserID: UUID,
        coupleID: UUID,
        ensureCurrent: () throws -> Void
    ) async throws {
        try ensureCurrent()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: end,
            updatedAt: Date()
        )
        trackPause(until: end)
        try ensureCurrent()

        try await enqueueLocationPreference(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: end,
            source: .settingsToggle
        )
        try ensureCurrent()

        if end != nil {
            // The server removes the stored location when a pause starts. Drop ours too,
            // and any position still waiting in the queue, so none is sent after the pause begins.
            try? await ownLocationStore.delete(ownerUserID: ownerUserID, coupleID: coupleID)
            await dropQueuedLocationUploads(
                ownerUserID: ownerUserID,
                keeping: nil,
                reason: "cancelled because location sharing was paused"
            )
        }
        try ensureCurrent()
    }
}
