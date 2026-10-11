import Foundation
import Testing
@testable import PaeoniaApp

/// Sharing choices racing a GPS fix, permission changes, and what the map card
/// shows for each state.
@MainActor
struct LocationSharingFlowTests {
    private let ownerUserID = flowUUID("11111111-1111-1111-1111-111111111111")
    private let coupleID = flowUUID("22222222-2222-2222-2222-222222222222")

    /// Turning sharing off while a refresh waits for a GPS fix used to be
    /// dropped silently (the switch snapped back on), and the refresh then
    /// queued the location anyway.
    @Test func turningSharingOffWinsOverARefreshWaitingForGPS() async throws {
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
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

    @Test func sharingSwitchReportsBusyAndCardShowsProgressWhileLocating() async {
        let capture = ControlledLocationCapture(authorizationState: .authorized)
        let viewModel = makeViewModel(capture: capture)
        await viewModel.configure(identity: identity)
        #expect(viewModel.mapState == .currentUnknown)

        let optIn = Task { await viewModel.setSharingEnabled(true) }
        await capture.waitUntilRequested()

        #expect(viewModel.isUpdatingSharing)
        #expect(viewModel.mapState == .locatingCurrent)

        capture.finish(with: .success(sampleLocation))
        await optIn.value

        #expect(!viewModel.isUpdatingSharing)
        #expect(viewModel.sharingEnabled)
    }

    /// "Don't Allow" on the system prompt is a choice, so no error banner. The
    /// card switches to the "location access is off" state instead.
    @Test func decliningTheSystemPromptIsQuietAndShowsAccessOff() async {
        let capture = ControlledLocationCapture(authorizationState: .notDetermined)
        capture.authorizationAfterRequest = .denied
        let viewModel = makeViewModel(capture: capture)
        await viewModel.configure(identity: identity)

        let optIn = Task { await viewModel.setSharingEnabled(true) }
        await capture.waitUntilRequested()
        capture.finish(with: .failure(ForegroundLocationCaptureError.authorizationDenied))
        await optIn.value

        #expect(!viewModel.sharingEnabled)
        #expect(viewModel.notice == nil)
        #expect(viewModel.authorizationState == .denied)
        #expect(viewModel.mapState == .locationAccessOff)
    }

    @Test func permissionAlreadyOffStillExplainsWhySharingDidNotTurnOn() async {
        let capture = ControlledLocationCapture(authorizationState: .denied)
        let viewModel = makeViewModel(capture: capture)
        await viewModel.configure(identity: identity)

        let optIn = Task { await viewModel.setSharingEnabled(true) }
        await capture.waitUntilRequested()
        capture.finish(with: .failure(ForegroundLocationCaptureError.authorizationDenied))
        await optIn.value

        #expect(!viewModel.sharingEnabled)
        #expect(viewModel.notice == .permissionDenied)
    }

    /// Opening the app indoors must not raise an error banner every time.
    @Test func automaticRefreshFailureIsQuietButManualRefreshExplains() async throws {
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let capture = ControlledLocationCapture(authorizationState: .authorized)
        capture.immediateResult = .failure(ForegroundLocationCaptureError.unavailable)
        let viewModel = makeViewModel(visibilityStore: visibilityStore, capture: capture)
        await viewModel.configure(identity: identity)

        await viewModel.refreshOwnLocationIfSharingEnabled(source: .foregroundOpen, mayPromptForAuthorization: false)
        #expect(viewModel.notice == nil)
        #expect(viewModel.mapState == .currentLocationMissing)

        await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        #expect(viewModel.notice == .locationUnavailable)
    }

    /// Returning from the Settings app with location turned back on reaches the
    /// card through the scene-activation refresh.
    @Test func permissionChangeIsPickedUpOnTheNextRefresh() async {
        let capture = ControlledLocationCapture(authorizationState: .denied)
        let viewModel = makeViewModel(capture: capture)
        await viewModel.configure(identity: identity)
        #expect(viewModel.mapState == .locationAccessOff)

        capture.authorizationState = .authorized
        await viewModel.refreshOwnLocationIfSharingEnabled(source: .foregroundOpen, mayPromptForAuthorization: false)

        #expect(viewModel.authorizationState == .authorized)
        #expect(viewModel.mapState == .currentUnknown)
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
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
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
        visibilityStore: InMemoryLocationVisibilitySnapshotRepository = InMemoryLocationVisibilitySnapshotRepository(),
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

    private func snapshot(
        _ state: PartnerLocationVisibilityState,
        partnerSharing: Bool = true,
        partner: LocationPoint? = nil
    ) -> LocationVisibilitySnapshot {
        LocationVisibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            viewerUserID: ownerUserID,
            partnerUserID: flowUUID("33333333-3333-3333-3333-333333333333"),
            visibilityState: state,
            viewerSharingEnabled: true,
            partnerSharingEnabled: partnerSharing,
            partnerLocation: partner,
            partnerLocationIsStale: false,
            updatedAt: Date(timeIntervalSince1970: 200),
            refreshedAt: Date(timeIntervalSince1970: 201)
        )
    }
}

extension LocationSharingFlowTests {
    // MARK: - Map state

    @Test func mapStateCoversEveryCardState() throws {
        let own = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: sampleLocation,
            source: .foregroundOpen,
            pendingOperationID: nil,
            updatedAt: Date()
        )
        let partnerLocation = LocationPoint(latitude: 69.96, longitude: 23.27, capturedAt: Date())

        #expect(LocationMapViewModel.resolveMapState(visibility: nil, ownLocation: nil) == .currentUnknown)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: nil, ownLocation: nil, isLocating: true
        ) == .locatingCurrent)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.visible, partner: partnerLocation),
            ownLocation: nil
        ) == .currentLocationMissing)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.visible, partner: partnerLocation),
            ownLocation: own,
            authorization: .denied
        ) == .locationAccessOff)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.visible, partner: partnerLocation),
            ownLocation: own
        ) == .ready(current: sampleLocation, partner: partnerLocation, partnerWasStaleAtLastRefresh: false))
    }

    @Test func mapStateNamesWhyThePartnerIsMissing() {
        let own = OwnLocationSnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            location: sampleLocation,
            source: .foregroundOpen,
            pendingOperationID: nil,
            updatedAt: Date()
        )

        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.notSharing, partnerSharing: true),
            ownLocation: own
        ) == .waitingForPartnerLocation)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.notSharing, partnerSharing: false),
            ownLocation: own
        ) == .partnerUnknown(.notSharing))
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.unknown("local"), partnerSharing: false),
            ownLocation: own
        ) == .partnerUnknown(.notSharing))
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.unknown("local"), partnerSharing: true),
            ownLocation: own
        ) == .waitingForPartnerLocation)
        #expect(LocationMapViewModel.resolveMapState(
            visibility: snapshot(.relationshipEnded, partnerSharing: false),
            ownLocation: own
        ) == .partnerUnknown(.relationshipEnded))
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
