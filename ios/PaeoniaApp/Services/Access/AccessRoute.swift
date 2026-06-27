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

        if snapshot.hasPendingInvite {
            return .invitePending
        }

        if snapshot.userEntitlement?.isEntitled == true {
            return .unpaired
        }

        return .limitedAuthenticated
    }
}
