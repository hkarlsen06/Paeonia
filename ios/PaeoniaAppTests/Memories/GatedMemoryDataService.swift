import Foundation
@testable import PaeoniaApp

// The forwarding methods mirror `MemoryDataServicing`, including its parameter counts.
// swiftlint:disable function_parameter_count

/// Forwards to a real data service, but can hold one cached read after it has read the
/// store, so a test can let a newer read finish first.
actor GatedMemoryDataService {
    private let base: MemoryDataService
    private var shouldHoldNextLoad = false
    private var failsReads = false
    private var failingRemovalCall: Int?
    private var removalCalls = 0
    private var heldLoad: CheckedContinuation<Void, Never>?
    private var beforeNextNoteWrite: (@Sendable () async throws -> Void)?

    init(base: MemoryDataService) {
        self.base = base
    }

    func setReadFailure(_ shouldFail: Bool) {
        failsReads = shouldFail
    }

    func failRemoval(call: Int) {
        failingRemovalCall = call
    }

    /// Runs `hook` when the next note write starts, after the caller read the memory.
    func runBeforeNextNoteWrite(_ hook: @escaping @Sendable () async throws -> Void) {
        beforeNextNoteWrite = hook
    }

    func holdNextLoad() {
        shouldHoldNextLoad = true
    }

    func waitUntilHolding() async {
        while heldLoad == nil {
            await Task.yield()
        }
    }

    func release() {
        heldLoad?.resume()
        heldLoad = nil
    }

    func repairQueuedCacheWrite(_ record: MemoryRecord) async throws {
        try await base.repairQueuedCacheWrite(record)
    }

    func loadCachedMemories(ownerUserID: UUID, includeHidden: Bool) async throws -> [MemoryRecord] {
        if failsReads { throw CocoaError(.fileReadUnknown) }
        let records = try await base.loadCachedMemories(ownerUserID: ownerUserID, includeHidden: includeHidden)
        if shouldHoldNextLoad {
            shouldHoldNextLoad = false
            await withCheckedContinuation { heldLoad = $0 }
        }
        return records
    }

    func loadCachedMemory(ownerUserID: UUID, memoryID: UUID) async throws -> MemoryRecord? {
        if failsReads { throw CocoaError(.fileReadUnknown) }
        return try await base.loadCachedMemory(ownerUserID: ownerUserID, memoryID: memoryID)
    }

    func createMemory(
        ownerUserID: UUID,
        coupleID: UUID,
        memoryID: UUID,
        title: String,
        memoryDate: String,
        noteBody: String?,
        optimisticMedia: [MemoryMediaSnapshot],
        place: MemoryPlace?,
        visitID: UUID?,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await base.createMemory(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            memoryID: memoryID,
            title: title,
            memoryDate: memoryDate,
            noteBody: noteBody,
            optimisticMedia: optimisticMedia,
            place: place,
            visitID: visitID,
            operation: operation
        )
    }

    func setMemoryPlace(
        ownerUserID: UUID,
        memoryID: UUID,
        place: MemoryPlace?,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await base.setMemoryPlace(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            place: place,
            operation: operation
        )
    }

    func updateMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        title: String,
        memoryDate: String,
        photoDescriptions: [MemoryPhotoDescription] = [],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await base.updateMemory(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            expectedRevision: expectedRevision,
            title: title,
            memoryDate: memoryDate,
            photoDescriptions: photoDescriptions,
            operation: operation
        )
    }

    func hideMemory(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await base.hideMemory(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            expectedRevision: expectedRevision,
            operation: operation
        )
    }

    func upsertMemoryNote(
        ownerUserID: UUID,
        memoryID: UUID,
        expectedRevision: Int?,
        body: String,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        if let hook = beforeNextNoteWrite {
            beforeNextNoteWrite = nil
            try await hook()
        }
        return try await base.upsertMemoryNote(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            expectedRevision: expectedRevision,
            body: body,
            operation: operation
        )
    }

    func attachMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        optimisticMedia: [MemoryMediaSnapshot],
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        try await base.attachMemoryMedia(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            optimisticMedia: optimisticMedia,
            operation: operation
        )
    }

    func removeMemoryMedia(
        ownerUserID: UUID,
        memoryID: UUID,
        memoryMediaID: UUID,
        operation: SyncClientOperation
    ) async throws -> MemoryRecord {
        removalCalls += 1
        if removalCalls == failingRemovalCall { throw CocoaError(.fileWriteUnknown) }
        return try await base.removeMemoryMedia(
            ownerUserID: ownerUserID,
            memoryID: memoryID,
            memoryMediaID: memoryMediaID,
            operation: operation
        )
    }

    func deleteOwnNote(ownerUserID: UUID, memoryID: UUID, operation: SyncClientOperation) async throws
        -> MemoryRecord {
        try await base.deleteOwnNote(ownerUserID: ownerUserID, memoryID: memoryID, operation: operation)
    }
}

extension GatedMemoryDataService: MemoryDataServicing {}
// swiftlint:enable function_parameter_count
