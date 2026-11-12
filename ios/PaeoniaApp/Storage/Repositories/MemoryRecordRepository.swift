import Foundation
import SwiftData

protocol MemoryRecordPersisting: Actor {
    func saveRemote(
        _ rows: [MemoryRemoteRow],
        ownerUserID: UUID,
        mergePolicy: MemoryRemoteMergePolicy
    ) async throws
    func saveLocal(_ record: MemoryRecord) async throws
    func load(
        ownerUserID: UUID,
        includeHidden: Bool
    ) async throws -> [MemoryRecord]
    func load(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord?
    /// Deletes this phone's copy of a memory the server never kept under that id.
    func remove(ownerUserID: UUID, memoryID: UUID) async throws
}

nonisolated enum MemoryRemoteMergePolicy: Equatable, Sendable {
    /// Normal pull behavior: keep any local record that still has unsent changes.
    case preserveLocalChanges
    /// Administrative or test behavior: accept the remote row even over local changes.
    case overwriteLocalChanges
    /// A pending operation just succeeded. Replace the local record only when that exact
    /// operation is still the latest local change; preserve anything edited afterward.
    case overwriteIfPendingOperationMatches(UUID)
}

actor SwiftDataMemoryRecordRepository: MemoryRecordPersisting {
    private let container: ModelContainer
    private let mediaCache: (any MediaCacheEvicting)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer, mediaCache: (any MediaCacheEvicting)? = MemoryMediaImageService.shared) {
        self.container = container
        self.mediaCache = mediaCache
    }

    func saveRemote(
        _ rows: [MemoryRemoteRow],
        ownerUserID: UUID,
        mergePolicy: MemoryRemoteMergePolicy = .preserveLocalChanges
    ) async throws {
        try await evictPhotos(ownerUserID: ownerUserID) { context in
            try self.apply(rows, ownerUserID: ownerUserID, mergePolicy: mergePolicy, in: context)
        }
        let context = ModelContext(container)
        _ = try apply(rows, ownerUserID: ownerUserID, mergePolicy: mergePolicy, in: context)
        try context.save()
        LocalStoreChanges.post(.memories, ownerUserID: ownerUserID)
    }

    func saveLocal(_ record: MemoryRecord) async throws {
        try await evictPhotos(ownerUserID: record.snapshot.ownerUserID) { context in
            try self.apply(record, in: context)
        }
        let context = ModelContext(container)
        _ = try apply(record, in: context)
        try context.save()
        LocalStoreChanges.post(.memories, ownerUserID: record.snapshot.ownerUserID)
    }

    /// Applies remote rows to `context` and returns the photos the memories they change stop showing.
    private func apply(
        _ rows: [MemoryRemoteRow],
        ownerUserID: UUID,
        mergePolicy: MemoryRemoteMergePolicy,
        in context: ModelContext
    ) throws -> Set<UUID> {
        var unshownPhotos = Set<UUID>()
        for row in rows {
            let remoteRecord = MemoryRecord(
                snapshot: row.snapshot(ownerUserID: ownerUserID),
                syncStatus: .clean,
                pendingOperationID: nil,
                conflictReason: nil,
                localUpdatedAt: row.syncUpdatedAt
            )

            if let existing = try fetch(ownerUserID: ownerUserID, memoryID: row.memoryID, in: context) {
                if shouldPreserveLocalRecord(existing, mergePolicy: mergePolicy) {
                    continue
                }
                unshownPhotos.formUnion(try photosNoLongerShown(by: existing, after: remoteRecord))
                try update(existing, from: remoteRecord)
            } else {
                context.insert(try localRecord(from: remoteRecord))
            }
        }
        return unshownPhotos
    }

    /// Applies a local change to `context` and returns the photos the memory stops showing.
    private func apply(_ record: MemoryRecord, in context: ModelContext) throws -> Set<UUID> {
        guard let existing = try fetch(
            ownerUserID: record.snapshot.ownerUserID,
            memoryID: record.snapshot.memoryID,
            in: context
        ) else {
            context.insert(try localRecord(from: record))
            return []
        }
        let unshownPhotos = try photosNoLongerShown(by: existing, after: record)
        try update(existing, from: record)
        return unshownPhotos
    }

    private func update(_ existing: LocalMemoryRecord, from record: MemoryRecord) throws {
        existing.update(
            from: record,
            ownNoteData: try encode(record.snapshot.ownNote),
            partnerNoteData: try encode(record.snapshot.partnerNote),
            visibleMemoryMediaIDsData: try encode(record.snapshot.visibleMemoryMediaIDs),
            visibleMediaAssetIDsData: try encode(record.snapshot.visibleMediaAssetIDs),
            mediaData: try encode(record.snapshot.media),
            placeData: try encode(record.snapshot.place)
        )
    }

    func load(
        ownerUserID: UUID,
        includeHidden: Bool = false
    ) throws -> [MemoryRecord] {
        try records(ownerUserID: ownerUserID, in: ModelContext(container))
            .filter { includeHidden || $0.snapshot.isVisible }
    }

    /// Includes the changes `context` has not saved yet.
    private func records(ownerUserID: UUID, in context: ModelContext) throws -> [MemoryRecord] {
        let descriptor = FetchDescriptor<LocalMemoryRecord>(
            predicate: #Predicate { record in
                record.ownerUserID == ownerUserID
            },
            sortBy: [
                SortDescriptor(\.memoryDate, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.memoryID)
            ]
        )
        return try context.fetch(descriptor).map(record(from:))
    }

    func load(
        ownerUserID: UUID,
        memoryID: UUID
    ) throws -> MemoryRecord? {
        let context = ModelContext(container)
        guard let localRecord = try fetch(ownerUserID: ownerUserID, memoryID: memoryID, in: context) else {
            return nil
        }

        return try record(from: localRecord)
    }

    private func photosNoLongerShown(by existing: LocalMemoryRecord, after update: MemoryRecord) throws -> Set<UUID> {
        try record(from: existing).snapshot.shownMediaAssetIDs.subtracting(update.snapshot.shownMediaAssetIDs)
    }

    /// A delete by either partner reaches this phone as a changed memory. The photos the
    /// change stops showing leave the photo cache before the change is saved, so if the app
    /// ends in between, the change arrives again and evicts them again. `change` runs in a
    /// context that is never saved. A photo another memory still shows stays.
    private func evictPhotos(
        ownerUserID: UUID,
        unshownBy change: (ModelContext) throws -> Set<UUID>
    ) async throws {
        guard let mediaCache else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let candidates = try change(context)
        guard !candidates.isEmpty else { return }
        let stillShown = try records(ownerUserID: ownerUserID, in: context)
            .reduce(into: Set<UUID>()) { $0.formUnion($1.snapshot.shownMediaAssetIDs) }
        let unshown = candidates.subtracting(stillShown)
        if !unshown.isEmpty {
            await mediaCache.evict(mediaAssetIDs: Array(unshown))
        }
    }

    func remove(ownerUserID: UUID, memoryID: UUID) async throws {
        try await evictPhotos(ownerUserID: ownerUserID) { context in
            guard let localRecord = try self.fetch(ownerUserID: ownerUserID, memoryID: memoryID, in: context) else {
                return []
            }
            let shown = try self.record(from: localRecord).snapshot.shownMediaAssetIDs
            context.delete(localRecord)
            return shown
        }
        let context = ModelContext(container)
        guard let localRecord = try fetch(ownerUserID: ownerUserID, memoryID: memoryID, in: context) else { return }
        context.delete(localRecord)
        try context.save()
        LocalStoreChanges.post(.memories, ownerUserID: ownerUserID)
    }

    private func localRecord(from record: MemoryRecord) throws -> LocalMemoryRecord {
        try LocalMemoryRecord(
            record: record,
            ownNoteData: encode(record.snapshot.ownNote),
            partnerNoteData: encode(record.snapshot.partnerNote),
            visibleMemoryMediaIDsData: encode(record.snapshot.visibleMemoryMediaIDs),
            visibleMediaAssetIDsData: encode(record.snapshot.visibleMediaAssetIDs),
            mediaData: encode(record.snapshot.media),
            placeData: encode(record.snapshot.place)
        )
    }

    private func record(from local: LocalMemoryRecord) throws -> MemoryRecord {
        MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: local.ownerUserID,
                memoryID: local.memoryID,
                coupleID: local.coupleID,
                title: local.title,
                memoryDate: local.memoryDate,
                place: try decode(MemoryPlace.self, from: local.placeData),
                createdByUserID: local.createdByUserID,
                lastEditedByUserID: local.lastEditedByUserID,
                revision: local.revision,
                moderationStatus: MemoryModerationStatus(rawValue: local.moderationStatusRawValue),
                deletedAt: local.deletedAt,
                createdAt: local.createdAt,
                updatedAt: local.updatedAt,
                syncUpdatedAt: local.syncUpdatedAt,
                ownNote: try decode(MemoryNoteSnapshot.self, from: local.ownNoteData),
                partnerNote: try decode(MemoryNoteSnapshot.self, from: local.partnerNoteData),
                visibleMemoryMediaIDs: try decode([UUID].self, from: local.visibleMemoryMediaIDsData),
                visibleMediaAssetIDs: try decode([UUID].self, from: local.visibleMediaAssetIDsData),
                media: try decode([MemoryMediaSnapshot].self, from: local.mediaData),
                threadID: local.threadID,
                visitID: local.visitID
            ),
            syncStatus: SyncRecordStatus(rawValue: local.syncStatusRawValue) ?? .clean,
            pendingOperationID: local.pendingOperationID,
            conflictReason: local.conflictReason,
            localUpdatedAt: local.localUpdatedAt
        )
    }

    private func fetch(
        ownerUserID: UUID,
        memoryID: UUID,
        in context: ModelContext
    ) throws -> LocalMemoryRecord? {
        let storageKey = LocalMemoryRecord.storageKey(ownerUserID: ownerUserID, memoryID: memoryID)
        var descriptor = FetchDescriptor<LocalMemoryRecord>(
            predicate: #Predicate { record in
                record.storageKey == storageKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func shouldPreserveLocalRecord(
        _ existing: LocalMemoryRecord,
        mergePolicy: MemoryRemoteMergePolicy
    ) -> Bool {
        guard existing.syncStatusRawValue != SyncRecordStatus.clean.rawValue else {
            return false
        }

        switch mergePolicy {
        case .preserveLocalChanges:
            return true
        case .overwriteLocalChanges:
            return false
        case let .overwriteIfPendingOperationMatches(operationID):
            return existing.pendingOperationID != operationID
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try encoder.encode(value)
    }

    private func encode<Value: Encodable>(_ value: Value?) throws -> Data? {
        guard let value else {
            return nil
        }

        return try encoder.encode(value)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?
    ) throws -> Value? {
        guard let data else {
            return nil
        }

        return try decoder.decode(type, from: data)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        try decoder.decode(type, from: data)
    }
}

actor InMemoryMemoryRecordRepository: MemoryRecordPersisting {
    private var records: [String: MemoryRecord] = [:]

    func saveRemote(
        _ rows: [MemoryRemoteRow],
        ownerUserID: UUID,
        mergePolicy: MemoryRemoteMergePolicy = .preserveLocalChanges
    ) throws {
        for row in rows {
            let key = key(ownerUserID: ownerUserID, memoryID: row.memoryID)
            if let existing = records[key], shouldPreserveLocalRecord(existing, mergePolicy: mergePolicy) {
                continue
            }
            records[key] = MemoryRecord(
                snapshot: row.snapshot(ownerUserID: ownerUserID),
                syncStatus: .clean,
                pendingOperationID: nil,
                conflictReason: nil,
                localUpdatedAt: row.syncUpdatedAt
            )
        }
        LocalStoreChanges.post(.memories, ownerUserID: ownerUserID)
    }

    func saveLocal(_ record: MemoryRecord) throws {
        records[key(ownerUserID: record.snapshot.ownerUserID, memoryID: record.snapshot.memoryID)] = record
        LocalStoreChanges.post(.memories, ownerUserID: record.snapshot.ownerUserID)
    }

    func load(
        ownerUserID: UUID,
        includeHidden: Bool = false
    ) throws -> [MemoryRecord] {
        records.values
            .filter { $0.snapshot.ownerUserID == ownerUserID }
            .filter { includeHidden || $0.snapshot.isVisible }
            .sorted { lhs, rhs in
                if lhs.snapshot.memoryDate != rhs.snapshot.memoryDate {
                    return lhs.snapshot.memoryDate > rhs.snapshot.memoryDate
                }
                if lhs.snapshot.createdAt != rhs.snapshot.createdAt {
                    return lhs.snapshot.createdAt > rhs.snapshot.createdAt
                }
                return lhs.snapshot.memoryID.uuidString < rhs.snapshot.memoryID.uuidString
            }
    }

    func load(
        ownerUserID: UUID,
        memoryID: UUID
    ) throws -> MemoryRecord? {
        records[key(ownerUserID: ownerUserID, memoryID: memoryID)]
    }

    func remove(ownerUserID: UUID, memoryID: UUID) {
        records[key(ownerUserID: ownerUserID, memoryID: memoryID)] = nil
        LocalStoreChanges.post(.memories, ownerUserID: ownerUserID)
    }

    private func key(ownerUserID: UUID, memoryID: UUID) -> String {
        LocalMemoryRecord.storageKey(ownerUserID: ownerUserID, memoryID: memoryID)
    }

    private func shouldPreserveLocalRecord(
        _ existing: MemoryRecord,
        mergePolicy: MemoryRemoteMergePolicy
    ) -> Bool {
        guard existing.syncStatus != .clean else {
            return false
        }

        switch mergePolicy {
        case .preserveLocalChanges:
            return true
        case .overwriteLocalChanges:
            return false
        case let .overwriteIfPendingOperationMatches(operationID):
            return existing.pendingOperationID != operationID
        }
    }
}
