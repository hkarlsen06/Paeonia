import CryptoKit
import Foundation

nonisolated struct VisitMemoryJoin: Sendable {
    enum Write: Sendable {
        case note(String, expectedRevision: Int)
        case deleteNote(expectedRevision: Int)
        case remove(UUID)
        case attach([MemoryMediaSnapshot])
        case describe([MemoryPhotoDescription])
    }

    /// Each write's key holds what it writes, so a join that runs again after the app ended in
    /// the middle of one queues a changed write anew and skips an unchanged one.
    let writes: [(key: String, write: Write)]

    init(
        waitingCopy waiting: MemorySnapshot,
        sentCreate sent: CreateMemoryOperationPayload,
        joinedRow joined: MemoryRemoteRow,
        descriptionEdits descriptions: [MemoryPhotoDescription]
    ) {
        let owner = waiting.ownerUserID
        let sentIDs = Set(sent.optimisticMedia.map(\.memoryMediaID))
        let ownOnJoined = joined.memoryMediaStates.map(\.snapshot).filter { $0.ownerUserID == owner && $0.isVisible }
        let addedByJoin = ownOnJoined.filter { sentIDs.contains($0.memoryMediaID) }
        guard waiting.deletedAt == nil else {
            let theirs = sentIDs.union(waiting.media.filter { $0.ownerUserID == owner }.map(\.memoryMediaID))
            let theirPhotos = ownOnJoined.filter { theirs.contains($0.memoryMediaID) }
            writes = Self.undoingJoin(joined: joined, theirPhotos: theirPhotos)
            return
        }

        var writes: [(key: String, write: Write)] = []
        let note = Self.note(title: waiting.title, body: waiting.ownNote?.visibleBody, joinedTitle: joined.title)
        if let note, note != joined.ownNoteBody {
            writes.append(("note:\(Self.digest(note))", .note(note, expectedRevision: joined.ownNoteRevision ?? 0)))
        }
        let kept = waiting.media.filter { $0.ownerUserID == owner && $0.isVisible }
        let keptIDs = Set(kept.map(\.memoryMediaID))
        writes += addedByJoin.filter { !keptIDs.contains($0.memoryMediaID) }
            .map { ("remove:\($0.memoryMediaID)", .remove($0.memoryMediaID)) }
        let onJoinedIDs = Set(ownOnJoined.map(\.memoryMediaID))
        let addedWhileWaiting = kept.filter {
            !onJoinedIDs.contains($0.memoryMediaID) && !sentIDs.contains($0.memoryMediaID)
        }
        writes += addedWhileWaiting.map { ("attach:\($0.memoryMediaID)", .attach([$0])) }
        let keptAssets = Set(kept.map(\.mediaAssetID))
        let latest = Dictionary(descriptions.map { ($0.mediaAssetID, $0) }, uniquingKeysWith: { $1 })
        let changed = latest.values.filter { keptAssets.contains($0.mediaAssetID) }
            .sorted { $0.mediaAssetID.uuidString < $1.mediaAssetID.uuidString }
        if !changed.isEmpty {
            let text = changed.map { "\($0.mediaAssetID)=\($0.text)" }.joined(separator: "\n")
            writes.append(("describe:\(Self.digest(text))", .describe(changed)))
        }
        self.writes = writes
    }

    /// The person deleted their waiting memory. Their note on the joined memory came with the
    /// join, because the server joins only when they have no note there, so it goes with their
    /// photos from the waiting memory.
    private static func undoingJoin(
        joined: MemoryRemoteRow,
        theirPhotos: [MemoryMediaSnapshot]
    ) -> [(key: String, write: Write)] {
        var writes: [(key: String, write: Write)] = []
        if joined.ownNoteBody != nil, let revision = joined.ownNoteRevision {
            writes.append(("delete-note:\(revision)", .deleteNote(expectedRevision: revision)))
        }
        return writes + theirPhotos.map { ("remove:\($0.memoryMediaID)", .remove($0.memoryMediaID)) }
    }

    func operationIDs(after create: SyncClientOperation) -> Set<UUID> {
        Set(writes.map { Self.stableOperation($0.key, after: create, order: 0).id })
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func note(title: String?, body: String?, joinedTitle: String?) -> String? {
        let parts = [title == joinedTitle ? nil : title, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    static func stableOperation(_ key: String, after create: SyncClientOperation, order: Int) -> SyncClientOperation {
        SyncClientOperation(
            id: UUID(hashing: "\(create.id.uuidString)/\(key)"),
            clientID: create.clientID,
            clientSequence: create.clientSequence,
            localCreatedAt: Date().addingTimeInterval(Double(order) / 1_000)
        )
    }
}

nonisolated extension UUID {
    /// The same id for the same text.
    init(hashing text: String) {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private nonisolated struct JoinedMemoryNotOnServerYet: Error {}

extension MemoryPendingOperationRefresh {
    nonisolated static func joined(
        _ create: PendingSyncOperationSnapshot,
        into joined: UUID,
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting,
        pendingStore: any PendingSyncOperationPersisting
    ) async throws {
        let owner = create.ownerUserID
        let sent = try JSONDecoder()
            .decodeQueuedPayload(CreateMemoryOperationPayload.self, from: create.requestData ?? Data())
        guard try await memoryStore.load(ownerUserID: owner, memoryID: sent.memoryID) != nil else {
            try await fail(writes(on: sent.memoryID, owner: owner, pendingStore: pendingStore), in: pendingStore)
            return
        }
        guard let row = try await serverRow(memoryID: joined, gateway: gateway) else {
            throw JoinedMemoryNotOnServerYet()
        }
        await MemoryWriteLock.shared.take([sent.memoryID, joined])
        defer { MemoryWriteLock.shared.release([sent.memoryID, joined]) }
        let queued = try await writes(on: sent.memoryID, owner: owner, pendingStore: pendingStore)
        var planned: Set<UUID> = []
        if let waiting = try await memoryStore.load(ownerUserID: owner, memoryID: sent.memoryID) {
            try await memoryStore.saveRemote([row], ownerUserID: owner, mergePolicy: .preserveLocalChanges)
            if row.isVisibleMemory {
                let descriptions = queued.filter { $0.operationKind == .updateMemory }.flatMap {
                    (try? JSONDecoder().decode(UpdateMemoryOperationPayload.self, from: $0.requestData ?? Data()))?
                        .photoDescriptions ?? []
                }
                let plan = VisitMemoryJoin(
                    waitingCopy: waiting.snapshot, sentCreate: sent, joinedRow: row, descriptionEdits: descriptions
                )
                planned = plan.operationIDs(after: create.operation)
                try await MemoryDataService(memoryStore: memoryStore, pendingOperationStore: pendingStore)
                    .queue(plan, on: joined, ownerUserID: owner, after: create.operation)
                try await moveComments(from: sent.memoryID, to: joined, owner: owner, pendingStore: pendingStore)
            }
        }
        try await fail(
            earlierRun(of: create, on: joined, other: planned, pendingStore: pendingStore), in: pendingStore
        )
        try await fail(queued, in: pendingStore)
        try await memoryStore.remove(ownerUserID: owner, memoryID: sent.memoryID)
    }

    /// Writes an earlier run of this join queued and did not send before the app ended, which the
    /// current plan replaces. They share the create's client and sequence.
    private nonisolated static func earlierRun(
        of create: PendingSyncOperationSnapshot,
        on joined: UUID,
        other planned: Set<UUID>,
        pendingStore: any PendingSyncOperationPersisting
    ) async throws -> [PendingSyncOperationSnapshot] {
        try await writes(on: joined, owner: create.ownerUserID, pendingStore: pendingStore).filter {
            $0.operation.clientID == create.operation.clientID
                && $0.operation.clientSequence == create.operation.clientSequence
                && !planned.contains($0.operation.id)
        }
    }

    private nonisolated static func writes(
        on memoryID: UUID,
        owner: UUID,
        pendingStore: any PendingSyncOperationPersisting
    ) async throws -> [PendingSyncOperationSnapshot] {
        var queued: [PendingSyncOperationSnapshot] = []
        for kind in memoryWriteKinds where kind != .createMemory {
            queued += try await pendingStore.inFlightOperations(ownerUserID: owner, kind: kind)
                .filter { $0.requestData.flatMap(memoryID(in:)) == memoryID }
        }
        return queued
    }

    private nonisolated static func fail(
        _ writes: [PendingSyncOperationSnapshot],
        in pendingStore: any PendingSyncOperationPersisting
    ) async throws {
        for write in writes {
            try await pendingStore.markTerminalFailure(
                clientOperationID: write.operation.id,
                errorDescription: "The memory joined the partner's memory for the visit",
                at: Date()
            )
        }
    }
}

extension MemoryDataService {
    /// Takes the person's own note off a memory. The memory and the partner's note stay.
    func deleteOwnNote(ownerUserID: UUID, memoryID: UUID, operation: SyncClientOperation) async throws
        -> MemoryRecord {
        await MemoryWriteLock.shared.take([memoryID])
        defer { MemoryWriteLock.shared.release([memoryID]) }
        let existing = try await requireMemory(ownerUserID: ownerUserID, memoryID: memoryID)
        guard let note = existing.snapshot.ownNote, note.visibleBody != nil, let revision = note.revision else {
            return existing
        }
        let write = VisitMemoryJoin.Write.deleteNote(expectedRevision: revision)
        try await enqueue(write, on: existing.snapshot, operation: operation)
        let next = applying(write, to: existing, operation: operation)
        try await cacheQueuedRecord(next)
        return next
    }

    func queue(
        _ plan: VisitMemoryJoin,
        on joinedID: UUID,
        ownerUserID: UUID,
        after create: SyncClientOperation
    ) async throws {
        guard var record = try await memoryStore.load(ownerUserID: ownerUserID, memoryID: joinedID) else { return }
        for (order, entry) in plan.writes.enumerated() {
            let operation = VisitMemoryJoin.stableOperation(entry.key, after: create, order: order)
            try await enqueue(entry.write, on: record.snapshot, operation: operation)
            record = applying(entry.write, to: record, operation: operation)
        }
        try await memoryStore.saveLocal(record)
    }

    private func enqueue(
        _ write: VisitMemoryJoin.Write,
        on memory: MemorySnapshot,
        operation: SyncClientOperation
    ) async throws {
        let memoryID = memory.memoryID
        let scope = memoryID.uuidString.lowercased()
        func queue(_ kind: SyncPendingOperationKind, _ scope: String, _ payload: some Encodable) async throws {
            try await enqueue(
                ownerUserID: memory.ownerUserID, operation: operation, kind: kind, scope: scope, payload: payload
            )
        }
        switch write {
        case let .note(body, revision):
            try await queue(
                .upsertMemoryNote, "memory-note:\(scope)",
                UpsertMemoryNoteOperationPayload(memoryID: memoryID, expectedRevision: revision, body: body)
            )
        case let .deleteNote(revision):
            try await queue(
                .deleteMemoryNote, "memory-note:\(scope)",
                DeleteMemoryNoteOperationPayload(memoryID: memoryID, expectedRevision: revision)
            )
        case let .remove(mediaID):
            try await queue(
                .removeMemoryMedia, "memory-media:\(mediaID.uuidString.lowercased())",
                RemoveMemoryMediaOperationPayload(memoryID: memoryID, memoryMediaID: mediaID)
            )
        case let .attach(media):
            try await queue(.attachMemoryMedia, "memory-media:\(scope)", AttachMemoryMediaOperationPayload(
                memoryID: memoryID, mediaAssetIDs: media.map(\.mediaAssetID), optimisticMedia: media
            ))
        case let .describe(descriptions):
            try await queue(.updateMemory, "memory:\(scope)", UpdateMemoryOperationPayload(
                memoryID: memoryID, expectedRevision: memory.revision, title: memory.title ?? "",
                memoryDate: memory.memoryDate, baseTitle: memory.title, baseMemoryDate: memory.memoryDate,
                photoDescriptions: descriptions
            ))
        }
    }

    private func applying(
        _ write: VisitMemoryJoin.Write,
        to record: MemoryRecord,
        operation: SyncClientOperation
    ) -> MemoryRecord {
        let snapshot = record.snapshot
        let at = operation.localCreatedAt
        let note = { (body: String?, revision: Int) in
            MemoryNoteSnapshot(
                noteID: snapshot.ownNote?.noteID, userID: snapshot.ownerUserID, body: body, revision: revision,
                updatedAt: at, deletedAt: body == nil ? at : nil, moderationStatus: .visible
            )
        }
        switch write {
        case let .note(body, revision):
            return self.record(
                from: record, operation: operation, syncStatus: .dirty, ownNote: note(body, revision + 1)
            )
        case let .deleteNote(revision):
            return self.record(from: record, operation: operation, syncStatus: .dirty, ownNote: note(nil, revision))
        case let .remove(mediaID):
            let media = snapshot.media.map { $0.memoryMediaID == mediaID ? $0.removed(at: at) : $0 }
            return self.record(record, media: media, operation)
        case let .attach(media):
            let merged = (snapshot.media + media).uniquedByMemoryMediaID().sortedForMemoryDisplay()
            return self.record(record, media: merged, operation)
        case let .describe(descriptions):
            return self.record(
                from: record, operation: operation, syncStatus: .dirty, revision: snapshot.revision + 1,
                media: snapshot.media.map { $0.applying(descriptions, author: snapshot.ownerUserID) }
            )
        }
    }

    private func record(_ record: MemoryRecord, media: [MemoryMediaSnapshot], _ operation: SyncClientOperation)
        -> MemoryRecord {
        let visible = media.filter(\.isVisible)
        return self.record(
            from: record, operation: operation, syncStatus: .dirty,
            visibleMemoryMediaIDs: visible.map(\.memoryMediaID), visibleMediaAssetIDs: visible.map(\.mediaAssetID),
            media: media
        )
    }
}

struct DeleteMemoryNotePendingOperationHandler: PendingSyncOperationHandling {
    nonisolated let operationKind: SyncPendingOperationKind = .deleteMemoryNote

    private let gateway: any MemoryGateway
    private let memoryStore: any MemoryRecordPersisting

    init(gateway: any MemoryGateway, memoryStore: any MemoryRecordPersisting) {
        self.gateway = gateway
        self.memoryStore = memoryStore
    }

    func send(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        guard let requestData = operation.requestData else {
            return .terminalFailure("Missing delete memory note payload")
        }
        let payload = try JSONDecoder().decodeQueuedPayload(DeleteMemoryNoteOperationPayload.self, from: requestData)
        let refresh = MemoryPendingOperationRefresh.self
        do {
            try await gateway.deleteMemoryNote(payload, operation: operation.operation)
        } catch where refresh.isMemoryConflict(error) {
            return try await keepNoteChangedSinceTheDelete(operation, context: context)
        } catch {
            return try await refresh.settleRejectedWrite(
                error, memoryID: payload.memoryID, operation,
                gateway: gateway, memoryStore: memoryStore, context: context
            )
        }
        return try await refresh.succeeded(operation, gateway: gateway, memoryStore: memoryStore, context: context)
    }

    private func keepNoteChangedSinceTheDelete(
        _ operation: PendingSyncOperationSnapshot,
        context: SyncContext
    ) async throws -> PendingSyncOperationSendResult {
        try await MemoryPendingOperationRefresh.succeeded(
            operation, gateway: gateway, memoryStore: memoryStore, context: context
        )
    }
}
