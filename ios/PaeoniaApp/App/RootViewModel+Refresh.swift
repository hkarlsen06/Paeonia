import Foundation

/// Access refreshes the screens ask for: after a purchase, a renewal, a
/// pairing change, or confirming that a relationship ended.
extension RootViewModel {
    func refreshAfterSubscriptionChange() async {
        await refreshAccessKeepingSession()
    }

    /// Checks access again after a purchase, a renewal, or a pairing change.
    /// It reuses the session already on screen instead of restoring it, so a
    /// failed check can never sign anyone out. Without a signed-in session it
    /// restores one the way a launch does.
    private func refreshAccessKeepingSession() async {
        if case let .limitedAuthenticated(session) = authRoute {
            await resolveAccessRoute(for: session)
        } else {
            await refreshAuthRoute()
        }
        await startSyncIfNeeded()
    }

    func refreshAfterPairingChange() async {
        await refreshAccessKeepingSession()
    }

    /// Confirms the user has read the relationship-ended notice. Marks the notice
    /// seen on the backend so it does not reappear after the next sync, then
    /// re-resolves access to land on the user's real next state (usually unpaired).
    /// On failure the notice stays put and a banner explains what happened.
    func acknowledgeRelationshipEnded() async {
        guard !isWorking,
              case let .access(session, resolution) = route,
              resolution.route == .relationshipEndedNotice,
              let coupleID = resolution.activeCoupleID
        else {
            return
        }

        isWorking = true
        notice = nil

        do {
            try await accessRouteService?.markRelationshipEndedNoticeSeen(coupleID: coupleID)
            await resolveAccessRoute(for: session)
            await startSyncIfNeeded()
        } catch {
            notice = .relationshipEndedAcknowledgeFailed(PaeoniaFailure(error))
        }

        isWorking = false
    }
}
