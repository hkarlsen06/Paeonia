import Foundation

nonisolated enum AccessRoute: Equatable, Sendable {
    case limitedAuthenticated
    case unpaired
    case invitePending
    case paired
    case pairedPaywalled
    case relationshipEndedNotice

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
        }
    }

    var allowsInviteAcceptance: Bool {
        switch self {
        case .limitedAuthenticated, .unpaired, .invitePending:
            true
        case .paired, .pairedPaywalled, .relationshipEndedNotice:
            false
        }
    }
}

nonisolated struct AccessRouteSnapshot: Equatable, Sendable {
    let userEntitlement: SupabaseUserEntitlement?
    let coupleEntitlement: SupabaseCoupleEntitlement?
    let relationshipState: SupabaseRelationshipState?
    let hasPendingInvite: Bool

    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init(
        userEntitlement: SupabaseUserEntitlement?,
        coupleEntitlement: SupabaseCoupleEntitlement?,
        relationshipState: SupabaseRelationshipState?,
        hasPendingInvite: Bool
    ) {
        self.userEntitlement = userEntitlement
        self.coupleEntitlement = coupleEntitlement
        self.relationshipState = relationshipState
        self.hasPendingInvite = hasPendingInvite
    }
}

nonisolated struct AccessRouteResolution: Equatable, Sendable {
    let route: AccessRoute
    let snapshot: AccessRouteSnapshot

    nonisolated init(route: AccessRoute, snapshot: AccessRouteSnapshot) {
        self.route = route
        self.snapshot = snapshot
    }

    var partnerDisplayName: String? {
        snapshot.relationshipState?.partnerDisplayName?.trimmedNonEmpty
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

    var pairingCelebrationPairID: UUID? {
        snapshot.relationshipState?.pairID
    }
}

nonisolated struct AccessRouteResolver: Sendable {
    func route(for snapshot: AccessRouteSnapshot) -> AccessRoute {
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

/// Decides when a captured incoming invite should take precedence over the
/// ordinary post-auth destination. An entitled, unpaired user would normally be
/// sent to invite creation, but someone who already entered a partner's code must
/// instead finish that join flow first.
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

        switch state {
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
             .deletingAccount:
            false
        }
    }
}
