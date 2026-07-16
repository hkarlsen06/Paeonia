import Foundation
import Observation

/// Chooses at most one automatic permission primer for a paired identity in an
/// app session. Location is evaluated first because it is relationship-scoped;
/// notification priming remains installation-scoped and can wait for a later
/// session rather than stacking two sheets after pairing.
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
    private var automaticallyPrimedIdentity: LocationIdentity?
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

    func presentIfNeeded(
        identity: LocationIdentity,
        sharingStateIsKnown: Bool,
        sharingEnabled: Bool,
        locationAuthorizationState: ForegroundLocationAuthorizationState,
        pushAuthorization: any PushAuthorizationProviding
    ) async {
        if let presentedIdentity, presentedIdentity != identity {
            dismiss()
        }

        guard let ownerUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              sharingStateIsKnown,
              automaticallyPrimedIdentity != identity,
              presentedPrimer == nil
        else {
            return
        }

        evaluationGeneration &+= 1
        let activeEvaluationGeneration = evaluationGeneration

        if shouldPresentLocationPrimer(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            sharingEnabled: sharingEnabled,
            authorizationState: locationAuthorizationState
        ) {
            automaticallyPrimedIdentity = identity
            presentedIdentity = identity
            presentedPrimer = .location
            return
        }

        await presentPushPrimerIfNeeded(
            identity: identity,
            evaluationGeneration: activeEvaluationGeneration,
            pushAuthorization: pushAuthorization
        )
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

    private func presentPushPrimerIfNeeded(
        identity: LocationIdentity,
        evaluationGeneration activeEvaluationGeneration: Int,
        pushAuthorization: any PushAuthorizationProviding
    ) async {
        guard !pushPrimerStore.hasResponded() else {
            return
        }

        let isNotDetermined = await pushAuthorization.isNotDetermined()

        guard !Task.isCancelled,
              activeEvaluationGeneration == evaluationGeneration,
              automaticallyPrimedIdentity != identity,
              presentedPrimer == nil,
              !pushPrimerStore.hasResponded()
        else {
            return
        }

        if isNotDetermined {
            automaticallyPrimedIdentity = identity
            presentedIdentity = identity
            presentedPrimer = .notifications
        } else {
            // A prior system choice makes the primer irrelevant on every paired
            // transition on this installation.
            pushPrimerStore.markResponded()
        }
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
