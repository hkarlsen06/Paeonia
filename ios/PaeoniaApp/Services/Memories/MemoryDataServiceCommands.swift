import Foundation

extension MemoryDataService {
    func createMemory(
        ownerUserID: UUID,
        coupleID: UUID,
        memoryID: UUID = UUID(),
        title: String,
        memoryDate: String,
        noteBody: String?,
        optimisticMedia: [MemoryMediaSnapshot] = [],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        let normalizedNote = Self.normalizedOptional(noteBody)
        guard normalizedNote != nil || !optimisticMedia.isEmpty else {
            throw MemoryDataServiceError.missingCreateContent
        }
        let normalizedTitle = Self.normalizedRequired(title)
        guard !normalizedTitle.isEmpty else {
            throw MemoryDataServiceError.emptyTitle
        }

        let payload = CreateMemoryOperationPayload(
            memoryID: memoryID,
            coupleID: coupleID,
            title: normalizedTitle,
            memoryDate: memoryDate,
            noteBody: normalizedNote,
            mediaAssetIDs: optimisticMedia.map(\.mediaAssetID),
            optimisticMedia: optimisticMedia
        )

        let now = operation.localCreatedAt
        let record = MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: ownerUserID,
                memoryID: memoryID,
                coupleID: coupleID,
                title: payload.title,
                memoryDate: memoryDate,
                createdByUserID: ownerUserID,
                lastEditedByUserID: ownerUserID,
                revision: 1,
                moderationStatus: .visible,
                deletedAt: nil,
                createdAt: now,
                updatedAt: now,
                syncUpdatedAt: now,
                ownNote: normalizedNote.map {
                    MemoryNoteSnapshot(
                        noteID: nil,
                        userID: ownerUserID,
                        body: $0,
                        revision: nil,
                        updatedAt: now,
                        deletedAt: nil,
                        moderationStatus: .visible
                    )
                },
                partnerNote: nil,
                visibleMemoryMediaIDs: optimisticMedia.filter(\.isVisible).map(\.memoryMediaID),
                visibleMediaAssetIDs: optimisticMedia.filter(\.isVisible).map(\.mediaAssetID),
                media: optimisticMedia,
                threadID: nil
            ),
            syncStatus: .dirty,
            pendingOperationID: operation.id,
            localUpdatedAt: now
        )

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .createMemory,
            scope: "memory:\(memoryID.uuidString.lowercased())",
            payload: payload
        )
        try await memoryStore.saveLocal(record)
        return record
    }

    func updateMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        title: String,
        memoryDate: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        let existing = try await requireMemory(ownerUserID: ownerUserID, memoryID: memoryID)
        let normalizedTitle = Self.normalizedRequired(title)
        guard !normalizedTitle.isEmpty else {
            throw MemoryDataServiceError.emptyTitle
        }

        let payload = UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: expectedRevision,
            title: normalizedTitle,
            memoryDate: memoryDate
        )
        let next = record(
            from: existing,
            operation: operation,
            syncStatus: .dirty,
            title: payload.title,
            memoryDate: payload.memoryDate,
            lastEditedByUserID: ownerUserID
        )

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .updateMemory,
            scope: "memory:\(memoryID.uuidString.lowercased())",
            payload: payload
        )
        try await memoryStore.saveLocal(next)
        return next
    }

    func hideMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        let existing = try await requireMemory(ownerUserID: ownerUserID, memoryID: memoryID)
        let payload = HideMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: expectedRevision
        )
        let next = record(
            from: existing,
            operation: operation,
            syncStatus: .pendingDelete,
            deletedAt: operation.localCreatedAt,
            lastEditedByUserID: ownerUserID
        )

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .hideMemory,
            scope: "memory:\(memoryID.uuidString.lowercased())",
            payload: payload
        )
        try await memoryStore.saveLocal(next)
        return next
    }

    func upsertMemoryNote(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int?,
        body: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        let normalizedBody = Self.normalizedOptional(body)
        guard let normalizedBody else {
            throw MemoryDataServiceError.emptyNote
        }

        let existing = try await requireMemory(ownerUserID: ownerUserID, memoryID: memoryID)
        let resolvedRevision = expectedRevision ?? existing.snapshot.ownNote?.revision ?? 0
        let payload = UpsertMemoryNoteOperationPayload(
            memoryID: memoryID,
            expectedRevision: resolvedRevision,
            body: normalizedBody
        )
        let ownNote = MemoryNoteSnapshot(
            noteID: existing.snapshot.ownNote?.noteID,
            userID: ownerUserID,
            body: normalizedBody,
            revision: existing.snapshot.ownNote?.revision,
            updatedAt: operation.localCreatedAt,
            deletedAt: nil,
            moderationStatus: .visible
        )
        let next = record(
            from: existing,
            operation: operation,
            syncStatus: .dirty,
            ownNote: ownNote
        )

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .upsertMemoryNote,
            scope: "memory-note:\(memoryID.uuidString.lowercased())",
            payload: payload
        )
        try await memoryStore.saveLocal(next)
        return next
    }

    func attachMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        optimisticMedia: [MemoryMediaSnapshot],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        guard !optimisticMedia.isEmpty else {
            throw MemoryDataServiceError.emptyMediaAttachment
        }

        let existing = try await requireMemory(ownerUserID: ownerUserID, memoryID: memoryID)
        let payload = AttachMemoryMediaOperationPayload(
            memoryID: memoryID,
            mediaAssetIDs: optimisticMedia.map(\.mediaAssetID),
            optimisticMedia: optimisticMedia
        )
        let mergedMedia = (existing.snapshot.media + optimisticMedia)
            .uniquedByMemoryMediaID()
            .sortedForMemoryDisplay()
        let next = record(
            from: existing,
            operation: operation,
            syncStatus: .dirty,
            visibleMemoryMediaIDs: mergedMedia.filter(\.isVisible).map(\.memoryMediaID),
            visibleMediaAssetIDs: mergedMedia.filter(\.isVisible).map(\.mediaAssetID),
            media: mergedMedia
        )

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .attachMemoryMedia,
            scope: "memory-media:\(memoryID.uuidString.lowercased())",
            payload: payload
        )
        try await memoryStore.saveLocal(next)
        return next
    }

    func removeMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        memoryMediaID: UUID,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        let existing = try await requireMemory(ownerUserID: ownerUserID, memoryID: memoryID)
        let payload = RemoveMemoryMediaOperationPayload(
            memoryID: memoryID,
            memoryMediaID: memoryMediaID
        )
        let media = existing.snapshot.media.map { item in
            guard item.memoryMediaID == memoryMediaID else {
                return item
            }

            return MemoryMediaSnapshot(
                memoryMediaID: item.memoryMediaID,
                mediaAssetID: item.mediaAssetID,
                ownerUserID: item.ownerUserID,
                sortOrder: item.sortOrder,
                deletedAt: operation.localCreatedAt,
                moderationStatus: item.moderationStatus,
                assetDeletedAt: item.assetDeletedAt,
                assetModerationStatus: item.assetModerationStatus,
                assetStorageDeleteStatus: item.assetStorageDeleteStatus,
                updatedAt: operation.localCreatedAt
            )
        }
        let next = record(
            from: existing,
            operation: operation,
            syncStatus: .dirty,
            visibleMemoryMediaIDs: media.filter(\.isVisible).map(\.memoryMediaID),
            visibleMediaAssetIDs: media.filter(\.isVisible).map(\.mediaAssetID),
            media: media
        )

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .removeMemoryMedia,
            scope: "memory-media:\(memoryMediaID.uuidString.lowercased())",
            payload: payload
        )
        try await memoryStore.saveLocal(next)
        return next
    }

    func createMemoryThreadMessage(
        ownerUserID: UUID,
        memoryID: UUID,
        body: String,
        mediaAssetIDs: [UUID] = [],
        operation: SyncClientOperation
    ) async throws {
        let normalizedBody = Self.normalizedOptional(body)
        guard normalizedBody != nil || !mediaAssetIDs.isEmpty else {
            throw MemoryDataServiceError.emptyThreadMessage
        }

        let payload = CreateMemoryThreadMessageOperationPayload(
            memoryID: memoryID,
            body: normalizedBody ?? "",
            mediaAssetIDs: mediaAssetIDs
        )

        if let existing = try await memoryStore.load(ownerUserID: ownerUserID, memoryID: memoryID) {
            try await memoryStore.saveLocal(
                record(
                    from: existing,
                    operation: operation,
                    syncStatus: .dirty
                )
            )
        }

        try await enqueue(
            ownerUserID: ownerUserID,
            operation: operation,
            kind: .createMemoryThreadWithMessage,
            scope: "memory-thread:\(memoryID.uuidString.lowercased())",
            payload: payload
        )
    }
}
