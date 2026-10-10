import Foundation
import Testing
@testable import PaeoniaApp

private let liveOwnerID = UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111") ?? UUID()
private let liveCoupleID = UUID(uuidString: "AAAAAAAA-2222-2222-2222-222222222222") ?? UUID()
private let livePartnerID = UUID(uuidString: "AAAAAAAA-3333-3333-3333-333333333333") ?? UUID()

private func visibilityRowJSON(
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
private final class PushTransport: LiveQueryTransport, @unchecked Sendable {
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
    private func stored(in store: InMemoryLocationVisibilitySnapshotRepository) async -> LocationVisibilitySnapshot? {
        (try? await store.load(ownerUserID: liveOwnerID, coupleID: liveCoupleID)) ?? nil
    }

    private func makeFeed(
        store: InMemoryLocationVisibilitySnapshotRepository,
        pending: InMemoryPendingSyncOperationRepository = InMemoryPendingSyncOperationRepository()
    ) -> LocationVisibilityLiveFeed {
        LocationVisibilityLiveFeed(visibilityStore: store, pendingOperationStore: pending)
    }

    @Test func writesTheStoreForEveryValue() async {
        let transport = PushTransport()
        let store = InMemoryLocationVisibilitySnapshotRepository()
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

        await makeFeed(store: InMemoryLocationVisibilitySnapshotRepository())
            .run(session: session, live: LiveQueryService(transport: transport))

        #expect(transport.openedPaths.value.isEmpty)
    }

    @Test func keepsAnUnsentSharingChoiceWhenAPartnerUpdateArrives() async throws {
        let transport = PushTransport()
        let store = InMemoryLocationVisibilitySnapshotRepository()
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

struct LocationSharingChoiceRaceTests {
    private func optOutRequest() -> PendingSyncOperationRequest {
        PendingSyncOperationRequest(
            ownerUserID: liveOwnerID,
            operation: SyncClientOperation(
                id: UUID(),
                clientID: UUID(),
                clientSequence: 1,
                localCreatedAt: Date(timeIntervalSince1970: 100)
            ),
            operationKind: .updateLocationSharingPreference,
            idempotencyScope: "test-location-preference"
        )
    }

    private func serverSnapshot(viewerSharing: Bool) -> LocationVisibilitySnapshot {
        LocationVisibilitySnapshot(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            viewerUserID: liveOwnerID,
            partnerUserID: livePartnerID,
            visibilityState: .visible,
            viewerSharingEnabled: viewerSharing,
            partnerSharingEnabled: true,
            partnerLocation: LocationPoint(latitude: 59.91, longitude: 10.75, capturedAt: Date()),
            partnerLocationIsStale: false,
            updatedAt: Date(),
            refreshedAt: Date()
        )
    }

    private func stored(in store: any LocationVisibilitySnapshotPersisting) async -> LocationVisibilitySnapshot? {
        (try? await store.load(ownerUserID: liveOwnerID, coupleID: liveCoupleID)) ?? nil
    }

    private func optOut(in store: any LocationVisibilitySnapshotPersisting) async throws {
        try await store.setViewerSharingEnabled(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            isEnabled: false,
            updatedAt: Date()
        )
    }

    @Test func feedSaveBetweenTheLocalWriteAndTheEnqueueKeepsTheOptOut() async throws {
        let transport = PushTransport()
        let store = InMemoryLocationVisibilitySnapshotRepository()
        let pending = InMemoryPendingSyncOperationRepository()
        // The opt-out is written locally, the operation is not queued yet.
        try await optOut(in: store)
        let session = SyncSession(userID: liveOwnerID, activeCoupleID: liveCoupleID)
        let task = Task {
            await LocationVisibilityLiveFeed(visibilityStore: store, pendingOperationStore: pending)
                .run(session: session, live: LiveQueryService(transport: transport))
        }

        await transport.push(visibilityRowJSON(viewerSharing: true))
        let arrived = await waitUntil { await stored(in: store)?.partnerLocation != nil }
        let current = await stored(in: store)

        #expect(arrived)
        #expect(current?.viewerSharingEnabled == false)
        #expect(current?.visibilityState == .disabled)
        task.cancel()
        await task.value
    }

    @Test func feedThatReadTheOutboxBeforeTheEnqueueStillKeepsTheOptOut() async throws {
        let transport = PushTransport()
        let store = InMemoryLocationVisibilitySnapshotRepository()
        let pending = InMemoryPendingSyncOperationRepository()
        let gated = OutboxReadGate(inner: pending)
        let session = SyncSession(userID: liveOwnerID, activeCoupleID: liveCoupleID)
        let task = Task {
            await LocationVisibilityLiveFeed(visibilityStore: store, pendingOperationStore: gated)
                .run(session: session, live: LiveQueryService(transport: transport))
        }

        await transport.push(visibilityRowJSON(viewerSharing: true))
        // The feed has read an empty outbox and waits before it saves.
        await gated.waitUntilReadFinishes()
        try await optOut(in: store)
        try await pending.enqueue(optOutRequest())
        await gated.release()

        let arrived = await waitUntil { await stored(in: store)?.partnerLocation != nil }
        #expect(arrived)
        #expect(await stored(in: store)?.viewerSharingEnabled == false)
        task.cancel()
        await task.value
    }

    @Test func choiceStaysUntilTheServerConfirmsIt() async throws {
        let store = InMemoryLocationVisibilitySnapshotRepository()
        try await optOut(in: store)

        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: false)
        #expect(await stored(in: store)?.viewerSharingEnabled == false)

        // The server now agrees, which clears the pending choice.
        try await store.saveRemote(serverSnapshot(viewerSharing: false), preservingLocalSharingChoiceIf: false)
        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: false)
        #expect(await stored(in: store)?.viewerSharingEnabled == true)
    }

    @Test func confirmedChoiceLetsServerValuesThrough() async throws {
        let store = InMemoryLocationVisibilitySnapshotRepository()
        try await optOut(in: store)

        try await store.confirmViewerSharing(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            isEnabled: false,
            updatedAt: Date(),
            otherChoicesPending: false
        )
        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: false)

        #expect(await stored(in: store)?.viewerSharingEnabled == true)
    }

    @Test func outboxOperationKeepsTheChoiceAfterARelaunchLosesTheMarker() async throws {
        let store = InMemoryLocationVisibilitySnapshotRepository()
        try await store.save(serverSnapshot(viewerSharing: false))

        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: true)

        #expect(await stored(in: store)?.viewerSharingEnabled == false)
    }

    @Test func separateSwiftDataRepositoriesShareThePendingChoice() async throws {
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let owner = UUID()
        let couple = UUID()
        let viewModelSide = SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container)
        let feedSide = SwiftDataLocationVisibilitySnapshotRepository(container: localStore.container)
        func server(_ viewerSharing: Bool) -> LocationVisibilitySnapshot {
            LocationVisibilitySnapshot(
                ownerUserID: owner,
                coupleID: couple,
                viewerUserID: owner,
                partnerUserID: livePartnerID,
                visibilityState: .visible,
                viewerSharingEnabled: viewerSharing,
                partnerSharingEnabled: true,
                partnerLocation: nil,
                partnerLocationIsStale: false,
                updatedAt: Date(),
                refreshedAt: Date()
            )
        }
        try await feedSide.save(server(true))

        try await viewModelSide.setViewerSharingEnabled(
            ownerUserID: owner,
            coupleID: couple,
            isEnabled: false,
            updatedAt: Date()
        )
        try await feedSide.saveRemote(server(true), preservingLocalSharingChoiceIf: false)
        #expect(try await viewModelSide.load(ownerUserID: owner, coupleID: couple)?.viewerSharingEnabled == false)

        try await viewModelSide.confirmViewerSharing(
            ownerUserID: owner,
            coupleID: couple,
            isEnabled: false,
            updatedAt: Date(),
            otherChoicesPending: false
        )
        try await feedSide.saveRemote(server(true), preservingLocalSharingChoiceIf: false)
        #expect(try await viewModelSide.load(ownerUserID: owner, coupleID: couple)?.viewerSharingEnabled == true)
    }

    @Test func failedSaveRestoreDoesNotLeaveAPendingChoice() async throws {
        let store = InMemoryLocationVisibilitySnapshotRepository()
        try await store.save(serverSnapshot(viewerSharing: true))
        try await optOut(in: store)

        try await store.setViewerSharingEnabled(
            ownerUserID: liveOwnerID,
            coupleID: liveCoupleID,
            isEnabled: true,
            updatedAt: Date(),
            isPendingConfirmation: false
        )
        try await store.saveRemote(serverSnapshot(viewerSharing: false), preservingLocalSharingChoiceIf: false)

        #expect(await stored(in: store)?.viewerSharingEnabled == false)
    }
}

/// Wraps an outbox. The first read of in-flight operations returns, then waits
/// until the test releases it, so the test can act between the read and the save.
private actor OutboxReadGate: PendingSyncOperationPersisting {
    private let inner: InMemoryPendingSyncOperationRepository
    private var hasRead = false
    private var isReleased = false
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(inner: InMemoryPendingSyncOperationRepository) {
        self.inner = inner
    }

    func waitUntilReadFinishes() async {
        guard !hasRead else { return }
        await withCheckedContinuation { readWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters = []
    }

    func inFlightOperations(
        ownerUserID: UUID,
        kind: SyncPendingOperationKind
    ) async throws -> [PendingSyncOperationSnapshot] {
        let result = try await inner.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
        if !hasRead {
            hasRead = true
            readWaiters.forEach { $0.resume() }
            readWaiters = []
            if !isReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
        }
        return result
    }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        try await inner.enqueue(request)
    }

    func readyOperations(
        ownerUserID: UUID,
        limit: Int,
        now: Date
    ) async throws -> [PendingSyncOperationSnapshot] {
        try await inner.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await inner.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await inner.markSending(clientOperationID: clientOperationID, at: date)
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await inner.markSucceeded(clientOperationID: clientOperationID, at: date)
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        errorDescription: String,
        nextRetryAt: Date?,
        at date: Date
    ) async throws {
        try await inner.markRetryableFailure(
            clientOperationID: clientOperationID,
            errorDescription: errorDescription,
            nextRetryAt: nextRetryAt,
            at: date
        )
    }

    func markTerminalFailure(
        clientOperationID: UUID,
        errorDescription: String,
        at date: Date
    ) async throws {
        try await inner.markTerminalFailure(
            clientOperationID: clientOperationID,
            errorDescription: errorDescription,
            at: date
        )
    }

    func deleteCompleted(ownerUserID: UUID) async throws {
        try await inner.deleteCompleted(ownerUserID: ownerUserID)
    }

    func resetInFlight(ownerUserID: UUID) async throws {
        try await inner.resetInFlight(ownerUserID: ownerUserID)
    }
}

@MainActor
struct LocationLiveReloadTests {
    private func makeViewModel(
        visibilityStore: InMemoryLocationVisibilitySnapshotRepository,
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
        let visibilityStore = InMemoryLocationVisibilitySnapshotRepository()
        let ownLocationStore = InMemoryOwnLocationSnapshotRepository()
        let viewModel = makeViewModel(visibilityStore: visibilityStore, ownLocationStore: ownLocationStore)
        try await visibilityStore.save(snapshot(state: .notSharing, capturedAt: Date()))
        await viewModel.configure(identity: LocationIdentity(currentUserID: liveOwnerID, coupleID: liveCoupleID))
        #expect(viewModel.mapState == .currentUnknown)

        try await ownLocationStore.save(ownLocation())
        let partnerNotSharing = await waitUntil {
            await viewModel.mapState == .partnerUnknown(.notSharing)
        }
        #expect(partnerNotSharing)

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

    func captureCurrentLocation() async throws -> LocationPoint {
        throw ForegroundLocationCaptureError.unavailable
    }
}
