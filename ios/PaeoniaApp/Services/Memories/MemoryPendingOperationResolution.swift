import Foundation

extension UpdateMemoryOperationPayload {
    /// This edit replayed on top of the server's current memory. A field the edit
    /// changed keeps the edit's value; a field it left alone takes the server's value,
    /// so the partner's change to it survives.
    nonisolated func rebased(onto row: MemoryRemoteRow) -> UpdateMemoryOperationPayload {
        let changedTitle = title != baseTitle
        let changedDate = memoryDate != baseMemoryDate
        return UpdateMemoryOperationPayload(
            memoryID: memoryID,
            expectedRevision: row.revision,
            title: changedTitle ? title : (row.title ?? title),
            memoryDate: changedDate ? memoryDate : row.memoryDate,
            baseTitle: baseTitle,
            baseMemoryDate: baseMemoryDate
        )
    }
}

extension MemoryRemoteRow {
    /// Whether the memory still exists for the couple on the server.
    nonisolated var isVisibleMemory: Bool {
        deletedAt == nil && moderationStatus == .visible
    }
}

/// Shared steps for the memory outbox handlers: pulling the server copy after a
/// write, finding one memory's server row, and settling refused writes.
enum MemoryPendingOperationRefresh {
    /// Pulls the server copy after an accepted write. The local record is replaced only
    /// while this operation is still its latest change, so a newer queued edit stays.
    nonisolated static func succeeded(
        _ operation: PendingSyncOperationSnapshot,
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) async throws -> PendingSyncOperationSendResult {
        try await refresh(
            gateway: gateway,
            memoryStore: memoryStore,
            ownerUserID: operation.ownerUserID,
            confirmedOperationID: operation.operation.id
        )
        return .succeeded
    }

    // ponytail: pages through every memory of the couple. A single-memory query on the
    // backend would make this one request.
    nonisolated static func refresh(
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting,
        ownerUserID: UUID,
        confirmedOperationID: UUID,
        pageSize: Int = 100
    ) async throws {
        var cursor = SyncCursor()

        while true {
            let rows = try await gateway.loadMemories(
                updatedAfter: cursor.updatedAt,
                cursorMemoryID: cursor.tieID,
                limit: pageSize
            )

            guard !rows.isEmpty else {
                return
            }

            try await memoryStore.saveRemote(
                rows,
                ownerUserID: ownerUserID,
                mergePolicy: .overwriteIfPendingOperationMatches(confirmedOperationID)
            )

            guard let last = rows.last, rows.count == pageSize else {
                return
            }

            cursor = SyncCursor(updatedAt: last.syncUpdatedAt, tieID: last.memoryID)
        }
    }

    /// An older write of the same kind to the same memory that hasn't gone through yet,
    /// usually one waiting to retry after a network error. The outbox moves on to newer
    /// writes meanwhile, so without this check the older edit would land last and
    /// replace the newer one.
    nonisolated static func olderPendingWrite(
        before operation: PendingSyncOperationSnapshot,
        memoryID: UUID,
        context: SyncContext,
        memoryIDIn: (Data) -> UUID?
    ) async throws -> PendingSyncOperationSnapshot? {
        guard let kind = operation.operationKind else { return nil }
        let pending = try await context.pendingOperationStore.inFlightOperations(
            ownerUserID: operation.ownerUserID,
            kind: kind
        )
        let current = operation.operation
        return pending.first { other in
            let order = other.operation
            let isOlder = order.localCreatedAt == current.localCreatedAt
                ? order.clientSequence < current.clientSequence
                : order.localCreatedAt < current.localCreatedAt
            return order.id != current.id && isOlder && other.requestData.flatMap(memoryIDIn) == memoryID
        }
    }

    /// When to try a write again that waits for `older`: right after the older one's own
    /// retry, or in a few seconds if it is being sent now.
    nonisolated static func retryDate(after older: PendingSyncOperationSnapshot) -> Date {
        older.nextRetryAt ?? Date().addingTimeInterval(5)
    }

    /// The server's current row for one memory, or nil if the server doesn't have it
    /// (for example, its create hasn't been sent yet).
    nonisolated static func serverRow(
        memoryID: UUID,
        gateway: any MemoryGateway,
        pageSize: Int = 100
    ) async throws -> MemoryRemoteRow? {
        var cursor = SyncCursor()
        while true {
            let rows = try await gateway.loadMemories(
                updatedAfter: cursor.updatedAt,
                cursorMemoryID: cursor.tieID,
                limit: pageSize
            )
            if let match = rows.last(where: { $0.memoryID == memoryID }) {
                return match
            }
            guard let last = rows.last, rows.count == pageSize else {
                return nil
            }
            cursor = SyncCursor(updatedAt: last.syncUpdatedAt, tieID: last.memoryID)
        }
    }

    /// After the server refused a write: when the memory is gone there, show that on
    /// this device and stop retrying. When a check refused it (`23514`, such as a
    /// title or note over the length limit), stop retrying too, so newer edits to the
    /// memory stop waiting behind it. The text stays on this phone, so the person can
    /// open the memory, shorten it, and save again. Otherwise (no access right now, or
    /// the memory's create hasn't reached the server yet) the error is thrown so the
    /// write retries.
    nonisolated static func settleRejectedWrite(
        _ error: any Error,
        memoryID: UUID,
        _ operation: PendingSyncOperationSnapshot,
        gateway: any MemoryGateway,
        memoryStore: any MemoryRecordPersisting
    ) async throws -> PendingSyncOperationSendResult {
        guard isServerRejection(error) else { throw error }
        if isReplayOfRebasedWrite(error) {
            return try await succeeded(operation, gateway: gateway, memoryStore: memoryStore)
        }
        guard let row = try? await serverRow(memoryID: memoryID, gateway: gateway) else {
            throw error
        }
        guard row.isVisibleMemory else {
            return try await acceptRemoval(row, operation, memoryStore: memoryStore)
        }
        guard case let PaeoniaConvexError.server(code, _) = error, code == "23514" else {
            throw error
        }
        return .terminalFailure("Memory change refused: \(error)")
    }

    nonisolated static func acceptRemoval(
        _ row: MemoryRemoteRow,
        _ operation: PendingSyncOperationSnapshot,
        memoryStore: any MemoryRecordPersisting
    ) async throws -> PendingSyncOperationSendResult {
        try await memoryStore.saveRemote(
            [row],
            ownerUserID: operation.ownerUserID,
            mergePolicy: .overwriteLocalChanges
        )
        return .terminalFailure("Memory no longer exists")
    }

    nonisolated static func isMemoryConflict(_ error: any Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("revision conflict") || description.contains("40001")
    }

    /// The backend ran the function and refused the write, as opposed to a network or
    /// sign-in failure.
    nonisolated static func isServerRejection(_ error: any Error) -> Bool {
        if case PaeoniaConvexError.server = error {
            return true
        }
        return false
    }

    /// A rebased resend reuses the operation id with a different request. If its
    /// response was lost, the next retry sends the original request and the server
    /// reports a hash mismatch, which means this operation already went through.
    nonisolated static func isReplayOfRebasedWrite(_ error: any Error) -> Bool {
        String(describing: error).lowercased().contains("replay hash mismatch")
    }
}
