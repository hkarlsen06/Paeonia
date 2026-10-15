import Foundation
import Testing
@testable import PaeoniaApp

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
        (try? await store.load(ownerUserID: liveOwnerID, coupleID: liveCoupleID))
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
        let store = InMemoryLocationVisibilityRepository()
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
        let store = InMemoryLocationVisibilityRepository()
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
        let store = InMemoryLocationVisibilityRepository()
        try await optOut(in: store)

        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: false)
        #expect(await stored(in: store)?.viewerSharingEnabled == false)

        // The server now agrees, which clears the pending choice.
        try await store.saveRemote(serverSnapshot(viewerSharing: false), preservingLocalSharingChoiceIf: false)
        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: false)
        #expect(await stored(in: store)?.viewerSharingEnabled == true)
    }

    @Test func confirmedChoiceLetsServerValuesThrough() async throws {
        let store = InMemoryLocationVisibilityRepository()
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
        let store = InMemoryLocationVisibilityRepository()
        try await store.save(serverSnapshot(viewerSharing: false))

        try await store.saveRemote(serverSnapshot(viewerSharing: true), preservingLocalSharingChoiceIf: true)

        #expect(await stored(in: store)?.viewerSharingEnabled == false)
    }

    @Test func separateSwiftDataRepositoriesShareThePendingChoice() async throws {
        let localStore = try PaeoniaLocalStore(inMemory: true)
        let owner = UUID()
        let couple = UUID()
        let viewModelSide = SwiftDataLocationVisibilityRepository(container: localStore.container)
        let feedSide = SwiftDataLocationVisibilityRepository(container: localStore.container)
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
        let store = InMemoryLocationVisibilityRepository()
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
