import Foundation
import Testing
@testable import PaeoniaApp

extension MemoryRemoteRow {
    static func fixture(
        ownerUserID: UUID,
        memoryID: UUID,
        coupleID: UUID,
        title: String,
        memoryDate: String = "2026-06-30",
        revision: Int = 1,
        deletedAt: Date? = nil,
        ownNoteRevision: Int? = nil,
        memoryMediaIDs: [UUID] = [],
        syncUpdatedAt: Date
    ) -> MemoryRemoteRow {
        MemoryRemoteRow(
            memoryID: memoryID,
            coupleID: coupleID,
            title: title,
            memoryDate: memoryDate,
            place: nil,
            createdByUserID: ownerUserID,
            lastEditedByUserID: ownerUserID,
            revision: revision,
            moderationStatus: .visible,
            deletedAt: deletedAt,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: syncUpdatedAt,
            syncUpdatedAt: syncUpdatedAt,
            ownNoteID: nil,
            ownNoteBody: nil,
            ownNoteRevision: ownNoteRevision,
            ownNoteUpdatedAt: nil,
            ownNoteDeletedAt: nil,
            ownNoteModerationStatus: nil,
            partnerNoteID: nil,
            partnerNoteUserID: nil,
            partnerNoteBody: nil,
            partnerNoteRevision: nil,
            partnerNoteUpdatedAt: nil,
            partnerNoteDeletedAt: nil,
            partnerNoteModerationStatus: nil,
            memoryMediaIDs: memoryMediaIDs,
            mediaAssetIDs: memoryMediaIDs,
            memoryMediaStates: [],
            threadID: nil
        )
    }
}

struct MemoryLiveFeedTests {
    /// Keeps every subscription open so the test decides what each one yields. Each
    /// subscription is recorded in one step with its continuation, and the accessors
    /// wait for a subscription to open (or throw), so a slow machine fails a test
    /// instead of crashing the test host on an out-of-range index.
    private final class PushTransport: LiveQueryTransport, @unchecked Sendable {
        struct Subscription {
            let path: String
            let args: [String: String]
            let continuation: AsyncThrowingStream<Data, any Error>.Continuation
        }

        struct SubscriptionNeverOpened: Error {
            let index: Int
        }

        private let subscriptions = LockedBox<[Subscription]>([])

        var openCount: Int {
            subscriptions.value.count
        }

        func subscription(_ index: Int) async throws -> Subscription {
            _ = await waitUntil(timeout: .seconds(10)) { self.subscriptions.value.count > index }
            let opened = subscriptions.value
            guard opened.indices.contains(index) else { throw SubscriptionNeverOpened(index: index) }
            return opened[index]
        }

        func args(ofSubscription index: Int) async throws -> [String: String] {
            try await subscription(index).args
        }

        func path(ofSubscription index: Int) async throws -> String {
            try await subscription(index).path
        }

        func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
            AsyncThrowingStream { continuation in
                subscriptions.mutate { $0.append(Subscription(path: path, args: args, continuation: continuation)) }
            }
        }

        func send(_ rows: [MemoryRemoteRow], toSubscription index: Int) async throws {
            let data = try PaeoniaConvexClient.encoder.encode(rows)
            try await subscription(index).continuation.yield(data)
        }
    }

    private struct Environment {
        let feed: MemoryLiveFeed
        let live: LiveQueryService
        let transport: PushTransport
        let memoryStore: InMemoryMemoryRecordRepository
        let stateStore: InMemorySyncStateRepository
        let session: SyncSession
    }

    private static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    private static let coupleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
    private static let firstID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
    private static let secondID = UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID()
    private static let thirdID = UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()

    private static func makeEnvironment(coupleID: UUID? = coupleID) -> Environment {
        let memoryStore = InMemoryMemoryRecordRepository()
        let stateStore = InMemorySyncStateRepository()
        let transport = PushTransport()
        return Environment(
            feed: MemoryLiveFeed(memoryStore: memoryStore, stateStore: stateStore, retryDelay: .milliseconds(5)),
            live: LiveQueryService(transport: transport),
            transport: transport,
            memoryStore: memoryStore,
            stateStore: stateStore,
            session: SyncSession(userID: userID, activeCoupleID: coupleID)
        )
    }

    private static func row(
        _ id: UUID,
        title: String,
        at seconds: TimeInterval,
        revision: Int = 1,
        deletedAt: Date? = nil
    ) -> MemoryRemoteRow {
        .fixture(
            ownerUserID: userID,
            memoryID: id,
            coupleID: coupleID,
            title: title,
            revision: revision,
            deletedAt: deletedAt,
            syncUpdatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private static func storedCursor(_ env: Environment) async -> SyncCursor? {
        try? await env.stateStore.cursor(
            ownerUserID: userID,
            scope: SyncStreamScope(kind: .couple, id: coupleID),
            streamKey: .memories
        )
    }

    private static func stop(_ task: Task<Void, Never>) async {
        task.cancel()
        await task.value
    }

    @Test func firstSubscriptionStartsFromTheBeginningAndSavesTheRows() async throws {
        let env = Self.makeEnvironment()
        let task = Task { await env.feed.run(session: env.session, live: env.live) }

        #expect(await waitUntil { env.transport.openCount == 1 })
        #expect(try await env.transport.path(ofSubscription: 0) == "memories:get_memories")
        #expect(try await env.transport.args(ofSubscription: 0).isEmpty)
        try await env.transport.send(
            [Self.row(Self.firstID, title: "First", at: 100), Self.row(Self.secondID, title: "Second", at: 200)],
            toSubscription: 0
        )

        #expect(await waitUntil {
            ((try? await env.memoryStore.load(ownerUserID: Self.userID, includeHidden: true)) ?? []).count == 2
        })
        await Self.stop(task)
    }

    @Test func pagesThroughHistoryByResubscribingFromTheLastRow() async throws {
        let env = Self.makeEnvironment()
        let task = Task { await env.feed.run(session: env.session, live: env.live) }
        #expect(await waitUntil { env.transport.openCount == 1 })

        try await env.transport.send([Self.row(Self.firstID, title: "First", at: 100)], toSubscription: 0)
        #expect(await waitUntil { env.transport.openCount == 2 })
        try await env.transport.send([Self.row(Self.secondID, title: "Second", at: 200)], toSubscription: 1)
        #expect(await waitUntil { env.transport.openCount == 3 })

        let args = try await env.transport.args(ofSubscription: 2)
        #expect(args["p_updated_after"] == "\"1970-01-01T00:03:20.000Z\"")
        #expect(args["p_cursor_memory_id"] == "\"\(Self.secondID.uuidString)\"")
        #expect(await Self.storedCursor(env) == SyncCursor(
            updatedAt: Date(timeIntervalSince1970: 200),
            tieID: Self.secondID
        ))
        await Self.stop(task)
    }

    @Test func resumesFromTheStoredCursorAfterARestart() async throws {
        let env = Self.makeEnvironment()
        try await env.stateStore.markSucceeded(
            ownerUserID: Self.userID,
            scope: SyncStreamScope(kind: .couple, id: Self.coupleID),
            streamKey: .memories,
            cursor: SyncCursor(updatedAt: Date(timeIntervalSince1970: 1_000.123), tieID: Self.firstID),
            at: Date()
        )
        let task = Task { await env.feed.run(session: env.session, live: env.live) }

        #expect(await waitUntil { env.transport.openCount == 1 })
        let args = try await env.transport.args(ofSubscription: 0)
        #expect(args["p_updated_after"] == "\"1970-01-01T00:16:40.123Z\"")
        #expect(args["p_cursor_memory_id"] == "\"\(Self.firstID.uuidString)\"")
        await Self.stop(task)
    }

    @Test func aLiveUpdateFromThePartnerIsSavedAndAHiddenMemoryLeavesTheTimeline() async throws {
        let env = Self.makeEnvironment()
        let task = Task { await env.feed.run(session: env.session, live: env.live) }
        #expect(await waitUntil { env.transport.openCount == 1 })
        try await env.transport.send([Self.row(Self.firstID, title: "First", at: 100)], toSubscription: 0)
        #expect(await waitUntil { env.transport.openCount == 2 })

        try await env.transport.send([Self.row(Self.thirdID, title: "Partner's", at: 300)], toSubscription: 1)
        #expect(await waitUntil {
            ((try? await env.memoryStore.load(ownerUserID: Self.userID, includeHidden: false)) ?? []).count == 2
        })

        try await env.transport.send(
            [
                Self.row(
                    Self.thirdID,
                    title: "Partner's",
                    at: 400,
                    revision: 2,
                    deletedAt: Date(timeIntervalSince1970: 400)
                )
            ],
            toSubscription: 2
        )
        #expect(await waitUntil {
            ((try? await env.memoryStore.load(ownerUserID: Self.userID, includeHidden: false)) ?? []).count == 1
        })
        await Self.stop(task)
    }

    @Test func rowsNeverOverwriteALocalRecordWithQueuedChanges() async throws {
        let env = Self.makeEnvironment()
        try await env.memoryStore.saveRemote(
            [Self.row(Self.firstID, title: "Mine", at: 50)],
            ownerUserID: Self.userID,
            mergePolicy: .overwriteLocalChanges
        )
        var local = try #require(await env.memoryStore.load(ownerUserID: Self.userID, memoryID: Self.firstID))
        local.syncStatus = .dirty
        try await env.memoryStore.saveLocal(local)
        let task = Task { await env.feed.run(session: env.session, live: env.live) }
        #expect(await waitUntil { env.transport.openCount == 1 })

        try await env.transport.send(
            [
                Self.row(Self.firstID, title: "Server", at: 100, revision: 2),
                Self.row(Self.secondID, title: "Other", at: 200)
            ],
            toSubscription: 0
        )
        #expect(await waitUntil { env.transport.openCount == 2 })

        let kept = try #require(await env.memoryStore.load(ownerUserID: Self.userID, memoryID: Self.firstID))
        #expect(kept.snapshot.title == "Mine")
        #expect(kept.syncStatus == .dirty)
        let added = try await env.memoryStore.load(ownerUserID: Self.userID, memoryID: Self.secondID)
        #expect(added?.snapshot.title == "Other")
        await Self.stop(task)
    }

    @Test func stopsWritingAfterCancellation() async throws {
        let env = Self.makeEnvironment()
        let task = Task { await env.feed.run(session: env.session, live: env.live) }
        #expect(await waitUntil { env.transport.openCount == 1 })

        await Self.stop(task)
        try await env.transport.send([Self.row(Self.firstID, title: "Late", at: 100)], toSubscription: 0)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(try await env.memoryStore.load(ownerUserID: Self.userID, includeHidden: true).isEmpty)
        #expect(await Self.storedCursor(env) == SyncCursor())
        #expect(env.transport.openCount == 1)
    }
}
