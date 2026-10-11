import Foundation
import SwiftData

protocol LocalPrivacyRecordPurging: Actor {
    func purgeDepartingUser(ownerUserID: UUID) async throws
    func hideRelationshipAccess(ownerUserID: UUID) async throws
    func purgeRelationshipContent(
        ownerUserID: UUID,
        clearAccessSnapshot: Bool
    ) async throws
}

actor SwiftDataLocalPrivacyRecordStore: LocalPrivacyRecordPurging {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func purgeDepartingUser(ownerUserID: UUID) async throws {
        let context = ModelContext(container)

        for value in try context.fetch(
            FetchDescriptor<LocalSyncState>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
        for value in try context.fetch(
            FetchDescriptor<LocalPendingSyncOperation>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
        for value in try context.fetch(
            FetchDescriptor<LocalAccessSyncSnapshot>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
        for value in try context.fetch(
            FetchDescriptor<LocalRelationshipSyncEvent>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
        try deleteLocationRecords(ownerUserID: ownerUserID, in: context)
        PendingSharingChoiceLedger.shared.removeChoices(ownerUserID: ownerUserID)
        try deleteMemoryRecords(ownerUserID: ownerUserID, in: context)

        try context.save()
        Self.postChanges(Self.purgedDomains, ownerUserID: ownerUserID)
    }

    /// Keeps the person's unconfirmed sharing choices. Their queued sharing
    /// change survives this scope, and without the choice a server value that
    /// has not seen it yet would show sharing as on again.
    func hideRelationshipAccess(ownerUserID: UUID) async throws {
        let context = ModelContext(container)
        try deleteRelationshipSyncState(ownerUserID: ownerUserID, in: context)
        try deleteLocationRecords(ownerUserID: ownerUserID, in: context)

        try context.save()
        Self.postChanges([.locationVisibility, .ownLocation], ownerUserID: ownerUserID)
    }

    func purgeRelationshipContent(
        ownerUserID: UUID,
        clearAccessSnapshot: Bool
    ) async throws {
        let context = ModelContext(container)
        try deleteRelationshipSyncState(ownerUserID: ownerUserID, in: context)
        for value in try context.fetch(
            FetchDescriptor<LocalPendingSyncOperation>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
        try deleteLocationRecords(ownerUserID: ownerUserID, in: context)
        PendingSharingChoiceLedger.shared.removeChoices(ownerUserID: ownerUserID)
        try deleteMemoryRecords(ownerUserID: ownerUserID, in: context)
        try deleteRelationshipEvents(ownerUserID: ownerUserID, in: context)
        if clearAccessSnapshot {
            try deleteAccessSnapshot(ownerUserID: ownerUserID, in: context)
        }

        try context.save()
        Self.postChanges(Self.purgedDomains, ownerUserID: ownerUserID)
    }

    /// Open screens re-read and drop what the purge removed. `.access` is left
    /// out on purpose. Root starts the purge from its access routing, so a post
    /// here would run that routing again.
    private static let purgedDomains: [LocalStoreDomain] = [
        .pendingOperations,
        .relationshipEvents,
        .locationVisibility,
        .ownLocation,
        .memories,
    ]

    private static func postChanges(_ domains: [LocalStoreDomain], ownerUserID: UUID) {
        for domain in domains {
            LocalStoreChanges.post(domain, ownerUserID: ownerUserID)
        }
    }

    private func deleteRelationshipSyncState(
        ownerUserID: UUID,
        in context: ModelContext
    ) throws {
        let userScope = SyncScopeKind.user.rawValue
        for value in try context.fetch(
            FetchDescriptor<LocalSyncState>(
                predicate: #Predicate { value in
                    value.ownerUserID == ownerUserID && value.scopeKindRawValue != userScope
                }
            )
        ) {
            context.delete(value)
        }
    }

    private func deleteLocationRecords(
        ownerUserID: UUID,
        in context: ModelContext
    ) throws {
        for value in try context.fetch(
            FetchDescriptor<LocalLocationVisibilitySnapshot>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
        for value in try context.fetch(
            FetchDescriptor<LocalOwnLocationSnapshot>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
    }

    private func deleteMemoryRecords(
        ownerUserID: UUID,
        in context: ModelContext
    ) throws {
        for value in try context.fetch(
            FetchDescriptor<LocalMemoryRecord>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
    }

    private func deleteRelationshipEvents(
        ownerUserID: UUID,
        in context: ModelContext
    ) throws {
        for value in try context.fetch(
            FetchDescriptor<LocalRelationshipSyncEvent>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
    }

    private func deleteAccessSnapshot(
        ownerUserID: UUID,
        in context: ModelContext
    ) throws {
        for value in try context.fetch(
            FetchDescriptor<LocalAccessSyncSnapshot>(
                predicate: #Predicate { value in value.ownerUserID == ownerUserID }
            )
        ) {
            context.delete(value)
        }
    }
}

actor NoOpLocalPrivacyRecordStore: LocalPrivacyRecordPurging {
    func purgeDepartingUser(ownerUserID: UUID) {}
    func hideRelationshipAccess(ownerUserID: UUID) {}
    func purgeRelationshipContent(ownerUserID: UUID, clearAccessSnapshot: Bool) {}
}
