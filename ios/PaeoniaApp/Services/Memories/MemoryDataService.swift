import Foundation

// The write methods mirror the backend functions' arguments one to one.
// swiftlint:disable function_parameter_count
nonisolated protocol MemoryDataServicing: Actor {
    func loadCachedMemories(
        ownerUserID: UUID,
        includeHidden: Bool
    ) async throws -> [MemoryRecord]
    func loadCachedMemory(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord?
    func createMemory(
        ownerUserID: UUID,
        coupleID: UUID,
        memoryID: UUID,
        title: String,
        memoryDate: String,
        noteBody: String?,
        optimisticMedia: [MemoryMediaSnapshot],
        place: MemoryPlace?,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func updateMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        title: String,
        memoryDate: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func setMemoryPlace(
        ownerUserID: UUID,
        memoryID: UUID,
        place: MemoryPlace?,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func hideMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func upsertMemoryNote(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int?,
        body: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func attachMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        optimisticMedia: [MemoryMediaSnapshot],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func removeMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        memoryMediaID: UUID,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord
    func createMemoryThreadMessage(
        ownerUserID: UUID,
        memoryID: UUID,
        body: String,
        mediaAssetIDs: [UUID],
        operation: SyncClientOperation
    ) async throws
}
// swiftlint:enable function_parameter_count

nonisolated enum MemoryDataServiceError: Error, Equatable, Sendable {
    case missingMemory
    /// The memory changed on this device since the caller read it (usually the
    /// partner's edit arriving). Read it again and recompute the edit.
    case staleRevision
    case missingCreateContent
    case emptyTitle
    case emptyNote
    /// Longer than the server accepts. See `MemoryDataService.titleCharacterLimit`.
    case titleTooLong
    case noteTooLong
    case emptyThreadMessage
    case emptyMediaAttachment
    /// A place with no name or with coordinates off the globe. Map search never gives one.
    case invalidPlace
}

actor MemoryDataService: MemoryDataServicing {
    let memoryStore: any MemoryRecordPersisting
    let pendingOperationStore: any PendingSyncOperationPersisting
    let encoder = JSONEncoder()

    init(
        memoryStore: any MemoryRecordPersisting,
        pendingOperationStore: any PendingSyncOperationPersisting
    ) {
        self.memoryStore = memoryStore
        self.pendingOperationStore = pendingOperationStore
    }

    func loadCachedMemories(
        ownerUserID: UUID,
        includeHidden: Bool = false
    ) async throws -> [MemoryRecord] {
        try await memoryStore.load(ownerUserID: ownerUserID, includeHidden: includeHidden)
    }

    func loadCachedMemory(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord? {
        try await memoryStore.load(ownerUserID: ownerUserID, memoryID: memoryID)
    }

    /// The memory to change. A memory that is deleted (by either partner, even if the
    /// delete hasn't synced yet) or hidden counts as missing, so nothing new is queued
    /// for it. The server would refuse those writes anyway.
    func requireMemory(
        ownerUserID: UUID,
        memoryID: UUID
    ) async throws -> MemoryRecord {
        guard let existing = try await memoryStore.load(ownerUserID: ownerUserID, memoryID: memoryID),
              existing.snapshot.isVisible,
              existing.syncStatus != .pendingDelete
        else {
            throw MemoryDataServiceError.missingMemory
        }
        return existing
    }

    func enqueue<Payload: Encodable>(
        ownerUserID: UUID,
        operation: SyncClientOperation,
        kind: SyncPendingOperationKind,
        scope: String,
        payload: Payload
    ) async throws {
        try await pendingOperationStore.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: ownerUserID,
                operation: operation,
                operationKind: kind,
                idempotencyScope: scope,
                requestData: try encoder.encode(payload)
            )
        )
    }

    func record(
        from existing: MemoryRecord,
        operation: SyncClientOperation,
        syncStatus: SyncRecordStatus,
        title: String? = nil,
        memoryDate: String? = nil,
        place: MemoryPlace?? = nil,
        revision: Int? = nil,
        deletedAt: Date? = nil,
        lastEditedByUserID: UUID? = nil,
        ownNote: MemoryNoteSnapshot? = nil,
        visibleMemoryMediaIDs: [UUID]? = nil,
        visibleMediaAssetIDs: [UUID]? = nil,
        media: [MemoryMediaSnapshot]? = nil
    ) -> MemoryRecord {
        let snapshot = existing.snapshot
        return MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: snapshot.ownerUserID,
                memoryID: snapshot.memoryID,
                coupleID: snapshot.coupleID,
                title: title ?? snapshot.title,
                memoryDate: memoryDate ?? snapshot.memoryDate,
                place: place ?? snapshot.place,
                createdByUserID: snapshot.createdByUserID,
                lastEditedByUserID: lastEditedByUserID ?? snapshot.lastEditedByUserID,
                revision: revision ?? snapshot.revision,
                moderationStatus: snapshot.moderationStatus,
                deletedAt: deletedAt ?? snapshot.deletedAt,
                createdAt: snapshot.createdAt,
                updatedAt: operation.localCreatedAt,
                syncUpdatedAt: operation.localCreatedAt,
                ownNote: ownNote ?? snapshot.ownNote,
                partnerNote: snapshot.partnerNote,
                visibleMemoryMediaIDs: visibleMemoryMediaIDs ?? snapshot.visibleMemoryMediaIDs,
                visibleMediaAssetIDs: visibleMediaAssetIDs ?? snapshot.visibleMediaAssetIDs,
                media: media ?? snapshot.media,
                threadID: snapshot.threadID
            ),
            syncStatus: syncStatus,
            pendingOperationID: operation.id,
            conflictReason: nil,
            localUpdatedAt: operation.localCreatedAt
        )
    }

    /// The server's limits. It counts Unicode code points of the trimmed text, so
    /// an emoji made of several code points counts as several.
    static let titleCharacterLimit = 160
    static let noteCharacterLimit = 4_000

    static func isOverLimit(_ text: String, _ limit: Int) -> Bool {
        text.unicodeScalars.count > limit
    }

    /// The longest start of `text` that fits in `limit` code points, without
    /// cutting a character in half.
    static func prefix(_ text: String, fittingCodePoints limit: Int) -> String {
        var count = 0
        let end = text.firstIndex { character in
            count += character.unicodeScalars.count
            return count > limit
        } ?? text.endIndex
        return String(text[..<end])
    }

    static let placeNameCharacterLimit = 160
    static let placeCityCharacterLimit = 120

    /// The place in the form the server accepts: trimmed text cut to its limits, and a
    /// country code only when it is two capital letters. Matching the server's checks
    /// here means a queued place is never refused later, when nobody is looking.
    static func normalizedPlace(_ place: MemoryPlace?) throws -> MemoryPlace? {
        guard let place else { return nil }
        let name = prefix(normalizedRequired(place.name), fittingCodePoints: placeNameCharacterLimit)
        guard !name.isEmpty,
              place.latitude.isFinite, (-90...90).contains(place.latitude),
              place.longitude.isFinite, (-180...180).contains(place.longitude)
        else {
            throw MemoryDataServiceError.invalidPlace
        }
        let city = normalizedOptional(place.city).map { prefix($0, fittingCodePoints: placeCityCharacterLimit) }
        let countryCode = normalizedOptional(place.countryCode).flatMap { code in
            code.count == 2 && code.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) } ? code : nil
        }
        return MemoryPlace(
            name: name,
            latitude: place.latitude,
            longitude: place.longitude,
            city: city,
            countryCode: countryCode
        )
    }

    static func normalizedRequired(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedOptional(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        return normalized
    }
}

nonisolated enum MemoryDataServiceFactory {
    static func makeDefault() -> any MemoryDataServicing {
        if let localStore = PaeoniaLocalStore.shared {
            return MemoryDataService(
                memoryStore: SwiftDataMemoryRecordRepository(container: localStore.container),
                pendingOperationStore: SwiftDataPendingSyncOperationRepository(container: localStore.container)
            )
        }

        return MemoryDataService(
            memoryStore: InMemoryMemoryRecordRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
    }

    /// Wipes the signed-in user's locally cached memories when the relationship ends.
    /// Memories are couple-private content, so losing access should remove the local
    /// copy the same way the widget, daily, and media caches are cleared on un-pair.
    static func clearForPrivacy(ownerUserID: UUID) async {
        guard let localStore = PaeoniaLocalStore.shared else { return }
        let repository = SwiftDataMemoryRecordRepository(container: localStore.container)
        try? await repository.deleteAll(ownerUserID: ownerUserID)
    }
}
