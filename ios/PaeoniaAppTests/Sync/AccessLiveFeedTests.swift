import Foundation
import Testing
@testable import PaeoniaApp

/// Plays pushed JSON into every subscription the feed opens, and records them.
final class RecordingLiveTransport: LiveQueryTransport, @unchecked Sendable {
    let paths = LockedBox<[String]>([])
    let args = LockedBox<[[String: String]]>([])
    private let continuations = LockedBox<[AsyncThrowingStream<Data, any Error>.Continuation]>([])

    var subscriptionCount: Int {
        paths.value.count
    }

    func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        paths.mutate { $0.append(path) }
        self.args.mutate { $0.append(args) }
        return AsyncThrowingStream { continuation in
            self.continuations.mutate { $0.append(continuation) }
        }
    }

    /// Sends to the newest subscription, like the server pushes to the live one.
    func send(_ value: some Encodable) throws {
        let data = try PaeoniaConvexClient.encoder.encode(value)
        continuations.value.last?.yield(data)
    }
}

struct AccessLiveFeedTests {
    private let ownerUserID = UUID()
    private let coupleID = UUID()

    @Test func writesTheSnapshotIntoTheStore() async throws {
        let env = AccessFeedEnv(ownerUserID: ownerUserID)
        await env.start()

        try env.transport.send([RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID)])

        #expect(await waitUntil { (try? await env.store.load(ownerUserID: ownerUserID)) != nil })
        let stored = try await env.store.load(ownerUserID: ownerUserID)
        #expect(stored?.relationshipState?.coupleID == coupleID)
        #expect(stored?.relationshipState?.partnerDisplayName == "Alex")
        #expect(stored?.coupleEntitlement?.isEntitled == true)
        #expect(stored?.userEntitlement?.userID == ownerUserID)
        #expect(env.transport.paths.value == ["access:get_access_snapshot"])
        await env.stop()
    }

    @Test func partnerChangesReplaceTheStoredSnapshot() async throws {
        let env = AccessFeedEnv(ownerUserID: ownerUserID)
        await env.start()
        try env.transport.send([RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID)])
        #expect(await waitUntil { (try? await env.store.load(ownerUserID: ownerUserID)) != nil })

        try env.transport.send([
            RemoteAccessSnapshot.paired(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                partnerDisplayName: "Alexandra",
                startedOn: "2025-01-02"
            )
        ])

        #expect(await waitUntil {
            (try? await env.store.load(ownerUserID: ownerUserID))?.relationshipState?.startedOn == "2025-01-02"
        })
        let stored = try await env.store.load(ownerUserID: ownerUserID)
        #expect(stored?.relationshipState?.partnerDisplayName == "Alexandra")
        await env.stop()
    }

    @Test func storesAnEndedRelationshipAndLostEntitlement() async throws {
        let env = AccessFeedEnv(ownerUserID: ownerUserID)
        await env.start()

        try env.transport.send([
            RemoteAccessSnapshot.paired(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                status: .ended,
                memberStatus: .endedNoticePending,
                coupleEntitled: false
            )
        ])

        #expect(await waitUntil { (try? await env.store.load(ownerUserID: ownerUserID)) != nil })
        let stored = try await env.store.load(ownerUserID: ownerUserID)
        #expect(stored?.relationshipState?.needsEndedNotice == true)
        #expect(stored?.coupleEntitlement?.isEntitled == false)
        await env.stop()
    }

    @Test func anUnchangedSnapshotIsNotWrittenAgain() async throws {
        let env = AccessFeedEnv(ownerUserID: ownerUserID)
        let writes = LockedBox(0)
        let ownerUserID = ownerUserID
        let changes = LocalStoreChanges.changes(in: .access)
        let observer = Task {
            for await change in changes where change.ownerUserID == ownerUserID {
                writes.mutate { $0 += 1 }
            }
        }
        await env.start()
        let snapshot = RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID)

        try env.transport.send([snapshot])
        #expect(await waitUntil { writes.value == 1 })
        try env.transport.send([snapshot])
        try env.transport.send([snapshot])
        try? await Task.sleep(for: .milliseconds(80))

        #expect(writes.value == 1)
        await env.stop()
        observer.cancel()
    }

    @Test func anEmptyResultStoresAnEmptySnapshot() async throws {
        let env = AccessFeedEnv(ownerUserID: ownerUserID)
        await env.start()

        try env.transport.send([RemoteAccessSnapshot]())

        #expect(await waitUntil { (try? await env.store.load(ownerUserID: ownerUserID)) != nil })
        let stored = try await env.store.load(ownerUserID: ownerUserID)
        #expect(stored?.relationshipState == nil)
        #expect(stored?.userEntitlement == nil)
        await env.stop()
    }

    @Test func stopsWritingAfterCancel() async throws {
        let env = AccessFeedEnv(ownerUserID: ownerUserID)
        await env.start()
        await env.stop()

        try env.transport.send([RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID)])
        try? await Task.sleep(for: .milliseconds(80))

        #expect(try await env.store.load(ownerUserID: ownerUserID) == nil)
    }
}

private final class AccessFeedEnv: @unchecked Sendable {
    let transport = RecordingLiveTransport()
    let store = InMemoryAccessSyncSnapshotRepository()
    let session: SyncSession
    private let feed: AccessLiveFeed
    private let live: LiveQueryService
    private var task: Task<Void, Never>?

    init(ownerUserID: UUID) {
        session = SyncSession(userID: ownerUserID)
        feed = AccessLiveFeed(snapshotStore: store)
        live = LiveQueryService(transport: transport)
    }

    func start() async {
        task = Task { [feed, session, live] in await feed.run(session: session, live: live) }
        _ = await waitUntil { [transport] in transport.subscriptionCount == 1 }
    }

    func stop() async {
        task?.cancel()
        await task?.value
    }
}

extension RemoteAccessSnapshot {
    private static let pairID = UUID()
    private static let partnerUserID = UUID()

    static func paired(
        ownerUserID: UUID,
        coupleID: UUID,
        partnerDisplayName: String = "Alex",
        startedOn: String = "2024-06-24",
        status: RemoteRelationshipStatus = .active,
        memberStatus: RemoteRelationshipMemberStatus = .active,
        coupleEntitled: Bool = true
    ) -> RemoteAccessSnapshot {
        RemoteAccessSnapshot(
            userEntitlement: RemoteUserEntitlement(
                userID: ownerUserID,
                isEntitled: true,
                source: "storekit",
                status: "active",
                productID: nil,
                billingPeriod: nil,
                currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            coupleEntitlement: RemoteCoupleEntitlement(
                coupleID: coupleID,
                isEntitled: coupleEntitled,
                coveringUserID: ownerUserID,
                source: "storekit",
                status: coupleEntitled ? "active" : "expired",
                productID: nil,
                billingPeriod: nil,
                currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            relationshipState: RemoteRelationshipState(
                coupleID: coupleID,
                pairID: pairID,
                relationshipStatus: status,
                memberStatus: memberStatus,
                acceptedInvite: false,
                partnerUserID: partnerUserID,
                partnerDisplayName: partnerDisplayName,
                partnerProfilePhotoAssetID: nil,
                startedOn: startedOn,
                endedAt: nil,
                deleteAfter: nil,
                endedNoticeSeenAt: nil
            )
        )
    }
}
