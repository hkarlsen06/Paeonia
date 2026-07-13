import Foundation

nonisolated protocol RelationshipSyncEventApplying: Sendable {
    func apply(
        _ events: [SupabaseRelationshipSyncEvent],
        context: SyncContext
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
        _ events: [SupabaseRelationshipSyncEvent],
        context: SyncContext
    ) async throws {
        // Owner-wide deletion is intentionally never inferred without a current
        // relationship identity. Root access resolution owns that nil-identity
        // case using its current and persisted access snapshots. This prevents
        // a delayed event from an old couple erasing a newer invite or draft.
        guard let relationshipCoupleID = context.session.relationshipCoupleID else {
            return
        }
        let privacyRelevantEvents = events.filter { $0.coupleID == relationshipCoupleID }

        if let purgeScope = relationshipPurgeScope(for: privacyRelevantEvents),
           let localPrivacyPurger {
            await localPrivacyPurger.purge(
                ownerUserID: context.session.userID,
                scope: purgeScope
            )
            return
        }

        if shouldClearWidgetCache(for: privacyRelevantEvents), let widgetCanvasService {
            await widgetCanvasService.clearForPrivacy()
        }
    }

    private func relationshipPurgeScope(
        for events: [SupabaseRelationshipSyncEvent]
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
        _ event: SupabaseRelationshipSyncEvent
    ) -> Bool {
        event.localPurgeScope["relationship_content"] == "hide"
            || event.localPurgeScope["relationship_content"] == "purge"
            || Self.widgetClearingEventKinds.contains(event.eventKind)
    }

    private func shouldClearWidgetCache(for events: [SupabaseRelationshipSyncEvent]) -> Bool {
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

struct NoOpRelationshipSyncEventApplier: RelationshipSyncEventApplying {
    func apply(
        _ events: [SupabaseRelationshipSyncEvent],
        context: SyncContext
    ) async throws {}
}
