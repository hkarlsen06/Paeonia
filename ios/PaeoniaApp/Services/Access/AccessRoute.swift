import Foundation

nonisolated enum AccessRoute: Equatable, Sendable {
    case limitedAuthenticated
    case unpaired
    case invitePending
    case paired
    case pairedPaywalled
    case relationshipEndedNotice
    /// Paeonia banned this account.
    case accountClosed

    var appState: AppState {
        switch self {
        case .limitedAuthenticated:
            .limitedAuthenticated
        case .unpaired:
            .unpaired
        case .invitePending:
            .invitePending
        case .paired:
            .paired
        case .pairedPaywalled:
            .pairedPaywalled
        case .relationshipEndedNotice:
            .relationshipEndedNotice
        case .accountClosed:
            .accountClosed
        }
    }

    var allowsInviteAcceptance: Bool {
        switch self {
        case .limitedAuthenticated, .unpaired, .invitePending:
            true
        case .paired, .pairedPaywalled, .relationshipEndedNotice, .accountClosed:
            false
        }
    }
}

nonisolated struct AccessRouteSnapshot: Equatable, Sendable {
    let userEntitlement: RemoteUserEntitlement?
    let coupleEntitlement: RemoteCoupleEntitlement?
    let relationshipState: RemoteRelationshipState?
    let hasPendingInvite: Bool
    let isBanned: Bool

    nonisolated init(
        userEntitlement: RemoteUserEntitlement?,
        coupleEntitlement: RemoteCoupleEntitlement?,
        relationshipState: RemoteRelationshipState?,
        hasPendingInvite: Bool,
        isBanned: Bool = false
    ) {
        self.userEntitlement = userEntitlement
        self.coupleEntitlement = coupleEntitlement
        self.relationshipState = relationshipState
        self.hasPendingInvite = hasPendingInvite
        self.isBanned = isBanned
    }
}

nonisolated struct AccessRouteResolution: Equatable, Sendable {
    let route: AccessRoute
    let snapshot: AccessRouteSnapshot

    nonisolated init(route: AccessRoute, snapshot: AccessRouteSnapshot) {
        self.route = route
        self.snapshot = snapshot
    }

    /// What this person calls their partner. Nil without a relationship.
    var partnerName: PartnerName? {
        snapshot.relationshipState?.partnerName
    }

    /// The partner's name as this person sees it: their nickname, otherwise the partner's own name.
    var partnerDisplayName: String? {
        partnerName?.display
    }

    var partnerUserID: UUID? {
        snapshot.relationshipState?.partnerUserID
    }

    var activeCoupleID: UUID? {
        snapshot.relationshipState?.coupleID
    }

    var partnerProfilePhotoAssetID: UUID? {
        snapshot.relationshipState?.partnerProfilePhotoAssetID
    }

    /// The day the relationship started (`couples.started_on`) as an `yyyy-MM-dd`
    /// string, used to count down to the couple's next milestone.
    var relationshipStartedOn: String? {
        snapshot.relationshipState?.startedOn
    }

    /// This person joined with the partner's invite code.
    var acceptedInvite: Bool {
        snapshot.relationshipState?.acceptedInvite ?? false
    }

    var pairingCelebrationPairID: UUID? {
        snapshot.relationshipState?.pairID
    }
}

nonisolated struct AccessRouteResolver: Sendable {
    func route(for snapshot: AccessRouteSnapshot) -> AccessRoute {
        if snapshot.isBanned {
            return .accountClosed
        }

        if let relationshipState = snapshot.relationshipState {
            if relationshipState.needsEndedNotice {
                return .relationshipEndedNotice
            }

            if relationshipState.isActiveRelationship {
                return snapshot.coupleEntitlement?.isEntitled == true
                    ? .paired
                    : .pairedPaywalled
            }
        }

        if snapshot.hasPendingInvite && snapshot.userEntitlement?.isEntitled == true {
            return .invitePending
        }

        if snapshot.userEntitlement?.isEntitled == true {
            return .unpaired
        }

        return .limitedAuthenticated
    }
}

/// Decides when a saved partner code takes precedence over the ordinary post-auth
/// destination. The root then shows the join screen instead of the paywall or the
/// invite screen, so someone with a partner's code finishes joining first.
nonisolated struct PendingJoinInviteFlowResolver: Sendable {
    func shouldPresentInviteAcceptance(
        for state: AppState,
        pendingInviteCode: String?
    ) -> Bool {
        guard let pendingInviteCode,
              (try? PairingInviteCode.normalized(pendingInviteCode)) != nil
        else {
            return false
        }

        return switch state {
        case .limitedAuthenticated, .unpaired, .invitePending:
            true
        case .launching,
             .unauthenticated,
             .onboarding,
             .paired,
             .pairedPaywalled,
             .entitlementLost,
             .entitlementRestored,
             .relationshipEndedNotice,
             .accountClosed,
             .deletingAccount:
            false
        }
    }
}
