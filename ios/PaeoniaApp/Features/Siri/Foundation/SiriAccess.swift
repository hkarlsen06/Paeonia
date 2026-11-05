import Foundation

/// The couple Siri may act for: who is signed in on this phone and who their partner is.
nonisolated struct SiriCouple: Equatable, Sendable {
    let ownerUserID: UUID
    let coupleID: UUID
    let partnerUserID: UUID?
    /// What this person calls their partner (`PartnerName.displayOrFallback`).
    let partnerName: String

    var dateNames: CoupleDateNames {
        CoupleDateNames(currentUserID: ownerUserID, partnerUserID: partnerUserID, partnerName: partnerName)
    }
}

/// Whether Siri, Shortcuts and Spotlight may read or change the couple's content, decided
/// from what this phone saved: the signed-in session, whose data is on the phone, and the
/// cached access snapshot. Paeonia has no free tier, so every intent, query and index pass
/// asks this first and does nothing for anything but `.allowed`.
nonisolated enum SiriAccess: Equatable, Sendable {
    case signedOut
    /// Signed in, but not in an active relationship yet (or still setting up).
    case notPaired
    /// Paired, but the couple has no subscription or grant.
    case noAccess
    case allowed(SiriCouple)

    var couple: SiriCouple? {
        if case let .allowed(couple) = self { couple } else { nil }
    }

    /// Entity queries cannot open the app to unlock it, so they return no private content while locked.
    func coupleForEntityQuery(appIsLocked: Bool) -> SiriCouple? {
        appIsLocked ? nil : couple
    }

    /// The plain sentence Siri says when it can't act. Nil when it can.
    var refusal: LocalizedStringResource? {
        switch self {
        case .signedOut: .siriAccessSignedOut
        case .notPaired: .siriAccessNotPaired
        case .noAccess: .siriAccessNoAccess
        case .allowed: nil
        }
    }

    /// `resolution` is the cached snapshot resolved the way Root resolves it. A session for
    /// someone other than the phone's data owner counts as signed out, because Root clears
    /// that data before it shows anything.
    static func decide(
        session: AuthSession?,
        deviceOwnerUserID: String?,
        resolution: AccessRouteResolution?
    ) -> SiriAccess {
        guard let session,
              let deviceOwnerUserID,
              AuthUserIdentity.matches(deviceOwnerUserID, session.id),
              let ownerUserID = UUID(uuidString: session.id)
        else {
            return .signedOut
        }
        guard session.profileStatus == .complete, let resolution else {
            return .notPaired
        }
        switch resolution.route {
        case .paired:
            guard let coupleID = resolution.activeCoupleID else { return .notPaired }
            return .allowed(
                SiriCouple(
                    ownerUserID: ownerUserID,
                    coupleID: coupleID,
                    partnerUserID: resolution.partnerUserID,
                    partnerName: resolution.partnerName?.displayOrFallback
                        ?? String(localized: .pairingCelebrationPartnerName)
                )
            )
        case .pairedPaywalled, .accountClosed:
            return .noAccess
        case .limitedAuthenticated, .unpaired, .invitePending, .relationshipEndedNotice:
            return .notPaired
        }
    }
}
