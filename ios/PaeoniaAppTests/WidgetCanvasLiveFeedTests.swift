import Foundation
import Testing
@testable import PaeoniaApp

struct WidgetCanvasLiveFeedTests {
    private let me = UUID()
    private let couple = UUID()

    @Test func syncsOnlyWhenTheRevisionDiffersFromTheLastSynced() async {
        let env = Env(me: me, couple: couple)
        let revisionA = UUID()
        let revisionB = UUID()
        env.lastSynced.mutate { $0 = revisionA.uuidString }
        await env.start()

        env.push(revision: revisionA)
        env.push(revision: revisionB)
        #expect(await waitUntil { env.syncer.callCount == 1 })

        // The sync marks B as shown, so the same canvas arriving again does nothing.
        env.push(revision: revisionB)
        env.pushEmpty()
        let revisionC = UUID()
        env.push(revision: revisionC)
        #expect(await waitUntil { env.syncer.callCount == 2 })
        #expect(env.syncer.identities.allSatisfy { $0.currentUserID == me })
        #expect(env.syncer.identities.first?.partnerDisplayName == "Partner")
        #expect(env.transport.paths.value == ["widget:get_widget_canvas"])
        #expect(env.transport.args.value.first?["p_couple_id"] == "\"\(couple.uuidString)\"")

        await env.stop()
    }

    @Test func neverRunsTwoSyncsAtOnce() async {
        let env = Env(me: me, couple: couple)
        env.syncer.onSync = nil
        env.syncer.holdSyncs()
        await env.start()

        env.push(revision: UUID())
        #expect(await waitUntil { env.syncer.callCount == 1 })
        env.push(revision: UUID())
        env.push(revision: UUID())
        try? await Task.sleep(for: .milliseconds(50))
        #expect(env.syncer.callCount == 1)

        env.syncer.releaseSyncs()
        #expect(await waitUntil { env.syncer.callCount == 3 })
        #expect(env.syncer.maxConcurrent == 1)

        await env.stop()
    }

    @Test func stopsSyncingAfterCancel() async {
        let env = Env(me: me, couple: couple)
        await env.start()
        env.push(revision: UUID())
        #expect(await waitUntil { env.syncer.callCount == 1 })

        await env.stop()
        env.push(revision: UUID())
        try? await Task.sleep(for: .milliseconds(50))

        #expect(env.syncer.callCount == 1)
    }

    @Test func returnsAtOnceWithoutAnActiveCouple() async {
        let env = Env(me: me, couple: nil)

        await env.feed.run(session: env.session, live: env.live)

        #expect(env.transport.paths.value.isEmpty)
    }
}

private final class Env: @unchecked Sendable {
    let transport = FeedTransport()
    let syncer = SyncSpy()
    let lastSynced = LockedBox<String?>(nil)
    let session: SyncSession
    let live: LiveQueryService
    let feed: WidgetCanvasLiveFeed
    private var task: Task<Void, Never>?

    init(me: UUID, couple: UUID?) {
        session = SyncSession(userID: me, activeCoupleID: couple, relationshipCoupleID: couple)
        live = LiveQueryService(transport: transport)
        let lastSynced = lastSynced
        let syncer = syncer
        syncer.onSync = { revision in lastSynced.mutate { $0 = revision } }
        feed = WidgetCanvasLiveFeed(
            syncer: syncer,
            lastSyncedRevisionID: { lastSynced.value },
            storedIdentity: {
                WidgetSyncIdentity(currentUserID: nil, currentDisplayName: "Me", partnerDisplayName: "Partner")
            }
        )
        syncer.latestRevision = { [transport] in transport.lastRevision.value }
    }

    func start() async {
        task = Task { [feed, session, live] in await feed.run(session: session, live: live) }
        _ = await waitUntil { [transport] in !transport.paths.value.isEmpty }
    }

    func stop() async {
        task?.cancel()
        await task?.value
    }

    func push(revision: UUID) {
        transport.lastRevision.mutate { $0 = revision.uuidString }
        transport.send(
            """
            [{"canvas_id":"\(UUID().uuidString.lowercased())","active_revision_id":"\(revision.uuidString.lowercased())"}]
            """
        )
    }

    func pushEmpty() {
        transport.send("[]")
    }
}

private final class FeedTransport: LiveQueryTransport, @unchecked Sendable {
    let paths = LockedBox<[String]>([])
    let args = LockedBox<[[String: String]]>([])
    let lastRevision = LockedBox<String?>(nil)
    private let continuation = LockedBox<AsyncThrowingStream<Data, any Error>.Continuation?>(nil)

    func updates(path: String, args: [String: String]) -> AsyncThrowingStream<Data, any Error> {
        paths.mutate { $0.append(path) }
        self.args.mutate { $0.append(args) }
        return AsyncThrowingStream { continuation in
            self.continuation.mutate { $0 = continuation }
        }
    }

    func send(_ json: String) {
        continuation.value?.yield(Data(json.utf8))
    }
}

/// Records calls and, like the real service, marks the revision it saw as shown.
private final class SyncSpy: WidgetCanvasSyncing, @unchecked Sendable {
    private let state = LockedBox(State())
    var onSync: (@Sendable (String?) -> Void)?
    var latestRevision: (@Sendable () -> String?)?

    private struct State {
        var identities: [WidgetSyncIdentity] = []
        var running = 0
        var maxConcurrent = 0
        var held = false
    }

    var callCount: Int { state.value.identities.count }
    var identities: [WidgetSyncIdentity] { state.value.identities }
    var maxConcurrent: Int { state.value.maxConcurrent }

    func holdSyncs() { state.mutate { $0.held = true } }
    func releaseSyncs() { state.mutate { $0.held = false } }

    func sync(identity: WidgetSyncIdentity) async {
        state.mutate {
            $0.identities.append(identity)
            $0.running += 1
            $0.maxConcurrent = max($0.maxConcurrent, $0.running)
        }
        while state.value.held {
            try? await Task.sleep(for: .milliseconds(5))
        }
        onSync?(latestRevision?())
        state.mutate { $0.running -= 1 }
    }

    func hideForPrivacy() async {}
    func clearForPrivacy() async {}
}
