import Foundation

nonisolated protocol RelationshipSyncEventApplying: Sendable {
    func apply(
        _ events: [RemoteRelationshipSyncEvent],
        session: SyncSession
    ) async throws
}

struct RelationshipSyncEventApplier: RelationshipSyncEventApplying {
    private let widgetCanvasService: (any WidgetCanvasManaging)?
    private let localPrivacyPurger: (any LocalPrivacyPurging)?

    init(
        widgetCanvasService: (any WidgetCanvasManaging)? = WidgetCanvasService.shared,
        localPrivacyPurger: (any LocalPrivacyPurging)? = nil
    ) {
        self.widgetCanvasService = widgetCanvasService
        self.localPrivacyPurger = localPrivacyPurger
    }

    func apply(
        _ events: [RemoteRelationshipSyncEvent],
        session: SyncSession
    ) async throws {
        // Owner-wide deletion is intentionally never inferred without a current
        // relationship identity. Root access resolution owns that nil-identity
        // case using its current and persisted access snapshots. This prevents
        // a delayed event from an old couple erasing a newer invite or draft.
        guard let relationshipCoupleID = session.relationshipCoupleID else {
            return
        }
        let privacyRelevantEvents = Self.eventsSinceLastStart(events.filter { $0.coupleID == relationshipCoupleID })

        if let purgeScope = relationshipPurgeScope(for: privacyRelevantEvents),
           let localPrivacyPurger {
            await localPrivacyPurger.purge(
                ownerUserID: session.userID,
                scope: purgeScope
            )
            return
        }

        if shouldClearWidgetCache(for: privacyRelevantEvents), let widgetCanvasService {
            await widgetCanvasService.clearForPrivacy()
        }
    }

    /// A couple that ended and came back starts again with `relationship_started`. A phone
    /// that was away the whole time gets the end and the start together, and the end must
    /// not purge what the couple has again. Events arrive oldest first.
    private static func eventsSinceLastStart(
        _ events: [RemoteRelationshipSyncEvent]
    ) -> ArraySlice<RemoteRelationshipSyncEvent> {
        guard let lastStart = events.lastIndex(where: { $0.eventKind == "relationship_started" }) else {
            return events[...]
        }
        return events[events.index(after: lastStart)...]
    }

    private func relationshipPurgeScope(
        for events: ArraySlice<RemoteRelationshipSyncEvent>
    ) -> LocalPrivacyPurgeScope? {
        guard events.contains(where: requiresRelationshipContentPurge) else {
            return nil
        }

        // The backend currently emits `review` when a relationship ends. MVP has
        // no recovery/review surface, so retaining payload-bearing queued writes
        // would keep inaccessible private content on disk indefinitely. Treat it
        // as purge until such a recovery flow exists.
        let shouldPurgeOwnedContent = events.contains { event in
            event.localPurgeScope["pending_uploads"] == "review"
                || event.localPurgeScope["pending_uploads"] == "purge"
                || event.localPurgeScope["relationship_content"] == "purge"
                || Self.pendingOperationPurgingEventKinds.contains(event.eventKind)
        }

        return shouldPurgeOwnedContent
            ? .relationshipContentPurged(clearAccessSnapshot: false)
            : .relationshipAccessHidden
    }

    private func requiresRelationshipContentPurge(
        _ event: RemoteRelationshipSyncEvent
    ) -> Bool {
        event.localPurgeScope["relationship_content"] == "hide"
            || event.localPurgeScope["relationship_content"] == "purge"
            || Self.widgetClearingEventKinds.contains(event.eventKind)
    }

    private func shouldClearWidgetCache(for events: ArraySlice<RemoteRelationshipSyncEvent>) -> Bool {
        events.contains { event in
            if event.localPurgeScope["widget_cache"] == "purge" {
                return true
            }

            if event.localPurgeScope["relationship_content"] == "hide"
                || event.localPurgeScope["relationship_content"] == "purge" {
                return true
            }

            return Self.widgetClearingEventKinds.contains(event.eventKind)
        }
    }

    private static let widgetClearingEventKinds: Set<String> = [
        "relationship_ended",
        "relationship_deleted",
        "entitlement_lost",
        "content_hidden",
        "content_purged",
        "account_deletion_started",
        "account_deleted"
    ]

    private static let pendingOperationPurgingEventKinds: Set<String> = [
        "relationship_ended",
        "relationship_deleted",
        "content_purged",
        "account_deletion_started",
        "account_deleted"
    ]
}
