import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct LocationMapViewModelTests {
    @Test
    func missingSnapshotDoesNotMasqueradeAsRestoredOptOut() async {
        let viewModel = LocationMapViewModel(
            visibilityStore: InMemoryLocationVisibilityRepository(),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.unavailable)
        )

        await viewModel.configure(
            identity: LocationIdentity(
                currentUserID: locationTestUUID("11111111-1111-1111-1111-111111111111"),
                coupleID: locationTestUUID("22222222-2222-2222-2222-222222222222")
            )
        )

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.isSharingLoaded)
        #expect(!viewModel.hasResolvedSharingPreference)
        #expect(!viewModel.sharingEnabled)
    }

    @Test
    func freshViewModelRestoresSharingFromDurableSnapshot() async throws {
        let ownerUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilityRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.unavailable)
        )

        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.isSharingLoaded)
        #expect(viewModel.hasResolvedSharingPreference)
        #expect(viewModel.sharingEnabled)
    }

    @Test
    func restoredSharingDoesNotPromptForSystemPermission() async throws {
        let ownerUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let capture = CountingLocationCapture(authorizationState: .notDetermined)
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: capture
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        await viewModel.refreshOwnLocationIfSharingEnabled(
            source: .foregroundOpen,
            mayPromptForAuthorization: false
        )

        #expect(capture.requestCount == 0)
    }

    @Test
    func primerActionCapturesLocationWhenServerPreferenceIsAlreadyEnabled() async throws {
        let ownerUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let coupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let pendingStore = InMemoryPendingSyncOperationRepository()
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let viewModel = LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: InMemoryOwnLocationSnapshotRepository(),
            pendingOperationStore: pendingStore,
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(
                location: LocationPoint(
                    latitude: 59.91,
                    longitude: 10.75,
                    capturedAt: Date(timeIntervalSince1970: 101)
                )
            )
        )
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: ownerUserID, coupleID: coupleID)
        )

        await viewModel.promptForCurrentLocation()

        #expect(try await locationWriteCount(pendingStore, ownerUserID: ownerUserID) == 1)
    }

    @Test
    func previousIdentityReloadCannotPublishIntoNewCouple() async throws {
        let firstUserID = locationTestUUID("11111111-1111-1111-1111-111111111111")
        let firstCoupleID = locationTestUUID("22222222-2222-2222-2222-222222222222")
        let secondUserID = locationTestUUID("44444444-4444-4444-4444-444444444444")
        let secondCoupleID = locationTestUUID("55555555-5555-5555-5555-555555555555")
        let firstSnapshot = try visibilitySnapshot(
            ownerUserID: firstUserID,
            coupleID: firstCoupleID,
            visibilityState: .visible,
            partnerLocationIsStale: false
        )
        let visibilityStore = IdentitySwitchVisibilityStore(
            suspendedOwnerUserID: firstUserID,
            suspendedSnapshot: firstSnapshot
        )
        let viewModel = try await makeViewModelWithSavedLocation(
            visibilityStore: visibilityStore,
            ownerUserID: firstUserID,
            coupleID: firstCoupleID
        )

        let firstConfiguration = Task {
            await viewModel.configure(
                identity: LocationIdentity(currentUserID: firstUserID, coupleID: firstCoupleID)
            )
        }
        await visibilityStore.waitUntilSuspendedLoadStarts()
        await viewModel.configure(
            identity: LocationIdentity(currentUserID: secondUserID, coupleID: secondCoupleID)
        )
        await visibilityStore.finishSuspendedLoad()
        await firstConfiguration.value

        #expect(viewModel.mapState == .loading)
    }

    private func makeViewModelWithSavedLocation(
        visibilityStore: any LocationVisibilitySnapshotPersisting,
        ownerUserID: UUID,
        coupleID: UUID
    ) async throws -> LocationMapViewModel {
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(
            OwnLocationSnapshot(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                location: ownLocationSnapshot().location,
                source: .foregroundOpen,
                pendingOperationID: nil,
                updatedAt: Date(timeIntervalSince1970: 101)
            )
        )
        return LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: UniqueOperationProvider(),
            locationCapture: StubLocationCapture(error: ForegroundLocationCaptureError.unavailable)
        )
    }
}
