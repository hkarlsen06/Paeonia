import Foundation
import Observation

/// What the person just sent their partner. The asks after sharing use it.
enum PartnerShare: Equatable {
    case drawing
    /// `awaitsPartner` is true for a daily question the partner has not answered yet.
    case answer(awaitsPartner: Bool)
}

/// Decides when the permission primers show. The location primer is offered
/// when Home settles. The notification primer waits until the person has sent
/// their partner something, so the ask comes when it makes sense to them.
@MainActor
@Observable
final class RootPairingPermissionPrimerCoordinator {
    enum Primer: String, Identifiable {
        case location
        case notifications
        /// The one later ask after "Not now", shown while the partner's answer is still to come.
        case notificationsWhileWaiting

        var id: String { rawValue }
    }

    private struct PushPrimed: Hashable {
        let identity: LocationIdentity
        let primer: Primer
    }

    private let pushPrimerStore: any PushPermissionPrimerPersisting
    private let locationPrimerStore: any LocationSharingPrimerPersisting
    /// Each notification ask shows at most once per identity while the app runs.
    private var pushPrimed: Set<PushPrimed> = []
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
    /// iOS has not asked about notifications yet. After "Not now" one more ask
    /// is left. It waits for a later day, when the person answers a daily
    /// question before their partner, so the partner's answer is what they would
    /// hear about. The day is the phone's calendar day.
    func presentNotificationPrimerIfNeeded(
        identity: LocationIdentity,
        share: PartnerShare,
        pushAuthorization: any PushAuthorizationProviding,
        now: Date = .now
    ) async {
        if let presentedIdentity, presentedIdentity != identity {
            dismiss()
        }

        guard identity.currentUserID != nil,
              identity.coupleID != nil,
              presentedPrimer == nil,
              let primer = duePushPrimer(share: share, now: now),
              !pushPrimed.contains(PushPrimed(identity: identity, primer: primer))
        else {
            return
        }

        evaluationGeneration &+= 1
        let activeEvaluationGeneration = evaluationGeneration
        let isNotDetermined = await pushAuthorization.isNotDetermined()

        guard !Task.isCancelled,
              activeEvaluationGeneration == evaluationGeneration,
              presentedPrimer == nil,
              duePushPrimer(share: share, now: now) == primer,
              !pushPrimed.contains(PushPrimed(identity: identity, primer: primer))
        else {
            return
        }

        if isNotDetermined {
            pushPrimed.insert(PushPrimed(identity: identity, primer: primer))
            presentedIdentity = identity
            presentedPrimer = primer
            // The second ask counts once it is on screen, so it can never show twice.
            if primer == .notificationsWhileWaiting {
                pushPrimerStore.markFinished()
            }
        } else {
            // A prior system choice makes both asks irrelevant on every paired
            // transition on this installation.
            pushPrimerStore.markFinished()
        }
    }

    private func duePushPrimer(share: PartnerShare, now: Date) -> Primer? {
        switch pushPrimerStore.progress() {
        case .notAsked:
            return .notifications
        case let .declinedFirstAsk(declinedAt):
            guard share == .answer(awaitsPartner: true),
                  !Calendar.current.isDate(declinedAt, inSameDayAs: now)
            else {
                return nil
            }
            return .notificationsWhileWaiting
        case .finished:
            return nil
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

    func markPushDeclined(at date: Date = .now) {
        pushPrimerStore.markDeclinedFirstAsk(at: date)
    }

    func markPushFinished() {
        pushPrimerStore.markFinished()
    }

    func dismiss() {
        evaluationGeneration &+= 1
        presentedPrimer = nil
        presentedIdentity = nil
    }
}
