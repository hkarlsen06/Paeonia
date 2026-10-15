import Foundation
import Testing
@testable import PaeoniaApp

struct LocalStoreChangesTests {
    /// Waits for the next change that belongs to `owner`. Other tests post to
    /// the same center, so every assertion filters on a unique owner.
    private func next(
        _ stream: AsyncStream<LocalStoreChange>,
        owner: UUID
    ) async -> LocalStoreChange? {
        for await change in stream where change.ownerUserID == owner {
            return change
        }
        return nil
    }

    @Test func postedChangesReachTheStreamForThatDomain() async {
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .memories)

        LocalStoreChanges.post(.memories, ownerUserID: owner)

        #expect(await next(stream, owner: owner) == LocalStoreChange(domain: .memories, ownerUserID: owner))
    }

    @Test func otherDomainsAreFilteredOut() async {
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .access)

        LocalStoreChanges.post(.memories, ownerUserID: owner)
        LocalStoreChanges.post(.access, ownerUserID: owner)

        #expect(await next(stream, owner: owner)?.domain == .access)
    }

    @Test func aStreamCanWatchSeveralDomainsInWriteOrder() async {
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .ownLocation, .locationVisibility)

        LocalStoreChanges.post(.locationVisibility, ownerUserID: owner)
        LocalStoreChanges.post(.ownLocation, ownerUserID: owner)

        var iterator = stream.filter { $0.ownerUserID == owner }.makeAsyncIterator()
        #expect(await iterator.next()?.domain == .locationVisibility)
        #expect(await iterator.next()?.domain == .ownLocation)
    }

    @Test func changesBeforeSubscribingAreNotReplayed() async {
        let owner = UUID()
        LocalStoreChanges.post(.access, ownerUserID: owner)
        let stream = LocalStoreChanges.changes(in: .access)
        let marker = UUID()

        LocalStoreChanges.post(.access, ownerUserID: marker)

        #expect(await next(stream, owner: marker)?.ownerUserID == marker)
    }

    @Test func aBurstOfIdenticalWritesReachesASlowConsumerOnce() async {
        let owner = UUID()
        let marker = UUID()
        let stream = LocalStoreChanges.changes(in: .access)

        for _ in 0..<50 {
            LocalStoreChanges.post(.access, ownerUserID: owner)
        }
        LocalStoreChanges.post(.access, ownerUserID: marker)

        var received: [UUID?] = []
        for await change in stream where change.ownerUserID == owner || change.ownerUserID == marker {
            received.append(change.ownerUserID)
            if change.ownerUserID == marker {
                break
            }
        }
        #expect(received == [owner, marker])
    }

    @Test func mergingNeverHidesAnotherDomain() async {
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .dailyChallenge, .pendingOperations)

        LocalStoreChanges.post(.dailyChallenge, ownerUserID: owner)
        for _ in 0..<20 {
            LocalStoreChanges.post(.pendingOperations, ownerUserID: owner)
        }

        var iterator = stream.filter { $0.ownerUserID == owner }.makeAsyncIterator()
        #expect(await iterator.next()?.domain == .dailyChallenge)
        #expect(await iterator.next()?.domain == .pendingOperations)
    }

    @Test func cancellingTheConsumerRemovesTheObserver() async {
        let owner = UUID()
        let received = LockedBox(0)
        let consumer = Task {
            for await change in LocalStoreChanges.changes(in: .access) where change.ownerUserID == owner {
                received.mutate { $0 += 1 }
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        LocalStoreChanges.post(.access, ownerUserID: owner)
        #expect(await waitUntil { received.value == 1 })

        consumer.cancel()
        await consumer.value
        LocalStoreChanges.post(.access, ownerUserID: owner)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(received.value == 1)
    }

    // MARK: - Repository writes

    @Test func accessSnapshotWritesPostChanges() async throws {
        let owner = UUID()
        let repository = InMemoryAccessSyncSnapshotRepository()
        let stream = LocalStoreChanges.changes(in: .access)

        try await repository.save(
            AccessSyncSnapshot(ownerUserID: owner, userEntitlement: nil, coupleEntitlement: nil, relationshipState: nil)
        )
        try await repository.delete(ownerUserID: owner)

        var iterator = stream.filter { $0.ownerUserID == owner }.makeAsyncIterator()
        #expect(await iterator.next()?.domain == .access)
        #expect(await iterator.next()?.domain == .access)
    }

    @Test func swiftDataSnapshotWriteWaitsForTheSaveThenPosts() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataAccessSyncSnapshotRepository(container: store.container)
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .access)

        try await repository.save(
            AccessSyncSnapshot(ownerUserID: owner, userEntitlement: nil, coupleEntitlement: nil, relationshipState: nil)
        )

        #expect(await next(stream, owner: owner)?.domain == .access)
        // A view model that re-reads on the change sees the committed row.
        #expect(try await repository.load(ownerUserID: owner)?.ownerUserID == owner)
    }

    @Test func memoryWritesPostChanges() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataMemoryRecordRepository(container: store.container)
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .memories)

        try await repository.saveRemote([], ownerUserID: owner, mergePolicy: .preserveLocalChanges)
        try await repository.deleteAll(ownerUserID: owner)

        var iterator = stream.filter { $0.ownerUserID == owner }.makeAsyncIterator()
        #expect(await iterator.next()?.domain == .memories)
        #expect(await iterator.next()?.domain == .memories)
    }

    @Test func locationWritesPostTheirOwnDomains() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let visibility = SwiftDataLocationVisibilityRepository(container: store.container)
        let owner = UUID()
        let couple = UUID()
        let stream = LocalStoreChanges.changes(in: .locationVisibility)

        try await visibility.setViewerSharingEnabled(
            ownerUserID: owner,
            coupleID: couple,
            isEnabled: true,
            updatedAt: Date()
        )

        #expect(await next(stream, owner: owner)?.domain == .locationVisibility)
    }

    @Test func relationshipEventDeletePostsChanges() async throws {
        let repository = InMemoryRelationshipSyncEventRepository()
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .relationshipEvents)

        try await repository.deleteEvents(ownerUserID: owner)

        #expect(await next(stream, owner: owner)?.domain == .relationshipEvents)
    }

    @Test func pendingOperationEnqueuePostsChanges() async throws {
        let repository = InMemoryPendingSyncOperationRepository()
        let owner = UUID()
        let stream = LocalStoreChanges.changes(in: .pendingOperations)
        let operation = SyncClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: 1,
            localCreatedAt: Date()
        )

        try await repository.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner,
                operation: operation,
                operationKind: .submitDailyAnswer,
                idempotencyScope: "daily:test"
            )
        )

        #expect(await next(stream, owner: owner)?.domain == .pendingOperations)
    }
}
