@preconcurrency import ConvexMobile
import Foundation

/// Saves relationship sync events as the server records them and applies their
/// privacy effects (hide or purge local data, clear the widget cache).
///
/// The query returns events after a cursor. Each non-empty result is saved and
/// applied, the cursor moves to the last event, and the feed subscribes again
/// from the new cursor. The cursor advances only after the events are applied,
/// so a failure or a cancelled purge replays the same events on the next run.
///
/// A replayed `entitlement_lost` event can be older than a renewal. Before the
/// feed applies one, it reads the current access snapshot from the server and
/// skips the event when that couple is active and entitled now. Without this, a
/// launch after a lapse and renewal would hide caches that the other feeds had
/// just filled, and Root has no route change to restart them.
///
/// Root also purges when the access snapshot shows the relationship ended. That
/// purge runs with every feed paused, so anything this feed or another feed
/// wrote for the old couple in between is removed there.
nonisolated struct RelationshipEventsLiveFeed: LiveFeed {
    let name = "relationshipEvents"

    private let eventStore: any RelationshipSyncEventPersisting
    private let stateStore: any SyncStatePersisting
    private let applier: any RelationshipSyncEventApplying
    private let pageSize: Int
    private let retryDelay: Duration

    init(
        eventStore: any RelationshipSyncEventPersisting,
        stateStore: any SyncStatePersisting,
        applier: any RelationshipSyncEventApplying,
        pageSize: Int = 100,
        retryDelay: Duration = .seconds(5)
    ) {
        self.eventStore = eventStore
        self.stateStore = stateStore
        self.applier = applier
        self.pageSize = pageSize
        self.retryDelay = retryDelay
    }

    /// The feed the app runs: the shared stores and an applier that purges through
    /// `LocalPrivacyPurgeService`.
    static func make(stores: PaeoniaSyncServiceDefaults.Stores) -> RelationshipEventsLiveFeed {
        RelationshipEventsLiveFeed(
            eventStore: stores.relationshipEventStore,
            stateStore: stores.stateStore,
            applier: RelationshipSyncEventApplier(
                localPrivacyPurger: LocalPrivacyPurgeService(recordStore: stores.privacyRecordStore)
            )
        )
    }

    func run(session: SyncSession, live: LiveQueryService) async {
        let scope = SyncStreamScope(kind: .user)
        var cursor = (try? await stateStore.cursor(
            ownerUserID: session.userID,
            scope: scope,
            streamKey: .relationshipEvents
        )) ?? SyncCursor()

        while !Task.isCancelled {
            guard let events = await nextEvents(after: cursor, live: live),
                  let last = events.last
            else {
                return
            }
            let next = SyncCursor(updatedAt: last.createdAt, tieID: last.id)
            guard next != cursor else {
                // The server returned events at or before the cursor. Wait instead of spinning.
                try? await Task.sleep(for: retryDelay)
                continue
            }

            do {
                try await eventStore.save(events)
                guard let applicable = await dropRenewedEntitlementLoss(events, live: live) else {
                    return
                }
                try await applier.apply(applicable, session: session)
                try await stateStore.markSucceeded(
                    ownerUserID: session.userID,
                    scope: scope,
                    streamKey: .relationshipEvents,
                    cursor: next,
                    at: Date()
                )
                cursor = next
            } catch {
                // Subscribe again from the old cursor once the store recovers.
                try? await Task.sleep(for: retryDelay)
            }
        }
    }

    /// Removes `entitlement_lost` events for a couple that is active and entitled
    /// in the server's current snapshot. Returns nil once the task is cancelled.
    /// Other events, including `relationship_ended`, are never dropped.
    private func dropRenewedEntitlementLoss(
        _ events: [RemoteRelationshipSyncEvent],
        live: LiveQueryService
    ) async -> [RemoteRelationshipSyncEvent]? {
        guard events.contains(where: { $0.eventKind == "entitlement_lost" }) else {
            return events
        }
        let results = live.subscribe("access:get_access_snapshot", as: [RemoteAccessSnapshot].self)
        for await result in results {
            if Task.isCancelled {
                return nil
            }
            guard case let .value(rows) = result else {
                continue
            }
            let snapshot = rows.first
            return events.filter { event in
                guard event.eventKind == "entitlement_lost" else {
                    return true
                }
                let isActiveAndEntitled = snapshot?.relationshipState?.coupleID == event.coupleID
                    && snapshot?.relationshipState?.isActiveRelationship == true
                    && snapshot?.coupleEntitlement?.coupleID == event.coupleID
                    && snapshot?.coupleEntitlement?.isEntitled == true
                return !isActiveAndEntitled
            }
        }
        return nil
    }

    /// The first non-empty result after `cursor`, or nil once the task is cancelled.
    /// Dropping the stream cancels the subscription.
    private func nextEvents(after cursor: SyncCursor, live: LiveQueryService) async -> [RemoteRelationshipSyncEvent]? {
        let results = live.subscribe(
            "relationship:get_relationship_sync_events",
            args: arguments(for: cursor),
            as: [RemoteRelationshipSyncEvent].self
        )
        for await result in results {
            if Task.isCancelled {
                return nil
            }
            if case let .value(events) = result, !events.isEmpty {
                return events
            }
        }
        return nil
    }

    private func arguments(for cursor: SyncCursor) -> [String: ConvexEncodable?] {
        var args: [String: ConvexEncodable?] = ["p_limit": Double(pageSize)]
        // The client encoder rounds to the middle of the millisecond. A plain
        // formatter can print `.122` for a stored `.123`, and the server would
        // then return the same event again.
        if let createdAt = cursor.updatedAt,
           let data = try? PaeoniaConvexClient.encoder.encode(createdAt),
           let timestamp = try? JSONDecoder().decode(String.self, from: data) {
            args["p_after_created_at"] = timestamp
            if let tieID = cursor.tieID {
                args["p_after_id"] = tieID.uuidString
            }
        }
        return args
    }
}
