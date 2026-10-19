import Foundation
import Testing
@testable import PaeoniaApp

/// Sharing choices racing a GPS fix, queued location uploads, and the live feed.
@MainActor
struct LocationSharingFlowTests {
    private let ownerUserID = flowUUID("11111111-1111-1111-1111-111111111111")
    private let coupleID = flowUUID("22222222-2222-2222-2222-222222222222")

    /// Turning sharing off while a refresh waits for a GPS fix used to be
    /// dropped silently (the switch snapped back on), and the refresh then
    /// queued the location anyway.
    @Test func turningSharingOffWinsOverARefreshWaitingForGPS() async throws {
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let capture = ControlledLocationCapture(authorizationState: .authorized)
        let viewModel = makeViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            pendingStore: pendingStore,
            capture: capture
        )
        await viewModel.configure(identity: identity)
        #expect(viewModel.sharingEnabled)

        let refresh = Task { await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh) }
        await capture.waitUntilRequested()

        await viewModel.setSharingEnabled(false)
        #expect(!viewModel.sharingEnabled)

        capture.finish(with: .success(sampleLocation))
        await refresh.value

        let queued = try await pendingStore.readyOperations(ownerUserID: ownerUserID, limit: 10, now: Date())
        #expect(queued.map(\.operationKind) == [.updateLocationSharingPreference])
        #expect(try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID) == nil)
        #expect(!viewModel.sharingEnabled)
        #expect(viewModel.notice == nil)
    }

    /// Locations queued while offline used to replay one by one. Only the
    /// latest position matters, so a newer one replaces older queued ones.
    @Test func newerLocationReplacesOlderQueuedOnes() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = try await sharingViewModel(pendingStore: pendingStore)

        for _ in 0..<3 {
            await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        }

        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        )
        #expect(queued.count == 1)
    }

    /// An upload already on its way is left alone; only queued ones are dropped.
    @Test func locationAlreadySendingIsNotDropped() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = try await sharingViewModel(pendingStore: pendingStore)
        await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        let sending = try #require(try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        ).first)
        try await pendingStore.markSending(clientOperationID: sending.operation.id, at: Date())

        await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)

        let queued = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        )
        #expect(queued.count == 2)
        #expect(queued.contains { $0.operation.id == sending.operation.id })
    }

    /// A privacy purge deletes the snapshot rows, so their unconfirmed choices
    /// must go too, or they would override the server after the next sign-in.
    @Test func purgeForgetsOnlyThatUsersUnconfirmedChoices() {
        let ledger = PendingSharingChoiceLedger()
        let otherUserID = flowUUID("44444444-4444-4444-4444-444444444444")
        let ownKey = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: coupleID)
        let otherKey = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: otherUserID, coupleID: coupleID)
        ledger.withChoices { choices in
            choices[ownKey] = true
            choices[otherKey] = false
        }

        ledger.removeChoices(ownerUserID: ownerUserID)

        #expect(ledger.withChoices { $0 } == [otherKey: false])
    }

    // MARK: - Helpers

    private var identity: LocationIdentity {
        LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
    }

    private var sampleLocation: LocationPoint {
        LocationPoint(latitude: 59.91, longitude: 10.75, capturedAt: Date(timeIntervalSince1970: 500))
    }

    /// A configured view model that already shares and gets a fix right away.
    private func sharingViewModel(
        pendingStore: InMemoryPendingSyncOperationRepository
    ) async throws -> LocationMapViewModel {
        let visibilityStore = InMemoryLocationVisibilityRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let capture = ControlledLocationCapture(authorizationState: .authorized)
        capture.immediateResult = .success(sampleLocation)
        let viewModel = makeViewModel(visibilityStore: visibilityStore, pendingStore: pendingStore, capture: capture)
        await viewModel.configure(identity: identity)
        return viewModel
    }

    private func makeViewModel(
        visibilityStore: InMemoryLocationVisibilityRepository = InMemoryLocationVisibilityRepository(),
        ownLocationStore: InMemoryOwnLocationSnapshotRepository = InMemoryOwnLocationSnapshotRepository(),
        pendingStore: InMemoryPendingSyncOperationRepository = InMemoryPendingSyncOperationRepository(),
        capture: ControlledLocationCapture
    ) -> LocationMapViewModel {
        LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            pendingOperationStore: pendingStore,
            operationProvider: FlowOperationProvider(),
            locationCapture: capture
        )
    }
}

/// A location capture the test answers by hand. `immediateResult` answers at
/// once; otherwise the request waits for `finish(with:)`.
@MainActor
private final class ControlledLocationCapture: ForegroundLocationCapturing {
    var authorizationState: ForegroundLocationAuthorizationState
    /// What iOS reports once the system prompt was answered.
    var authorizationAfterRequest: ForegroundLocationAuthorizationState?
    var immediateResult: Result<LocationPoint, any Error>?
    private var continuation: CheckedContinuation<LocationPoint, any Error>?

    init(authorizationState: ForegroundLocationAuthorizationState) {
        self.authorizationState = authorizationState
    }

    func captureCurrentLocation() async throws -> LocationPoint {
        if let immediateResult {
            return try immediateResult.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func finish(with result: Result<LocationPoint, any Error>) {
        if let authorizationAfterRequest {
            authorizationState = authorizationAfterRequest
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}

private final class FlowOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(
            id: UUID(),
            clientID: flowUUID("99999999-9999-9999-9999-999999999999"),
            clientSequence: sequence,
            localCreatedAt: Date(timeIntervalSince1970: TimeInterval(sequence))
        )
    }
}

private func flowUUID(_ rawValue: String) -> UUID {
    guard let uuid = UUID(uuidString: rawValue) else {
        preconditionFailure("Invalid test UUID: \(rawValue)")
    }
    return uuid
}

extension LocationSharingFlowTests {
    // MARK: - Live feed while open

    @Test func liveFeedSendsAMoveButNotTheSameSpotAgain() async throws {
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let viewModel = makeViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            capture: ControlledLocationCapture(authorizationState: .authorized)
        )
        await viewModel.configure(identity: identity)
        let start = Date()
        let stored = { try await ownLocationStore.load(ownerUserID: self.ownerUserID, coupleID: self.coupleID) }

        await viewModel.submitObservedLocation(LocationPoint(latitude: 59.91, longitude: 10.75, capturedAt: start))
        #expect(try await stored()?.location.latitude == 59.91)

        // About 10 m away a few seconds later: nothing new to send.
        await viewModel.submitObservedLocation(
            LocationPoint(latitude: 59.9101, longitude: 10.75, capturedAt: start.addingTimeInterval(5))
        )
        #expect(try await stored()?.location.latitude == 59.91)

        // About 4 km away: sent right away.
        await viewModel.submitObservedLocation(
            LocationPoint(latitude: 59.95, longitude: 10.75, capturedAt: start.addingTimeInterval(10))
        )
        #expect(try await stored()?.location.latitude == 59.95)
        #expect(try await stored()?.pendingOperationID != nil)
    }

    @Test func liveFeedSendsNothingWhileNotSharing() async throws {
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        let viewModel = makeViewModel(
            ownLocationStore: ownLocationStore,
            capture: ControlledLocationCapture(authorizationState: .authorized)
        )
        await viewModel.configure(identity: identity)

        await viewModel.submitObservedLocation(sampleLocation)

        #expect(try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID) == nil)
    }
}
