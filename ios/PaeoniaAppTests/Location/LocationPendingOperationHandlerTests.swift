import Foundation
import Testing
@testable import PaeoniaApp

struct LocationPendingOperationHandlerTests {
    @Test
    func preferenceHandlerSendsRpcPayloadAndUpdatesLocalPreference() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let payload = enabledPreferencePayload(coupleID: coupleID)
        let gateway = enabledPreferenceGateway(ownerUserID: ownerUserID, coupleID: coupleID)
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let handler = LocationSharingPendingOperationHandler(
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
    func preferenceHandlerKeepsANewerLocalChoiceWhenAnOlderOperationSucceeds() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let payload = enabledPreferencePayload(coupleID: coupleID)
        let gateway = enabledPreferenceGateway(ownerUserID: ownerUserID, coupleID: coupleID)
        let visibilityStore = InMemoryLocationVisibilityRepository()
        // The user turned sharing back off after this operation was queued.
        try await visibilityStore.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: false,
            updatedAt: Date(timeIntervalSince1970: 102)
        )
        let handler = LocationSharingPendingOperationHandler(
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
        let stored = try await visibilityStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored?.viewerSharingEnabled == false)
    }

    @Test
    func rejectedLocationIsTerminalAndDoesNotOverwriteLocalLocation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let newerLocal = newerLocalSnapshot(ownerUserID: ownerUserID, coupleID: coupleID)
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(newerLocal)
        let handler = LatestLocationPendingOperationHandler(
            gateway: RecordingLocationGateway(
                // What the server answers once sharing was turned off.
                locationError: PaeoniaConvexError.server(
                    code: "42501",
                    message: "location sharing must be enabled before updating location"
                )
            ),
            ownLocationStore: ownLocationStore
        )
        let stalePayload = staleLocationPayload(coupleID: coupleID, latitude: 59, longitude: 10)

        let result = try await handler.send(
            pendingOperation(
                ownerUserID: ownerUserID,
                operation: operation,
                kind: .updateLatestPartnerLocation,
                payload: stalePayload
            ),
            context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID)
        )

        guard case .terminalFailure = result else {
            Issue.record("Expected a terminal failure, got \(result)")
            return
        }
        let stored = try await ownLocationStore.load(ownerUserID: ownerUserID, coupleID: coupleID)
        #expect(stored == newerLocal)
    }

    /// The server also answers `42501` before it can see the sign-in. That used to
    /// drop the location for good.
    @Test func locationRefusedForAMissingSignInIsRetried() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let handler = LatestLocationPendingOperationHandler(
            gateway: RecordingLocationGateway(
                locationError: PaeoniaConvexError.server(code: "42501", message: "authenticated user required")
            ),
            ownLocationStore: InMemoryOwnLocationSnapshotRepository()
        )
        let payload = LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: LocationPoint(latitude: 59, longitude: 10, capturedAt: Date(timeIntervalSince1970: 200)),
            source: .foregroundOpen
        )

        let snapshot = try pendingOperation(
            ownerUserID: ownerUserID,
            operation: operation(id: "33333333-3333-3333-3333-333333333333"),
            kind: .updateLatestPartnerLocation,
            payload: payload
        )

        await #expect(throws: PaeoniaConvexError.self) {
            try await handler.send(snapshot, context: syncContext(ownerUserID: ownerUserID, coupleID: coupleID))
        }
    }

    @Test func staleLocationSuccessDoesNotOverwriteNewerLocalLocation() async throws {
        let ownerUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let coupleID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = try operation(id: "33333333-3333-3333-3333-333333333333")
        let newerLocal = newerLocalSnapshot(ownerUserID: ownerUserID, coupleID: coupleID)
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        try await ownLocationStore.save(newerLocal)
        let handler = LatestLocationPendingOperationHandler(
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
        let stalePayload = staleLocationPayload(coupleID: coupleID, latitude: 58, longitude: 9)

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

    private func enabledPreferenceGateway(ownerUserID: UUID, coupleID: UUID) -> RecordingLocationGateway {
        RecordingLocationGateway(
            preferenceResponse: LocationSharingPreferenceUpdateResponse(
                coupleID: coupleID,
                userID: ownerUserID,
                isEnabled: true,
                enabledAt: Date(timeIntervalSince1970: 100),
                disabledAt: nil,
                updatedAt: Date(timeIntervalSince1970: 101)
            )
        )
    }

    private func enabledPreferencePayload(coupleID: UUID) -> LocationSharingOperationPayload {
        LocationSharingOperationPayload(
            coupleID: coupleID,
            isEnabled: true,
            consentVersion: "location-sharing-v1",
            source: .settingsToggle
        )
    }

    private func newerLocalSnapshot(ownerUserID: UUID, coupleID: UUID) -> OwnLocationSnapshot {
        OwnLocationSnapshot(
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
    }

    private func staleLocationPayload(
        coupleID: UUID,
        latitude: Double,
        longitude: Double
    ) -> LatestPartnerLocationOperationPayload {
        LatestPartnerLocationOperationPayload(
            coupleID: coupleID,
            location: LocationPoint(
                latitude: latitude,
                longitude: longitude,
                capturedAt: Date(timeIntervalSince1970: 200)
            ),
            source: .foregroundOpen
        )
    }
}
