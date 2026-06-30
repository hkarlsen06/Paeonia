import Foundation
import SwiftData

protocol MemoryRecordPersisting: Actor {
    func saveRemote(
        _ rows: [MemoryRemoteRow],
        ownerUserID: UUID,
        preserveDirtyRecords: Bool
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
    func markConflict(
        ownerUserID: UUID,
        memoryID: UUID,
        reason: String
    ) async throws
    func delete(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws
    func deleteAll(ownerUserID: UUID) async throws
}

actor SwiftDataMemoryRecordRepository: MemoryRecordPersisting {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
    }

    func saveRemote(
        _ rows: [MemoryRemoteRow],
        ownerUserID: UUID,
        preserveDirtyRecords: Bool = true
    ) async throws {
        let context = ModelContext(container)

        for row in rows {
            let remoteRecord = MemoryRecord(
                snapshot: row.snapshot(ownerUserID: ownerUserID),
                syncStatus: .clean,
                pendingOperationID: nil,
                conflictReason: nil,
                localUpdatedAt: row.syncUpdatedAt
            )

            if let existing = try fetch(ownerUserID: ownerUserID, memoryID: row.memoryID, in: context) {
                if preserveDirtyRecords, existing.syncStatusRawValue != SyncRecordStatus.clean.rawValue {
                    continue
                }
                existing.update(
                    from: remoteRecord,
                    ownNoteData: try encode(remoteRecord.snapshot.ownNote),
                    partnerNoteData: try encode(remoteRecord.snapshot.partnerNote),
                    visibleMemoryMediaIDsData: try encode(remoteRecord.snapshot.visibleMemoryMediaIDs),
                    visibleMediaAssetIDsData: try encode(remoteRecord.snapshot.visibleMediaAssetIDs),
                    mediaData: try encode(remoteRecord.snapshot.media)
                )
            } else {
                context.insert(
                    try localRecord(from: remoteRecord)
                )
            }
        }

        try context.save()
    }

    func saveLocal(_ record: MemoryRecord) async throws {
        let context = ModelContext(container)

        if let existing = try fetch(
            ownerUserID: record.snapshot.ownerUserID,
            memoryID: record.snapshot.memoryID,
            in: context
        ) {
            existing.update(
                from: record,
                ownNoteData: try encode(record.snapshot.ownNote),
                partnerNoteData: try encode(record.snapshot.partnerNote),
                visibleMemoryMediaIDsData: try encode(record.snapshot.visibleMemoryMediaIDs),
                visibleMediaAssetIDsData: try encode(record.snapshot.visibleMediaAssetIDs),
                mediaData: try encode(record.snapshot.media)
            )
        } else {
            context.insert(try localRecord(from: record))
        }

        try context.save()
    }

    func load(
        ownerUserID: UUID,
        includeHidden: Bool = false
    ) async throws -> [MemoryRecord] {
        let context = ModelContext(container)
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

        return try context.fetch(descriptor)
            .map(record(from:))
            .filter { includeHidden || $0.snapshot.isVisible }
    }

    func load(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord? {
        let context = ModelContext(container)
        guard let localRecord = try fetch(ownerUserID: ownerUserID, memoryID: memoryID, in: context) else {
            return nil
        }

        return try record(from: localRecord)
    }

    func markConflict(
        ownerUserID: UUID,
        memoryID: UUID,
        reason: String
    ) async throws {
        let context = ModelContext(container)
        guard let record = try fetch(ownerUserID: ownerUserID, memoryID: memoryID, in: context) else {
            return
        }

        record.syncStatusRawValue = SyncRecordStatus.conflict.rawValue
        record.conflictReason = reason
        record.pendingOperationID = nil
        record.localUpdatedAt = Date()
        try context.save()
    }

    func delete(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws {
        let context = ModelContext(container)
        if let record = try fetch(ownerUserID: ownerUserID, memoryID: memoryID, in: context) {
            context.delete(record)
            try context.save()
        }
    }

    func deleteAll(ownerUserID: UUID) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalMemoryRecord>(
            predicate: #Predicate { record in
                record.ownerUserID == ownerUserID
            }
        )

        for record in try context.fetch(descriptor) {
            context.delete(record)
        }

        try context.save()
    }

    private func localRecord(from record: MemoryRecord) throws -> LocalMemoryRecord {
        try LocalMemoryRecord(
            record: record,
            ownNoteData: encode(record.snapshot.ownNote),
            partnerNoteData: encode(record.snapshot.partnerNote),
            visibleMemoryMediaIDsData: encode(record.snapshot.visibleMemoryMediaIDs),
            visibleMediaAssetIDsData: encode(record.snapshot.visibleMediaAssetIDs),
            mediaData: encode(record.snapshot.media)
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
                threadID: local.threadID
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
        preserveDirtyRecords: Bool = true
    ) async throws {
        for row in rows {
            let key = key(ownerUserID: ownerUserID, memoryID: row.memoryID)
            if preserveDirtyRecords, let existing = records[key], existing.syncStatus != .clean {
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
    }

    func saveLocal(_ record: MemoryRecord) async throws {
        records[key(ownerUserID: record.snapshot.ownerUserID, memoryID: record.snapshot.memoryID)] = record
    }

    func load(
        ownerUserID: UUID,
        includeHidden: Bool = false
    ) async throws -> [MemoryRecord] {
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
    ) async throws -> MemoryRecord? {
        records[key(ownerUserID: ownerUserID, memoryID: memoryID)]
    }

    func markConflict(
        ownerUserID: UUID,
        memoryID: UUID,
        reason: String
    ) async throws {
        let recordKey = key(ownerUserID: ownerUserID, memoryID: memoryID)
        guard var record = records[recordKey] else {
            return
        }

        record.syncStatus = .conflict
        record.pendingOperationID = nil
        record.conflictReason = reason
        record.localUpdatedAt = Date()
        records[recordKey] = record
    }

    func delete(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws {
        records[key(ownerUserID: ownerUserID, memoryID: memoryID)] = nil
    }

    func deleteAll(ownerUserID: UUID) async throws {
        records = records.filter { $0.value.snapshot.ownerUserID != ownerUserID }
    }

    private func key(ownerUserID: UUID, memoryID: UUID) -> String {
        LocalMemoryRecord.storageKey(ownerUserID: ownerUserID, memoryID: memoryID)
    }
}
