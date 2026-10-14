import Foundation

/// Access resolution: choosing the signed-in route from the server, the live
/// access feed, or the snapshot saved on this phone, and running the privacy
/// purge that an ended or paywalled relationship requires before it shows.
extension RootViewModel {
    func resolveAccessRoute(for session: AuthSession) async {
        let generation = beginAccessResolution()
        let previous = route.accessResolution
        route = .resolvingAccess(session, previous: previous, holding: route.appState)
        let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil

        guard let accessRouteService else {
            let fallback = await fallbackAccessResolution(for: session, previous: previous)
            await finishAccessResolution(generation, resolution: fallback, for: session)
            return
        }

        // On a cold launch there is nothing on screen yet. If the server is slow,
        // show the state saved on this phone instead of holding the launch screen.
        let savedPreview = previous == nil
            ? scheduleSavedAccessPreview(for: session, generation: generation)
            : nil
        defer { savedPreview?.cancel() }

        let resolution: AccessRouteResolution
        do {
            resolution = try await accessRouteService.resolveAccess(hasPendingInvite: hasPendingInvite)
        } catch {
            resolution = await fallbackAccessResolution(for: session, previous: previous)
        }
        savedPreview?.cancel()
        await finishAccessResolution(generation, resolution: resolution, for: session)
    }

    /// After `savedAccessGracePeriod`, shows a saved paired snapshot as the
    /// visible state of a still-running resolution, so Home opens with what is
    /// on this phone. It does not commit the route, purge, or celebrate. The
    /// server result (or the live feed) settles all of that. Other saved states
    /// keep waiting, since their screens need the server anyway.
    private func scheduleSavedAccessPreview(
        for session: AuthSession,
        generation: Int
    ) -> Task<Void, Never> {
        let gracePeriod = savedAccessGracePeriod
        return Task { [weak self] in
            do {
                try await Task.sleep(for: gracePeriod)
            } catch {
                return
            }

            guard let self,
                  let saved = await self.syncedAccessResolution(
                    for: session,
                    hasPendingInvite: self.inviteStore.loadInvite(for: session.id) != nil
                  ),
                  saved.route == .paired,
                  !Task.isCancelled,
                  generation == self.accessResolutionGeneration,
                  case .resolvingAccess(let currentSession, .none, let holding) = self.route,
                  AuthUserIdentity.matches(currentSession.id, session.id)
            else {
                return
            }

            self.route = .resolvingAccess(currentSession, previous: saved, holding: holding)
        }
    }

    func observeAccessChanges(for userID: UUID) {
        guard accessObservation?.userID != userID else {
            return
        }

        accessObservation?.task.cancel()
        // Subscribe before the task starts so a write that lands in between is not missed.
        let changes = LocalStoreChanges.changes(in: .access)
        let task = Task { [weak self] in
            for await change in changes where change.ownerUserID == userID {
                guard let self else {
                    return
                }
                await self.applyLiveAccessSnapshot()
            }
        }
        accessObservation = (userID, task)
    }

    func stopObservingAccessChanges() {
        accessObservation?.task.cancel()
        accessObservation = nil
    }

    /// Routes from the snapshot the live access feed just stored. Covers a partner
    /// accepting an invite, leaving or blocking, an entitlement change, and
    /// partner name, photo, or start date edits. An unchanged snapshot (a
    /// resubscribe, or the echo of an HTTP re-resolve) does nothing.
    private func applyLiveAccessSnapshot() async {
        guard let session = currentSession, route.isAccessSettled || route.isResolvingAccess else {
            return
        }

        let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil
        guard let resolution = await syncedAccessResolution(
            for: session,
            hasPendingInvite: hasPendingInvite
        ) else {
            return
        }

        // The store read suspended. Sign-out, account deletion, or a user change may have won.
        guard let currentSession,
              AuthUserIdentity.matches(currentSession.id, session.id),
              route.isAccessSettled || route.isResolvingAccess,
              !(route.isAccessSettled && route.accessResolution == resolution)
        else {
            return
        }

        // Claim the generation so an older HTTP resolve that is still in flight
        // cannot overwrite this newer snapshot.
        let generation = beginAccessResolution()
        await finishAccessResolution(generation, resolution: resolution, for: session)
        await startSyncIfNeeded()
    }

    private func syncedAccessResolution(
        for session: AuthSession,
        hasPendingInvite: Bool
    ) async -> AccessRouteResolution? {
        guard let userID = UUID(uuidString: session.id),
              let accessSnapshotStore
        else {
            return nil
        }

        guard let snapshot = try? await accessSnapshotStore.load(ownerUserID: userID) else {
            return nil
        }

        let routeSnapshot = AccessRouteSnapshot(
            userEntitlement: snapshot.userEntitlement,
            coupleEntitlement: snapshot.coupleEntitlement,
            relationshipState: snapshot.relationshipState,
            hasPendingInvite: hasPendingInvite
        )

        return AccessRouteResolution(
            route: AccessRouteResolver().route(for: routeSnapshot),
            snapshot: routeSnapshot
        )
    }

    private func fallbackAccessResolution(
        for session: AuthSession,
        previous: AccessRouteResolution?
    ) async -> AccessRouteResolution {
        let hasPendingInvite = inviteStore.loadInvite(for: session.id) != nil

        if let syncedResolution = await syncedAccessResolution(
            for: session,
            hasPendingInvite: hasPendingInvite
        ) {
            return syncedResolution
        }

        if let previous {
            return previous
        }

        return AccessRouteResolution(
            route: hasPendingInvite ? .invitePending : .limitedAuthenticated,
            snapshot: AccessRouteSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: nil,
                hasPendingInvite: hasPendingInvite
            )
        )
    }

    func beginAccessResolution() -> Int {
        accessResolutionGeneration += 1
        return accessResolutionGeneration
    }

    func invalidateAccessResolution() {
        accessResolutionGeneration += 1
    }

    /// Commits `resolution` if no newer resolution, sign-out, or user change won
    /// in the meantime. `previous` is whatever is on screen at commit time, which
    /// may be a saved preview shown while the server was slow.
    private func finishAccessResolution(
        _ generation: Int,
        resolution: AccessRouteResolution,
        for session: AuthSession
    ) async {
        // Every access commit waits for an older privacy purge, including a
        // newer `.paired` result. This prevents a stale ended/paywalled result
        // from continuing to clear caches after the new route becomes visible.
        if let pendingPurge = inFlightAccessPrivacyPurge {
            let purgeResult = await pendingPurge.task.value
            privacyLifecycle.record(purgeResult)
        }

        guard generation == accessResolutionGeneration else {
            return
        }

        let previous = route.accessResolution
        await purgePrivateRelationshipDataIfNeeded(
            for: resolution,
            ownerSession: session,
            previous: previous
        )

        // Privacy cleanup is asynchronous. A sign-out, user change, or newer
        // access resolution may have won while it ran, so never let the older
        // result restore a stale route afterwards.
        guard generation == accessResolutionGeneration else {
            return
        }

        if resolution.route == .paired {
            guard await privacyLifecycle.retryPending() else {
                schedulePrivacyPurgeRecovery(for: session)
                return
            }
        }

        applyAccessResolution(resolution, for: session)
    }

    func schedulePrivacyPurgeRecovery(for session: AuthSession) {
        privacyLifecycle.scheduleRecovery { [weak self] in
            guard let self,
                  let currentSession = self.currentSession,
                  AuthUserIdentity.matches(currentSession.id, session.id) else {
                return
            }
            await self.resolveAccessRoute(for: session)
            await self.startSyncIfNeeded()
        }
    }

    private func purgePrivateRelationshipDataIfNeeded(
        for resolution: AccessRouteResolution,
        ownerSession: AuthSession,
        previous: AccessRouteResolution?
    ) async {
        guard let ownerUserID = UUID(uuidString: ownerSession.id),
              let permanently = await purgePermanence(
                for: resolution,
                ownerUserID: ownerUserID,
                previous: previous
              )
        else {
            return
        }

        let purgeID = UUID()
        let purgeTask = Task {
            await syncService.purgeRelationshipAccess(
                ownerUserID: ownerUserID,
                permanently: permanently
            )
        }
        inFlightAccessPrivacyPurge = (purgeID, purgeTask)
        let purgeResult = await purgeTask.value
        privacyLifecycle.record(purgeResult)
        if inFlightAccessPrivacyPurge?.id == purgeID {
            inFlightAccessPrivacyPurge = nil
        }
    }

    /// Nil when `resolution` needs no purge. False hides relationship surfaces
    /// that can come back; true removes relationship content for good.
    private func purgePermanence(
        for resolution: AccessRouteResolution,
        ownerUserID: UUID,
        previous: AccessRouteResolution?
    ) async -> Bool? {
        switch resolution.route {
        case .pairedPaywalled:
            // Entitlement can return. Hide downloaded relationship surfaces,
            // but keep canonical local drafts, memories, and pending writes.
            return false
        case .relationshipEndedNotice:
            return true
        case .limitedAuthenticated, .unpaired, .invitePending:
            if let relationshipState = resolution.snapshot.relationshipState {
                return Self.isKnownEndedRelationship(relationshipState) ? true : nil
            }
            // After retention removes the ended relationship row, the current
            // snapshot is intentionally empty. The prior in-memory or persisted
            // snapshot is the only cold-launch proof that this is access loss
            // rather than a person who has never paired.
            return await hadPriorRelationship(ownerUserID: ownerUserID, previous: previous) ? true : nil
        case .paired:
            return nil
        }
    }

    private func hadPriorRelationship(
        ownerUserID: UUID,
        previous: AccessRouteResolution?
    ) async -> Bool {
        if previous?.snapshot.relationshipState != nil {
            return true
        }

        guard let accessSnapshotStore else {
            return false
        }

        do {
            return try await accessSnapshotStore
                .load(ownerUserID: ownerUserID)?
                .relationshipState != nil
        } catch {
            // An unavailable history store is not proof of relationship loss.
            // Keep local pending work rather than deleting it speculatively.
            return false
        }
    }

    private static func isKnownEndedRelationship(
        _ relationshipState: RemoteRelationshipState
    ) -> Bool {
        if relationshipState.endedAt != nil {
            return true
        }

        return switch (relationshipState.relationshipStatus, relationshipState.memberStatus) {
        case (.ended, _),
             (.deleted, _),
             (_, .left),
             (_, .endedNoticePending),
             (_, .endedNoticeSeen):
            true
        default:
            false
        }
    }
}
