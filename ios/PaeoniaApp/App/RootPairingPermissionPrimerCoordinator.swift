import Foundation
import Observation

/// Decides when the permission primers show. The location primer is offered
/// when Home settles. The notification primer waits until the person has sent
/// their partner something, so the ask comes when it makes sense to them.
@MainActor
@Observable
final class RootPairingPermissionPrimerCoordinator {
    enum Primer: String, Identifiable {
        case location
        case notifications

        var id: String { rawValue }
    }

    private let pushPrimerStore: any PushPermissionPrimerPersisting
    private let locationPrimerStore: any LocationSharingPrimerPersisting
    private var pushPrimedIdentities: Set<LocationIdentity> = []
    private var locationPrimedIdentities: Set<LocationIdentity> = []
    private var evaluationGeneration = 0

    private(set) var presentedPrimer: Primer?
    private(set) var presentedIdentity: LocationIdentity?

    init(
        pushPrimerStore: any PushPermissionPrimerPersisting,
        locationPrimerStore: any LocationSharingPrimerPersisting
    ) {
        self.pushPrimerStore = pushPrimerStore
        self.locationPrimerStore = locationPrimerStore
    }

    /// The location primer needs the saved sharing preference, so it waits
    /// until that is known.
    func presentLocationPrimerIfNeeded(
        identity: LocationIdentity,
        sharingStateIsKnown: Bool,
        sharingEnabled: Bool,
        locationAuthorizationState: ForegroundLocationAuthorizationState
    ) {
        if let presentedIdentity, presentedIdentity != identity {
            dismiss()
        }

        guard let ownerUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              presentedPrimer == nil,
              sharingStateIsKnown,
              !locationPrimedIdentities.contains(identity)
        else {
            return
        }

        if shouldPresentLocationPrimer(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            sharingEnabled: sharingEnabled,
            authorizationState: locationAuthorizationState
        ) {
            locationPrimedIdentities.insert(identity)
            presentedIdentity = identity
            presentedPrimer = .location
        }
    }

    /// Offered after the person answers a question or sends a drawing, while
    /// iOS has not asked about notifications yet.
    func presentNotificationPrimerIfNeeded(
        identity: LocationIdentity,
        pushAuthorization: any PushAuthorizationProviding
    ) async {
        if let presentedIdentity, presentedIdentity != identity {
            dismiss()
        }

        guard identity.currentUserID != nil,
              identity.coupleID != nil,
              presentedPrimer == nil,
              !pushPrimerStore.hasResponded(),
              !pushPrimedIdentities.contains(identity)
        else {
            return
        }

        evaluationGeneration &+= 1
        let activeEvaluationGeneration = evaluationGeneration
        let isNotDetermined = await pushAuthorization.isNotDetermined()

        guard !Task.isCancelled,
              activeEvaluationGeneration == evaluationGeneration,
              presentedPrimer == nil,
              !pushPrimerStore.hasResponded(),
              !pushPrimedIdentities.contains(identity)
        else {
            return
        }

        if isNotDetermined {
            pushPrimedIdentities.insert(identity)
            presentedIdentity = identity
            presentedPrimer = .notifications
        } else {
            // A prior system choice makes the primer irrelevant on every paired
            // transition on this installation.
            pushPrimerStore.markResponded()
        }
    }

    private func shouldPresentLocationPrimer(
        ownerUserID: UUID,
        coupleID: UUID,
        sharingEnabled: Bool,
        authorizationState: ForegroundLocationAuthorizationState
    ) -> Bool {
        if authorizationState == .denied {
            // iOS will not show its prompt again, so an automatic primer with a
            // Share action cannot succeed. Settings remains the recovery path.
            locationPrimerStore.markResponded(
                ownerUserID: ownerUserID,
                coupleID: coupleID
            )
            return false
        }

        if sharingEnabled, authorizationState != .notDetermined {
            locationPrimerStore.markResponded(
                ownerUserID: ownerUserID,
                coupleID: coupleID
            )
            return false
        }

        return !locationPrimerStore.hasResponded(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        )
    }

    func markLocationResponded(identity: LocationIdentity) {
        guard let ownerUserID = identity.currentUserID,
              let coupleID = identity.coupleID
        else {
            return
        }

        locationPrimerStore.markResponded(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        )
    }

    func markPushResponded() {
        pushPrimerStore.markResponded()
    }

    func dismiss() {
        evaluationGeneration &+= 1
        presentedPrimer = nil
        presentedIdentity = nil
    }
}
