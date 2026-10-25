import Foundation

/// Read-only state derived from the route, for the views.
extension RootViewModel {
    var state: AppState {
        route.appState
    }

    var authRoute: AuthRoute {
        route.authRoute
    }

    var currentSession: AuthSession? {
        route.session
    }

    var currentPartnerName: PartnerName? {
        route.accessResolution?.partnerName
    }

    /// The partner's name as this person sees it. See `PartnerName`.
    var currentPartnerDisplayName: String? {
        currentPartnerName?.display
    }

    var currentPartnerUserID: UUID? {
        route.accessResolution?.partnerUserID
    }

    var currentActiveCoupleID: UUID? {
        route.accessResolution?.activeCoupleID
    }

    var currentRelationshipStartedOn: String? {
        route.accessResolution?.relationshipStartedOn
    }

    var currentOwnAccess: OwnAccess {
        route.accessResolution?.ownAccess ?? .nothing
    }

    var currentLapsedAccess: LapsedAccess {
        route.accessResolution?.lapsedAccess ?? .partnerCovered
    }

    var currentRelationshipAcceptedInvite: Bool {
        route.accessResolution?.acceptedInvite ?? false
    }

    var currentPairID: UUID? {
        route.accessResolution?.pairingCelebrationPairID
    }

    var currentProfilePhotoAssetID: UUID? {
        currentSession?.profilePhotoAssetID
    }

    var currentCustomProfilePhotoAssetID: UUID? {
        currentSession?.customProfilePhotoAssetID
    }

    var currentProviderProfilePhotoAssetID: UUID? {
        currentSession?.providerProfilePhotoAssetID
    }

    var currentPartnerProfilePhotoAssetID: UUID? {
        route.accessResolution?.partnerProfilePhotoAssetID
    }

    /// Read on each render, so the ending notice appears on its day without a server change.
    var currentAccessNotice: AccessNotice? {
        guard let snapshot = route.accessResolution?.snapshot else { return nil }
        return AccessNotice(user: snapshot.userEntitlement, couple: snapshot.coupleEntitlement, now: .now)
    }
}
