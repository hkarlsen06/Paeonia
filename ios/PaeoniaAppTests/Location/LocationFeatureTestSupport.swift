import Foundation
import Testing
@testable import PaeoniaApp

actor RecordingLocationGateway: LocationGateway {
    private let preferenceResponse: LocationSharingPreferenceUpdateResponse?
    private let locationResponse: LatestPartnerLocationUpdateResponse?
    private let locationError: (any Error)?
    private(set) var preferencePayloads: [LocationSharingOperationPayload] = []
    private(set) var latestLocationPayloads: [LatestPartnerLocationOperationPayload] = []

    init(
        preferenceResponse: LocationSharingPreferenceUpdateResponse? = nil,
        locationResponse: LatestPartnerLocationUpdateResponse? = nil,
        locationError: (any Error)? = nil
    ) {
        self.preferenceResponse = preferenceResponse
        self.locationResponse = locationResponse
        self.locationError = locationError
    }

    func updateLocationSharingPreference(
        payload: LocationSharingOperationPayload,
        operation _: SyncClientOperation
    ) throws -> LocationSharingPreferenceUpdateResponse? {
        preferencePayloads.append(payload)
        return preferenceResponse
    }

    func updateLatestPartnerLocation(
        payload: LatestPartnerLocationOperationPayload,
        operation _: SyncClientOperation
    ) throws -> LatestPartnerLocationUpdateResponse? {
        latestLocationPayloads.append(payload)
        if let locationError {
            throw locationError
        }
        return locationResponse
    }
}

actor IdentitySwitchVisibilityStore: LocationVisibilitySnapshotPersisting {
    private let suspendedOwnerUserID: UUID
    private let suspendedSnapshot: LocationVisibilitySnapshot
    private var loadContinuation: CheckedContinuation<LocationVisibilitySnapshot?, Never>?

    init(
        suspendedOwnerUserID: UUID,
        suspendedSnapshot: LocationVisibilitySnapshot
    ) {
        self.suspendedOwnerUserID = suspendedOwnerUserID
        self.suspendedSnapshot = suspendedSnapshot
    }

    func save(_ snapshot: LocationVisibilitySnapshot) throws {}

    func saveRemote(
        _ snapshot: LocationVisibilitySnapshot,
        preservingLocalSharingChoiceIf hasPendingSharingOperation: Bool
    ) throws {}

    func load(ownerUserID: UUID, coupleID _: UUID) async throws -> LocationVisibilitySnapshot? {
        guard ownerUserID == suspendedOwnerUserID else { return nil }
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func setViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        choice: ViewerSharingChoice,
        updatedAt: Date,
        isPendingConfirmation: Bool
    ) throws {}

    func confirmViewerSharing(
        ownerUserID: UUID,
        coupleID: UUID,
        confirmation: ViewerSharingConfirmation,
        updatedAt: Date,
        otherChoicesPending: Bool
    ) throws {}

    func delete(ownerUserID: UUID, coupleID: UUID) throws {}

    func waitUntilSuspendedLoadStarts() async {
        while loadContinuation == nil {
            await Task.yield()
        }
    }

    func finishSuspendedLoad() {
        loadContinuation?.resume(returning: suspendedSnapshot)
        loadContinuation = nil
    }
}

@MainActor
final class FixedOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = locationTestUUID("99999999-9999-9999-9999-999999999999")

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            id: locationTestUUID("88888888-8888-8888-8888-888888888888"),
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

@MainActor
final class UniqueOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = locationTestUUID("99999999-9999-9999-9999-999999999999")

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            id: UUID(),
            clientID: clientID,
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

func queuedLocationWriteIDs(
    _ store: InMemoryPendingSyncOperationRepository,
    ownerUserID: UUID
) async throws -> [UUID] {
    try await store.readyOperations(ownerUserID: ownerUserID, limit: 100, now: Date())
        .filter { $0.operationKind == .updateLatestPartnerLocation }
        .map(\.operation.id)
}

func locationWriteCount(
    _ store: InMemoryPendingSyncOperationRepository,
    ownerUserID: UUID
) async throws -> Int {
    try await store.readyOperations(ownerUserID: ownerUserID, limit: 100, now: Date())
        .filter { $0.operationKind == .updateLatestPartnerLocation }
        .count
}

@MainActor
final class StubLocationCapture: ForegroundLocationCapturing {
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

    func captureCurrentLocation() throws -> LocationPoint {
        if let location {
            return location
        }
        throw error ?? ForegroundLocationCaptureError.unavailable
    }
}

@MainActor
final class SuspendedLocationCapture: ForegroundLocationCapturing {
    let authorizationState: ForegroundLocationAuthorizationState = .authorized
    private var continuation: CheckedContinuation<LocationPoint, Never>?
    private(set) var requestCount = 0

    func captureCurrentLocation() async throws -> LocationPoint {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func finish(with location: LocationPoint) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}

@MainActor
final class CountingLocationCapture: ForegroundLocationCapturing {
    let authorizationState: ForegroundLocationAuthorizationState
    private(set) var requestCount = 0

    init(authorizationState: ForegroundLocationAuthorizationState) {
        self.authorizationState = authorizationState
    }

    // swiftlint:disable:next async_without_await
    func captureCurrentLocation() async throws -> LocationPoint {
        requestCount += 1
        throw ForegroundLocationCaptureError.unavailable
    }
}

@MainActor
final class AuthorizedUnavailableLocationCapture: ForegroundLocationCapturing {
    let authorizationState: ForegroundLocationAuthorizationState = .authorized

    // swiftlint:disable:next async_without_await
    func captureCurrentLocation() async throws -> LocationPoint {
        throw ForegroundLocationCaptureError.unavailable
    }
}

actor FailingLocationPendingOperationStore: PendingSyncOperationPersisting {
    private enum Failure: Error {
        case locationEnqueueFailed
    }

    private var operationKinds: [SyncPendingOperationKind] = []

    // Protocol witnesses intentionally model synchronous in-memory behavior.
    // swiftlint:disable async_without_await
    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        guard request.operationKind != .updateLatestPartnerLocation else {
            throw Failure.locationEnqueueFailed
        }
        operationKinds.append(request.operationKind)
    }

    func enqueuedOperationKinds() -> [SyncPendingOperationKind] {
        operationKinds
    }

    func readyOperations(
        ownerUserID _: UUID,
        limit _: Int,
        now _: Date
    ) async throws -> [PendingSyncOperationSnapshot] {
        []
    }

    func nextPendingOperationDate(ownerUserID _: UUID, now _: Date) async throws -> Date? {
        nil
    }

    func inFlightOperations(
        ownerUserID _: UUID,
        kind _: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        []
    }

    func markSending(clientOperationID _: UUID, at _: Date) async throws {}
    func markSucceeded(clientOperationID _: UUID, at _: Date) async throws {}
    func markRetryableFailure(
        clientOperationID _: UUID,
        errorDescription _: String,
        nextRetryAt _: Date?,
        at _: Date
    ) async throws {}
    func markTerminalFailure(
        clientOperationID _: UUID,
        errorDescription _: String,
        at _: Date
    ) async throws {}
    func deleteCompleted(ownerUserID _: UUID) async throws {}
    func resetInFlight(ownerUserID _: UUID) async throws {}
    // swiftlint:enable async_without_await
}

func visibilitySnapshot(
    ownerUserID: UUID = locationTestUUID("11111111-1111-1111-1111-111111111111"),
    coupleID: UUID = locationTestUUID("22222222-2222-2222-2222-222222222222"),
    visibilityState: PartnerLocationVisibilityState,
    partnerLocationIsStale: Bool,
    partnerLocationCapturedAt: Date = Date(timeIntervalSince1970: 200)
) throws -> LocationVisibilitySnapshot {
    LocationVisibilitySnapshot(
        ownerUserID: ownerUserID,
        coupleID: coupleID,
        viewerUserID: ownerUserID,
        partnerUserID: locationTestUUID("33333333-3333-3333-3333-333333333333"),
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

func ownLocationSnapshot() -> OwnLocationSnapshot {
    OwnLocationSnapshot(
        ownerUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
        coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222"),
        location: LocationPoint(
            latitude: 59,
            longitude: 10,
            capturedAt: Date(timeIntervalSince1970: 100)
        ),
        source: .foregroundOpen,
        pendingOperationID: nil,
        updatedAt: Date(timeIntervalSince1970: 101)
    )
}

func locationTestUUID(_ rawValue: String) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        preconditionFailure("Invalid test UUID: \(rawValue)")
    }
    return uuid
}

func operation(id: String) throws -> SyncClientOperation {
    SyncClientOperation(
        id: try #require(UUID(uuidString: id)),
        clientID: try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999")),
        clientSequence: 1,
        localCreatedAt: Date(timeIntervalSince1970: 100)
    )
}

func pendingOperation<Payload: Encodable>(
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

func syncContext(ownerUserID: UUID, coupleID: UUID) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: ownerUserID, activeCoupleID: coupleID),
        reason: .manualRefresh,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: InMemoryPendingSyncOperationRepository()
    )
}
