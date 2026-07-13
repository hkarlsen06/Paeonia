import Foundation
import Observation

@MainActor
@Observable
final class LocationMapViewModel: PresentationReadinessProviding {
    enum Notice: Equatable {
        case saveFailed
        case permissionDenied
        case locationUnavailable
    }

    private enum Constants {
        static let consentVersion = "location-sharing-v1"
    }

    private enum LocationOperationAbort: Error {
        case identityChanged
    }

    private let visibilityStore: any LocationVisibilitySnapshotPersisting
    private let ownLocationStore: any OwnLocationSnapshotPersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let operationProvider: any SyncClientOperationProviding
    private let locationCapture: any ForegroundLocationCapturing
    private let encoder = JSONEncoder()
    private var localChangeSyncHandler: (@MainActor () async -> Void)?

    private var identity = LocationIdentity(currentUserID: nil, coupleID: nil)
    private var reloadGeneration = 0
    private var activeLocationOperationID: UUID?

    private(set) var mapState: CoupleMapState = .loading
    private(set) var isPresentationReady = false
    private(set) var sharingEnabled = false
    private(set) var isSharingLoaded = false
    private(set) var notice: Notice?

    init(
        visibilityStore: (any LocationVisibilitySnapshotPersisting)? = nil,
        ownLocationStore: (any OwnLocationSnapshotPersisting)? = nil,
        pendingOperationStore: (any PendingSyncOperationPersisting)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil,
        locationCapture: (any ForegroundLocationCapturing)? = nil
    ) {
        let defaultStores = Self.makeDefaultStores(
            needsVisibilityStore: visibilityStore == nil,
            needsOwnLocationStore: ownLocationStore == nil,
            needsPendingOperationStore: pendingOperationStore == nil
        )
        self.visibilityStore = visibilityStore ?? defaultStores?.visibilityStore ?? InMemoryLocationVisibilitySnapshotRepository()
        self.ownLocationStore = ownLocationStore ?? defaultStores?.ownLocationStore ?? InMemoryOwnLocationSnapshotRepository()
        self.pendingOperationStore = pendingOperationStore
            ?? defaultStores?.pendingOperationStore
            ?? InMemoryPendingSyncOperationRepository()
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
        self.locationCapture = locationCapture ?? ForegroundLocationCaptureService()
    }

    func configure(identity: LocationIdentity) async {
        guard self.identity != identity else {
            await reload()
            return
        }

        // The suspended request belongs to the previous account/couple. Its
        // identity checks prevent it from committing when it resumes, while the
        // token comparison in `defer` prevents it from clearing a newer request.
        activeLocationOperationID = nil
        self.identity = identity
        reloadGeneration &+= 1
        mapState = .loading
        isPresentationReady = false
        sharingEnabled = false
        isSharingLoaded = false
        notice = nil
        await reload()
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    func reload() async {
        reloadGeneration &+= 1
        let activeReloadGeneration = reloadGeneration
        let requestedIdentity = identity

        guard let currentUserID = requestedIdentity.currentUserID,
              let coupleID = requestedIdentity.coupleID
        else {
            mapState = .loading
            isPresentationReady = false
            sharingEnabled = false
            isSharingLoaded = false
            return
        }

        do {
            let visibility = try await visibilityStore.load(ownerUserID: currentUserID, coupleID: coupleID)
            let ownLocation = try await ownLocationStore.load(ownerUserID: currentUserID, coupleID: coupleID)
            guard identity == requestedIdentity,
                  reloadGeneration == activeReloadGeneration
            else {
                return
            }

            // Keep an in-flight opt-in/opt-out stable while a scene-activation
            // reload runs behind the system location sheet.
            if activeLocationOperationID == nil {
                sharingEnabled = visibility?.viewerSharingEnabled ?? false
            }
            isSharingLoaded = true
            mapState = Self.resolveMapState(visibility: visibility, ownLocation: ownLocation)
            isPresentationReady = true
        } catch {
            guard identity == requestedIdentity,
                  reloadGeneration == activeReloadGeneration
            else {
                return
            }

            mapState = .partnerUnknown(.unknown("local_load_failed"))
            isPresentationReady = true
            isSharingLoaded = true
        }
    }

    func setSharingEnabled(_ enabled: Bool) async {
        guard enabled != sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginLocationOperation()
        else {
            return
        }

        let operationIdentity = identity
        defer { finishLocationOperation(operationID) }

        let previousValue = sharingEnabled
        sharingEnabled = enabled
        isSharingLoaded = true

        do {
            try await persistSharingChange(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                enabled: enabled,
                operationIdentity: operationIdentity
            )

            await syncAfterLocalChange()
            try requireCurrentIdentity(operationIdentity)
            await reload()
        } catch LocationOperationAbort.identityChanged {
            return
        } catch {
            await restoreSharingChange(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                previousValue: previousValue,
                operationIdentity: operationIdentity,
                error: error
            )
        }
    }

    func promptForCurrentLocation() async {
        guard activeLocationOperationID == nil else { return }

        if sharingEnabled {
            await refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        } else {
            await setSharingEnabled(true)
        }
    }

    func refreshOwnLocationIfSharingEnabled(source: LocationSharingSource) async {
        guard sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID,
              let operationID = beginLocationOperation()
        else {
            return
        }

        let operationIdentity = identity
        defer { finishLocationOperation(operationID) }

        do {
            let location = try await locationCapture.captureCurrentLocation()
            try requireCurrentIdentity(operationIdentity)
            guard try await shouldSendLocation(
                location,
                source: source,
                ownerUserID: currentUserID,
                coupleID: coupleID,
                operationIdentity: operationIdentity
            ) else { return }

            try await saveAndEnqueueOwnLocation(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                location: location,
                source: source
            )
            try requireCurrentIdentity(operationIdentity)

            await syncAfterLocalChange()
            try requireCurrentIdentity(operationIdentity)
            await reload()
        } catch LocationOperationAbort.identityChanged {
            return
        } catch {
            guard identity == operationIdentity else { return }
            notice = notice(for: error)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    static func resolveMapState(
        visibility: LocationVisibilitySnapshot?,
        ownLocation: OwnLocationSnapshot?
    ) -> CoupleMapState {
        guard let visibility else {
            return .partnerUnknown(.unknown("missing_visibility"))
        }
        guard visibility.viewerSharingEnabled else {
            return .currentUnknown
        }
        guard let current = ownLocation?.location else {
            return .currentUnknown
        }
        guard visibility.visibilityState == .visible,
              let partner = visibility.partnerLocation
        else {
            return .partnerUnknown(visibility.visibilityState)
        }

        return .ready(
            current: current,
            partner: partner,
            partnerWasStaleAtLastRefresh: visibility.partnerLocationIsStale
        )
    }

    private func enqueueLocationPreference(
        ownerUserID: UUID,
        coupleID: UUID,
        isEnabled: Bool,
        source: LocationSharingSource
    ) async throws {
        let operation = operationProvider.makeOperation()
        let payload = LocationSharingPreferenceOperationPayload(
            coupleID: coupleID,
            isEnabled: isEnabled,
            consentVersion: isEnabled ? Constants.consentVersion : nil,
            source: source
        )
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .updateLocationSharingPreference,
                idempotencyScope: "location-preference:\(coupleID.uuidString.lowercased()):\(operation.id.uuidString.lowercased())",
                requestData: try encoder.encode(payload)
            )
        )
    }

    private func persistSharingChange(
        ownerUserID: UUID,
        coupleID: UUID,
        enabled: Bool,
        operationIdentity: LocationIdentity
    ) async throws {
        let capturedLocation = enabled ? try await locationCapture.captureCurrentLocation() : nil
        try requireCurrentIdentity(operationIdentity)

        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: enabled,
            updatedAt: Date()
        )
        try requireCurrentIdentity(operationIdentity)

        try await enqueueLocationPreference(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: enabled,
            source: .settingsToggle
        )
        try requireCurrentIdentity(operationIdentity)

        if let capturedLocation {
            try await saveAndEnqueueOwnLocation(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: capturedLocation,
                source: .settingsToggle
            )
        } else {
            try? await ownLocationStore.delete(ownerUserID: ownerUserID, coupleID: coupleID)
        }
        try requireCurrentIdentity(operationIdentity)
    }

    private func restoreSharingChange(
        ownerUserID: UUID,
        coupleID: UUID,
        previousValue: Bool,
        operationIdentity: LocationIdentity,
        error: any Error
    ) async {
        guard identity == operationIdentity else { return }
        sharingEnabled = previousValue
        try? await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: previousValue,
            updatedAt: Date()
        )
        guard identity == operationIdentity else { return }
        notice = notice(for: error)
        await reload()
    }

    private func shouldSendLocation(
        _ location: LocationPoint,
        source: LocationSharingSource,
        ownerUserID: UUID,
        coupleID: UUID,
        operationIdentity: LocationIdentity
    ) async throws -> Bool {
        // A routine foreground refresh only writes when the fix is stale or the
        // user moved; explicit refreshes always write.
        guard source == .foregroundOpen else { return true }

        let lastSent = (try? await ownLocationStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        ))?.location
        try requireCurrentIdentity(operationIdentity)
        return RoutineLocationThrottle.shouldSend(
            lastSent: lastSent,
            current: location,
            now: Date()
        )
    }

    private func beginLocationOperation() -> UUID? {
        guard activeLocationOperationID == nil else { return nil }
        let operationID = UUID()
        activeLocationOperationID = operationID
        return operationID
    }

    private func finishLocationOperation(_ operationID: UUID) {
        if activeLocationOperationID == operationID {
            activeLocationOperationID = nil
        }
    }

    private func requireCurrentIdentity(_ expectedIdentity: LocationIdentity) throws {
        guard identity == expectedIdentity else {
            throw LocationOperationAbort.identityChanged
        }
    }

    private func saveAndEnqueueOwnLocation(
        ownerUserID: UUID,
        coupleID: UUID,
        location: LocationPoint,
        source: LocationSharingSource
    ) async throws {
        let operation = operationProvider.makeOperation()
        try await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: location,
                source: source,
                pendingOperationID: operation.id,
                updatedAt: Date()
            )
        )

        let payload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: location,
            source: source
        )
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: .updateLatestPartnerLocation,
                idempotencyScope: "latest-location:\(coupleID.uuidString.lowercased()):\(operation.id.uuidString.lowercased())",
                requestData: try encoder.encode(payload)
            )
        )
    }

    private func syncAfterLocalChange() async {
        await localChangeSyncHandler?()
    }

    private func notice(for error: any Error) -> Notice {
        if let locationError = error as? ForegroundLocationCaptureError {
            switch locationError {
            case .authorizationDenied:
                return .permissionDenied
            case .unavailable, .alreadyRequesting:
                return .locationUnavailable
            }
        }

        return .saveFailed
    }

    private static func makeDefaultStores(
        needsVisibilityStore: Bool,
        needsOwnLocationStore: Bool,
        needsPendingOperationStore: Bool
    ) -> (
        visibilityStore: any LocationVisibilitySnapshotPersisting,
        ownLocationStore: any OwnLocationSnapshotPersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    )? {
        guard needsVisibilityStore || needsOwnLocationStore || needsPendingOperationStore else {
            return nil
        }

        guard let localStore = PaeoniaLocalStore.shared else {
            return nil
        }

        return (
            SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container),
            SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
            SwiftDataPendingSyncOperationRepository(container: localStore.container)
        )
    }
}
