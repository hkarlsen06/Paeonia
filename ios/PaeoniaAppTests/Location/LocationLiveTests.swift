import Foundation
import Testing
@testable import PaeoniaApp

let liveOwnerID = UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111") ?? UUID()
let liveCoupleID = UUID(uuidString: "AAAAAAAA-2222-2222-2222-222222222222") ?? UUID()
let livePartnerID = UUID(uuidString: "AAAAAAAA-3333-3333-3333-333333333333") ?? UUID()

func visibilityRowJSON(
    state: String = "visible",
    viewerSharing: Bool = true,
    partnerSharing: Bool = true,
    capturedAt: String? = "2026-05-01T10:00:00.000Z",
    serverStale: Bool = false
) -> String {
    let latitude = capturedAt == nil ? "null" : "59.91"
    let longitude = capturedAt == nil ? "null" : "10.75"
    let captured = capturedAt.map { "\"\($0)\"" } ?? "null"
    return """
    [{"couple_id":"\(liveCoupleID.uuidString)","viewer_user_id":"\(liveOwnerID.uuidString)",
    "partner_user_id":"\(livePartnerID.uuidString)","visibility_state":"\(state)",
    "viewer_sharing_enabled":\(viewerSharing),"partner_sharing_enabled":\(partnerSharing),
    "partner_location_latitude":\(latitude),"partner_location_longitude":\(longitude),
    "partner_location_accuracy_m":null,"partner_location_captured_at":\(captured),
    "partner_location_is_stale":\(serverStale),"updated_at":"2026-05-01T10:00:01.000Z"}]
    """
}

/// A transport the test pushes values into, like the server pushing a query update.
final class PushTransport: LiveQueryTransport, @unchecked Sendable {
    private let open = LockedBox<AsyncThrowingStream<Data, any Error>.Continuation?>(nil)
    let openedPaths = LockedBox<[String]>([])
    let openedArgs = LockedBox<[[String: String]]>([])

    func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        openedPaths.mutate { $0.append(path) }
        openedArgs.mutate { $0.append(args) }
        return AsyncThrowingStream { continuation in
            open.mutate { $0 = continuation }
        }
    }

    func push(_ json: String) async {
        _ = await waitUntil { open.value != nil }
        open.value?.yield(Data(json.utf8))
    }
}

struct LocationVisibilityLiveFeedTests {
    private func stored(in store: InMemoryLocationVisibilityRepository) async -> LocationVisibilitySnapshot? {
        (try? await store.load(ownerUserID: liveOwnerID, coupleID: liveCoupleID))
    }

    private func makeFeed(
        store: InMemoryLocationVisibilityRepository,
        pending: InMemoryPendingSyncOperationRepository = InMemoryPendingSyncOperationRepository()
    ) -> LocationVisibilityLiveFeed {
        LocationVisibilityLiveFeed(visibilityStore: store, pendingOperationStore: pending)
    }

    @Test func writesTheStoreForEveryValue() async {
        let transport = PushTransport()
        let store = InMemoryLocationVisibilityRepository()
        let session = SyncSession(userID: liveOwnerID, activeCoupleID: liveCoupleID)
        let task = Task {
            await makeFeed(store: store).run(session: session, live: LiveQueryService(transport: transport))
        }

        await transport.push(visibilityRowJSON(state: "not_sharing", partnerSharing: false, capturedAt: nil))
        let notSharing = await waitUntil {
            await stored(in: store)?.visibilityState == .notSharing
        }
        #expect(notSharing)

        await transport.push(visibilityRowJSON())
        let visible = await waitUntil {
            let current = await stored(in: store)
            return current?.visibilityState == .visible && current?.partnerLocation != nil
        }
        #expect(visible)

        await transport.push(visibilityRowJSON(state: "relationship_ended", capturedAt: nil))
        let ended = await waitUntil {
            await stored(in: store)?.visibilityState == .relationshipEnded
        }
        #expect(ended)

        #expect(transport.openedPaths.value == ["location:get_partner_location_visibility"])
        #expect(transport.openedArgs.value == [["p_couple_id": "\"\(liveCoupleID.uuidString.lowercased())\""]])
        task.cancel()
        await task.value
    }

    @Test func returnsAtOnceWithoutAnActiveCouple() async {
        let transport = PushTransport()
        let session = SyncSession(userID: liveOwnerID, activeCoupleID: nil)

        await makeFeed(store: InMemoryLocationVisibilityRepository())
            .run(session: session, live: LiveQueryService(transport: transport))

        #expect(transport.openedPaths.value.isEmpty)
    }

    @Test func keepsAnUnsentSharingChoiceWhenAPartnerUpdateArrives() async throws {
        let transport = PushTransport()
        let store = InMemoryLocationVisibilityRepository()
        let pending = InMemoryPendingSyncOperationRepository()
        try await store.setViewerSharingEnabled(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            isEnabled: false,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try await pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: liveOwnerID,
            operation: SyncClientOperation(
                id: UUID(),
                clientID: UUID(),
                clientSequence: 1,
                localCreatedAt: Date(timeIntervalSince1970: 100)
            ),
            operationKind: .updateLocationSharingPreference,
            idempotencyScope: "test-location-preference"
        ))
        let session = SyncSession(userID: liveOwnerID, activeCoupleID: liveCoupleID)
        let task = Task {
            await makeFeed(store: store, pending: pending)
                .run(session: session, live: LiveQueryService(transport: transport))
        }

        // The server still says sharing is on, because our opt-out has not been sent.
        await transport.push(visibilityRowJSON(viewerSharing: true))
        let arrived = await waitUntil {
            await stored(in: store)?.partnerLocation != nil
        }
        let current = await stored(in: store)

        #expect(arrived)
        #expect(current?.viewerSharingEnabled == false)
        task.cancel()
        await task.value
    }
}

@MainActor
struct LocationLiveReloadTests {
    private func makeViewModel(
        visibilityStore: InMemoryLocationVisibilityRepository,
        ownLocationStore: InMemoryOwnLocationSnapshotRepository
    ) -> LocationMapViewModel {
        LocationMapViewModel(
            visibilityStore: visibilityStore,
            ownLocationStore: ownLocationStore,
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            locationCapture: LiveTestLocationCapture()
        )
    }

    private func snapshot(
        state: PartnerLocationVisibilityState,
        capturedAt: Date,
        serverStale: Bool = false
    ) -> LocationVisibilitySnapshot {
        LocationVisibilitySnapshot(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            viewerUserID: liveOwnerID,
            partnerUserID: livePartnerID,
            visibilityState: state,
            viewerSharingEnabled: true,
            partnerSharingEnabled: true,
            partnerLocation: LocationPoint(latitude: 59.91, longitude: 10.75, capturedAt: capturedAt),
            partnerLocationIsStale: serverStale,
            updatedAt: Date(),
            refreshedAt: Date()
        )
    }

    private func ownLocation() -> OwnLocationSnapshot {
        OwnLocationSnapshot(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            location: LocationPoint(latitude: 60, longitude: 11, capturedAt: Date()),
            source: .foregroundOpen,
            pendingOperationID: nil,
            updatedAt: Date()
        )
    }

    @Test func rereadsWhenThePartnerChangesAndWhenOwnLocationArrives() async throws {
        let visibilityStore = InMemoryLocationVisibilityRepository()
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        let viewModel = makeViewModel(visibilityStore: visibilityStore, ownLocationStore: ownLocationStore)
        try await visibilityStore.save(snapshot(state: .notSharing, capturedAt: Date()))
        await viewModel.configure(identity: LocationIdentity(currentUserID: liveOwnerID, coupleID: liveCoupleID))
        // Sharing is on but this phone has not found its own location yet.
        #expect(viewModel.mapState == .currentLocationMissing)

        try await ownLocationStore.save(ownLocation())
        // The partner switched sharing on but has not sent a location yet.
        let partnerWaiting = await waitUntil {
            await viewModel.mapState == .waitingForPartnerLocation
        }
        #expect(partnerWaiting)

        try await visibilityStore.save(snapshot(state: .visible, capturedAt: Date()))
        let ready = await waitUntil {
            if case .ready = await viewModel.mapState { return true }
            return false
        }
        #expect(ready)

        try await visibilityStore.save(snapshot(state: .relationshipEnded, capturedAt: Date()))
        let ended = await waitUntil {
            await viewModel.mapState == .partnerUnknown(.relationshipEnded)
        }
        #expect(ended)
    }

    @Test func computesStalenessFromCaptureTimeNotTheServerFlag() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let own = ownLocation()
        let recentButFlagged = snapshot(
            state: .visible,
            capturedAt: now.addingTimeInterval(-60),
            serverStale: true
        )
        let oldButUnflagged = snapshot(
            state: .visible,
            capturedAt: now.addingTimeInterval(-25 * 60 * 60),
            serverStale: false
        )

        let recent = LocationMapViewModel.resolveMapState(visibility: recentButFlagged, ownLocation: own, now: now)
        let old = LocationMapViewModel.resolveMapState(visibility: oldButUnflagged, ownLocation: own, now: now)

        guard case let .ready(_, _, recentStale) = recent, case let .ready(_, _, oldStale) = old else {
            Issue.record("Expected ready states")
            return
        }
        #expect(!recentStale)
        #expect(oldStale)
    }
}

@MainActor
private final class LiveTestLocationCapture: ForegroundLocationCapturing {
    var authorizationState: ForegroundLocationAuthorizationState { .authorized }

    func captureCurrentLocation() throws -> LocationPoint {
        throw ForegroundLocationCaptureError.unavailable
    }
}
