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
        static let partnerLocationUnknownAfter: TimeInterval = 7 * 24 * 60 * 60
    }

    private let visibilityStore: any LocationVisibilitySnapshotPersisting
    private let ownLocationStore: any OwnLocationSnapshotPersisting
    private let pendingOperationStore: any PendingSyncOperationPersisting
    private let operationProvider: any SyncClientOperationProviding
    private let locationCapture: any ForegroundLocationCapturing
    private let encoder = JSONEncoder()
    private var localChangeSyncHandler: (@MainActor () async -> Void)?

    private var identity = LocationIdentity(currentUserID: nil, coupleID: nil)

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

        self.identity = identity
        mapState = .loading
        isPresentationReady = false
        sharingEnabled = false
        isSharingLoaded = false
        await reload()
    }

    func setLocalChangeSyncHandler(_ handler: (@MainActor () async -> Void)?) {
        localChangeSyncHandler = handler
    }

    func reload() async {
        guard let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID
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
            sharingEnabled = visibility?.viewerSharingEnabled ?? false
            isSharingLoaded = true
            mapState = Self.resolveMapState(visibility: visibility, ownLocation: ownLocation)
            isPresentationReady = true
        } catch {
            mapState = .partnerUnknown(.unknown("local_load_failed"))
            isPresentationReady = true
            isSharingLoaded = true
        }
    }

    func setSharingEnabled(_ enabled: Bool) async {
        guard enabled != sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID
        else {
            return
        }

        let previousValue = sharingEnabled
        sharingEnabled = enabled
        isSharingLoaded = true

        do {
            let capturedLocation = enabled ? try await locationCapture.captureCurrentLocation() : nil
            try await visibilityStore.setViewerSharingEnabled(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                isEnabled: enabled,
                updatedAt: Date()
            )
            try await enqueueLocationPreference(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                isEnabled: enabled,
                source: .settingsToggle
            )

            if let capturedLocation {
                try await saveAndEnqueueOwnLocation(
                    ownerUserID: currentUserID,
                    coupleID: coupleID,
                    location: capturedLocation,
                    source: .settingsToggle
                )
        } else {
            try? await ownLocationStore.delete(ownerUserID: currentUserID, coupleID: coupleID)
        }

            await syncAfterLocalChange()
            await reload()
        } catch {
            sharingEnabled = previousValue
            try? await visibilityStore.setViewerSharingEnabled(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                isEnabled: previousValue,
                updatedAt: Date()
            )
            notice = notice(for: error)
            await reload()
        }
    }

    func promptForCurrentLocation() async {
        if sharingEnabled {
            await refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        } else {
            await setSharingEnabled(true)
        }
    }

    func refreshOwnLocationIfSharingEnabled(source: LocationSharingSource) async {
        guard sharingEnabled,
              let currentUserID = identity.currentUserID,
              let coupleID = identity.coupleID
        else {
            return
        }

        do {
            try await captureAndEnqueueOwnLocation(
                ownerUserID: currentUserID,
                coupleID: coupleID,
                source: source
            )
            await syncAfterLocalChange()
            await reload()
        } catch {
            notice = notice(for: error)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    static func resolveMapState(
        visibility: LocationVisibilitySnapshot?,
        ownLocation: OwnLocationSnapshot?,
        now: Date = Date()
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
              let partner = visibility.partnerLocation,
              !partnerLocationIsExpired(partner, now: now)
        else {
            return .partnerUnknown(visibility.visibilityState)
        }

        return .ready(current: current, partner: partner)
    }

    private static func partnerLocationIsExpired(_ location: LocationPoint, now: Date) -> Bool {
        now.timeIntervalSince(location.capturedAt) >= Constants.partnerLocationUnknownAfter
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

    private func captureAndEnqueueOwnLocation(
        ownerUserID: UUID,
        coupleID: UUID,
        source: LocationSharingSource
    ) async throws {
        let location = try await locationCapture.captureCurrentLocation()
        try await saveAndEnqueueOwnLocation(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: location,
            source: source
        )
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

        do {
            let localStore = try PaeoniaLocalStore()
            return (
                SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container),
                SwiftDataOwnLocationSnapshotRepository(container: localStore.container),
                SwiftDataPendingSyncOperationRepository(container: localStore.container)
            )
        } catch {
            return nil
        }
    }
}
