import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct LocationMapViewModelSharingTests {
    @MainActor
    @Test
    func deniedPermissionDoesNotEnableSharingOrQueueOperation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let visibilityStore = InMemoryLocationVisibilityRepository()
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
        // Declining the system prompt is a choice, not an error banner.
        #expect(viewModel.notice == nil)
        let readyOperations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(readyOperations.isEmpty)
    }

    @MainActor
    @Test
    func turningSharingOffCancelsQueuedLocationUploads() async throws {
        let ownerUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilityRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(latitude: 59.91, longitude: 10.75, capturedAt: Date(timeIntervalSince1970: 100))
            )
        )
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))
        await viewModel.setSharingEnabled(true)
        let queuedUploads = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        )
        #expect(queuedUploads.count == 1)

        await viewModel.setSharingEnabled(false)

        let remainingUploads = try await pendingStore.inFlightOperations(
            ownerUserID: ownerUserID,
            kind: .updateLatestPartnerLocation
        )
        #expect(remainingUploads.isEmpty)
    }

    @Test
    func authorizedTemporaryLocationFailureStillPersistsSharingChoice() async throws {
        let ownerUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: AuthorizedUnavailableLocationCapture()
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        await viewModel.setSharingEnabled(true)

        #expect(viewModel.sharingEnabled)
        #expect(viewModel.notice == .locationUnavailable)
        #expect(try await visibilityStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        )?.viewerSharingEnabled == true)
        let operations = try await pendingStore.readyOperations(
            ownerUserID: ownerUserID,
            limit: 10,
            now: Date()
        )
        #expect(operations.map(\.operationKind) == [.updateLocationSharingPreference])
    }

    @Test
    func failedLocationEnqueueRestoresSnapshotSoForegroundRefreshCanRetry() async throws {
        let previousSnapshot = ownLocationSnapshot()
        let ownerUserID = previousSnapshot.ownerUserID
        let coupleID = previousSnapshot.coupleID
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(previousSnapshot)
        let pendingStore = FailingLocationPendingOperationStore()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilityRepository(),
            ownLocationStore: ownLocationStore,
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 60.39,
                    longitude: 5.32,
                    capturedAt: Date(timeIntervalSince1970: 200)
                )
            )
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        await viewModel.setSharingEnabled(true)

        #expect(viewModel.sharingEnabled)
        #expect(viewModel.notice == .saveFailed)
        #expect(try await ownLocationStore.load(
            ownerUserID: ownerUserID,
            coupleID: coupleID
        ) == previousSnapshot)
        #expect(await pendingStore.enqueuedOperationKinds() == [.updateLocationSharingPreference])
    }

    @Test
    func repeatedShareTapDoesNotStartCompetingLocationRequests() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let locationCapture = SuspendedLocationCapture()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilityRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: locationCapture
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        let firstRequest = Task { await viewModel.promptForCurrentLocation() }
        await locationCapture.waitUntilRequested()
        await viewModel.promptForCurrentLocation()

        #expect(locationCapture.requestCount == 1)

        locationCapture.finish(
            with: LocationPoint(
                latitude: 59.91,
                longitude: 10.75,
                capturedAt: Date(timeIntervalSince1970: 100)
            )
        )
        await firstRequest.value
        #expect(viewModel.notice == nil)
    }

    @MainActor
    @Test
    func foregroundRefreshIsThrottledButManualRefreshAlwaysWrites() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilityRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 59.91,
                    longitude: 10.75,
                    capturedAt: Date()
                )
            )
        )
        await viewModel.configure(identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID))

        // Enabling sharing captures and enqueues the first fix.
        await viewModel.setSharingEnabled(true)
        let firstWrite = try await queuedLocationWriteIDs(pendingStore, ownerUserID: ownerUserID)
        #expect(firstWrite.count == 1)

        // A foreground-open refresh moments later, from the same position, is throttled away.
        await viewModel.refreshOwnLocationIfSharingEnabled(source: .foregroundOpen)
        #expect(try await queuedLocationWriteIDs(pendingStore, ownerUserID: ownerUserID) == firstWrite)

        // A manual pull-to-refresh always writes, even without moving. Only the
        // latest position matters, so the new write replaces the queued one.
        await viewModel.refreshOwnLocationIfSharingEnabled(source: .manualRefresh)
        let secondWrite = try await queuedLocationWriteIDs(pendingStore, ownerUserID: ownerUserID)
        #expect(secondWrite.count == 1)
        #expect(secondWrite != firstWrite)
    }
}
