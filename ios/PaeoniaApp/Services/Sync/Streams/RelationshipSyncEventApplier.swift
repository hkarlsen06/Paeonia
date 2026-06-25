import Foundation

nonisolated protocol RelationshipSyncEventApplying: Sendable {
    func apply(
        _ events: [SupabaseRelationshipSyncEvent],
        context: SyncContext
    ) async throws
}

struct RelationshipSyncEventApplier: RelationshipSyncEventApplying {
    private let widgetCanvasService: (any WidgetCanvasManaging)?

    init(widgetCanvasService: (any WidgetCanvasManaging)? = WidgetCanvasService.shared) {
        self.widgetCanvasService = widgetCanvasService
    }

    func apply(
        _ events: [SupabaseRelationshipSyncEvent],
        context _: SyncContext
    ) async throws {
        guard shouldClearWidgetCache(for: events), let widgetCanvasService else {
            return
        }

        await widgetCanvasService.clearForPrivacy()
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
}

struct NoOpRelationshipSyncEventApplier: RelationshipSyncEventApplying {
    func apply(
        _ events: [SupabaseRelationshipSyncEvent],
        context: SyncContext
    ) async throws {}
}
