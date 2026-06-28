import Foundation
import Testing
@testable import PaeoniaApp

struct LocationSnapshotRepositoryTests {
    @Test
    func visibilityRepositoryPersistsPartnerLocationAndStaleState() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataLocationVisibilitySnapshotRepository(container: store.container)
        let snapshot = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: true
        )

        try await repository.save(snapshot)

        let loaded = try await repository.load(
            ownerUserID: snapshot.ownerUserID,
            coupleID: snapshot.coupleID
        )
        #expect(loaded == snapshot)
        #expect(loaded?.partnerLocationIsStale == true)
    }

    @Test
    func ownLocationRepositoryReplacesStoredLocation() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataOwnLocationSnapshotRepository(container: store.container)
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let first = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 59.91,
                longitude: 10.75,
                capturedAt: Date(timeIntervalSince1970: 100)
            ),
            source: .foregroundOpen,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 101)
        )
        let replacementOperationID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let replacement = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 69.96,
                longitude: 23.27,
                accuracyMeters: 12,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .manualRefresh,
            pendingOperationID: replacementOperationID,
            updatedAt: Date(timeIntervalSince1970: 201)
        )

        try await repository.save(first)
        try await repository.save(replacement)

        let loaded = try await repository.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(loaded == replacement)
    }
}

struct LocationVisibilitySyncStreamTests {
    @Test
    func pullStoresVisibilitySnapshotAndAdvancesCursor() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let snapshot = try visibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            visibilityState: .visible,
            partnerLocationIsStale: false
        )
        let gateway = RecordingLocationGateway(visibilitySnapshot: snapshot)
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let stream = LocationVisibilitySyncStream(
            gateway: gateway,
            visibilityStore: visibilityStore
        )
        let context = SyncContext(
            session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID),
            reason: .manualRefresh,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )

        let cursor = try await stream.pull(context: context)

        let stored = try await visibilityStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == snapshot)
        #expect(cursor == SyncCursor(updatedAt: snapshot.updatedAt, tieID: snapshot.coupleID))
    }
}

struct LocationPendingOperationHandlerTests {
    @Test
    func preferenceHandlerSendsRpcPayloadAndUpdatesLocalPreference() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let payload = LocationSharingPreferenceOperationPayload(
            coupleID: coupleID,
            isEnabled: true,
            consentVersion: "location-sharing-v1",
            source: .settingsToggle
        )
        let gateway = RecordingLocationGateway(
            preferenceResponse: LocationSharingPreferenceUpdateResponse(
                coupleID: coupleID,
                userID: ownerUserID,
                isEnabled: true,
                enabledAt: Date(timeIntervalSince1970: 100),
                disabledAt: nil,
                updatedAt: Date(timeIntervalSince1970: 101)
            )
        )
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let handler = LocationSharingPreferencePendingOperationHandler(
            gateway: gateway,
            visibilityStore: visibilityStore
        )

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLocationSharingPreference,
                payload: payload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(result == .succeeded)
        let preferencePayloads = await gateway.preferencePayloads
        #expect(preferencePayloads == [payload])
        let stored = try await visibilityStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored?.viewerSharingEnabled == true)
    }

    @Test
    func staleLocationRetryIsTerminalAndDoesNotOverwriteLocalLocation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let newerLocal = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 60,
                longitude: 11,
                capturedAt: Date(timeIntervalSince1970: 300)
            ),
            source: .manualRefresh,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 301)
        )
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(newerLocal)
        let handler = LatestPartnerLocationPendingOperationHandler(
            gateway: RecordingLocationGateway(
                locationError: StaleLocationError(description: "stale location update was rejected")
            ),
            ownLocationStore: ownLocationStore
        )
        let stalePayload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 59,
                longitude: 10,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .foregroundOpen
        )

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLatestPartnerLocation,
                payload: stalePayload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(result == .terminalFailure("Stale location update rejected"))
        let stored = try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == newerLocal)
    }

    @Test func staleLocationSuccessDoesNotOverwriteNewerLocalLocation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let newerLocal = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 60,
                longitude: 11,
                capturedAt: Date(timeIntervalSince1970: 300)
            ),
            source: .manualRefresh,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 301)
        )
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(newerLocal)
        let handler = LatestPartnerLocationPendingOperationHandler(
            gateway: RecordingLocationGateway(
                locationResponse: LatestPartnerLocationUpdateResponse(
                    coupleID: coupleID,
                    userID: ownerUserID,
                    latitude: 59,
                    longitude: 10,
                    accuracyMeters: nil,
                    capturedAt: Date(timeIntervalSince1970: 250),
                    receivedAt: Date(timeIntervalSince1970: 251),
                    updatedAt: Date(timeIntervalSince1970: 252)
                )
            ),
            ownLocationStore: ownLocationStore
        )
        let stalePayload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: LocationPoint(
                latitude: 58,
                longitude: 9,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .foregroundOpen
        )

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLatestPartnerLocation,
                payload: stalePayload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(result == .succeeded)
        let stored = try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == newerLocal)
    }
}

struct SupabaseLocationGatewayRequestEncodingTests {
    @Test
    func preferenceRequestEncodesNilConsentVersionAsNull() throws {
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let request = UpdateLocationSharingPreferenceRequest(
            payload: LocationSharingPreferenceOperationPayload(
                coupleID: coupleID,
                isEnabled: false,
                consentVersion: nil,
                source: .settingsToggle
            ),
            operation: try operation(id: "33333333-3333-3333-3333-333333333333")
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded)
        let object = try #require(json as? [String: Any])

        #expect(object.keys.contains("p_consent_version"))
        #expect(object["p_consent_version"] is NSNull)
        #expect(object["p_is_enabled"] as? Bool == false)
    }

    @Test
    func latestLocationRequestEncodesNilAccuracyAsNull() throws {
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let request = UpdateLatestPartnerLocationRequest(
            payload: LatestPartnerLocationOperationPayload(
                coupleID: coupleID,
                location: LocationPoint(
                    latitude: 59,
                    longitude: 10,
                    capturedAt: Date(timeIntervalSince1970: 100)
                ),
                source: .manualRefresh
            ),
            operation: try operation(id: "33333333-3333-3333-3333-333333333333")
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded)
        let object = try #require(json as? [String: Any])

        #expect(object.keys.contains("p_accuracy_m"))
        #expect(object["p_accuracy_m"] is NSNull)
        #expect(object["p_source"] as? String == LocationSharingSource.manualRefresh.rawValue)
    }
}

@MainActor
struct LocationMapViewModelTests {
    @Test
    func mapStateRequiresCurrentAndPartnerLocations() throws {
        let current = OwnLocationSnapshot(
            ownerUserID: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            coupleID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            location: LocationPoint(
                latitude: 59,
                longitude: 10,
                capturedAt: Date(timeIntervalSince1970: 100)
            ),
            source: .foregroundOpen,
            pendingOperationID: nil,
            updatedAt: Date(timeIntervalSince1970: 101)
        )
        let visible = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: false
        )
        let stale = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: true
        )
        let expired = try visibilitySnapshot(
            visibilityState: .visible,
            partnerLocationIsStale: true,
            partnerLocationCapturedAt: Date(timeIntervalSince1970: 200)
        )
        let nowBeforeSevenDays = Date(timeIntervalSince1970: 200 + 6 * 24 * 60 * 60)
        let nowAfterSevenDays = Date(timeIntervalSince1970: 200 + 7 * 24 * 60 * 60)
        let partnerLocation = try #require(visible.partnerLocation)

        #expect(LocationMapViewModel.resolveMapState(
            visibility: visible,
            ownLocation: current,
            now: nowBeforeSevenDays
        ) == .ready(
            current: current.location,
            partner: partnerLocation
        ))
        #expect(LocationMapViewModel.resolveMapState(visibility: visible, ownLocation: nil) == .currentUnknown)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: stale,
            ownLocation: current,
            now: nowBeforeSevenDays
        ) == .ready(
            current: current.location,
            partner: partnerLocation
        ))
        #expect(LocationMapViewModel.resolveMapState(
            visibility: expired,
            ownLocation: current,
            now: nowAfterSevenDays
        ) == .partnerUnknown(.visible))
    }

    @MainActor
    @Test
    func enablingSharingRequestsLocalChangeSync() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let syncRecorder = LocalChangeSyncRecorder()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilitySnapshotRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: FixedOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 59.91,
                    longitude: 10.75,
                    capturedAt: Date(timeIntervalSince1970: 100)
                )
            )
        )
        viewModel.setLocalChangeSyncHandler {
            syncRecorder.record()
        }
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))

        await viewModel.setSharingEnabled(true)

        #expect(syncRecorder.callCount == 1)
    }

    @MainActor
    @Test
    func deniedPermissionDoesNotEnableSharingOrQueueOperation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: FixedOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.authorizationDenied)
        )
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))

        await viewModel.setSharingEnabled(true)

        #expect(viewModel.sharingEnabled == false)
        #expect(viewModel.notice == .permissionDenied)
        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(readyOperations.isEmpty)
    }
}

private actor RecordingLocationGateway: SupabaseLocationGateway {
    private let visibilitySnapshot: LocationVisibilitySnapshot?
    private let preferenceResponse: LocationSharingPreferenceUpdateResponse?
    private let locationResponse: LatestPartnerLocationUpdateResponse?
    private let locationError: (any Error)?
    private(set) var preferencePayloads: [LocationSharingPreferenceOperationPayload] = []
    private(set) var latestLocationPayloads: [LatestPartnerLocationOperationPayload] = []

    init(
        visibilitySnapshot: LocationVisibilitySnapshot? = nil,
        preferenceResponse: LocationSharingPreferenceUpdateResponse? = nil,
        locationResponse: LatestPartnerLocationUpdateResponse? = nil,
        locationError: (any Error)? = nil
    ) {
        self.visibilitySnapshot = visibilitySnapshot
        self.preferenceResponse = preferenceResponse
        self.locationResponse = locationResponse
        self.locationError = locationError
    }

    func loadPartnerLocationVisibility(
        ownerUserID _: UUID,
        coupleID _: UUID
    ) async throws -> LocationVisibilitySnapshot? {
        visibilitySnapshot
    }

    func updateLocationSharingPreference(
        payload: LocationSharingPreferenceOperationPayload,
        operation _: SyncClientOperation
    ) async throws -> LocationSharingPreferenceUpdateResponse? {
        preferencePayloads.append(payload)
        return preferenceResponse
    }

    func updateLatestPartnerLocation(
        payload: LatestPartnerLocationOperationPayload,
        operation _: SyncClientOperation
    ) async throws -> LatestPartnerLocationUpdateResponse? {
        latestLocationPayloads.append(payload)
        if let locationError {
            throw locationError
        }
        return locationResponse
    }
}

private struct StaleLocationError: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class LocalChangeSyncRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

@MainActor
private final class FixedOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = testUUID("99999999-9999-9999-9999-999999999999")

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            id: testUUID("88888888-8888-8888-8888-888888888888"),
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

@MainActor
private final class StubLocationCapture: ForegroundLocationCapturing {
    private let location: LocationPoint?
    private let error: (any Error)?

    init(location: LocationPoint) {
        self.location = location
        error = nil
    }

    init(error: any Error) {
        location = nil
        self.error = error
    }

    func captureCurrentLocation() async throws -> LocationPoint {
        if let location {
            return location
        }
        throw error ?? ForegroundLocationCaptureError.unavailable
    }
}

private func visibilitySnapshot(
    ownerUserID: UUID = testUUID("11111111-1111-1111-1111-111111111111"),
    coupleID: UUID = testUUID("22222222-2222-2222-2222-222222222222"),
    visibilityState: PartnerLocationVisibilityState,
    partnerLocationIsStale: Bool,
    partnerLocationCapturedAt: Date = Date(timeIntervalSince1970: 200)
) throws -> LocationVisibilitySnapshot {
    LocationVisibilitySnapshot(
        ownerUserID: ownerUserID,
        coupleID: coupleID,
        viewerUserID: ownerUserID,
        partnerUserID: testUUID("33333333-3333-3333-3333-333333333333"),
        visibilityState: visibilityState,
        viewerSharingEnabled: true,
        partnerSharingEnabled: true,
        partnerLocation: LocationPoint(
            latitude: 69.96,
            longitude: 23.27,
            accuracyMeters: 20,
            capturedAt: partnerLocationCapturedAt,
            updatedAt: Date(timeIntervalSince1970: 201)
        ),
        partnerLocationIsStale: partnerLocationIsStale,
        updatedAt: Date(timeIntervalSince1970: 202),
        refreshedAt: Date(timeIntervalSince1970: 203)
    )
}

private func testUUID(_ rawValue: String) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        preconditionFailure("Invalid test UUID: \(rawValue)")
    }
    return uuid
}

private func operation(id: String) throws -> SyncClientOperation {
    SyncClientOperation(
        id: try #require(UUID(uuidString: id)),
        clientID: try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999")),
        clientSequence: 1,
        localCreatedAt: Date(timeIntervalSince1970: 100)
    )
}

private func pendingOperation<Payload: Encodable>(
    ownerUserID: UUID,
    operation: SyncClientOperation,
    kind: SyncPendingOperationKind,
    payload: Payload
) throws -> PendingSyncOperationSnapshot {
    PendingSyncOperationSnapshot(
        ownerUserID: ownerUserID,
        operation: operation,
        operationKind: kind,
        idempotencyScope: "test:\(operation.id.uuidString)",
        requestHash: nil,
        requestData: try JSONEncoder().encode(payload),
        status: .queued,
        attemptCount: 0,
        lastAttemptAt: nil,
        nextRetryAt: nil,
        lastError: nil,
        completedAt: nil
    )
}

private func syncContext(ownerUserID: UUID, coupleID: UUID) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID),
        reason: .manualRefresh,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository()
    )
}
