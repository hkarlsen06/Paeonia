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

    var currentPartnerDisplayName: String? {
        route.accessResolution?.partnerDisplayName
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
}
