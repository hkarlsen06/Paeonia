import Foundation
import Observation

/// Sequences the automatic permission primers after pairing. Notifications are
/// always resolved first; location can be presented by a later evaluation only
/// after that sheet and any system prompt have gone away.
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
              presentedPrimer == nil
        else {
            return
        }

        evaluationGeneration &+= 1
        let activeEvaluationGeneration = evaluationGeneration

        let didPresentPushPrimer = await presentPushPrimerIfNeeded(
            identity: identity,
            evaluationGeneration: activeEvaluationGeneration,
            pushAuthorization: pushAuthorization
        )
        guard !didPresentPushPrimer,
              !Task.isCancelled,
              activeEvaluationGeneration == evaluationGeneration,
              presentedPrimer == nil,
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
    ) async -> Bool {
        guard !pushPrimerStore.hasResponded(),
              !pushPrimedIdentities.contains(identity)
        else {
            return false
        }

        let isNotDetermined = await pushAuthorization.isNotDetermined()

        guard !Task.isCancelled,
              activeEvaluationGeneration == evaluationGeneration,
              presentedPrimer == nil,
              !pushPrimerStore.hasResponded(),
              !pushPrimedIdentities.contains(identity)
        else {
            return false
        }

        if isNotDetermined {
            pushPrimedIdentities.insert(identity)
            presentedIdentity = identity
            presentedPrimer = .notifications
            return true
        } else {
            // A prior system choice makes the primer irrelevant on every paired
            // transition on this installation.
            pushPrimerStore.markResponded()
            return false
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
