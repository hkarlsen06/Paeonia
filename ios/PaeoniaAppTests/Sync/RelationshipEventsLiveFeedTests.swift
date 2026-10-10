import Foundation
import Testing
@testable import PaeoniaApp

struct RelationshipEventsLiveFeedTests {
    private let ownerUserID = UUID()

    @Test func savesAppliesAndResubscribesFromTheLastEvent() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let first = try event(id: "22222222-2222-2222-2222-222222222222", createdAt: 100)
        let second = try event(id: "33333333-3333-3333-3333-333333333333", createdAt: 200)
        await env.start()

        // The first subscription starts from the beginning.
        let firstArgs = try #require(env.transport.args.value.first)
        #expect(firstArgs["p_after_created_at"] == nil)
        #expect(firstArgs["p_after_id"] == nil)
        #expect(firstArgs["p_limit"] != nil)

        try env.transport.send([first, second])

        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        #expect(try await env.eventStore.events(ownerUserID: ownerUserID).map(\.id) == [first.id, second.id])
        #expect(await env.applier.appliedEventIDs == [first.id, second.id])
        let cursor = try await env.stateStore.cursor(
            ownerUserID: ownerUserID,
            scope: SyncStreamScope(kind: .user),
            streamKey: .relationshipEvents
        )
        #expect(cursor == SyncCursor(updatedAt: second.createdAt, tieID: second.id))

        // The next subscription asks only for events after the last one.
        let nextArgs = env.transport.args.value[1]
        #expect(nextArgs["p_after_id"] == "\"\(second.id.uuidString)\"")
        #expect(nextArgs["p_after_created_at"]?.contains("1970-01-01T00:03:20") == true)
        #expect(env.transport.paths.value.allSatisfy { $0 == "relationship:get_relationship_sync_events" })
        await env.stop()
    }

    @Test func eventsArrivingLaterAreAppliedInOrder() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let first = try event(id: "22222222-2222-2222-2222-222222222222", createdAt: 100)
        let second = try event(id: "33333333-3333-3333-3333-333333333333", createdAt: 200)
        await env.start()

        try env.transport.send([first])
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        try env.transport.send([RemoteRelationshipSyncEvent]())
        try env.transport.send([second])
        #expect(await waitUntil { env.transport.subscriptionCount == 3 })

        #expect(await env.applier.appliedEventIDs == [first.id, second.id])
        await env.stop()
    }

    @Test func startsFromTheSavedCursor() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let tieID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        try await env.stateStore.markSucceeded(
            ownerUserID: ownerUserID,
            scope: SyncStreamScope(kind: .user),
            streamKey: .relationshipEvents,
            cursor: SyncCursor(updatedAt: Date(timeIntervalSince1970: 100), tieID: tieID),
            at: Date()
        )

        await env.start()

        let args = try #require(env.transport.args.value.first)
        #expect(args["p_after_id"] == "\"\(tieID.uuidString)\"")
        #expect(args["p_after_created_at"] != nil)
        await env.stop()
    }

    @Test func aFailedApplyKeepsTheCursorAndRetriesTheSameEvents() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID, failingApplies: 1)
        let only = try event(id: "22222222-2222-2222-2222-222222222222", createdAt: 100)
        await env.start()

        try env.transport.send([only])
        // The retry subscribes again from the old cursor.
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        #expect(env.transport.args.value[1]["p_after_id"] == nil)
        let cursorAfterFailure = try await env.stateStore.cursor(
            ownerUserID: ownerUserID,
            scope: SyncStreamScope(kind: .user),
            streamKey: .relationshipEvents
        )
        #expect(cursorAfterFailure == SyncCursor())

        try env.transport.send([only])
        #expect(await waitUntil { env.transport.subscriptionCount == 3 })
        #expect(await env.applier.appliedEventIDs == [only.id])
        #expect(env.transport.args.value[2]["p_after_id"] == "\"\(only.id.uuidString)\"")
        await env.stop()
    }

    @Test func stopsAfterCancel() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        await env.start()
        await env.stop()

        try env.transport.send([try event(id: "22222222-2222-2222-2222-222222222222", createdAt: 100)])
        try? await Task.sleep(for: .milliseconds(80))

        #expect(try await env.eventStore.events(ownerUserID: ownerUserID).isEmpty)
        #expect(await env.applier.appliedEventIDs.isEmpty)
    }

    @Test func replayedEntitlementLossIsSkippedWhenAccessIsEntitledNow() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let coupleID = UUID()
        let lost = try event(
            id: "22222222-2222-2222-2222-222222222222",
            createdAt: 100,
            coupleID: coupleID,
            eventKind: "entitlement_lost"
        )
        await env.start()

        try env.transport.send([lost])
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        #expect(env.transport.paths.value[1] == "access:get_access_snapshot")
        try env.transport.send([RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID)])
        #expect(await waitUntil { env.transport.subscriptionCount == 3 })

        #expect(await env.applier.appliedEventIDs.isEmpty)
        #expect(try await env.eventStore.events(ownerUserID: ownerUserID).map(\.id) == [lost.id])
        let cursor = try await env.stateStore.cursor(
            ownerUserID: ownerUserID,
            scope: SyncStreamScope(kind: .user),
            streamKey: .relationshipEvents
        )
        #expect(cursor == SyncCursor(updatedAt: lost.createdAt, tieID: lost.id))
        await env.stop()
    }

    @Test func ongoingEntitlementLossIsStillApplied() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let coupleID = UUID()
        let lost = try event(
            id: "22222222-2222-2222-2222-222222222222",
            createdAt: 100,
            coupleID: coupleID,
            eventKind: "entitlement_lost"
        )
        await env.start()

        try env.transport.send([lost])
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        try env.transport.send([
            RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID, coupleEntitled: false)
        ])
        #expect(await waitUntil { env.transport.subscriptionCount == 3 })

        #expect(await env.applier.appliedEventIDs == [lost.id])
        await env.stop()
    }

    @Test func entitlementLossForAnotherCoupleIsStillApplied() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let lost = try event(
            id: "22222222-2222-2222-2222-222222222222",
            createdAt: 100,
            eventKind: "entitlement_lost"
        )
        await env.start()

        try env.transport.send([lost])
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        try env.transport.send([RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: UUID())])
        #expect(await waitUntil { env.transport.subscriptionCount == 3 })

        // The applier compares the couple with its own session.
        #expect(await env.applier.appliedEventIDs == [lost.id])
        await env.stop()
    }

    @Test func relationshipEndIsAppliedWithoutReadingAccess() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let ended = try event(
            id: "22222222-2222-2222-2222-222222222222",
            createdAt: 100,
            eventKind: "relationship_ended"
        )
        await env.start()

        try env.transport.send([ended])
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })

        #expect(await env.applier.appliedEventIDs == [ended.id])
        #expect(env.transport.paths.value.allSatisfy { $0 == "relationship:get_relationship_sync_events" })
        await env.stop()
    }

    @Test func renewedLossDoesNotHideARelationshipEndInTheSameBatch() async throws {
        let env = EventsFeedEnv(ownerUserID: ownerUserID)
        let coupleID = UUID()
        let lost = try event(
            id: "22222222-2222-2222-2222-222222222222",
            createdAt: 100,
            coupleID: coupleID,
            eventKind: "entitlement_lost"
        )
        let ended = try event(
            id: "33333333-3333-3333-3333-333333333333",
            createdAt: 200,
            coupleID: coupleID,
            eventKind: "relationship_ended"
        )
        await env.start()

        try env.transport.send([lost, ended])
        #expect(await waitUntil { env.transport.subscriptionCount == 2 })
        try env.transport.send([RemoteAccessSnapshot.paired(ownerUserID: ownerUserID, coupleID: coupleID)])
        #expect(await waitUntil { env.transport.subscriptionCount == 3 })

        #expect(await env.applier.appliedEventIDs == [ended.id])
        await env.stop()
    }

    private func event(
        id: String,
        createdAt: TimeInterval,
        coupleID: UUID = UUID(),
        eventKind: String = "relationship_updated"
    ) throws -> RemoteRelationshipSyncEvent {
        RemoteRelationshipSyncEvent(
            id: try #require(UUID(uuidString: id)),
            userID: ownerUserID,
            coupleID: coupleID,
            initiatedByUserID: nil,
            eventKind: eventKind,
            reason: nil,
            occurredAt: Date(timeIntervalSince1970: createdAt),
            relationshipStatus: "active",
            memberStatus: "active",
            endedAt: nil,
            deleteAfter: nil,
            localPurgeScope: [:],
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

struct RelationshipSyncEventApplierTests {
    @Test func entitlementLossHidesCachesWithoutPurgingOwnedContent() async throws {
        let ownerUserID = UUID()
        let coupleID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let accessLossEvent = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: coupleID,
            createdAt: 100,
            eventKind: "entitlement_lost",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "preserve"
            ]
        )

        try await applier.apply(
            [accessLossEvent],
            session: session(ownerUserID: ownerUserID, relationshipCoupleID: coupleID)
        )

        #expect(
            await privacyPurger.calls == [
                PrivacyPurgeCall(ownerUserID: ownerUserID, scope: .relationshipAccessHidden)
            ]
        )
    }

    @Test func relationshipEndReviewPurgesContentBecauseMVPHasNoRecoverySurface() async throws {
        let ownerUserID = UUID()
        let coupleID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let relationshipEndEvent = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: coupleID,
            createdAt: 100,
            eventKind: "relationship_ended",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "review"
            ]
        )

        try await applier.apply(
            [relationshipEndEvent],
            session: session(ownerUserID: ownerUserID, relationshipCoupleID: coupleID)
        )

        #expect(
            await privacyPurger.calls == [
                PrivacyPurgeCall(
                    ownerUserID: ownerUserID,
                    scope: .relationshipContentPurged(clearAccessSnapshot: false)
                )
            ]
        )
    }

    @Test func oldRelationshipEventCannotPurgeAUsersNewActiveCouple() async throws {
        let ownerUserID = UUID()
        let oldCoupleID = UUID()
        let newCoupleID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let oldRelationshipEnd = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: oldCoupleID,
            createdAt: 100,
            eventKind: "relationship_ended",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "review"
            ]
        )

        try await applier.apply(
            [oldRelationshipEnd],
            session: session(ownerUserID: ownerUserID, activeCoupleID: newCoupleID)
        )

        #expect(await privacyPurger.calls.isEmpty)
    }

    @Test func oldEventCannotOwnerPurgeWhenCurrentRelationshipIdentityIsUnknown() async throws {
        let ownerUserID = UUID()
        let privacyPurger = RecordingLocalPrivacyPurger()
        let applier = RelationshipSyncEventApplier(
            widgetCanvasService: nil,
            localPrivacyPurger: privacyPurger
        )
        let oldRelationshipEnd = try event(
            id: UUID().uuidString,
            userID: ownerUserID,
            coupleID: UUID(),
            createdAt: 100,
            eventKind: "relationship_ended",
            localPurgeScope: [
                "relationship_content": "hide",
                "pending_uploads": "review"
            ]
        )

        try await applier.apply(
            [oldRelationshipEnd],
            session: session(ownerUserID: ownerUserID)
        )

        #expect(await privacyPurger.calls.isEmpty)
    }

    private func event(
        id: String,
        userID: UUID,
        coupleID: UUID? = nil,
        createdAt: TimeInterval,
        eventKind: String = "relationship_ended",
        localPurgeScope: [String: String] = ["relationship": "hide"]
    ) throws -> RemoteRelationshipSyncEvent {
        let resolvedCoupleID = try coupleID ?? #require(
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")
        )
        return RemoteRelationshipSyncEvent(
            id: try #require(UUID(uuidString: id)),
            userID: userID,
            coupleID: resolvedCoupleID,
            initiatedByUserID: nil,
            eventKind: eventKind,
            reason: "left_relationship",
            occurredAt: Date(timeIntervalSince1970: createdAt),
            relationshipStatus: "ended",
            memberStatus: "ended_notice_pending",
            endedAt: Date(timeIntervalSince1970: createdAt),
            deleteAfter: Date(timeIntervalSince1970: createdAt + 2_592_000),
            localPurgeScope: localPurgeScope,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func session(
        ownerUserID: UUID,
        activeCoupleID: UUID? = nil,
        relationshipCoupleID: UUID? = nil
    ) -> SyncSession {
        SyncSession(
            userID: ownerUserID,
            activeCoupleID: activeCoupleID,
            relationshipCoupleID: relationshipCoupleID
        )
    }
}

private actor RecordingRelationshipSyncEventApplier: RelationshipSyncEventApplying {
    private struct ApplyFailure: Error {}

    private var appliedIDs: [UUID] = []
    private var failuresRemaining: Int

    init(failingApplies: Int = 0) {
        failuresRemaining = failingApplies
    }

    var appliedEventIDs: [UUID] {
        appliedIDs
    }

    func apply(
        _ events: [RemoteRelationshipSyncEvent],
        session _: SyncSession
    ) async throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw ApplyFailure()
        }
        appliedIDs.append(contentsOf: events.map(\.id))
    }
}

private final class EventsFeedEnv: @unchecked Sendable {
    let transport = RecordingLiveTransport()
    let eventStore = InMemoryRelationshipSyncEventRepository()
    let stateStore = InMemorySyncStateRepository()
    let applier: RecordingRelationshipSyncEventApplier
    private let feed: RelationshipEventsLiveFeed
    private let session: SyncSession
    private let live: LiveQueryService
    private var task: Task<Void, Never>?

    init(ownerUserID: UUID, failingApplies: Int = 0) {
        applier = RecordingRelationshipSyncEventApplier(failingApplies: failingApplies)
        session = SyncSession(userID: ownerUserID)
        feed = RelationshipEventsLiveFeed(
            eventStore: eventStore,
            stateStore: stateStore,
            applier: applier,
            retryDelay: .milliseconds(1)
        )
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

private struct PrivacyPurgeCall: Equatable, Sendable {
    let ownerUserID: UUID
    let scope: LocalPrivacyPurgeScope
}

private actor RecordingLocalPrivacyPurger: LocalPrivacyPurging {
    private(set) var calls: [PrivacyPurgeCall] = []

    func purge(
        ownerUserID: UUID,
        scope: LocalPrivacyPurgeScope
    ) -> LocalPrivacyPurgeResult {
        calls.append(PrivacyPurgeCall(ownerUserID: ownerUserID, scope: scope))
        return .completed
    }
}
